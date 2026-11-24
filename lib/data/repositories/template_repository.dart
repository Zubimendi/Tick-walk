import 'dart:convert';
import 'package:drift/drift.dart';

import '../../core/clock.dart';
import '../../core/errors.dart';
import '../../core/ids.dart';
import '../../core/result.dart';
import '../../domain/models.dart';
import '../../domain/template_schema.dart';
import '../db/app_database.dart' as db;
import 'mappers.dart';

class TemplateRepository {
  TemplateRepository(this._db, this._clock);

  final db.AppDatabase _db;
  final Clock _clock;

  Future<bool> _isSignedIn() async {
    final row = await (_db.select(_db.settings)..where((t) => t.key.equals('sync_owner_id'))).getSingleOrNull();
    return row != null && row.value.trim().isNotEmpty;
  }

  Future<void> _enqueueOutbox({
    required String entity,
    required String entityId,
    required String op,
    required Map<String, dynamic> payload,
    required int now,
  }) async {
    await _db.into(_db.outbox).insert(
          db.OutboxCompanion.insert(
            entity: entity,
            entityId: entityId,
            op: op,
            payload: jsonEncode(payload),
            lane: const Value('records'),
            createdAt: now,
          ),
        );
  }

  Stream<List<Template>> watchTemplates() {
    return (_db.select(_db.templates)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm.desc(t.isStarter),
            (t) => OrderingTerm.desc(t.createdAt),
          ]))
        .watch()
        .map((rows) => rows.map(templateFromRow).toList());
  }

  Future<Result<Template>> getTemplate(String id) async {
    final row = await (_db.select(_db.templates)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null || row.deletedAt != null) {
      return const Err(AppError(
        klass: ErrorClass.notFound,
        message: 'Template not found',
      ));
    }
    return Ok(templateFromRow(row));
  }

  Future<Result<Template>> createTemplate({
    required String name,
    String? description,
    required TemplateStructure structure,
  }) async {
    final now = _clock.nowMillis();
    final id = newId();
    final signedIn = await _isSignedIn();

    try {
      final jsonStr = structure.serialize();
      await _db.transaction(() async {
        await _db.into(_db.templates).insert(
              db.TemplatesCompanion.insert(
                id: id,
                name: name.trim(),
                description: Value(description?.trim()),
                structure: jsonStr,
                isStarter: const Value(false),
                createdAt: now,
                updatedAt: now,
              ),
            );
        if (signedIn) {
          await _enqueueOutbox(
            entity: 'template',
            entityId: id,
            op: 'create',
            payload: {
              'id': id,
              'name': name.trim(),
              'description': description?.trim(),
              'structure': jsonDecode(jsonStr),
              'is_starter': false,
              'client_updated_at': now,
            },
            now: now,
          );
        }
      });

      return getTemplate(id);
    } on Object catch (e) {
      return Err(AppError(
        klass: ErrorClass.local,
        message: 'Failed to create template',
        cause: e,
      ));
    }
  }

  Future<Result<void>> updateTemplate({
    required String id,
    required String name,
    String? description,
    required TemplateStructure structure,
  }) async {
    final now = _clock.nowMillis();
    final signedIn = await _isSignedIn();
    try {
      final jsonStr = structure.serialize();
      var count = 0;
      await _db.transaction(() async {
        count = await (_db.update(_db.templates)..where((t) => t.id.equals(id))).write(
          db.TemplatesCompanion(
            name: Value(name.trim()),
            description: Value(description?.trim()),
            structure: Value(jsonStr),
            updatedAt: Value(now),
          ),
        );
        if (count > 0 && signedIn) {
          await _enqueueOutbox(
            entity: 'template',
            entityId: id,
            op: 'update',
            payload: {
              'name': name.trim(),
              'description': description?.trim(),
              'structure': jsonDecode(jsonStr),
              'client_updated_at': now,
            },
            now: now,
          );
        }
      });

      if (count == 0) {
        return const Err(AppError(
          klass: ErrorClass.notFound,
          message: 'Template not found for update',
        ));
      }
      return const Ok(null);
    } on Object catch (e) {
      return Err(AppError(
        klass: ErrorClass.local,
        message: 'Failed to update template',
        cause: e,
      ));
    }
  }

  Future<Result<Template>> duplicateTemplate(String id) async {
    final existingRes = await getTemplate(id);
    if (existingRes.isErr) return existingRes;

    final existing = existingRes.valueOrNull!;
    return createTemplate(
      name: '${existing.name} (Copy)',
      description: existing.description,
      structure: TemplateStructure.parse(existing.structure),
    );
  }

  Future<Result<void>> deleteTemplate(String id) async {
    final now = _clock.nowMillis();
    final signedIn = await _isSignedIn();
    try {
      var count = 0;
      await _db.transaction(() async {
        count = await (_db.update(_db.templates)..where((t) => t.id.equals(id))).write(
          db.TemplatesCompanion(
            deletedAt: Value(now),
            updatedAt: Value(now),
          ),
        );
        if (count > 0 && signedIn) {
          await _enqueueOutbox(
            entity: 'template',
            entityId: id,
            op: 'delete',
            payload: {'deleted_at': now, 'client_updated_at': now},
            now: now,
          );
        }
      });

      if (count == 0) {
        return const Err(AppError(
          klass: ErrorClass.notFound,
          message: 'Template not found for deletion',
        ));
      }
      return const Ok(null);
    } on Object catch (e) {
      return Err(AppError(
        klass: ErrorClass.local,
        message: 'Failed to delete template',
        cause: e,
      ));
    }
  }
}
