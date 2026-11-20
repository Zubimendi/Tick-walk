import 'package:drift/drift.dart';

import '../core/clock.dart';
import '../domain/models.dart';
import '../domain/template_schema.dart';
import 'db/app_database.dart' hide Template;

/// Appendix A: Three production sample starter templates.
final starterTemplates = <Template>[
  Template(
    id: 'tpl_starter_site_safety',
    name: 'Site safety walk',
    description: 'Construction sample inspection for access, PPE, and electrical hazards.',
    isStarter: true,
    structure: const TemplateStructure(
      schemaVersion: 1,
      sections: [
        TemplateSectionDefinition(
          id: 'sec_access',
          title: 'Access and housekeeping',
          items: [
            TemplateItemDefinition(
              id: 'item_walkways',
              prompt: 'Walkways and access routes are clear',
              type: ItemType.passFail,
              required: true,
              photoRequiredOnFail: true,
            ),
            TemplateItemDefinition(
              id: 'item_materials',
              prompt: 'Materials are stacked and stored safely',
              type: ItemType.passFail,
              photoRequiredOnFail: true,
            ),
            TemplateItemDefinition(
              id: 'item_signs',
              prompt: 'Warning signs and notices are visible',
              type: ItemType.passFail,
            ),
          ],
        ),
        TemplateSectionDefinition(
          id: 'sec_ppe',
          title: 'People and PPE',
          items: [
            TemplateItemDefinition(
              id: 'item_helmets',
              prompt: 'Workers are wearing helmets',
              type: ItemType.passFail,
              photoRequiredOnFail: true,
            ),
            TemplateItemDefinition(
              id: 'item_footwear',
              prompt: 'Workers are wearing safety footwear',
              type: ItemType.passFail,
            ),
            TemplateItemDefinition(
              id: 'item_first_aid',
              prompt: 'First aid kit is available and stocked',
              type: ItemType.passFail,
              required: true,
            ),
            TemplateItemDefinition(
              id: 'item_workers_count',
              prompt: 'Number of workers on site',
              type: ItemType.number,
              unit: 'people',
            ),
          ],
        ),
        TemplateSectionDefinition(
          id: 'sec_equipment',
          title: 'Equipment and power',
          items: [
            TemplateItemDefinition(
              id: 'item_scaffolding',
              prompt: 'Scaffolding and ladders look stable',
              type: ItemType.passFail,
              photoRequiredOnFail: true,
            ),
            TemplateItemDefinition(
              id: 'item_cables',
              prompt: 'Cables are protected and not across walkways',
              type: ItemType.passFail,
              photoRequiredOnFail: true,
            ),
            TemplateItemDefinition(
              id: 'item_extinguisher',
              prompt: 'Fire extinguisher is accessible',
              type: ItemType.passFail,
              required: true,
            ),
            TemplateItemDefinition(
              id: 'item_generator',
              prompt: 'Generator is ventilated and away from flammables',
              type: ItemType.passFail,
              photoRequiredOnFail: true,
            ),
          ],
        ),
        TemplateSectionDefinition(
          id: 'sec_safety_notes',
          title: 'Notes',
          items: [
            TemplateItemDefinition(
              id: 'item_observations',
              prompt: 'Other observations',
              type: ItemType.text,
            ),
          ],
        ),
      ],
    ).serialize(),
    createdAt: 0,
    updatedAt: 0,
  ),
  Template(
    id: 'tpl_starter_move_in',
    name: 'Rental property move-in check',
    description: 'Condition inspection for residential property handover.',
    isStarter: true,
    structure: const TemplateStructure(
      schemaVersion: 1,
      sections: [
        TemplateSectionDefinition(
          id: 'sec_entrance',
          title: 'Entrance and doors',
          items: [
            TemplateItemDefinition(
              id: 'item_doors',
              prompt: 'Doors close and lock properly',
              type: ItemType.passFail,
              photoRequiredOnFail: true,
            ),
            TemplateItemDefinition(
              id: 'item_keys',
              prompt: 'Number of keys handed over',
              type: ItemType.number,
              unit: 'keys',
            ),
          ],
        ),
        TemplateSectionDefinition(
          id: 'sec_living',
          title: 'Living areas',
          items: [
            TemplateItemDefinition(
              id: 'item_walls',
              prompt: 'Walls and ceiling are free of damage',
              type: ItemType.passFail,
              photoRequiredOnFail: true,
            ),
            TemplateItemDefinition(
              id: 'item_windows',
              prompt: 'Windows open, close and latch',
              type: ItemType.passFail,
            ),
            TemplateItemDefinition(
              id: 'item_floors',
              prompt: 'Floors are free of damage',
              type: ItemType.passFail,
              photoRequiredOnFail: true,
            ),
          ],
        ),
        TemplateSectionDefinition(
          id: 'sec_kitchen_bath',
          title: 'Kitchen and bathroom',
          items: [
            TemplateItemDefinition(
              id: 'item_sink',
              prompt: 'Sink drains and taps run',
              type: ItemType.passFail,
              photoRequiredOnFail: true,
            ),
            TemplateItemDefinition(
              id: 'item_cupboards',
              prompt: 'Cupboards and fittings are intact',
              type: ItemType.passFail,
            ),
            TemplateItemDefinition(
              id: 'item_toilet',
              prompt: 'Toilet flushes and does not leak',
              type: ItemType.passFail,
              photoRequiredOnFail: true,
            ),
            TemplateItemDefinition(
              id: 'item_shower',
              prompt: 'Shower and taps work',
              type: ItemType.passFail,
            ),
          ],
        ),
        TemplateSectionDefinition(
          id: 'sec_power_water',
          title: 'Power and water',
          items: [
            TemplateItemDefinition(
              id: 'item_sockets',
              prompt: 'Sockets and switches work',
              type: ItemType.passFail,
            ),
            TemplateItemDefinition(
              id: 'item_meter_num',
              prompt: 'Meter number',
              type: ItemType.text,
            ),
            TemplateItemDefinition(
              id: 'item_meter_reading',
              prompt: 'Meter reading',
              type: ItemType.number,
              unit: 'kWh',
            ),
            TemplateItemDefinition(
              id: 'item_water_supply',
              prompt: 'Water supply is working',
              type: ItemType.passFail,
            ),
          ],
        ),
      ],
    ).serialize(),
    createdAt: 0,
    updatedAt: 0,
  ),
  Template(
    id: 'tpl_starter_generator',
    name: 'Generator and power room check',
    description: 'Daily plant and backup power room checklist.',
    isStarter: true,
    structure: const TemplateStructure(
      schemaVersion: 1,
      sections: [
        TemplateSectionDefinition(
          id: 'sec_daily',
          title: 'Daily checks',
          items: [
            TemplateItemDefinition(
              id: 'item_fuel_level',
              prompt: 'Fuel level',
              type: ItemType.number,
              unit: 'litres',
            ),
            TemplateItemDefinition(
              id: 'item_oil_level',
              prompt: 'Oil level looks correct',
              type: ItemType.passFail,
              required: true,
            ),
            TemplateItemDefinition(
              id: 'item_leaks',
              prompt: 'No visible fuel or oil leaks',
              type: ItemType.passFail,
              photoRequiredOnFail: true,
            ),
            TemplateItemDefinition(
              id: 'item_exhaust',
              prompt: 'Exhaust vents outdoors',
              type: ItemType.passFail,
              required: true,
            ),
            TemplateItemDefinition(
              id: 'item_clear_area',
              prompt: 'Area is clear of flammable items',
              type: ItemType.passFail,
              photoRequiredOnFail: true,
            ),
            TemplateItemDefinition(
              id: 'item_gen_extinguisher',
              prompt: 'Fire extinguisher present and accessible',
              type: ItemType.passFail,
              required: true,
            ),
            TemplateItemDefinition(
              id: 'item_vibration',
              prompt: 'Unusual noise or vibration',
              type: ItemType.passFail,
            ),
          ],
        ),
        TemplateSectionDefinition(
          id: 'sec_records',
          title: 'Records',
          items: [
            TemplateItemDefinition(
              id: 'item_runtime_hours',
              prompt: 'Runtime hours',
              type: ItemType.number,
              unit: 'hours',
            ),
            TemplateItemDefinition(
              id: 'item_last_service',
              prompt: 'Last service date',
              type: ItemType.text,
            ),
            TemplateItemDefinition(
              id: 'item_gen_notes',
              prompt: 'Notes',
              type: ItemType.text,
            ),
          ],
        ),
      ],
    ).serialize(),
    createdAt: 0,
    updatedAt: 0,
  ),
];

/// Seeds the starter templates into the database if not already present.
Future<void> seedStarterTemplates(AppDatabase db, [Clock clock = const SystemClock()]) async {
  final now = clock.nowMillis();
  for (final tpl in starterTemplates) {
    await db.into(db.templates).insert(
          TemplatesCompanion.insert(
            id: tpl.id,
            name: tpl.name,
            description: Value(tpl.description),
            structure: tpl.structure,
            isStarter: const Value(true),
            createdAt: now,
            updatedAt: now,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }
}
