import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [
  Templates,
  Inspections,
  InspectionItems,
  Attachments,
  Settings,
  Outbox,
  SyncState,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement('PRAGMA foreign_keys = ON');
          // Seed initial system settings
          await into(settings).insert(
            SettingsCompanion.insert(key: 'inspector_name', value: ''),
          );
          await into(settings).insert(
            SettingsCompanion.insert(key: 'theme', value: 'system'),
          );
          await into(settings).insert(
            SettingsCompanion.insert(key: 'quality_profile', value: 'standard'),
          );
          await into(settings).insert(
            SettingsCompanion.insert(key: 'wifi_only', value: 'true'),
          );
          await into(settings).insert(
            SettingsCompanion.insert(key: 'allow_gallery', value: 'false'),
          );
          await into(settings).insert(
            SettingsCompanion.insert(key: 'onboarding_done', value: 'false'),
          );
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          await customStatement('PRAGMA journal_mode = WAL');
        },
      );

  /// Default production persistent database on device storage.
  static Future<AppDatabase> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'tickwalk.sqlite'));
    return AppDatabase(NativeDatabase.createInBackground(file));
  }

  /// In-memory database connection for unit & integration testing.
  static AppDatabase memory() {
    return AppDatabase(NativeDatabase.memory());
  }

  /// Separate connection for background isolate (same file, WAL mode).
  static Future<AppDatabase> openFile(String path) async {
    return AppDatabase(NativeDatabase(File(path)));
  }
}
