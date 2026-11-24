import 'dart:convert';
import 'package:drift/drift.dart';

import '../../core/clock.dart';
import '../../domain/models.dart';
import '../db/app_database.dart' as db;
import 'mappers.dart';

class OutboxRepository {
  OutboxRepository(this._db, this._clock);

  final db.AppDatabase _db;
  final Clock _clock;

  /// Returns pending outbox entries ordered strictly by `seq ASC`.
  Future<List<OutboxEntry>> getPendingEntries({
    OutboxLane? lane,
    int? limit,
  }) async {
    final query = _db.select(_db.outbox)
      ..where((t) => t.status.equals('pending'));

    if (lane != null) {
      query.where((t) => t.lane.equals(lane.value));
    }

    query.orderBy([(t) => OrderingTerm.asc(t.seq)]);

    if (limit != null && limit > 0) {
      query.limit(limit);
    }

    final rows = await query.get();
    return rows.map(outboxEntryFromRow).toList();
  }

  /// Watches pending outbox entries ordered by `seq ASC`.
  Stream<List<OutboxEntry>> watchPendingEntries({OutboxLane? lane}) {
    final query = _db.select(_db.outbox)
      ..where((t) => t.status.equals('pending'));

    if (lane != null) {
      query.where((t) => t.lane.equals(lane.value));
    }

    query.orderBy([(t) => OrderingTerm.asc(t.seq)]);

    return query.watch().map((rows) => rows.map(outboxEntryFromRow).toList());
  }

  /// Watches all media outbox entries (pending and parked) for the Uploads queue.
  Stream<List<OutboxEntry>> watchAllMediaEntries() {
    final query = _db.select(_db.outbox)
      ..where((t) => t.lane.equals('media'))
      ..orderBy([(t) => OrderingTerm.asc(t.seq)]);

    return query.watch().map((rows) => rows.map(outboxEntryFromRow).toList());
  }

  /// Watches count of pending outbox entries.
  Stream<int> watchPendingCount({OutboxLane? lane}) {
    final query = _db.selectOnly(_db.outbox)
      ..addColumns([_db.outbox.seq.count()])
      ..where(_db.outbox.status.equals('pending'));

    if (lane != null) {
      query.where(_db.outbox.lane.equals(lane.value));
    }

    return query
        .watchSingle()
        .map((row) => row.read(_db.outbox.seq.count()) ?? 0);
  }

  /// Enqueues a new outbox row.
  Future<int> enqueue({
    required OutboxEntity entity,
    required String entityId,
    required OutboxOp op,
    required String payload,
    OutboxLane lane = OutboxLane.records,
  }) async {
    final now = _clock.nowMillis();
    return _db.into(_db.outbox).insert(
          db.OutboxCompanion.insert(
            entity: entity.value,
            entityId: entityId,
            op: op.value,
            payload: payload,
            lane: Value(lane.value),
            createdAt: now,
          ),
        );
  }

  /// Deletes an outbox entry upon successful sync (Section 8.5 item 3).
  Future<void> deleteEntry(int seq) async {
    await (_db.delete(_db.outbox)..where((t) => t.seq.equals(seq))).go();
  }

  /// Records a retry attempt with computed backoff timestamp.
  Future<void> recordAttempt({
    required int seq,
    required int attempts,
    required int nextAttemptAt,
    String? lastError,
  }) async {
    await (_db.update(_db.outbox)..where((t) => t.seq.equals(seq))).write(
      db.OutboxCompanion(
        attempts: Value(attempts),
        nextAttemptAt: Value(nextAttemptAt),
        lastError: Value(lastError),
      ),
    );
  }

  /// Parks an entry on permanent failure so it does not block the queue.
  Future<void> parkEntry({
    required int seq,
    required String reason,
  }) async {
    await (_db.update(_db.outbox)..where((t) => t.seq.equals(seq))).write(
      db.OutboxCompanion(
        status: const Value('parked'),
        lastError: Value(reason),
      ),
    );
  }

  /// Resets a failed or parked entry so it can be retried immediately.
  Future<void> retryEntry(int seq) async {
    await (_db.update(_db.outbox)..where((t) => t.seq.equals(seq))).write(
      const db.OutboxCompanion(
        status: Value('pending'),
        attempts: Value(0),
        nextAttemptAt: Value(0),
        lastError: Value(null),
      ),
    );
  }

