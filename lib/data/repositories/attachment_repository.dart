import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';

import '../../core/clock.dart';
import '../../core/errors.dart';
import '../../core/result.dart';
import '../../domain/models.dart';
import '../db/app_database.dart' as db;
import 'mappers.dart';

class AttachmentRepository {
  AttachmentRepository(this._db, this._clock);

  final db.AppDatabase _db;
  final Clock _clock;

  Stream<List<Attachment>> watchAttachments(String inspectionId) {
    return (_db.select(_db.attachments)
          ..where((t) => t.inspectionId.equals(inspectionId))
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .watch()
        .map((rows) => rows.map(attachmentFromRow).toList());
  }

  Stream<List<Attachment>> watchItemAttachments(String itemId) {
    return (_db.select(_db.attachments)
          ..where((t) => t.itemId.equals(itemId))
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .watch()
        .map((rows) => rows.map(attachmentFromRow).toList());
  }

  Future<Result<Attachment>> getAttachment(String id) async {
    final row = await (_db.select(_db.attachments)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();

    if (row == null || row.deletedAt != null) {
      return const Err(AppError(
        klass: ErrorClass.notFound,
        message: 'Attachment not found',
      ));
    }
    return Ok(attachmentFromRow(row));
  }

  /// Inserts a newly captured photo attachment.
  /// Enforces:
  /// 1. Local file must exist on disk before DB insert (Rule 4).
  /// 2. Parent inspection must exist and not be completed (read-only enforcement).
  /// 3. One Drift transaction: attachment row + outbox row (if signed in).
  Future<Result<Attachment>> insertPhotoAttachment({
    required String id,
    required String inspectionId,
    String? itemId,
    required String localPath,
    required String thumbPath,
    required String sha256,
    required int bytes,
    int? width,
    int? height,
    required String compressionProfile,
    required int capturedAt,
    double? gpsLat,
    double? gpsLng,
    double? gpsAccuracyM,
    required GpsFixStatus gpsStatus,
    int? gpsAt,
    String? caption,
  }) async {
    // 1. Invariant: Never insert a database row for a file that does not exist on disk
    if (!File(localPath).existsSync()) {
      return Err(AppError(
        klass: ErrorClass.local,
        message: 'Cannot insert attachment: file does not exist on disk at $localPath',
      ));
    }

    final inspectionRow = await (_db.select(_db.inspections)
          ..where((t) => t.id.equals(inspectionId)))
        .getSingleOrNull();

    if (inspectionRow == null || inspectionRow.deletedAt != null) {
      return const Err(AppError(
        klass: ErrorClass.notFound,
        message: 'Parent inspection not found',
      ));
    }

    if (inspectionRow.status == 'completed') {
      return const Err(AppError(
        klass: ErrorClass.forbidden,
        message: 'Inspection is completed and read-only. Reopen to add photos.',
      ));
    }

    final now = _clock.nowMillis();

    // Check if user is signed in to queue outbox entry
    final syncOwner = await (_db.select(_db.settings)
          ..where((t) => t.key.equals('sync_owner_id')))
        .getSingleOrNull();
    final isSignedIn = syncOwner != null && syncOwner.value.trim().isNotEmpty;

    try {
      final companion = db.AttachmentsCompanion.insert(
        id: id,
        inspectionId: inspectionId,
        itemId: Value(itemId),
        kind: 'photo',
        localPath: Value(localPath),
        thumbPath: Value(thumbPath),
        sha256: sha256,
        bytes: bytes,
        width: Value(width),
        height: Value(height),
        compressionProfile: Value(compressionProfile),
        capturedAt: capturedAt,
        gpsLat: Value(gpsLat),
        gpsLng: Value(gpsLng),
        gpsAccuracyM: Value(gpsAccuracyM),
        gpsStatus: gpsStatus.value,
        gpsAt: Value(gpsAt),
        caption: Value(caption),
        createdAt: now,
        updatedAt: now,
      );

      await _db.transaction(() async {
        await _db.into(_db.attachments).insert(companion);

        if (isSignedIn) {
          final payload = jsonEncode({
            'id': id,
            'inspection_id': inspectionId,
            'item_id': itemId,
            'kind': 'photo',
            'hash': sha256,
            'bytes': bytes,
            'width': width,
            'height': height,
            'compression_profile': compressionProfile,
            'captured_at': capturedAt,
            'lat': gpsLat,
            'lng': gpsLng,
            'accuracy_m': gpsAccuracyM,
            'gps_status': gpsStatus.value,
            'gps_at': gpsAt,
            'caption': caption,
            'created_at': now,
            'updated_at': now,
          });

          await _db.into(_db.outbox).insert(
                db.OutboxCompanion.insert(
                  entity: 'attachment',
                  entityId: id,
                  op: 'create',
                  payload: payload,
                  lane: const Value('media'),
                  createdAt: now,
                ),
              );
        }
      });

      final inserted = await (_db.select(_db.attachments)
            ..where((t) => t.id.equals(id)))
          .getSingle();

      return Ok(attachmentFromRow(inserted));
    } on Object catch (e) {
      return Err(AppError(
        klass: ErrorClass.local,
        message: 'Failed to insert attachment row',
        cause: e,
      ));
    }
  }

  /// Soft-deletes an attachment and records outbox op if signed in.
  Future<Result<void>> deleteAttachment(String id) async {
    final attRes = await getAttachment(id);
    if (attRes.isErr) return Err(attRes.errorOrNull!);

    final att = attRes.valueOrNull!;

    // Check inspection status
    final inspectionRow = await (_db.select(_db.inspections)
          ..where((t) => t.id.equals(att.inspectionId)))
        .getSingleOrNull();

    if (inspectionRow?.status == 'completed') {
      return const Err(AppError(
        klass: ErrorClass.forbidden,
        message: 'Inspection is completed and read-only. Reopen to delete photos.',
      ));
    }

    final now = _clock.nowMillis();

    final syncOwner = await (_db.select(_db.settings)
          ..where((t) => t.key.equals('sync_owner_id')))
        .getSingleOrNull();
    final isSignedIn = syncOwner != null && syncOwner.value.trim().isNotEmpty;

    try {
      await _db.transaction(() async {
        await (_db.update(_db.attachments)..where((t) => t.id.equals(id))).write(
          db.AttachmentsCompanion(
            deletedAt: Value(now),
            updatedAt: Value(now),
          ),
        );

        if (isSignedIn) {
          // If already synced, queue delete in Lane 1 (records)
          await _db.into(_db.outbox).insert(
                db.OutboxCompanion.insert(
                  entity: 'attachment',
                  entityId: id,
                  op: 'delete',
                  payload: jsonEncode({'id': id, 'deleted_at': now}),
                  lane: const Value('records'),
                  createdAt: now,
                ),
              );
        }
      });

      return const Ok(null);
    } on Object catch (e) {
      return Err(AppError(
        klass: ErrorClass.local,
        message: 'Failed to delete attachment',
        cause: e,
      ));
    }
  }

  /// Restores a soft-deleted attachment (for undo).
  Future<Result<void>> restoreAttachment(String id) async {
    final now = _clock.nowMillis();
    try {
      await (_db.update(_db.attachments)..where((t) => t.id.equals(id))).write(
        db.AttachmentsCompanion(
          deletedAt: const Value(null),
          updatedAt: Value(now),
        ),
      );
      return const Ok(null);
    } on Object catch (e) {
      return Err(AppError(
        klass: ErrorClass.local,
        message: 'Failed to restore attachment',
        cause: e,
      ));
    }
  }

  /// Updates caption on an attachment.
  Future<Result<void>> updateCaption(String id, String? caption) async {
    final attRes = await getAttachment(id);
    if (attRes.isErr) return Err(attRes.errorOrNull!);

    final now = _clock.nowMillis();
    try {
      await (_db.update(_db.attachments)..where((t) => t.id.equals(id))).write(
        db.AttachmentsCompanion(
          caption: Value(caption?.trim()),
          updatedAt: Value(now),
        ),
      );
      return const Ok(null);
    } on Object catch (e) {
      return Err(AppError(
        klass: ErrorClass.local,
        message: 'Failed to update caption',
        cause: e,
      ));
    }
  }
}
