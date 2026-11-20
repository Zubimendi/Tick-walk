import '../db/app_database.dart';

class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  Stream<Map<String, String>> watchAll() {
    return _db.select(_db.settings).watch().map((rows) {
      return {for (final r in rows) r.key: r.value};
    });
  }

  Future<String?> get(String key) async {
    final row = await (_db.select(_db.settings)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> set(String key, String value) async {
    await _db.into(_db.settings).insertOnConflictUpdate(
          SettingsCompanion.insert(key: key, value: value),
        );
  }

  Future<String> inspectorName() async => (await get('inspector_name')) ?? '';

  Future<void> setInspectorName(String name) => set('inspector_name', name);

  Future<String> themeMode() async => (await get('theme')) ?? 'system';

  Future<String> qualityProfile() async => (await get('quality_profile')) ?? 'standard';

  Future<bool> wifiOnly() async => (await get('wifi_only')) != 'false';

  Future<void> setWifiOnly(bool enabled) => set('wifi_only', enabled ? 'true' : 'false');

  Future<bool> allowGallery() async => (await get('allow_gallery')) == 'true';

  Future<bool> onboardingDone() async => (await get('onboarding_done')) == 'true';

  Future<void> setOnboardingDone() => set('onboarding_done', 'true');

  Future<String?> syncOwnerId() => get('sync_owner_id');

  Future<void> setSyncOwnerId(String? ownerId) async {
    if (ownerId == null) {
      await (_db.delete(_db.settings)..where((t) => t.key.equals('sync_owner_id'))).go();
    } else {
      await set('sync_owner_id', ownerId);
    }
  }

  Future<bool> isSignedIn() async {
    final owner = await syncOwnerId();
    return owner != null && owner.isNotEmpty;
  }
}
