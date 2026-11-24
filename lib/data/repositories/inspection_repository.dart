import 'dart:convert';
import 'package:drift/drift.dart';

import '../../core/clock.dart';
import '../../core/errors.dart';
import '../../core/ids.dart';
import '../../core/result.dart';
import '../../domain/models.dart';
import '../../domain/template_schema.dart';
import '../../domain/validation.dart';
import '../db/app_database.dart' as db;
import 'mappers.dart';

class InspectionRepository {
  InspectionRepository(this._db, this._clock);

  final db.AppDatabase _db;
  final Clock _clock;

  /// Returns true when sync_owner_id is set (user is signed in) — Rule 6:
  /// every write also inserts an outbox row in the same transaction.
  Future<bool> _isSignedIn() async {
    final row = await (_db.select(_db.settings)..where((t) => t.key.equals('sync_owner_id'))).getSingleOrNull();
    return row != null && row.value.trim().isNotEmpty;
  }

  Future<void> _enqueueOutbox({
    required String entity,
    required String entityId,
    required String op,
    required Map<String, dynamic> payload,
    String lane = 'records',
    required int now,
  }) async {
    await _db.into(_db.outbox).insert(
          db.OutboxCompanion.insert(
            entity: entity,
            entityId: entityId,
            op: op,
            payload: jsonEncode(payload),
            lane: Value(lane),
            createdAt: now,
          ),
        );
  }

  Stream<List<Inspection>> watchInspections({InspectionStatus? status}) {
    final query = _db.select(_db.inspections)..where((t) => t.deletedAt.isNull());
    if (status != null) {
      query.where((t) => t.status.equals(status.value));
    }
    query.orderBy([(t) => OrderingTerm.desc(t.startedAt)]);
    return query.watch().map((rows) => rows.map(inspectionFromRow).toList());
  }

  Stream<Inspection?> watchInspection(String id) {
    return (_db.select(_db.inspections)..where((t) => t.id.equals(id)))
        .watchSingleOrNull()
        .map((row) => row != null ? inspectionFromRow(row) : null);
  }

