import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:pocketbase/pocketbase.dart';

import '../../core/clock.dart';
import '../../core/errors.dart';
import '../../core/result.dart';
import '../../domain/models.dart';
import '../api/error_mapper.dart';
import '../api/pb_client.dart';
import '../db/app_database.dart' as db;
import '../repositories/outbox_repository.dart';
import '../repositories/settings_repository.dart';
import 'backoff.dart';
import 'upload_scheduler.dart';

/// Lane 2 (Media): Manages bounded concurrent multipart uploads for photo attachments
/// with per-file exponential backoff, Wi-Fi gating, and one-batch override.
/// Invariant: Max 2 concurrent uploads, independent per-file backoff, does not block records.
class MediaLane {
  MediaLane({
    required PbClient pbClient,
    required db.AppDatabase db,
    required OutboxRepository outboxRepo,
    required SettingsRepository settingsRepo,
    required Clock clock,
    int concurrency = 2,
    Duration uploadTimeout = const Duration(seconds: 60),
  })  : _pbClient = pbClient,
        _db = db,
        _outboxRepo = outboxRepo,
        _settingsRepo = settingsRepo,
        _clock = clock,
        _concurrency = concurrency,
        _uploadTimeout = uploadTimeout;

  final PbClient _pbClient;
  final db.AppDatabase _db;
  final OutboxRepository _outboxRepo;
  final SettingsRepository _settingsRepo;
  final Clock _clock;
  final int _concurrency;
  final Duration _uploadTimeout;

  final Set<String> _inFlight = <String>{};
  final Map<String, UploadWaitingReason> _latestWaitingReasons = <String, UploadWaitingReason>{};

  bool _oneBatchOverride = false;

  Set<String> get inFlight => Set.unmodifiable(_inFlight);
  Map<String, UploadWaitingReason> get waitingReasons => Map.unmodifiable(_latestWaitingReasons);
  bool get oneBatchOverride => _oneBatchOverride;

  /// Sets one-batch override to permit mobile data upload for the next batch.
  void setOneBatchOverride(bool override) {
    _oneBatchOverride = override;
  }

  /// Evaluates pending media uploads and executes ready candidates up to concurrency limit.
  Future<Result<int>> processNextBatch({
    required NetworkConnectionType connection,
  }) async {
    if (!_pbClient.authStore.isValid) {
      return const Ok(0);
    }

    final now = _clock.nowMillis();
    final wifiOnly = await _settingsRepo.wifiOnly();

    // 1. Fetch pending records to ensure parent inspections/items are synced
    final pendingRecords = await _outboxRepo.getPendingEntries(lane: OutboxLane.records);
    final pendingParentIds = pendingRecords.map((r) => r.entityId).toSet();

    // 2. Fetch pending media outbox entries
    final mediaEntries = await _outboxRepo.getPendingEntries(lane: OutboxLane.media);
    if (mediaEntries.isEmpty) {
      _latestWaitingReasons.clear();
      return const Ok(0);
    }

    // 3. Build UploadCandidates with local file existence check
    final candidates = <UploadCandidate>[];
    for (final entry in mediaEntries) {
      // Look up attachment row to get local path
      final attRow = await (_db.select(_db.attachments)..where((t) => t.id.equals(entry.entityId))).getSingleOrNull();
      final localPath = attRow?.localPath;
      final fileExists = localPath != null && localPath.isNotEmpty && File(localPath).existsSync();

      candidates.add(UploadCandidate(
        outboxSeq: entry.seq,
        attachmentId: entry.entityId,
        inspectionId: attRow?.inspectionId ?? '',
        itemId: attRow?.itemId,
        localPath: localPath,
        fileExists: fileExists,
        nextAttemptAt: entry.nextAttemptAt,
        attempts: entry.attempts,
      ));
    }

    // 4. Run upload scheduler
    final schedule = nextUploads(
      queue: candidates,
      now: now,
      inFlight: _inFlight,
      concurrency: _concurrency,
      wifiOnly: wifiOnly,
      connection: connection,
      oneBatchOverride: _oneBatchOverride,
      pendingRecordEntityIds: pendingParentIds,
    );

    _latestWaitingReasons
      ..clear()
      ..addAll(schedule.waitingReasons);

    // Park any entries where the local file is permanently missing
    for (final entry in schedule.waitingReasons.entries) {
      if (entry.value == UploadWaitingReason.fileMissing) {
        final cand = candidates.firstWhere((c) => c.attachmentId == entry.key);
        await _outboxRepo.parkEntry(
          seq: cand.outboxSeq,
          reason: 'File missing on this phone',
        );
      }
    }

    if (schedule.toUpload.isEmpty) {
      return const Ok(0);
    }

    // If oneBatchOverride was used, reset it after scheduling
    if (_oneBatchOverride) {
      _oneBatchOverride = false;
    }

    // 5. Execute uploads in parallel up to concurrency
    final futures = schedule.toUpload.map((c) => _uploadSingle(c, mediaEntries));
    final results = await Future.wait(futures);

    final successfulCount = results.where((r) => r.isOk).length;
    return Ok(successfulCount);
  }

