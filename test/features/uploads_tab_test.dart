import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tickwalk/app_providers.dart';
import 'package:tickwalk/core/clock.dart';
import 'package:tickwalk/data/db/app_database.dart' as db;
import 'package:tickwalk/data/sync/upload_scheduler.dart';
import 'package:tickwalk/features/uploads/uploads_screen.dart';
import 'package:tickwalk/ui/theme.dart';

void main() {
  late Directory tempDir;

  setUpAll(() {
    // Suppress the "multiple databases" Drift warning in tests.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('uploads_tab_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  // ---------------------------------------------------------------------------
  // Helper: build a fresh in-memory DB, seed wifi_only=false, return it.
  // ---------------------------------------------------------------------------
  Future<db.AppDatabase> makeDatabase() async {
    final database = db.AppDatabase(NativeDatabase.memory());
    await database.into(database.settings).insertOnConflictUpdate(
          db.SettingsCompanion.insert(key: 'wifi_only', value: 'false'),
        );
    return database;
  }

  // ---------------------------------------------------------------------------
  // Helper: build the ProviderScope + MaterialApp for the UploadsScreen.
  // ---------------------------------------------------------------------------
  Widget buildTestWidget(
    db.AppDatabase database, {
    NetworkConnectionType connection = NetworkConnectionType.wifi,
  }) {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        clockProvider.overrideWithValue(FakeClock()),
        connectivityStateProvider.overrideWith(
          (ref) => Stream.value(connection),
        ),
      ],
      child: MaterialApp(
        theme: buildLightTheme(),
        home: const UploadsScreen(),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helper: seed an inspection + attachment + media outbox row.
  // ---------------------------------------------------------------------------
  Future<void> seedInspectionWithPhoto(
    db.AppDatabase database, {
    required String id,
    required String siteName,
    required String attId,
    required String status, // 'pending' or 'parked'
    int attempts = 0,
    String? lastError,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    await database.into(database.inspections).insert(
          db.InspectionsCompanion.insert(
            id: id,
            templateName: 'Site Safety',
            siteName: siteName,
            inspectorName: 'Inspector Test',
            status: 'in_progress',
            startedAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        );

    final file = File('${tempDir.path}/$attId.jpg');
    file.writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);

    await database.into(database.attachments).insert(
          db.AttachmentsCompanion.insert(
            id: attId,
            inspectionId: id,
            kind: 'photo',
            localPath: Value(file.path),
            sha256: 'hash_$attId',
            bytes: 1024,
            capturedAt: now,
            gpsStatus: 'fix',
            createdAt: now,
            updatedAt: now,
          ),
        );

    await database.into(database.outbox).insert(
          db.OutboxCompanion.insert(
            entity: 'attachment',
            entityId: attId,
            op: 'create',
            payload: jsonEncode({'id': attId, 'inspection': id}),
            lane: const Value('media'),
            status: Value(status),
            attempts: Value(attempts),
            lastError: Value(lastError),
            createdAt: now,
          ),
        );
  }

  // ---------------------------------------------------------------------------
  // Helper: pump 2 frames so StreamProviders emit their first value.
  // ---------------------------------------------------------------------------
  Future<void> pumpView(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  // ---------------------------------------------------------------------------
  // Helper: unmount the widget tree and close the DB so Drift timers drain.
  // ---------------------------------------------------------------------------
  Future<void> unmountAndClose(
    WidgetTester tester,
    db.AppDatabase database,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
    // Close the DB *after* the ProviderScope is gone so the pending
    // StreamQueryStore timer fires inside the DB close and doesn't leak.
    await database.close();
  }

  // ---------------------------------------------------------------------------
  group('UploadsScreen UI (T21)', () {
    // -------------------------------------------------------------------------
    testWidgets('renders empty state when queue is empty', (tester) async {
      final database = await makeDatabase();

      await tester.pumpWidget(buildTestWidget(database));
      await pumpView(tester);

      expect(find.text('Upload Queue'), findsOneWidget);
      expect(find.text('Upload queue is empty'), findsOneWidget);
      expect(find.text('QUEUED EVIDENCE (0)'), findsOneWidget);

      await unmountAndClose(tester, database);
    });

    // -------------------------------------------------------------------------
    testWidgets('renders sign-in banner when user is not signed in',
        (tester) async {
      final database = await makeDatabase();

      await tester.pumpWidget(buildTestWidget(database));
      await pumpView(tester);

      expect(find.text('Sign in to sync'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);

      await unmountAndClose(tester, database);
    });

    // -------------------------------------------------------------------------
    testWidgets('renders offline banner when connection is none', (tester) async {
      final database = await makeDatabase();

      await tester.pumpWidget(
          buildTestWidget(database, connection: NetworkConnectionType.none));
      await pumpView(tester);

      expect(find.text('Device is offline'), findsOneWidget);
      expect(find.text('Offline'), findsAtLeastNWidgets(1));

      await unmountAndClose(tester, database);
    });

    // -------------------------------------------------------------------------
    testWidgets(
        'renders queued items with site name, size, and waiting status chip',
        (tester) async {
      final database = await makeDatabase();

      await seedInspectionWithPhoto(
        database,
        id: 'insp1',
        siteName: 'Dock Warehouse A',
        attId: 'photo1',
        status: 'pending',
      );

      await tester.pumpWidget(buildTestWidget(database));
      await pumpView(tester);

      expect(find.text('Dock Warehouse A'), findsOneWidget);
      expect(find.text('QUEUED EVIDENCE (1)'), findsOneWidget);
      expect(find.text('Waiting'), findsOneWidget);

      await unmountAndClose(tester, database);
    });

    // -------------------------------------------------------------------------
    testWidgets('renders failed status with plain reason and Retry button',
        (tester) async {
      final database = await makeDatabase();

      await seedInspectionWithPhoto(
        database,
        id: 'insp2',
        siteName: 'Terminal B Gate',
        attId: 'photo_failed',
        status: 'parked',
        lastError: 'File missing on this phone',
      );

      await tester.pumpWidget(buildTestWidget(database));
      await pumpView(tester);

      expect(find.text('Terminal B Gate'), findsOneWidget);
      expect(find.text('File missing on this phone'), findsOneWidget);
      expect(find.byTooltip('Retry upload'), findsOneWidget);

      // Tap Retry button.
      await tester.tap(find.byTooltip('Retry upload'));
      await pumpView(tester);

      // Verify the outbox row status was reset to pending.
      final outbox =
          (await database.select(database.outbox).get()).first;
      expect(outbox.status, 'pending');
      expect(outbox.attempts, 0);

      await unmountAndClose(tester, database);
    });

    // -------------------------------------------------------------------------
    testWidgets('renders paused banner on cellular when Wi-Fi only is enabled',
        (tester) async {
      final database = await makeDatabase();

      await database.into(database.settings).insertOnConflictUpdate(
            db.SettingsCompanion.insert(key: 'wifi_only', value: 'true'),
          );

      await seedInspectionWithPhoto(
        database,
        id: 'insp3',
        siteName: 'Substation South',
        attId: 'photo_wifi',
        status: 'pending',
      );

      await tester.pumpWidget(
          buildTestWidget(database, connection: NetworkConnectionType.cellular));
      await pumpView(tester);

      expect(find.text('Paused on mobile data'), findsOneWidget);
      expect(find.text('Upload Now'), findsOneWidget);

      // Tap Upload Now.
      await tester.tap(find.text('Upload Now'));
      await pumpView(tester);

      expect(find.text('Starting upload on mobile data...'), findsOneWidget);

      await unmountAndClose(tester, database);
    });
  });
}
