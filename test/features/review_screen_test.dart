import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tickwalk/app_providers.dart';
import 'package:tickwalk/core/clock.dart';
import 'package:tickwalk/data/db/app_database.dart'
    hide Inspection, Template, InspectionItem, Attachment;
import 'package:tickwalk/data/repositories/inspection_repository.dart';
import 'package:tickwalk/data/repositories/template_repository.dart';
import 'package:tickwalk/domain/models.dart';
import 'package:tickwalk/domain/template_schema.dart';
import 'package:tickwalk/features/checklist/review_screen.dart';
import 'package:tickwalk/ui/theme.dart';

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late TemplateRepository templateRepo;
  late InspectionRepository inspectionRepo;
  late Inspection testInspection;
  late List<InspectionItem> testItems;

  setUp(() async {
    db = AppDatabase.memory();
    clock = FakeClock(DateTime.utc(2026, 11, 20, 10, 0, 0));
    templateRepo = TemplateRepository(db, clock);
    inspectionRepo = InspectionRepository(db, clock);

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
                id: 'it_fire_ext',
                prompt: 'Fire extinguishers inspected',
                type: ItemType.passFail,
                required: true,
                photoRequiredOnFail: false,
              ),
            ],
          ),
        ],
      ),
    )).valueOrNull!;

    testInspection = (await inspectionRepo.startInspection(
      templateId: tpl.id,
      siteName: 'Terminal 3 Logistics Hub',
      siteAddress: 'Pier 42, Bay Area',
      inspectorName: 'Pat Safety',
      startGpsStatus: GpsFixStatus.fix,
      startAccuracyM: 5.2,
    )).valueOrNull!;

    final itemsRows = await (db.select(db.inspectionItems)
          ..where((t) => t.inspectionId.equals(testInspection.id)))
        .get();
    testItems = itemsRows
        .map((r) => InspectionItem(
              id: r.id,
              inspectionId: r.inspectionId,
              sectionTitle: r.sectionTitle,
              sectionOrder: r.sectionOrder,
              itemOrder: r.itemOrder,
              prompt: r.prompt,
              itemType: ItemType.fromString(r.itemType),
              unit: r.unit,
              required: r.required,
              photoRequiredOnFail: r.photoRequiredOnFail,
              response: ItemResponse.fromString(r.response),
              severity: Severity.fromString(r.severity),
              textValue: r.textValue,
              numberValue: r.numberValue,
              note: r.note,
              respondedAt: r.respondedAt,
              createdAt: r.createdAt,
              updatedAt: r.updatedAt,
            ))
        .toList();
  });

  tearDown(() async {
    await db.close();
  });

  Widget buildTestReviewScreen({
    required String inspectionId,
  }) {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(clock),
      ],
      child: MaterialApp(
        theme: buildLightTheme(),
        home: Navigator(
          onGenerateRoute: (settings) {
            return MaterialPageRoute<Object?>(
              builder: (context) => ReviewScreen(inspectionId: inspectionId),
            );
          },
        ),
      ),
    );
  }

  group('Review and Finish Screen (T12)', () {
    testWidgets('Renders inspection metadata, summary counts, and blockers',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestReviewScreen(inspectionId: testInspection.id),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Header checks
      expect(find.text('Terminal 3 Logistics Hub'), findsOneWidget);
      expect(find.text('Pier 42, Bay Area'), findsOneWidget);
      expect(find.text('In Progress'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);

      // Blockers check: both required items are unanswered
      expect(find.text('2 Blockers to Resolve'), findsOneWidget);
      expect(find.text('Walkways are clear'), findsOneWidget);
      expect(find.text('Fire extinguishers inspected'), findsOneWidget);

      // Complete button is disabled
      final completeButton = tester.widget<FilledButton>(
        find.byKey(const ValueKey('complete_inspection_button')),
      );
      expect(completeButton.onPressed, isNull);

      // Clean unmount
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('Tapping a blocker pops screen returning the blocker itemId (jump to item link)',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      Object? poppedResult;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            clockProvider.overrideWithValue(clock),
          ],
          child: MaterialApp(
            theme: buildLightTheme(),
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: ElevatedButton(
                    onPressed: () async {
                      poppedResult = await Navigator.of(context).push<Object?>(
                        MaterialPageRoute<Object?>(
                          builder: (_) => ReviewScreen(
                            inspectionId: testInspection.id,
                          ),
                        ),
                      );
                    },
                    child: const Text('Open Review'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // Tap Open Review
      await tester.tap(find.text('Open Review'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('2 Blockers to Resolve'), findsOneWidget);

      // Tap first blocker
      await tester.tap(find.text('Walkways are clear'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Screen popped and returned the target item ID
      expect(poppedResult, equals(testItems[0].id));

      // Clean unmount
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('When all blockers are resolved, Complete button is enabled and completes inspection',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Answer both items as Pass
      await inspectionRepo.updateAnswer(
        itemId: testItems[0].id,
        response: ItemResponse.pass,
      );
      await inspectionRepo.updateAnswer(
        itemId: testItems[1].id,
        response: ItemResponse.pass,
      );

      await tester.pumpWidget(
        buildTestReviewScreen(inspectionId: testInspection.id),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify no blockers
      expect(find.text('All Requirements Met'), findsOneWidget);
      expect(find.text('2 Blockers to Resolve'), findsNothing);

      // Complete button is enabled
      final completeButtonFinder =
          find.byKey(const ValueKey('complete_inspection_button'));
      expect(completeButtonFinder, findsOneWidget);
      final completeButton = tester.widget<FilledButton>(completeButtonFinder);
      expect(completeButton.onPressed, isNotNull);

      // Tap Complete
      await tester.tap(completeButtonFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify in DB that inspection is completed
      final updatedInspection =
          (await inspectionRepo.getInspection(testInspection.id)).valueOrNull!;
      expect(updatedInspection.isCompleted, isTrue);
      expect(updatedInspection.completedAt, isNotNull);

      // Clean unmount (and dismiss SnackBar timer)
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('Completed inspection displays Completed status and allows Reopen',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Answer both items and complete
      await inspectionRepo.updateAnswer(
        itemId: testItems[0].id,
        response: ItemResponse.pass,
      );
      await inspectionRepo.updateAnswer(
        itemId: testItems[1].id,
        response: ItemResponse.pass,
      );
      await inspectionRepo.completeInspection(testInspection.id);

      await tester.pumpWidget(
        buildTestReviewScreen(inspectionId: testInspection.id),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Should display Completed banner
      expect(find.text('Inspection Completed'), findsOneWidget);
      expect(find.byKey(const ValueKey('reopen_inspection_button')),
          findsOneWidget);

      // Tap Reopen Inspection
      await tester.tap(find.byKey(const ValueKey('reopen_inspection_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Confirm dialog appears
      expect(find.text('Reopen Inspection?'), findsOneWidget);
      await tester.tap(find.text('Reopen'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify DB status is now in_progress
      final reopenedInspection =
          (await inspectionRepo.getInspection(testInspection.id)).valueOrNull!;
      expect(reopenedInspection.status, equals(InspectionStatus.inProgress));
      expect(reopenedInspection.reopenedCount, equals(1));

      // Clean unmount (and dismiss SnackBar timer)
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
