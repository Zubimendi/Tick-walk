import 'package:flutter_test/flutter_test.dart';
import 'package:tickwalk/core/clock.dart';
import 'package:tickwalk/data/db/app_database.dart';
import 'package:tickwalk/data/starter_templates.dart';
import 'package:tickwalk/domain/template_schema.dart';

void main() {
  late AppDatabase db;
  late FakeClock clock;

  setUp(() {
    db = AppDatabase.memory();
    clock = FakeClock(DateTime.utc(2026, 11, 20, 10, 0, 0));
  });

  tearDown(() async {
    await db.close();
  });

  group('Starter Templates (T6)', () {
    test('Three starter templates are defined and have valid schema v1', () {
      expect(starterTemplates.length, equals(3));

      for (final tpl in starterTemplates) {
        expect(tpl.isStarter, isTrue);
        expect(tpl.name.isNotEmpty, isTrue);

        // Verify JSON parse validity
        final structure = TemplateStructure.parse(tpl.structure);
        expect(structure.schemaVersion, equals(1));
        expect(structure.sections.isNotEmpty, isTrue);
        expect(structure.totalItems, isPositive);
      }
    });

    test('Starter templates are seeded automatically on database first launch', () async {
      // Trigger onCreate by querying templates
      final templates = await db.select(db.templates).get();
      expect(templates.length, equals(3));

      final names = templates.map((t) => t.name).toList();
      expect(names, contains('Site safety walk'));
      expect(names, contains('Rental property move-in check'));
      expect(names, contains('Generator and power room check'));

      for (final tpl in templates) {
        expect(tpl.isStarter, isTrue);
      }
    });

    test('seedStarterTemplates is idempotent and does not duplicate', () async {
      await seedStarterTemplates(db, clock);
      await seedStarterTemplates(db, clock);

      final templates = await db.select(db.templates).get();
      expect(templates.length, equals(3));
    });
  });
}
