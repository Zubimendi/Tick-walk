import 'package:drift/drift.dart';

import '../../core/clock.dart';
import '../../core/errors.dart';
import '../../core/ids.dart';
import '../../core/result.dart';
import '../../domain/models.dart';
import '../../domain/template_schema.dart';
import '../db/app_database.dart' as db;
import 'mappers.dart';

class InspectionRepository {
  InspectionRepository(this._db, this._clock);

  final db.AppDatabase _db;
  final Clock _clock;

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
        for (var sIdx = 0; sIdx < structure.sections.length; sIdx++) {
          final section = structure.sections[sIdx];
          for (var iIdx = 0; iIdx < section.items.length; iIdx++) {
            final item = section.items[iIdx];
            await _db.into(_db.inspectionItems).insert(
                  db.InspectionItemsCompanion.insert(
                    id: newId(),
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

    try {
      await (_db.update(_db.inspections)..where((t) => t.id.equals(id))).write(
        db.InspectionsCompanion(
          status: Value(InspectionStatus.inProgress.value),
          reopenedCount: Value(current.reopenedCount + 1),
          updatedAt: Value(now),
        ),
      );
      return const Ok(null);
    } on Object catch (e) {
      return Err(AppError(
        klass: ErrorClass.local,
        message: 'Failed to reopen inspection',
        cause: e,
      ));
    }
  }

  /// Marks an inspection completed and records completed_at.
  Future<Result<void>> completeInspection(String id) async {
    final now = _clock.nowMillis();
    final inspectionRes = await getInspection(id);
    if (inspectionRes.isErr) return Err(inspectionRes.errorOrNull!);

    try {
      await (_db.update(_db.inspections)..where((t) => t.id.equals(id))).write(
        db.InspectionsCompanion(
          status: Value(InspectionStatus.completed.value),
          completedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
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
