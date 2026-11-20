import 'dart:convert';
import 'models.dart';

class UnknownSchemaVersionException implements Exception {
  const UnknownSchemaVersionException(this.version);
  final int version;

  @override
  String toString() => 'UnknownSchemaVersionException: Schema version $version is not supported (expected 1)';
}

class TemplateValidationException implements Exception {
  const TemplateValidationException(this.message);
  final String message;

  @override
  String toString() => 'TemplateValidationException: $message';
}

/// Represents an item inside a template section.
class TemplateItemDefinition {
  const TemplateItemDefinition({
    required this.id,
    required this.prompt,
    required this.type,
    this.required = false,
    this.photoRequiredOnFail = false,
    this.unit,
  });

  final String id;
  final String prompt;
  final ItemType type;
  final bool required;
  final bool photoRequiredOnFail;
  final String? unit;

  factory TemplateItemDefinition.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.trim().isEmpty) {
      throw const TemplateValidationException('Item id must be a non-empty string');
    }

    final prompt = json['prompt'];
    if (prompt is! String || prompt.trim().isEmpty || prompt.length > 200) {
      throw const TemplateValidationException('Item prompt must be between 1 and 200 characters');
    }

    final typeStr = json['type'];
    if (typeStr is! String) {
      throw const TemplateValidationException('Item type must be a string');
    }
    final ItemType type;
    switch (typeStr) {
      case 'pass_fail':
        type = ItemType.passFail;
      case 'text':
        type = ItemType.text;
      case 'number':
        type = ItemType.number;
      default:
        throw TemplateValidationException('Unsupported item type: $typeStr');
    }

    final unit = json['unit'] as String?;
    if (unit != null && type != ItemType.number) {
      throw const TemplateValidationException('Unit can only be specified for number items');
    }

    return TemplateItemDefinition(
      id: id.trim(),
      prompt: prompt.trim(),
      type: type,
      required: json['required'] == true,
      photoRequiredOnFail: json['photoRequiredOnFail'] == true,
      unit: unit?.trim(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'prompt': prompt,
        'type': type.value,
        'required': required,
        'photoRequiredOnFail': photoRequiredOnFail,
        'unit': unit,
      };
}

/// Represents a section containing items within a template.
class TemplateSectionDefinition {
  const TemplateSectionDefinition({
    required this.id,
    required this.title,
    required this.items,
  });

  final String id;
  final String title;
  final List<TemplateItemDefinition> items;

  factory TemplateSectionDefinition.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.trim().isEmpty) {
      throw const TemplateValidationException('Section id must be a non-empty string');
    }

    final title = json['title'];
    if (title is! String || title.trim().isEmpty || title.length > 100) {
      throw const TemplateValidationException('Section title must be between 1 and 100 characters');
    }

    final rawItems = json['items'];
    if (rawItems is! List || rawItems.isEmpty) {
      throw const TemplateValidationException('Section items must be a non-empty list');
    }

    final items = <TemplateItemDefinition>[];
    for (final raw in rawItems) {
      if (raw is! Map<String, dynamic>) {
        throw const TemplateValidationException('Item must be a JSON object');
      }
      items.add(TemplateItemDefinition.fromJson(raw));
    }

    return TemplateSectionDefinition(
      id: id.trim(),
      title: title.trim(),
      items: List.unmodifiable(items),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'items': items.map((i) => i.toJson()).toList(),
      };
}

/// Root structure for a template (schemaVersion 1).
class TemplateStructure {
  const TemplateStructure({
    this.schemaVersion = 1,
    required this.sections,
  });

  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final List<TemplateSectionDefinition> sections;

  int get totalItems => sections.fold(0, (sum, sec) => sum + sec.items.length);

  factory TemplateStructure.parse(String jsonString) {
    final dynamic decoded = jsonDecode(jsonString);
    if (decoded is! Map<String, dynamic>) {
      throw const TemplateValidationException('Template structure must be a JSON object');
    }
    return TemplateStructure.fromJson(decoded);
  }

  factory TemplateStructure.fromJson(Map<String, dynamic> json) {
    final version = json['schemaVersion'];
    if (version is! int) {
      throw const TemplateValidationException('schemaVersion must be an integer');
    }
    if (version != currentSchemaVersion) {
      throw UnknownSchemaVersionException(version);
    }

    final rawSections = json['sections'];
    if (rawSections is! List || rawSections.isEmpty) {
      throw const TemplateValidationException('Template must contain at least one section');
    }

    final sections = <TemplateSectionDefinition>[];
    final sectionIds = <String>{};
    final itemIds = <String>{};

    for (final raw in rawSections) {
      if (raw is! Map<String, dynamic>) {
        throw const TemplateValidationException('Section must be a JSON object');
      }
      final section = TemplateSectionDefinition.fromJson(raw);
      if (!sectionIds.add(section.id)) {
        throw TemplateValidationException('Duplicate section id found: ${section.id}');
      }
      for (final item in section.items) {
        if (!itemIds.add(item.id)) {
          throw TemplateValidationException('Duplicate item id found: ${item.id}');
        }
      }
      sections.add(section);
    }

    return TemplateStructure(
      schemaVersion: version,
      sections: List.unmodifiable(sections),
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'sections': sections.map((s) => s.toJson()).toList(),
      };

  String serialize() => jsonEncode(toJson());
}
