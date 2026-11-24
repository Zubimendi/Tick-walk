import 'dart:async';
import 'package:flutter/widgets.dart';

import '../../core/errors.dart';
import '../../core/result.dart';
import '../api/auth.dart';
import 'connectivity.dart';
import 'media_lane.dart';
import 'record_lane.dart';
import 'upload_scheduler.dart';

/// Summary report of a coordinated sync cycle.
class SyncCycleReport {
  const SyncCycleReport({
    this.recordReport,
    this.mediaUploaded = 0,
    this.skipped = false,
    this.offline = false,
  });

  const SyncCycleReport.skipped()
      : recordReport = null,
        mediaUploaded = 0,
        skipped = true,
        offline = false;

  const SyncCycleReport.offline()
      : recordReport = null,
        mediaUploaded = 0,
        skipped = false,
        offline = true;

  final SyncReport? recordReport;
  final int mediaUploaded;
  final bool skipped;
  final bool offline;
}

/// Orchestrates multi-lane sync across application lifecycle transitions,
/// network connectivity changes, and manual sync requests (Section 8.7).
///
/// Invariant:
/// - Re-entrancy guard ensures only one sync cycle runs at a time.
/// - Signed-in check guards network operations.
/// - Lane 1 (Records) runs first so parent inspections/items are pushed before media.
/// - Lane 2 (Media) follows, processing batches permitted by current connectivity.
class SyncCoordinator with WidgetsBindingObserver {
  SyncCoordinator({
    required RecordLane recordLane,
    required MediaLane mediaLane,
    required ConnectivityService connectivityService,
    required AuthService authService,
    bool autoStart = false,
  })  : _recordLane = recordLane,
        _mediaLane = mediaLane,
        _connectivityService = connectivityService,
        _authService = authService {
    if (autoStart) {
      start();
    }
  }

  final RecordLane _recordLane;
  final MediaLane _mediaLane;
  final ConnectivityService _connectivityService;
  final AuthService _authService;

  StreamSubscription<NetworkConnectionType>? _connectivitySub;
  NetworkConnectionType _lastConnection = NetworkConnectionType.none;
  bool _isSyncing = false;
  bool _isStarted = false;

  bool get isSyncing => _isSyncing;
  bool get isStarted => _isStarted;

  /// Starts listening to connectivity changes and app lifecycle transitions.
  void start() {
    if (_isStarted) return;
    _isStarted = true;

    // Observe app lifecycle resume
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {
      // In some pure unit test environments WidgetsBinding may not be available.
    }

    // Observe connectivity changes
    _connectivitySub = _connectivityService.watch().listen((connection) {
      final wasOffline = _lastConnection == NetworkConnectionType.none;
      _lastConnection = connection;

      // Trigger sync if connectivity was regained
      if (wasOffline && connection != NetworkConnectionType.none) {
        triggerSync();
      }
    });
  }

  /// Stops observing lifecycle and cancels network subscriptions.
  void dispose() {
    _isStarted = false;
    _connectivitySub?.cancel();
    _connectivitySub = null;
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      triggerSync();
    }
  }

  /// Triggers a full synchronization cycle:
  /// 1. Verifies authentication and network connectivity.
  /// 2. Pushes records and pulls remote updates (Lane 1).
  /// 3. Uploads ready media in batches (Lane 2).
  Future<Result<SyncCycleReport>> triggerSync() async {
    if (_isSyncing) {
      return const Ok(SyncCycleReport.skipped());
    }

    if (!_authService.isSignedIn) {
      return const Ok(SyncCycleReport.skipped());
    }

    _isSyncing = true;
    try {
      final connection = await _connectivityService.check();
      if (connection == NetworkConnectionType.none) {
        return const Ok(SyncCycleReport.offline());
      }

      // 1. Lane 1: Push records then pull updates
      final recordRes = await _recordLane.syncRecords();
      if (recordRes.isErr) {
        return Err(recordRes.errorOrNull!);
      }

      // 2. Lane 2: Process media batches until none ready or backoff/error
      var totalMediaUploaded = 0;
      while (true) {
        final mediaRes = await _mediaLane.processNextBatch(connection: connection);
        if (mediaRes.isErr) {
          break;
        }
        final batchCount = mediaRes.valueOrNull ?? 0;
        totalMediaUploaded += batchCount;
        if (batchCount == 0) {
          // No more ready uploads in this batch
          break;
        }
      }

      return Ok(SyncCycleReport(
        recordReport: recordRes.valueOrNull,
        mediaUploaded: totalMediaUploaded,
      ));
    } on Object catch (e) {
      return Err(AppError(
        message: 'Sync failed: $e',
        klass: ErrorClass.unknown,
        cause: e,
      ));
    } finally {
      _isSyncing = false;
    }
  }
}
