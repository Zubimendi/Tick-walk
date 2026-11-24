import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../core/clock.dart';
import '../../core/errors.dart';
import '../../core/result.dart';
import '../../domain/models.dart';
import '../api/error_mapper.dart';
import '../api/pb_client.dart';
import '../db/app_database.dart' as db;
import '../repositories/outbox_repository.dart';
import 'backoff.dart';
import 'outbox_coalescing.dart';

/// Report summarizing a record lane synchronization cycle.
class SyncReport {
  const SyncReport({
    required this.pushed,
    required this.pulled,
  });

  final int pushed;
  final int pulled;
}

/// Lane 1 (Records): Handles strictly ordered JSON synchronization
/// (templates, inspections, inspection items, attachment metadata).
/// Invariant: Parents before children, coalesced mutations, stops on retryable errors,
/// parks permanent errors, resolves 409 stale_write via LWW (Section 8.2 & 8.8).
class RecordLane {
  RecordLane({
    required PbClient pbClient,
    required db.AppDatabase db,
    required OutboxRepository outboxRepo,
    required Clock clock,
  })  : _pbClient = pbClient,
        _db = db,
        _outboxRepo = outboxRepo,
        _clock = clock;

  final PbClient _pbClient;
  final db.AppDatabase _db;
  final OutboxRepository _outboxRepo;
  final Clock _clock;

  /// Returns collection name in PocketBase for a given domain [OutboxEntity].
  static String collectionFor(OutboxEntity entity) {
    switch (entity) {
      case OutboxEntity.template:
        return 'templates';
      case OutboxEntity.inspection:
        return 'inspections';
      case OutboxEntity.inspectionItem:
        return 'inspection_items';
      case OutboxEntity.attachment:
        return 'attachments';
    }
  }

  /// Drains pending record operations in strict seq order with outbox coalescing.
  /// Stops on retryable errors, parks permanent errors.
  Future<Result<int>> drain() async {
    if (!_pbClient.authStore.isValid) {
      return const Ok(0);
    }

    final rawEntries = await _outboxRepo.getPendingEntries(lane: OutboxLane.records);
    if (rawEntries.isEmpty) {
      return const Ok(0);
    }

    final now = _clock.nowMillis();
    final coalesced = coalesceOutbox(rawEntries);

    var pushedCount = 0;

    for (final entry in coalesced) {
      // Check if entry is waiting for backoff
      if (entry.nextAttemptAt > now) {
        // Strict sequence ordering: stop drain when encountering waiting backoff
        break;
      }

      final collection = collectionFor(entry.entity);
      Map<String, dynamic> payload = {};
      try {
        if (entry.payload.isNotEmpty) {
          payload = jsonDecode(entry.payload) as Map<String, dynamic>;
        }
      } catch (_) {}

      try {
        if (entry.op == OutboxOp.create) {
          await _executeCreate(collection, entry.entityId, payload);
        } else if (entry.op == OutboxOp.update) {
          await _executeUpdate(entry.entity, collection, entry.entityId, payload);
        } else if (entry.op == OutboxOp.delete) {
          await _executeDelete(collection, entry.entityId);
        }

        // On success: delete all underlying outbox rows for this entity up to this seq
        final matchingEntries = rawEntries
            .where((e) => e.entity == entry.entity && e.entityId == entry.entityId && e.seq <= entry.seq);
        for (final m in matchingEntries) {
          await _outboxRepo.deleteEntry(m.seq);
        }
        pushedCount++;
      } on Object catch (e, stack) {
        final appError = mapClientError(e, stack);

        if (appError.klass == ErrorClass.network || appError.klass == ErrorClass.transient) {
          // Retryable error: apply exponential backoff and STOP drain
          final backoff = computeBackoff(
            attempt: entry.attempts + 1,
            config: BackoffConfig.records,
          );
          await _outboxRepo.recordAttempt(
            seq: entry.seq,
            attempts: entry.attempts + 1,
            nextAttemptAt: now + backoff.inMilliseconds,
            lastError: appError.message,
          );
          return Err(appError);
        } else if (appError.klass == ErrorClass.auth) {
          // Session expired: stop drain
          return Err(appError);
        } else {
          // Permanent failure (validation, forbidden, tooLarge): Park entry and continue
          await _outboxRepo.parkEntry(
            seq: entry.seq,
            reason: appError.message,
          );
        }
      }
    }

    return Ok(pushedCount);
  }

