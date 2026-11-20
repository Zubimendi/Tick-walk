import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:tickwalk/core/clock.dart';
import 'package:tickwalk/core/errors.dart';
import 'package:tickwalk/data/db/app_database.dart';
import 'package:tickwalk/data/repositories/inspection_repository.dart';
import 'package:tickwalk/data/repositories/template_repository.dart';
import 'package:tickwalk/domain/models.dart';
import 'package:tickwalk/domain/template_schema.dart';

void main() {
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

  group('Template & Inspection Repositories (T7)', () {
    test('Template snapshot isolation: modifying template never alters started inspection', () async {
      // 1. Create a template
      final tplRes = await templateRepo.createTemplate(
        name: 'Initial Safety Check',
        structure: const TemplateStructure(
          schemaVersion: 1,
          sections: [
            TemplateSectionDefinition(
              id: 's1',
              title: 'Section A',
              items: [
                TemplateItemDefinition(id: 'i1', prompt: 'Original Prompt 1', type: ItemType.passFail),
                TemplateItemDefinition(id: 'i2', prompt: 'Original Prompt 2', type: ItemType.text),
              ],
            ),
          ],
        ),
      );
      expect(tplRes.isOk, isTrue);
      final tpl = tplRes.valueOrNull!;

      // 2. Start inspection from template
      final inspRes = await inspectionRepo.startInspection(
        templateId: tpl.id,
        siteName: 'Warehouse 12',
        inspectorName: 'Bob Inspector',
      );
      expect(inspRes.isOk, isTrue);
      final inspection = inspRes.valueOrNull!;
      expect(inspection.templateName, equals('Initial Safety Check'));
      expect(inspection.totalItems, equals(2));

      // 3. Mutate template: update prompt and name, or delete it
      await templateRepo.updateTemplate(
        id: tpl.id,
        name: 'Updated Safety Check Name',
        structure: const TemplateStructure(
          schemaVersion: 1,
          sections: [
            TemplateSectionDefinition(
              id: 's1',
              title: 'Section A',
              items: [
                TemplateItemDefinition(id: 'i1', prompt: 'Completely Changed Prompt', type: ItemType.passFail),
              ],
            ),
          ],
        ),
      );
      await templateRepo.deleteTemplate(tpl.id);

      // 4. Assert inspection and its snapshot items remain completely untouched!
      final reloadedInsp = (await inspectionRepo.getInspection(inspection.id)).valueOrNull!;
      expect(reloadedInsp.templateName, equals('Initial Safety Check'));
      expect(reloadedInsp.totalItems, equals(2));

      final items = await (db.select(db.inspectionItems)..where((t) => t.inspectionId.equals(inspection.id))).get();
      expect(items.length, equals(2));
      expect(items[0].prompt, equals('Original Prompt 1'));
      expect(items[1].prompt, equals('Original Prompt 2'));
    });

    test('Summary recompute consistency: in-transaction counts equal brute-force over random answer sequences', () async {
      // Create template with 5 mixed items
      final tplRes = await templateRepo.createTemplate(
        name: 'Multi-item Template',
        structure: const TemplateStructure(
          schemaVersion: 1,
          sections: [
            TemplateSectionDefinition(
              id: 's1',
              title: 'Section 1',
              items: [
                TemplateItemDefinition(id: 'pf1', prompt: 'Item 1', type: ItemType.passFail),
                TemplateItemDefinition(id: 'pf2', prompt: 'Item 2', type: ItemType.passFail),
                TemplateItemDefinition(id: 'pf3', prompt: 'Item 3', type: ItemType.passFail),
                TemplateItemDefinition(id: 't1', prompt: 'Item 4', type: ItemType.text),
                TemplateItemDefinition(id: 'n1', prompt: 'Item 5', type: ItemType.number, unit: 'bar'),
              ],
            ),
          ],
        ),
      );
      final tpl = tplRes.valueOrNull!;

      final inspRes = await inspectionRepo.startInspection(
        templateId: tpl.id,
        siteName: 'Site Delta',
        inspectorName: 'Sam Inspector',
      );
      final inspection = inspRes.valueOrNull!;

      final items = await (db.select(db.inspectionItems)..where((t) => t.inspectionId.equals(inspection.id))).get();
      expect(items.length, equals(5));

      final rand = Random(42);

      // Perform 25 randomized answer mutations and verify cached counts against brute-force after each mutation
      for (var step = 0; step < 25; step++) {
        final targetItem = items[rand.nextInt(items.length)];
        final type = ItemType.fromString(targetItem.itemType);

        switch (type) {
          case ItemType.passFail:
            final choices = [ItemResponse.pass, ItemResponse.fail, ItemResponse.na, null];
            final choice = choices[rand.nextInt(choices.length)];
            await inspectionRepo.updateAnswer(itemId: targetItem.id, response: choice);
          case ItemType.text:
            final texts = ['All clear', 'Found issue', '', null];
            final text = texts[rand.nextInt(texts.length)];
            await inspectionRepo.updateAnswer(itemId: targetItem.id, textValue: text);
          case ItemType.number:
            final nums = [10.5, 0.0, 99.9, null];
            final numVal = nums[rand.nextInt(nums.length)];
            await inspectionRepo.updateAnswer(itemId: targetItem.id, numberValue: numVal);
        }

        // Fetch current inspection state
        final current = (await inspectionRepo.getInspection(inspection.id)).valueOrNull!;

        // Brute force recalculation
        final dbItems = await (db.select(db.inspectionItems)..where((t) => t.inspectionId.equals(inspection.id))).get();
        var expAnswered = 0;
        var expPass = 0;
        var expFail = 0;
        var expNa = 0;

        for (final it in dbItems) {
          final isAns = switch (it.itemType) {
            'pass_fail' => it.response != null,
            'text' => it.textValue != null && it.textValue!.trim().isNotEmpty,
            'number' => it.numberValue != null,
            _ => false,
          };
          if (isAns) expAnswered++;
          if (it.response == 'pass') expPass++;
          if (it.response == 'fail') expFail++;
          if (it.response == 'na') expNa++;
        }

        expect(current.answeredItems, equals(expAnswered), reason: 'Step $step answeredItems mismatch');
        expect(current.passCount, equals(expPass), reason: 'Step $step passCount mismatch');
        expect(current.failCount, equals(expFail), reason: 'Step $step failCount mismatch');
        expect(current.naCount, equals(expNa), reason: 'Step $step naCount mismatch');
      }
    });

    test('Read-only enforcement: completed inspection rejects answer mutations until reopened', () async {
      final tplRes = await templateRepo.createTemplate(
        name: 'Lock Test',
        structure: const TemplateStructure(
          schemaVersion: 1,
          sections: [
            TemplateSectionDefinition(
              id: 's1',
              title: 'Section 1',
              items: [
                TemplateItemDefinition(id: 'i1', prompt: 'Item 1', type: ItemType.passFail),
              ],
            ),
          ],
        ),
      );
      final tpl = tplRes.valueOrNull!;

      final insp = (await inspectionRepo.startInspection(
        templateId: tpl.id,
        siteName: 'Site Locked',
        inspectorName: 'Inspector Lock',
      )).valueOrNull!;

      final items = await (db.select(db.inspectionItems)..where((t) => t.inspectionId.equals(insp.id))).get();
      final itemId = items.first.id;

      // 1. Answer works in progress
      final update1 = await inspectionRepo.updateAnswer(itemId: itemId, response: ItemResponse.pass);
      expect(update1.isOk, isTrue);

      // 2. Complete inspection
      final completeRes = await inspectionRepo.completeInspection(insp.id);
      expect(completeRes.isOk, isTrue);

      final completedInsp = (await inspectionRepo.getInspection(insp.id)).valueOrNull!;
      expect(completedInsp.isCompleted, isTrue);

      // 3. Attempting to update answer while completed must fail with validation error!
      final updateBlocked = await inspectionRepo.updateAnswer(itemId: itemId, response: ItemResponse.fail);
      expect(updateBlocked.isErr, isTrue);
      expect(updateBlocked.errorOrNull?.klass, equals(ErrorClass.validation));
      expect(updateBlocked.errorOrNull?.message, contains('completed and read-only'));

      // 4. Reopen inspection
      final reopenRes = await inspectionRepo.reopenInspection(insp.id);
      expect(reopenRes.isOk, isTrue);

      final reopenedInsp = (await inspectionRepo.getInspection(insp.id)).valueOrNull!;
      expect(reopenedInsp.status, equals(InspectionStatus.inProgress));
      expect(reopenedInsp.reopenedCount, equals(1));

      // 5. Updating answer now succeeds
      final updateAfterReopen = await inspectionRepo.updateAnswer(itemId: itemId, response: ItemResponse.fail);
      expect(updateAfterReopen.isOk, isTrue);
    });
  });
}