  Future<Result<void>> _uploadSingle(
    UploadCandidate candidate,
    List<OutboxEntry> entries,
  ) async {
    final id = candidate.attachmentId;
    _inFlight.add(id);

    final entry = entries.firstWhere((e) => e.entityId == id);
    final now = _clock.nowMillis();

    try {
      if (candidate.localPath == null || !candidate.fileExists) {
        // Local file missing: park with fileMissing (Section 8.5 item 1)
        await _outboxRepo.parkEntry(
          seq: candidate.outboxSeq,
          reason: 'File missing on this phone',
        );
        return const Err(AppError(
          klass: ErrorClass.fileMissing,
          message: 'File missing on this phone',
        ));
      }

      final file = File(candidate.localPath!);
      final bytes = await file.readAsBytes();
      final filename = p.basename(candidate.localPath!);

      Map<String, dynamic> metadata = {};
      try {
        if (entry.payload.isNotEmpty) {
          metadata = jsonDecode(entry.payload) as Map<String, dynamic>;
        }
      } catch (_) {}

      final body = Map<String, dynamic>.from(metadata);
      if (!body.containsKey('id')) {
        body['id'] = id;
      }

      final multipart = http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: filename,
      );

      RecordModel? serverRecord;
      try {
        serverRecord = await _pbClient.pb
            .collection('attachments')
            .create(
              body: body,
              files: [multipart],
            )
            .timeout(_uploadTimeout);
      } on ClientException catch (e) {
        if (e.statusCode == 400) {
          // Duplicate create check: if record already exists, treat as success (Section 8.5 item 4)
          try {
            serverRecord = await _pbClient.pb.collection('attachments').getOne(id);
          } catch (_) {
            rethrow;
          }
        } else {
          rethrow;
        }
      }

      // Success: update uploaded_at and server_received_at, delete outbox row (Section 8.5 item 3)
      final serverReceivedAt = serverRecord.data['received_at'] != null
          ? (serverRecord.data['received_at'] as num).toInt()
          : now;

      await (_db.update(_db.attachments)..where((t) => t.id.equals(id))).write(
        db.AttachmentsCompanion(
          uploadedAt: Value(now),
          serverReceivedAt: Value(serverReceivedAt),
          updatedAt: Value(now),
        ),
      );

      await _outboxRepo.deleteEntry(candidate.outboxSeq);
      return const Ok(null);
    } on Object catch (e, stack) {
      final appError = mapClientError(e, stack);

      if (appError.klass == ErrorClass.network || appError.klass == ErrorClass.transient) {
        // Retryable error: compute exponential backoff with jitter and 15 min cap
        final backoff = computeBackoff(
          attempt: candidate.attempts + 1,
          config: BackoffConfig.media,
        );
        await _outboxRepo.recordAttempt(
          seq: candidate.outboxSeq,
          attempts: candidate.attempts + 1,
          nextAttemptAt: now + backoff.inMilliseconds,
          lastError: appError.message,
        );
      } else {
        // Permanent error: park outbox entry
        await _outboxRepo.parkEntry(
          seq: candidate.outboxSeq,
          reason: appError.message,
        );
      }

      return Err(appError);
    } finally {
      _inFlight.remove(id);
    }
  }
}
