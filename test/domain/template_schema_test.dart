import 'package:flutter_test/flutter_test.dart';
import 'package:tickwalk/domain/models.dart';
import 'package:tickwalk/domain/template_schema.dart';

void main() {
  group('TemplateSchema (v1)', () {
    const validJson = '''
    {
      "schemaVersion": 1,
      "sections": [
        {
          "id": "sec_1",
          "title": "Access & Routes",
          "items": [
            {
              "id": "item_1",
              "prompt": "Emergency exits unobstructed",
              "type": "pass_fail",
              "required": true,
              "photoRequiredOnFail": true,
              "unit": null
            },
            {
              "id": "item_2",
              "prompt": "Ambient temperature",
              "type": "number",
              "required": false,
              "photoRequiredOnFail": false,
              "unit": "°C"
            }
          ]
        }
      ]
    }
    ''';

    test('Parses valid schema JSON and serializes back identically', () {
      final structure = TemplateStructure.parse(validJson);
      expect(structure.schemaVersion, equals(1));
      expect(structure.sections.length, equals(1));
      expect(structure.totalItems, equals(2));

      final section = structure.sections.first;
      expect(section.id, equals('sec_1'));
      expect(section.title, equals('Access & Routes'));
      expect(section.items.length, equals(2));

      final item1 = section.items[0];
      expect(item1.id, equals('item_1'));
      expect(item1.prompt, equals('Emergency exits unobstructed'));
      expect(item1.type, equals(ItemType.passFail));
      expect(item1.required, isTrue);
      expect(item1.photoRequiredOnFail, isTrue);
      expect(item1.unit, isNull);

      final item2 = section.items[1];
      expect(item2.id, equals('item_2'));
      expect(item2.type, equals(ItemType.number));
      expect(item2.unit, equals('°C'));

      // Round trip
      final jsonMap = structure.toJson();
      final roundTrip = TemplateStructure.fromJson(jsonMap);
      expect(roundTrip.totalItems, equals(2));
      expect(roundTrip.serialize(), equals(structure.serialize()));
    });

    test('Rejects unknown schemaVersion with UnknownSchemaVersionException', () {
      const unsupportedVersionJson = '''
      {
        "schemaVersion": 2,
        "sections": [
          {
            "id": "sec_1",
            "title": "Safety",
            "items": [{"id": "i1", "prompt": "Check", "type": "pass_fail"}]
          }
        ]
      }
      ''';

      expect(
        () => TemplateStructure.parse(unsupportedVersionJson),
        throwsA(isA<UnknownSchemaVersionException>().having((e) => e.version, 'version', 2)),
      );
    });

    test('Rejects duplicate section IDs', () {
      const duplicateSectionJson = '''
      {
        "schemaVersion": 1,
        "sections": [
          {
            "id": "dup_sec",
            "title": "Sec 1",
            "items": [{"id": "i1", "prompt": "Check 1", "type": "pass_fail"}]
          },
          {
            "id": "dup_sec",
            "title": "Sec 2",
            "items": [{"id": "i2", "prompt": "Check 2", "type": "pass_fail"}]
          }
        ]
      }
      ''';

      expect(
        () => TemplateStructure.parse(duplicateSectionJson),
        throwsA(isA<TemplateValidationException>().having(
          (e) => e.message,
          'message',
          contains('Duplicate section id'),
        )),
      );
    });

    test('Rejects duplicate item IDs across sections', () {
      const duplicateItemJson = '''
      {
        "schemaVersion": 1,
        "sections": [
          {
            "id": "sec_1",
            "title": "Sec 1",
            "items": [{"id": "dup_item", "prompt": "Check 1", "type": "pass_fail"}]
          },
          {
            "id": "sec_2",
            "title": "Sec 2",
            "items": [{"id": "dup_item", "prompt": "Check 2", "type": "pass_fail"}]
          }
        ]
      }
      ''';

      expect(
        () => TemplateStructure.parse(duplicateItemJson),
        throwsA(isA<TemplateValidationException>().having(
          (e) => e.message,
          'message',
          contains('Duplicate item id'),
        )),
      );
    });

    test('Rejects unit on non-number item types', () {
      const invalidUnitJson = '''
      {
        "schemaVersion": 1,
        "sections": [
          {
            "id": "sec_1",
            "title": "Sec 1",
            "items": [
              {
                "id": "i1",
                "prompt": "Pass fail with unit",
                "type": "pass_fail",
                "unit": "kg"
              }
            ]
          }
        ]
      }
      ''';

      expect(
        () => TemplateStructure.parse(invalidUnitJson),
        throwsA(isA<TemplateValidationException>().having(
          (e) => e.message,
          'message',
          contains('Unit can only be specified for number items'),
        )),
      );
    });

    test('Rejects empty sections list', () {
      const emptySectionsJson = '{"schemaVersion": 1, "sections": []}';
      expect(
        () => TemplateStructure.parse(emptySectionsJson),
        throwsA(isA<TemplateValidationException>()),
      );
    });
  });

  group('Domain Models Invariants', () {
    test('InspectionItem isAnswered evaluates correctly across types', () {
      // Pass/Fail
      const pfItem = InspectionItem(
        id: '1',
        inspectionId: 'insp1',
        sectionTitle: 'Title',
        sectionOrder: 1,
        itemOrder: 1,
        prompt: 'Check',
        itemType: ItemType.passFail,
        createdAt: 0,
        updatedAt: 0,
      );
      expect(pfItem.isAnswered, isFalse);
      expect(pfItem.copyWith(response: ItemResponse.pass).isAnswered, isTrue);
      expect(pfItem.copyWith(response: ItemResponse.fail).isAnswered, isTrue);
      expect(pfItem.copyWith(response: ItemResponse.na).isAnswered, isTrue);

      // Text
      const textItem = InspectionItem(
        id: '2',
        inspectionId: 'insp1',
        sectionTitle: 'Title',
        sectionOrder: 1,
        itemOrder: 2,
        prompt: 'Comments',
        itemType: ItemType.text,
        createdAt: 0,
        updatedAt: 0,
      );
      expect(textItem.isAnswered, isFalse);
      expect(textItem.copyWith(textValue: '   ').isAnswered, isFalse);
      expect(textItem.copyWith(textValue: 'All good').isAnswered, isTrue);

      // Number
      const numItem = InspectionItem(
        id: '3',
        inspectionId: 'insp1',
        sectionTitle: 'Title',
        sectionOrder: 1,
        itemOrder: 3,
        prompt: 'PSI',
        itemType: ItemType.number,
        createdAt: 0,
        updatedAt: 0,
      );
      expect(numItem.isAnswered, isFalse);
      expect(numItem.copyWith(numberValue: 0.0).isAnswered, isTrue);
      expect(numItem.copyWith(numberValue: 120.5).isAnswered, isTrue);
    });
  });
}
