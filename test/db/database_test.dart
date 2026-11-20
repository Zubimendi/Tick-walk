import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tickwalk/data/db/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.memory();
  });

  tearDown(() async {
    await db.close();
  });

  group('Drift Schema & AppDatabase (T5)', () {
    test('Database creates tables and seeds initial settings on first launch', () async {
      final allSettings = await db.select(db.settings).get();
      final settingsMap = {for (final s in allSettings) s.key: s.value};

      expect(settingsMap['inspector_name'], equals(''));
      expect(settingsMap['theme'], equals('system'));
      expect(settingsMap['quality_profile'], equals('standard'));
      expect(settingsMap['wifi_only'], equals('true'));
      expect(settingsMap['allow_gallery'], equals('false'));
      expect(settingsMap['onboarding_done'], equals('false'));
    });

    test('Foreign key enforcement: cannot insert item without parent inspection', () async {
      expect(
        () async {
          await db.into(db.inspectionItems).insert(
                InspectionItemsCompanion.insert(
                  id: 'item_orphan',
                  inspectionId: 'non_existent_inspection',
                  sectionTitle: 'Section 1',
                  sectionOrder: 1,
                  itemOrder: 1,
                  prompt: 'Check something',
                  itemType: 'pass_fail',
                  createdAt: 1000,
                  updatedAt: 1000,
                ),
              );
        },
        throwsA(isA<SqliteException>()),
      );
    });

    test('Inserts and reads template, inspection, item and attachment records', () async {
      // 1. Insert Template
      await db.into(db.templates).insert(
            TemplatesCompanion.insert(
              id: 'tpl_1',
              name: 'Facility Safety',
              structure: '{"schemaVersion": 1, "sections": []}',
              createdAt: 1000,
              updatedAt: 1000,
            ),
          );

      // 2. Insert Inspection
      await db.into(db.inspections).insert(
            InspectionsCompanion.insert(
              id: 'insp_1',
              templateName: 'Facility Safety',
              siteName: 'Plant North',
              inspectorName: 'Alex Inspector',
              status: 'in_progress',
              startedAt: 1000,
              createdAt: 1000,
              updatedAt: 1000,
            ),
          );

      // 3. Insert Item
      await db.into(db.inspectionItems).insert(
            InspectionItemsCompanion.insert(
              id: 'item_1',
              inspectionId: 'insp_1',
              sectionTitle: 'HVAC',
              sectionOrder: 1,
              itemOrder: 1,
              prompt: 'Air filters clean',
              itemType: 'pass_fail',
              createdAt: 1000,
              updatedAt: 1000,
            ),
          );

      // 4. Insert Attachment
      await db.into(db.attachments).insert(
            AttachmentsCompanion.insert(
              id: 'att_1',
              inspectionId: 'insp_1',
              itemId: const Value('item_1'),
              kind: 'photo',
              sha256: 'dummy_hash',
              bytes: 1024,
              gpsStatus: 'fix',
              capturedAt: 1000,
              createdAt: 1000,
              updatedAt: 1000,
            ),
          );

      final inspections = await db.select(db.inspections).get();
      expect(inspections.length, equals(1));
      expect(inspections.first.siteName, equals('Plant North'));

      final items = await (db.select(db.inspectionItems)..where((tbl) => tbl.inspectionId.equals('insp_1'))).get();
      expect(items.length, equals(1));
      expect(items.first.prompt, equals('Air filters clean'));

      final attachments = await (db.select(db.attachments)..where((tbl) => tbl.itemId.equals('item_1'))).get();
      expect(attachments.length, equals(1));
      expect(attachments.first.id, equals('att_1'));
    });
  });
}