  Future<void> _executeCreate(String collection, String id, Map<String, dynamic> payload) async {
    try {
      final body = Map<String, dynamic>.from(payload);
      if (!body.containsKey('id')) {
        body['id'] = id;
      }
      await _pbClient.pb.collection(collection).create(body: body);
    } on ClientException catch (e) {
      if (e.statusCode == 400) {
        // Check for duplicate create: if record exists on server, treat as success
        try {
          await _pbClient.pb.collection(collection).getOne(id);
          return;
        } catch (_) {
          rethrow;
        }
      }
      rethrow;
    }
  }

  Future<void> _executeUpdate(
    OutboxEntity entity,
    String collection,
    String id,
    Map<String, dynamic> payload,
  ) async {
    try {
      await _pbClient.pb.collection(collection).update(id, body: payload);
    } on ClientException catch (e) {
      if (e.statusCode == 409) {
        // 409 stale_write conflict: server has a newer version.
        // Resolve conflict by pulling server record and applying LWW to local Drift DB.
        final serverRec = await _pbClient.pb.collection(collection).getOne(id);
        await _applyServerRecord(entity, serverRec.data, {});
        return;
      }
      rethrow;
    }
  }

  Future<void> _executeDelete(String collection, String id) async {
    try {
      await _pbClient.pb.collection(collection).delete(id);
    } on ClientException catch (e) {
      if (e.statusCode == 404) {
        // 404 on delete treated as success (Section 10)
        return;
      }
      rethrow;
    }
  }

  /// Pulls remote changes from PocketBase using cursors per collection (Section 8.7).
  /// Skips entities with pending outbox ops; applies tombstones and recomputes counts.
  Future<Result<int>> pull() async {
    if (!_pbClient.authStore.isValid) {
      return const Ok(0);
    }

    try {
      var pulledTotal = 0;
      final pendingRows = await (_db.select(_db.outbox)
            ..where((t) => t.status.equals('pending')))
          .get();
      final pendingEntityIds = pendingRows.map((e) => e.entityId).toSet();

      final affectedInspectionIds = <String>{};

      // Pull each collection in dependency order: templates, inspections, items, attachments
      for (final entity in [
        OutboxEntity.template,
        OutboxEntity.inspection,
        OutboxEntity.inspectionItem,
        OutboxEntity.attachment,
      ]) {
        final collection = collectionFor(entity);
        final cursorKey = 'cursor:$collection';
        final cursorRow = await (_db.select(_db.syncState)..where((t) => t.key.equals(cursorKey))).getSingleOrNull();
        var cursor = cursorRow?.value ?? '';

        var page = 1;
        var hasMore = true;

        while (hasMore) {
          final filter = cursor.isNotEmpty ? 'updated >= "$cursor"' : '';
          final result = await _pbClient.pb.collection(collection).getList(
                page: page,
                perPage: 200,
                sort: '+updated,+id',
                filter: filter,
              );

          await _db.transaction(() async {
            for (final item in result.items) {
              if (pendingEntityIds.contains(item.id)) {
                // Skip entity with pending local changes
                continue;
              }

              await _applyServerRecord(entity, item.data, affectedInspectionIds);
              cursor = item.get<String>('updated');
              pulledTotal++;
            }

            if (cursor.isNotEmpty) {
              await _db.into(_db.syncState).insertOnConflictUpdate(
                    db.SyncStateCompanion.insert(
                      key: cursorKey,
                      value: cursor,
                    ),
                  );
            }
          });

          if (result.items.length < 200 || result.page >= result.totalPages) {
            hasMore = false;
          } else {
            page++;
          }
        }
      }

      // Recompute affected inspections
      for (final inspId in affectedInspectionIds) {
        await _recomputeInspectionCounts(inspId);
      }

      return Ok(pulledTotal);
    } on Object catch (e, stack) {
      return Err(mapClientError(e, stack));
    }
  }

