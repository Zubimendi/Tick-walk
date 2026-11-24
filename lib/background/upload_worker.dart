import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../core/clock.dart';
import '../data/api/auth.dart';
import '../data/api/pb_client.dart';
import '../data/api/token_storage.dart';
import '../data/db/app_database.dart';
import '../data/repositories/outbox_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/sync/media_lane.dart';
import '../data/sync/record_lane.dart';
import '../data/sync/upload_scheduler.dart';

const String backgroundUploadTaskTag = 'com.tickwalk.upload_worker';
const String backgroundUploadTaskName = 'backgroundUploadTask';

/// Top-level Workmanager entry point.
/// Must be annotated with `@pragma('vm:entry-point')` to survive tree shaking.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      final db = await AppDatabase.open();
      const clock = SystemClock();
      const tokenStorage = SecureTokenStorage();
      final pbClient = PbClient(tokenStorage: tokenStorage);

      final worker = UploadWorker(
        db: db,
        clock: clock,
        pbClient: pbClient,
        maxRuntime: const Duration(seconds: 45),
      );

      final success = await worker.run();
      await db.close();
      return success;
    } catch (e) {
      debugPrint('[UploadWorker] Background task failed: $e');
      return false;
    }
  });
}

/// Bounded background upload runner (Section 8.10).
/// Opens independent DB connection, syncs records and media batches within max runtime.
class UploadWorker {
  UploadWorker({
    required AppDatabase db,
    required Clock clock,
    required PbClient pbClient,
    this.maxRuntime = const Duration(seconds: 45),
  })  : _db = db,
        _clock = clock,
        _pbClient = pbClient;

  final AppDatabase _db;
  final Clock _clock;
  final PbClient _pbClient;
  final Duration maxRuntime;

  /// Executes bounded background upload. Returns true if completed normally.
  Future<bool> run() async {
    final startTime = _clock.nowMillis();
    final deadline = startTime + maxRuntime.inMilliseconds;

    // 1. Initialize auth and check credentials
    await _pbClient.init();
    if (!_pbClient.isAuthenticated) {
      return true; // Not signed in, nothing to upload
    }

    final settingsRepo = SettingsRepository(_db);
    final outboxRepo = OutboxRepository(_db, _clock);
    final authService = AuthService(
      pbClient: _pbClient,
      settingsRepository: settingsRepo,
      db: _db,
    );

    if (!authService.isSignedIn) {
      return true;
    }

    final wifiOnly = await settingsRepo.wifiOnly();
    final recordLane = RecordLane(
      pbClient: _pbClient,
      db: _db,
      outboxRepo: outboxRepo,
      clock: _clock,
    );
    final mediaLane = MediaLane(
      pbClient: _pbClient,
      db: _db,
      outboxRepo: outboxRepo,
      settingsRepo: settingsRepo,
      clock: _clock,
    );

    // 2. Lane 1: Drain records
    final recordRes = await recordLane.syncRecords();
    if (recordRes.isErr) {
      // If records lane stops on error, don't proceed to media
      return false;
    }

    // 3. Lane 2: Bounded media upload
    final connection = wifiOnly ? NetworkConnectionType.wifi : NetworkConnectionType.cellular;

    while (_clock.nowMillis() < deadline) {
      final mediaRes = await mediaLane.processNextBatch(connection: connection);
      if (mediaRes.isErr) {
        break;
      }
      final uploadedCount = mediaRes.valueOrNull ?? 0;
      if (uploadedCount == 0) {
        // Queue is drained or all remaining items are in backoff
        break;
      }
    }

    return true;
  }

  /// Configures and registers periodic Workmanager background tasks.
  static Future<void> registerBackgroundUpload({bool wifiOnly = true}) async {
    try {
      await Workmanager().initialize(
        callbackDispatcher,
      );

      await Workmanager().registerPeriodicTask(
        backgroundUploadTaskTag,
        backgroundUploadTaskName,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(
          networkType: wifiOnly ? NetworkType.unmetered : NetworkType.connected,
          requiresBatteryNotLow: true,
        ),
      );
    } catch (e) {
      debugPrint('[UploadWorker] Could not register Workmanager task: $e');
    }
  }

  /// Cancels periodic background task.
  static Future<void> cancelBackgroundUpload() async {
    try {
      await Workmanager().cancelByUniqueName(backgroundUploadTaskTag);
    } catch (_) {}
  }
}