  /// Enqueues all existing local non-deleted data when first signing in (Section 8.6).
  /// Push records, then media, then pull.
  Future<void> enqueueAllLocalData() async {
    final now = _clock.nowMillis();

    // Fetch existing pending outbox keys to prevent duplicates
    final existingPending = await (_db.select(_db.outbox)
          ..where((t) => t.status.equals('pending')))
        .get();
    final existingKeys = existingPending
        .map((e) => '${e.entity}:${e.entityId}:${e.op}')
        .toSet();

    await _db.transaction(() async {
      // 1. Templates (starter and custom)
      final templates = await (_db.select(_db.templates)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();

      for (final t in templates) {
        if (existingKeys.contains('template:${t.id}:create')) continue;
        final payload = jsonEncode({
          'id': t.id,
          'name': t.name,
          'description': t.description,
          'structure': jsonDecode(t.structure),
          'is_starter': t.isStarter,
          'client_updated_at': t.updatedAt,
        });

        await _db.into(_db.outbox).insert(
              db.OutboxCompanion.insert(
                entity: 'template',
                entityId: t.id,
                op: 'create',
                payload: payload,
                lane: const Value('records'),
                createdAt: now,
              ),
            );
      }

      // 2. Inspections
      final inspections = await (_db.select(_db.inspections)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.asc(t.startedAt)]))
          .get();

      for (final insp in inspections) {
        if (existingKeys.contains('inspection:${insp.id}:create')) continue;
        final payload = jsonEncode({
          'id': insp.id,
          'template_id': insp.templateId,
          'template_name': insp.templateName,
          'site_name': insp.siteName,
          'site_address': insp.siteAddress,
          'inspector_name': insp.inspectorName,
          'status': insp.status,
          'started_at': insp.startedAt,
          'completed_at': insp.completedAt,
          'reopened_count': insp.reopenedCount,
          'start_lat': insp.startLat,
          'start_lng': insp.startLng,
          'start_accuracy_m': insp.startAccuracyM,
          'start_gps_status': insp.startGpsStatus,
          'start_gps_at': insp.startGpsAt,
          'signature_attachment_id': insp.signatureAttachmentId,
          'notes': insp.notes,
          'total_items': insp.totalItems,
          'answered_items': insp.answeredItems,
          'pass_count': insp.passCount,
          'fail_count': insp.failCount,
          'na_count': insp.naCount,
          'client_updated_at': insp.updatedAt,
        });

        await _db.into(_db.outbox).insert(
              db.OutboxCompanion.insert(
                entity: 'inspection',
                entityId: insp.id,
                op: 'create',
                payload: payload,
                lane: const Value('records'),
                createdAt: now,
              ),
            );
      }

      // 3. Inspection Items (no deletedAt column in InspectionItems)
      final items = await (_db.select(_db.inspectionItems)
            ..orderBy([
              (t) => OrderingTerm.asc(t.sectionOrder),
              (t) => OrderingTerm.asc(t.itemOrder),
            ]))
          .get();

      for (final item in items) {
        if (existingKeys.contains('inspection_item:${item.id}:create')) continue;
        final payload = jsonEncode({
          'id': item.id,
          'inspection': item.inspectionId,
          'section_title': item.sectionTitle,
          'section_order': item.sectionOrder,
          'item_order': item.itemOrder,
          'prompt': item.prompt,
          'item_type': item.itemType,
          'unit': item.unit,
          'required': item.required,
          'photo_required_on_fail': item.photoRequiredOnFail,
          'response': item.response,
          'severity': item.severity,
          'text_value': item.textValue,
          'number_value': item.numberValue,
          'note': item.note,
          'responded_at': item.respondedAt,
          'client_updated_at': item.updatedAt,
        });

        await _db.into(_db.outbox).insert(
              db.OutboxCompanion.insert(
                entity: 'inspection_item',
                entityId: item.id,
                op: 'create',
                payload: payload,
                lane: const Value('records'),
                createdAt: now,
              ),
            );
      }

      // 4. Attachments where uploaded_at is null
      final attachments = await (_db.select(_db.attachments)
            ..where((t) => t.deletedAt.isNull() & t.uploadedAt.isNull())
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();

      for (final a in attachments) {
        if (existingKeys.contains('attachment:${a.id}:create')) continue;
        final payload = jsonEncode({
          'id': a.id,
          'inspection': a.inspectionId,
          'item': a.itemId,
          'kind': a.kind,
          'sha256': a.sha256,
          'bytes': a.bytes,
          'width': a.width,
          'height': a.height,
          'compression_profile': a.compressionProfile,
          'captured_at': a.capturedAt,
          'gps_lat': a.gpsLat,
          'gps_lng': a.gpsLng,
          'gps_accuracy_m': a.gpsAccuracyM,
          'gps_status': a.gpsStatus,
          'gps_at': a.gpsAt,
          'caption': a.caption,
          'client_updated_at': a.updatedAt,
        });

        await _db.into(_db.outbox).insert(
              db.OutboxCompanion.insert(
                entity: 'attachment',
                entityId: a.id,
                op: 'create',
                payload: payload,
                lane: const Value('media'),
                createdAt: now,
              ),
            );
      }
    });
  }
}