  /// Synchronizes records: pushes pending outbox mutations then pulls remote changes.
  Future<Result<SyncReport>> syncRecords() async {
    final drainRes = await drain();
    if (drainRes.isErr) return Err(drainRes.errorOrNull!);

    final pullRes = await pull();
    if (pullRes.isErr) return Err(pullRes.errorOrNull!);

    return Ok(SyncReport(
      pushed: drainRes.valueOrNull!,
      pulled: pullRes.valueOrNull!,
    ));
  }

  Future<void> _applyServerRecord(
    OutboxEntity entity,
    Map<String, dynamic> data,
    Set<String> affectedInspections,
  ) async {
    final id = data['id'] as String;
    final deletedAt = data['deleted_at'] as int?;
    final updatedAt = (data['client_updated_at'] as num?)?.toInt() ?? _clock.nowMillis();

    switch (entity) {
      case OutboxEntity.template:
        if (deletedAt != null) {
          await (_db.update(_db.templates)..where((t) => t.id.equals(id))).write(
            db.TemplatesCompanion(
              deletedAt: Value(deletedAt),
              updatedAt: Value(updatedAt),
            ),
          );
        } else {
          final structureJson = data['structure'] is String
              ? data['structure'] as String
              : jsonEncode(data['structure'] ?? {});
          await _db.into(_db.templates).insertOnConflictUpdate(
                db.TemplatesCompanion.insert(
                  id: id,
                  name: (data['name'] as String?) ?? 'Untitled Template',
                  description: Value(data['description'] as String?),
                  structure: structureJson,
                  isStarter: Value((data['is_starter'] as bool?) ?? false),
                  createdAt: updatedAt,
                  updatedAt: updatedAt,
                ),
              );
        }
        break;

      case OutboxEntity.inspection:
        if (deletedAt != null) {
          await (_db.update(_db.inspections)..where((t) => t.id.equals(id))).write(
            db.InspectionsCompanion(
              deletedAt: Value(deletedAt),
              updatedAt: Value(updatedAt),
            ),
          );
        } else {
          await _db.into(_db.inspections).insertOnConflictUpdate(
                db.InspectionsCompanion.insert(
                  id: id,
                  templateId: Value(data['template_id'] as String?),
                  templateName: (data['template_name'] as String?) ?? '',
                  siteName: (data['site_name'] as String?) ?? '',
                  siteAddress: Value(data['site_address'] as String?),
                  inspectorName: (data['inspector_name'] as String?) ?? '',
                  status: (data['status'] as String?) ?? 'in_progress',
                  startedAt: (data['started_at'] as num?)?.toInt() ?? updatedAt,
                  completedAt: Value((data['completed_at'] as num?)?.toInt()),
                  reopenedCount: Value((data['reopened_count'] as num?)?.toInt() ?? 0),
                  startLat: Value((data['start_lat'] as num?)?.toDouble()),
                  startLng: Value((data['start_lng'] as num?)?.toDouble()),
                  startAccuracyM: Value((data['start_accuracy_m'] as num?)?.toDouble()),
                  startGpsStatus: Value(data['start_gps_status'] as String?),
                  startGpsAt: Value((data['start_gps_at'] as num?)?.toInt()),
                  signatureAttachmentId: Value(data['signature_attachment_id'] as String?),
                  notes: Value(data['notes'] as String?),
                  totalItems: Value((data['total_items'] as num?)?.toInt() ?? 0),
                  answeredItems: Value((data['answered_items'] as num?)?.toInt() ?? 0),
                  passCount: Value((data['pass_count'] as num?)?.toInt() ?? 0),
                  failCount: Value((data['fail_count'] as num?)?.toInt() ?? 0),
                  naCount: Value((data['na_count'] as num?)?.toInt() ?? 0),
                  createdAt: updatedAt,
                  updatedAt: updatedAt,
                ),
              );
        }
        break;

      case OutboxEntity.inspectionItem:
        final inspectionId = (data['inspection'] as String?) ?? '';
        if (inspectionId.isNotEmpty) {
          affectedInspections.add(inspectionId);
        }

        // InspectionItems have no deletedAt column; if server tombstones an item,
        // skip it (the inspection-level delete handles cleanup).
        if (deletedAt == null) {
          await _db.into(_db.inspectionItems).insertOnConflictUpdate(
                db.InspectionItemsCompanion.insert(
                  id: id,
                  inspectionId: inspectionId,
                  sectionTitle: (data['section_title'] as String?) ?? '',
                  sectionOrder: (data['section_order'] as num?)?.toInt() ?? 0,
                  itemOrder: (data['item_order'] as num?)?.toInt() ?? 0,
                  prompt: (data['prompt'] as String?) ?? '',
                  itemType: (data['item_type'] as String?) ?? 'yes_no_na',
                  unit: Value(data['unit'] as String?),
                  required: Value((data['required'] as bool?) ?? false),
                  photoRequiredOnFail: Value((data['photo_required_on_fail'] as bool?) ?? false),
                  response: Value(data['response'] as String?),
                  severity: Value(data['severity'] as String?),
                  textValue: Value(data['text_value'] as String?),
                  numberValue: Value((data['number_value'] as num?)?.toDouble()),
                  note: Value(data['note'] as String?),
                  respondedAt: Value((data['responded_at'] as num?)?.toInt()),
                  createdAt: updatedAt,
                  updatedAt: updatedAt,
                ),
              );
        }
        break;

      case OutboxEntity.attachment:
        if (deletedAt != null) {
          await (_db.update(_db.attachments)..where((t) => t.id.equals(id))).write(
            db.AttachmentsCompanion(
              deletedAt: Value(deletedAt),
              updatedAt: Value(updatedAt),
            ),
          );
        } else {
          // Server-pulled attachment: local files are null (Section 8.7)
          await _db.into(_db.attachments).insertOnConflictUpdate(
                db.AttachmentsCompanion.insert(
                  id: id,
                  inspectionId: (data['inspection'] as String?) ?? '',
                  itemId: Value(data['item'] as String?),
                  kind: (data['kind'] as String?) ?? 'photo',
                  localPath: const Value(null),
                  thumbPath: const Value(null),
                  sha256: (data['sha256'] as String?) ?? '',
                  bytes: (data['bytes'] as num?)?.toInt() ?? 0,
                  width: Value((data['width'] as num?)?.toInt()),
                  height: Value((data['height'] as num?)?.toInt()),
                  compressionProfile: Value(data['compression_profile'] as String?),
                  capturedAt: (data['captured_at'] as num?)?.toInt() ?? updatedAt,
                  gpsLat: Value((data['gps_lat'] as num?)?.toDouble()),
                  gpsLng: Value((data['gps_lng'] as num?)?.toDouble()),
                  gpsAccuracyM: Value((data['gps_accuracy_m'] as num?)?.toDouble()),
                  gpsStatus: (data['gps_status'] as String?) ?? 'none',
                  gpsAt: Value((data['gps_at'] as num?)?.toInt()),
                  caption: Value(data['caption'] as String?),
                  serverReceivedAt: Value((data['received_at'] as num?)?.toInt()),
                  uploadedAt: Value(updatedAt),
                  createdAt: updatedAt,
                  updatedAt: updatedAt,
                ),
              );
        }
        break;
    }
  }

  Future<void> _recomputeInspectionCounts(String inspectionId) async {
    // InspectionItems has no deletedAt — filter only by inspectionId
    final items = await (_db.select(_db.inspectionItems)
          ..where((t) => t.inspectionId.equals(inspectionId)))
        .get();

    var answered = 0;
    var pass = 0;
    var fail = 0;
    var na = 0;

    for (final item in items) {
      if (item.response != null) answered++;
      if (item.response == 'pass') pass++;
      if (item.response == 'fail') fail++;
      if (item.response == 'na') na++;
    }

    await (_db.update(_db.inspections)..where((t) => t.id.equals(inspectionId))).write(
      db.InspectionsCompanion(
        totalItems: Value(items.length),
        answeredItems: Value(answered),
        passCount: Value(pass),
        failCount: Value(fail),
        naCount: Value(na),
      ),
    );
  }
}
