import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tickwalk/app.dart';
import 'package:tickwalk/app_providers.dart';
import 'package:tickwalk/core/clock.dart';
import 'package:tickwalk/data/db/app_database.dart';
import 'package:tickwalk/data/starter_templates.dart';

void main() {
  late AppDatabase db;
  late FakeClock clock;

  setUp(() async {
    db = AppDatabase.memory();
    clock = FakeClock(DateTime.utc(2026, 11, 20, 10, 0, 0));
    await seedStarterTemplates(db, clock);
  });

  tearDown(() async {
    await db.close();
  });

  Widget buildTestApp({bool onboardingDone = false}) {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(clock),
      ],
      child: const TickwalkApp(),
    );
  }

  group('Onboarding & Inspections List (T9)', () {
    testWidgets('First run prompts for inspector name, then navigates to inspections', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestApp(onboardingDone: false));
      // Pump frames until stream providers emit and UI renders
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Onboarding screen elements
      expect(find.text('Tickwalk'), findsOneWidget);
      expect(find.text('Get Started'), findsOneWidget);

      // Enter inspector name
      await tester.enterText(find.byType(TextField), 'Francis Inspector');
      await tester.pump();

      // Tap Get Started
      await tester.tap(find.text('Get Started'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // Navigated to Inspections screen
      expect(find.text('Inspections'), findsWidgets);
      expect(find.text('In Progress'), findsOneWidget);
      expect(find.text('No active walk-rounds'), findsOneWidget);

      // Clean unmount and drain stream cancellation timers
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('New Inspection Sheet & Start (T10)', () {
    testWidgets('Opens sheet, picks template, starts inspection with copied items', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Mark onboarding done
      await db.into(db.settings).insertOnConflictUpdate(
            SettingsCompanion.insert(key: 'onboarding_done', value: 'true'),
          );
      await db.into(db.settings).insertOnConflictUpdate(
            SettingsCompanion.insert(key: 'inspector_name', value: 'Francis Offiong'),
          );

      await tester.pumpWidget(buildTestApp(onboardingDone: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Tap New Walk-Round FAB
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // bottom sheet animation

      expect(find.text('New Inspection'), findsOneWidget);

      // Enter site name (the 1st TextField is site name)
      final textFields = find.byType(TextField);
      await tester.enterText(textFields.first, 'Metro Line B Depot');
      await tester.pump();

      // Tap Start Walk-Round button
      final startButton = find.text('Start Walk-Round');
      await tester.ensureVisible(startButton);
      await tester.tap(startButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify DB has the inspection and items copied!
      final inspections = await db.select(db.inspections).get();
      expect(inspections.length, equals(1));
      expect(inspections.first.siteName, equals('Metro Line B Depot'));
      expect(inspections.first.totalItems, isPositive);

      final items = await (db.select(db.inspectionItems)..where((t) => t.inspectionId.equals(inspections.first.id))).get();
      expect(items.length, equals(inspections.first.totalItems));
      expect(items.first.prompt.isNotEmpty, isTrue);

      // Clean unmount and drain stream cancellation timers
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
