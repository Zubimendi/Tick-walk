import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tickwalk/app_providers.dart';
import 'package:tickwalk/core/clock.dart';
import 'package:tickwalk/data/db/app_database.dart' hide Inspection, Template, InspectionItem, Attachment;
import 'package:tickwalk/data/repositories/inspection_repository.dart';
import 'package:tickwalk/data/repositories/template_repository.dart';
import 'package:tickwalk/domain/models.dart';
import 'package:tickwalk/domain/template_schema.dart';
import 'package:tickwalk/features/checklist/checklist_screen.dart';
import 'package:tickwalk/ui/theme.dart';

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late TemplateRepository templateRepo;
  late InspectionRepository inspectionRepo;
  late Inspection testInspection;

  setUp(() async {
    db = AppDatabase.memory();
    clock = FakeClock(DateTime.utc(2026, 11, 20, 10, 0, 0));
    templateRepo = TemplateRepository(db, clock);
    inspectionRepo = InspectionRepository(db, clock);

    // Create template with sections and items
    final tpl = (await templateRepo.createTemplate(
      name: 'Safety & Facility Check',
      structure: const TemplateStructure(
        schemaVersion: 1,
        sections: [
          TemplateSectionDefinition(
            id: 'sec_1',
            title: 'Housekeeping',
            items: [
              TemplateItemDefinition(
                id: 'it_walkways',
                prompt: 'Walkways are clear',
                type: ItemType.passFail,
                required: true,
                photoRequiredOnFail: true,
              ),
              TemplateItemDefinition(
                id: 'it_comments',
                prompt: 'General remarks',
                type: ItemType.text,
              ),
            ],
          ),
        ],
      ),
    )).valueOrNull!;

    testInspection = (await inspectionRepo.startInspection(
      templateId: tpl.id,
      siteName: 'Terminal 3 Logistics Hub',
      inspectorName: 'Pat Safety',
      startGpsStatus: GpsFixStatus.fix,
      startAccuracyM: 5.2,
    )).valueOrNull!;
  });

  tearDown(() async {
    await db.close();
  });

  Widget buildTestChecklist({required String inspectionId}) {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(clock),
      ],
      child: MaterialApp(
        theme: buildLightTheme(),
        home: ChecklistScreen(inspectionId: inspectionId),
      ),
    );
  }

  group('Checklist Screen & Interactions (T11)', () {
    testWidgets('Renders sections, prompts, and handles Pass/Fail answers with fail panel', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestChecklist(inspectionId: testInspection.id));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Header checks
      expect(find.text('Terminal 3 Logistics Hub'), findsOneWidget);
      expect(find.text('Safety & Facility Check'), findsOneWidget);
      expect(find.text('GPS ±5 m'), findsOneWidget);

      // Section header
      expect(find.text('HOUSEKEEPING'), findsOneWidget);

      // Prompts
      expect(find.text('Walkways are clear'), findsOneWidget);
      expect(find.text('Required'), findsOneWidget);

      // Answer Pass
      await tester.tap(find.text('Pass'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Progress updated in DB
      var updatedInsp = (await inspectionRepo.getInspection(testInspection.id)).valueOrNull!;
      expect(updatedInsp.passCount, equals(1));
      expect(updatedInsp.answeredItems, equals(1));

      // Now answer Fail -> expands Fail Panel
      await tester.tap(find.text('Fail'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Severity'), findsOneWidget);
      expect(find.text('Photo required'), findsOneWidget);
      expect(find.text('Add Evidence Photo'), findsOneWidget);

      // Tap High severity chip
      await tester.tap(find.text('High'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Check DB updated
      final items = await (db.select(db.inspectionItems)..where((t) => t.inspectionId.equals(testInspection.id))).get();
      final pfItem = items.firstWhere((i) => i.itemType == 'pass_fail');
      expect(pfItem.response, equals('fail'));
      expect(pfItem.severity, equals('high'));

      // Enter text for text item
      final textFields = find.byType(TextField);
      await tester.enterText(textFields.last, 'Everything in order');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      updatedInsp = (await inspectionRepo.getInspection(testInspection.id)).valueOrNull!;
      expect(updatedInsp.answeredItems, equals(2));

      // Clean unmount
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('Read-only banner displayed when completed and disables editing until Reopen', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Mark inspection completed directly in DB
      await (_dbDirect(db).update(db.inspections)..where((t) => t.id.equals(testInspection.id))).write(
        InspectionsCompanion(
          status: Value(InspectionStatus.completed.value),
          completedAt: Value(clock.nowMillis()),
        ),
      );

      await tester.pumpWidget(buildTestChecklist(inspectionId: testInspection.id));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Read-only banner is present
      expect(find.text('Inspection completed (Read-only).'), findsOneWidget);
      expect(find.text('Reopen to Edit'), findsOneWidget);

      // Reopen
      await tester.tap(find.text('Reopen to Edit'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final reopened = (await inspectionRepo.getInspection(testInspection.id)).valueOrNull!;
      expect(reopened.status, equals(InspectionStatus.inProgress));
      expect(reopened.reopenedCount, equals(1));

      // Clean unmount
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}

AppDatabase _dbDirect(AppDatabase db) => db;