  Stream<List<InspectionItem>> watchItems(String inspectionId) {
    return (_db.select(_db.inspectionItems)
          ..where((t) => t.inspectionId.equals(inspectionId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.sectionOrder),
            (t) => OrderingTerm.asc(t.itemOrder),
          ]))
        .watch()
        .map((rows) => rows.map(inspectionItemFromRow).toList());
  }

  Stream<List<Attachment>> watchAttachments(String inspectionId) {
    return (_db.select(_db.attachments)
          ..where((t) => t.inspectionId.equals(inspectionId))
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .watch()
        .map((rows) => rows.map(attachmentFromRow).toList());
  }

  Stream<Map<String, int>> watchPhotoCountByItem(String inspectionId) {
    return (_db.select(_db.attachments)
          ..where((t) => t.inspectionId.equals(inspectionId))
          ..where((t) => t.deletedAt.isNull())
          ..where((t) => t.kind.equals('photo')))
        .watch()
        .map((rows) {
          final counts = <String, int>{};
          for (final row in rows) {
            if (row.itemId != null) {
              counts[row.itemId!] = (counts[row.itemId!] ?? 0) + 1;
            }
          }
          return counts;
        });
  }

  Future<Result<Inspection>> getInspection(String id) async {
    final row = await (_db.select(_db.inspections)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null || row.deletedAt != null) {
      return const Err(AppError(
        klass: ErrorClass.notFound,
        message: 'Inspection not found',
      ));
    }
    return Ok(inspectionFromRow(row));
  }

  /// Invariant: Starting an inspection copies the template into `inspection_items` in ONE transaction.
  /// After this point, editing or deleting the template never alters this inspection.
  Future<Result<Inspection>> startInspection({
    required String templateId,
    required String siteName,
    String? siteAddress,
    required String inspectorName,
    double? startLat,
    double? startLng,
    double? startAccuracyM,
    GpsFixStatus? startGpsStatus,
    int? startGpsAt,
  }) async {
    final now = _clock.nowMillis();
    final inspectionId = newId();

    try {
      final tplRow = await (_db.select(_db.templates)..where((t) => t.id.equals(templateId))).getSingleOrNull();
      if (tplRow == null || tplRow.deletedAt != null) {
        return const Err(AppError(
          klass: ErrorClass.notFound,
          message: 'Template not found to start inspection',
        ));
      }

      final structure = TemplateStructure.parse(tplRow.structure);
      final totalCount = structure.totalItems;

      final signedIn = await _isSignedIn();

      await _db.transaction(() async {
        // 1. Insert Inspection with snapshot of template name
        await _db.into(_db.inspections).insert(
              db.InspectionsCompanion.insert(
                id: inspectionId,
                templateId: Value(templateId),
                templateName: tplRow.name,
                siteName: siteName.trim(),
                siteAddress: Value(siteAddress?.trim()),
                inspectorName: inspectorName.trim(),
                status: InspectionStatus.inProgress.value,
                startedAt: now,
                startLat: Value(startLat),
                startLng: Value(startLng),
                startAccuracyM: Value(startAccuracyM),
                startGpsStatus: Value(startGpsStatus?.value),
                startGpsAt: Value(startGpsAt),
                totalItems: Value(totalCount),
                answeredItems: const Value(0),
                passCount: const Value(0),
                failCount: const Value(0),
                naCount: const Value(0),
                createdAt: now,
                updatedAt: now,
              ),
            );

        // 2. Snapshot template items into inspection_items
        final itemIds = <String>[];
        for (var sIdx = 0; sIdx < structure.sections.length; sIdx++) {
          final section = structure.sections[sIdx];
          for (var iIdx = 0; iIdx < section.items.length; iIdx++) {
            final item = section.items[iIdx];
            final itemId = newId();
            itemIds.add(itemId);
            await _db.into(_db.inspectionItems).insert(
                  db.InspectionItemsCompanion.insert(
                    id: itemId,
                    inspectionId: inspectionId,
                    sectionTitle: section.title,
                    sectionOrder: sIdx,
                    itemOrder: iIdx,
                    prompt: item.prompt,
                    itemType: item.type.value,
                    unit: Value(item.unit),
                    required: Value(item.required),
                    photoRequiredOnFail: Value(item.photoRequiredOnFail),
                    createdAt: now,
                    updatedAt: now,
                  ),
                );
          }
        }

        // 3. Outbox: enqueue inspection create + all items (Rule 6)
        if (signedIn) {
          await _enqueueOutbox(
            entity: 'inspection',
            entityId: inspectionId,
            op: 'create',
            payload: {
              'id': inspectionId,
              'template_id': templateId,
              'template_name': tplRow.name,
              'site_name': siteName.trim(),
              'site_address': siteAddress?.trim(),
              'inspector_name': inspectorName.trim(),
              'status': InspectionStatus.inProgress.value,
              'started_at': now,
              'start_lat': startLat,
              'start_lng': startLng,
              'start_accuracy_m': startAccuracyM,
              'start_gps_status': startGpsStatus?.value,
              'start_gps_at': startGpsAt,
              'total_items': totalCount,
              'answered_items': 0,
              'pass_count': 0,
              'fail_count': 0,
              'na_count': 0,
              'client_updated_at': now,
            },
            now: now,
          );

          // Enqueue items — read back to get the ids we just inserted
          var iGlobal = 0;
          for (var sIdx = 0; sIdx < structure.sections.length; sIdx++) {
            final section = structure.sections[sIdx];
            for (var iIdx = 0; iIdx < section.items.length; iIdx++) {
              final item = section.items[iIdx];
              final itemId = itemIds[iGlobal++];
              await _enqueueOutbox(
                entity: 'inspection_item',
                entityId: itemId,
                op: 'create',
                payload: {
                  'id': itemId,
                  'inspection': inspectionId,
                  'section_title': section.title,
                  'section_order': sIdx,
                  'item_order': iIdx,
                  'prompt': item.prompt,
                  'item_type': item.type.value,
                  'unit': item.unit,
                  'required': item.required,
                  'photo_required_on_fail': item.photoRequiredOnFail,
                  'client_updated_at': now,
                },
                now: now,
              );
            }
          }
        }
      });

      return getInspection(inspectionId);
    } on Object catch (e) {
      return Err(AppError(
        klass: ErrorClass.local,
        message: 'Failed to start inspection',
        cause: e,
      ));
    }
  }

  /// Invariant: Every answer mutation recalculates the inspection's cached counts
  /// in the exact same Drift transaction.
  /// Invariant: Completed inspections reject writes until reopened.
  Future<Result<void>> updateAnswer({
    required String itemId,
    ItemResponse? response,
    Severity? severity,
    String? textValue,
    double? numberValue,
    String? note,
  }) async {
    final now = _clock.nowMillis();

    try {
      final itemRow = await (_db.select(_db.inspectionItems)..where((t) => t.id.equals(itemId))).getSingleOrNull();
      if (itemRow == null) {
        return const Err(AppError(
          klass: ErrorClass.notFound,
          message: 'Item not found',
        ));
      }

      final inspectionRow = await (_db.select(_db.inspections)..where((t) => t.id.equals(itemRow.inspectionId))).getSingleOrNull();
      if (inspectionRow == null) {
        return const Err(AppError(
          klass: ErrorClass.notFound,
          message: 'Inspection not found for item',
        ));
      }

      // Read-only check
      if (inspectionRow.status == InspectionStatus.completed.value) {
        return const Err(AppError(
          klass: ErrorClass.validation,
          message: 'Inspection is completed and read-only. Reopen to edit.',
        ));
      }

      final signedIn = await _isSignedIn();

      await _db.transaction(() async {
        // 1. Update the item
        await (_db.update(_db.inspectionItems)..where((t) => t.id.equals(itemId))).write(
          db.InspectionItemsCompanion(
            response: Value(response?.value),
            severity: Value(severity?.value),
            textValue: Value(textValue),
            numberValue: Value(numberValue),
            note: Value(note),
            respondedAt: Value(now),
            updatedAt: Value(now),
          ),
        );

        // 2. Recompute summary counts from items
        await _recomputeSummaryInsideTx(itemRow.inspectionId, now);

        // 3. Outbox: enqueue item update (Rule 6)
        if (signedIn) {
          await _enqueueOutbox(
            entity: 'inspection_item',
            entityId: itemId,
            op: 'update',
            payload: {
              'response': response?.value,
              'severity': severity?.value,
              'text_value': textValue,
              'number_value': numberValue,
              'note': note,
              'responded_at': now,
              'client_updated_at': now,
            },
            now: now,
          );
        }
      });

      return const Ok(null);
    } on Object catch (e) {
      return Err(AppError(
        klass: ErrorClass.local,
        message: 'Failed to update item answer',
        cause: e,
      ));
    }
  }

  /// Reopens a completed inspection, locking status to in_progress and incrementing reopened_count.
  Future<Result<void>> reopenInspection(String id) async {
    final now = _clock.nowMillis();
    final inspectionRes = await getInspection(id);
    if (inspectionRes.isErr) return Err(inspectionRes.errorOrNull!);

    final current = inspectionRes.valueOrNull!;
    if (current.status == InspectionStatus.inProgress) {
      return const Ok(null);
    }

    final signedIn = await _isSignedIn();

    try {
      await _db.transaction(() async {
        await (_db.update(_db.inspections)..where((t) => t.id.equals(id))).write(
          db.InspectionsCompanion(
            status: Value(InspectionStatus.inProgress.value),
            reopenedCount: Value(current.reopenedCount + 1),
            updatedAt: Value(now),
          ),
        );
        if (signedIn) {
          await _enqueueOutbox(
            entity: 'inspection',
            entityId: id,
            op: 'update',
            payload: {
              'status': InspectionStatus.inProgress.value,
              'reopened_count': current.reopenedCount + 1,
              'client_updated_at': now,
            },
            now: now,
          );
        }
      });
      return const Ok(null);
    } on Object catch (e) {
      return Err(AppError(
        klass: ErrorClass.local,
        message: 'Failed to reopen inspection',
        cause: e,
      ));
    }
  }

  /// Validates whether an inspection can be marked completed.
  /// Returns the list of blockers (if any).
  Future<Result<List<CompletionBlocker>>> validateCanComplete(String id) async {
    try {
      final itemsRows = await (_db.select(_db.inspectionItems)..where((t) => t.inspectionId.equals(id))).get();
      final items = itemsRows.map(inspectionItemFromRow).toList();

      final attRows = await (_db.select(_db.attachments)
            ..where((t) => t.inspectionId.equals(id))
            ..where((t) => t.deletedAt.isNull())
            ..where((t) => t.kind.equals('photo')))
          .get();

      final photoCountMap = <String, int>{};
      for (final att in attRows) {
        if (att.itemId != null) {
          photoCountMap[att.itemId!] = (photoCountMap[att.itemId!] ?? 0) + 1;
        }
      }

      final blockers = validateCompletion(
        items: items,
        photoCountByItem: photoCountMap,
      );

      return Ok(blockers);
    } on Object catch (e) {
      return Err(AppError(
        klass: ErrorClass.local,
        message: 'Failed to validate completion',
        cause: e,
      ));
    }
  }

  /// Marks an inspection completed and records completed_at.
  /// Rejects completion if any validation blockers exist.
  Future<Result<void>> completeInspection(String id) async {
    final now = _clock.nowMillis();
    final inspectionRes = await getInspection(id);
    if (inspectionRes.isErr) return Err(inspectionRes.errorOrNull!);

    // Run completion validation
    final validationRes = await validateCanComplete(id);
    if (validationRes.isErr) return Err(validationRes.errorOrNull!);

    final blockers = validationRes.valueOrNull!;
    if (blockers.isNotEmpty) {
      final reasons = blockers.map((b) => b.description).join('; ');
      return Err(AppError(
        klass: ErrorClass.validation,
        message: 'Cannot complete inspection: $reasons',
        cause: blockers,
      ));
    }

    try {
      final signedIn = await _isSignedIn();
      await _db.transaction(() async {
        await (_db.update(_db.inspections)..where((t) => t.id.equals(id))).write(
          db.InspectionsCompanion(
            status: Value(InspectionStatus.completed.value),
            completedAt: Value(now),
            updatedAt: Value(now),
          ),
        );
        if (signedIn) {
          await _enqueueOutbox(
            entity: 'inspection',
            entityId: id,
            op: 'update',
            payload: {
              'status': InspectionStatus.completed.value,
              'completed_at': now,
              'client_updated_at': now,
            },
            now: now,
          );
        }
      });
      return const Ok(null);
    } on Object catch (e) {
      return Err(AppError(
        klass: ErrorClass.local,
        message: 'Failed to complete inspection',
        cause: e,
      ));
    }
  }

  /// Internal helper: recomputes answered, pass, fail, na counts in-transaction.
  Future<void> _recomputeSummaryInsideTx(String inspectionId, int now) async {
    final allItems = await (_db.select(_db.inspectionItems)..where((t) => t.inspectionId.equals(inspectionId))).get();

    var answered = 0;
    var pass = 0;
    var fail = 0;
    var na = 0;

    for (final it in allItems) {
      final domainItem = inspectionItemFromRow(it);
      if (domainItem.isAnswered) {
        answered++;
      }
      if (it.response == 'pass') pass++;
      if (it.response == 'fail') fail++;
      if (it.response == 'na') na++;
    }

    await (_db.update(_db.inspections)..where((t) => t.id.equals(inspectionId))).write(
      db.InspectionsCompanion(
        totalItems: Value(allItems.length),
        answeredItems: Value(answered),
        passCount: Value(pass),
        failCount: Value(fail),
        naCount: Value(na),
        updatedAt: Value(now),
      ),
    );
  }
}
