import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:tickwalk/core/clock.dart';
import 'package:tickwalk/core/errors.dart';
import 'package:tickwalk/data/db/app_database.dart' hide InspectionItem;
import 'package:tickwalk/data/repositories/inspection_repository.dart';
import 'package:tickwalk/data/repositories/template_repository.dart';
import 'package:tickwalk/domain/models.dart';
import 'package:tickwalk/domain/template_schema.dart';
import 'package:tickwalk/domain/validation.dart';

void main() {
  group('Pure Completion Validation (T8)', () {
    const itemReq = InspectionItem(
      id: 'item_req',
      inspectionId: 'insp_1',
      sectionTitle: 'Safety',
      sectionOrder: 1,
      itemOrder: 1,
      prompt: 'Hard hat worn',
      itemType: ItemType.passFail,
      required: true,
      createdAt: 0,
      updatedAt: 0,
    );

    const itemFailPhoto = InspectionItem(
      id: 'item_fail',
      inspectionId: 'insp_1',
      sectionTitle: 'Safety',
      sectionOrder: 1,
      itemOrder: 2,
      prompt: 'Emergency exit clear',
      itemType: ItemType.passFail,
      required: false,
      photoRequiredOnFail: true,
      response: ItemResponse.fail,
      createdAt: 0,
      updatedAt: 0,
    );

    test('Identifies unanswered required items as blockers', () {
      final blockers = validateCompletion(
        items: [itemReq],
        photoCountByItem: {},
      );

      expect(blockers.length, equals(1));
      expect(blockers.first, isA<UnansweredRequiredBlocker>());
      expect(blockers.first.itemId, equals('item_req'));
      expect(blockers.first.description, contains('Unanswered: Hard hat worn'));
    });

    test('Identifies missing photo on failed item as blocker', () {
      final blockers = validateCompletion(
        items: [itemFailPhoto],
        photoCountByItem: {'item_fail': 0},
      );

      expect(blockers.length, equals(1));
      expect(blockers.first, isA<MissingPhotoBlocker>());
      expect(blockers.first.itemId, equals('item_fail'));
      expect(blockers.first.description, contains('Photo required'));
    });

    test('Resolves blocker when required item answered and photo attached', () {
      final answeredReq = itemReq.copyWith(response: ItemResponse.pass);
      final blockers = validateCompletion(
        items: [answeredReq, itemFailPhoto],
        photoCountByItem: {'item_fail': 1},
      );

      expect(blockers.isEmpty, isTrue);
    });
  });

  group('Repository Completion Enforcement (T8)', () {
    late AppDatabase db;
    late FakeClock clock;
    late TemplateRepository templateRepo;
    late InspectionRepository inspectionRepo;

    setUp(() {
      db = AppDatabase.memory();
      clock = FakeClock(DateTime.utc(2026, 11, 20, 10, 0, 0));
      templateRepo = TemplateRepository(db, clock);
      inspectionRepo = InspectionRepository(db, clock);
    });

    tearDown(() async {
      await db.close();
    });

    test('completeInspection rejected with validation error when blockers exist, succeeds when resolved', () async {
      // 1. Create template with 1 required item and 1 item requiring photo on fail
      final tplRes = await templateRepo.createTemplate(
        name: 'Strict Audit',
        structure: const TemplateStructure(
          schemaVersion: 1,
          sections: [
            TemplateSectionDefinition(
              id: 's1',
              title: 'Section 1',
              items: [
                TemplateItemDefinition(id: 'r1', prompt: 'First Aid Kit Stocked', type: ItemType.passFail, required: true),
                TemplateItemDefinition(id: 'f1', prompt: 'Fire Extinguisher Intact', type: ItemType.passFail, photoRequiredOnFail: true),
              ],
            ),
          ],
        ),
      );
      final tpl = tplRes.valueOrNull!;

      final insp = (await inspectionRepo.startInspection(
        templateId: tpl.id,
        siteName: 'Plant South',
        inspectorName: 'Chief Inspector',
      )).valueOrNull!;

      final items = await (db.select(db.inspectionItems)..where((t) => t.inspectionId.equals(insp.id))).get();
      final reqItem = items.firstWhere((i) => i.required);
      final failPhotoItem = items.firstWhere((i) => i.photoRequiredOnFail);

      // 2. Attempt completion without answering required item -> blocked!
      final completeAttempt1 = await inspectionRepo.completeInspection(insp.id);
      expect(completeAttempt1.isErr, isTrue);
      expect(completeAttempt1.errorOrNull?.klass, equals(ErrorClass.validation));
      expect(completeAttempt1.errorOrNull?.message, contains('Unanswered: First Aid Kit Stocked'));

      // 3. Answer required item, and fail the photo-required item without photo -> blocked!
      await inspectionRepo.updateAnswer(itemId: reqItem.id, response: ItemResponse.pass);
      await inspectionRepo.updateAnswer(itemId: failPhotoItem.id, response: ItemResponse.fail);

      final completeAttempt2 = await inspectionRepo.completeInspection(insp.id);
      expect(completeAttempt2.isErr, isTrue);
      expect(completeAttempt2.errorOrNull?.message, contains('Photo required'));

      // 4. Attach photo to the failed item
      await db.into(db.attachments).insert(
            AttachmentsCompanion.insert(
              id: 'att_proof_1',
              inspectionId: insp.id,
              itemId: Value(failPhotoItem.id),
              kind: 'photo',
              sha256: 'sha_proof',
              bytes: 2048,
              gpsStatus: 'fix',
              capturedAt: clock.nowMillis(),
              createdAt: clock.nowMillis(),
              updatedAt: clock.nowMillis(),
            ),
          );

      // 5. Completion now succeeds!
      final completeSuccess = await inspectionRepo.completeInspection(insp.id);
      expect(completeSuccess.isOk, isTrue);

      final completedInsp = (await inspectionRepo.getInspection(insp.id)).valueOrNull!;
      expect(completedInsp.isCompleted, isTrue);
      expect(completedInsp.completedAt, isNotNull);

      // 6. Completed inspection is read-only
      final editBlocked = await inspectionRepo.updateAnswer(itemId: reqItem.id, response: ItemResponse.fail);
      expect(editBlocked.isErr, isTrue);
      expect(editBlocked.errorOrNull?.klass, equals(ErrorClass.validation));
    });
  });
}
