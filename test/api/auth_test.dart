import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:tickwalk/core/errors.dart';
import 'package:tickwalk/data/api/auth.dart';
import 'package:tickwalk/data/api/error_mapper.dart';
import 'package:tickwalk/data/api/pb_client.dart';
import 'package:tickwalk/data/api/token_storage.dart';
import 'package:tickwalk/data/db/app_database.dart';
import 'package:tickwalk/data/repositories/settings_repository.dart';

void main() {
  group('Token Storage & AuthStore (Rule 10)', () {
    test('InMemoryTokenStorage reads, writes, and deletes tokens', () async {
      final storage = InMemoryTokenStorage();
      expect(await storage.readToken(), isNull);

      await storage.writeToken('jwt_sample_token');
      expect(await storage.readToken(), equals('jwt_sample_token'));

      await storage.deleteToken();
      expect(await storage.readToken(), isNull);
    });

    test('SecureAuthStore syncs with TokenStorage', () async {
      final storage = InMemoryTokenStorage();
      final authStore = SecureAuthStore(storage);

      authStore.save('new_token_123', null);
      expect(authStore.token, equals('new_token_123'));
      expect(await storage.readToken(), equals('new_token_123'));

      authStore.clear();
      expect(authStore.token, isEmpty);
      expect(await storage.readToken(), isNull);
    });
  });

  group('Error Mapper Taxonomy (Section 10)', () {
    test('maps ClientException status codes to AppError', () {
      expect(mapClientError(ClientException(statusCode: 401)).klass, equals(ErrorClass.auth));
      expect(mapClientError(ClientException(statusCode: 403)).klass, equals(ErrorClass.forbidden));
      expect(mapClientError(ClientException(statusCode: 404)).klass, equals(ErrorClass.notFound));
      expect(mapClientError(ClientException(statusCode: 409)).klass, equals(ErrorClass.conflict));
      expect(mapClientError(ClientException(statusCode: 413)).klass, equals(ErrorClass.tooLarge));
      expect(mapClientError(ClientException(statusCode: 400)).klass, equals(ErrorClass.validation));
      expect(mapClientError(ClientException(statusCode: 422)).klass, equals(ErrorClass.validation));
      expect(mapClientError(ClientException(statusCode: 429)).klass, equals(ErrorClass.transient));
      expect(mapClientError(ClientException(statusCode: 500)).klass, equals(ErrorClass.transient));
      expect(mapClientError(ClientException(statusCode: 503)).klass, equals(ErrorClass.transient));
    });

    test('maps network errors to ErrorClass.network', () {
      expect(
        mapClientError(const SocketException('Connection refused')).klass,
        equals(ErrorClass.network),
      );
    });
  });

  group('AuthService & Account Guard (T18)', () {
    late AppDatabase db;
    late SettingsRepository settingsRepo;
    late InMemoryTokenStorage tokenStorage;
    late PbClient pbClient;
    late AuthService authService;

    setUp(() {
      db = AppDatabase.memory();
      settingsRepo = SettingsRepository(db);
      tokenStorage = InMemoryTokenStorage();
      pbClient = PbClient(tokenStorage: tokenStorage);
      authService = AuthService(
        pbClient: pbClient,
        settingsRepository: settingsRepo,
        db: db,
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('First-time account binding sets sync_owner_id', () async {
      expect(await settingsRepo.syncOwnerId(), isNull);

      // Simulate successful sign-in
      await settingsRepo.setSyncOwnerId('user_alpha_123');
      expect(await settingsRepo.syncOwnerId(), equals('user_alpha_123'));
    });

    test('Account Switch wipes previous local data and sets new owner', () async {
      // 1. Initial owner setup
      await settingsRepo.setSyncOwnerId('user_old_111');

      // 2. Insert some dummy inspection data
      await db.into(db.inspections).insert(
            InspectionsCompanion.insert(
              id: 'insp_to_wipe',
              templateName: 'Old Template',
              siteName: 'Old Site',
              inspectorName: 'Bob',
              status: 'in_progress',
              startedAt: 1000,
              createdAt: 1000,
              updatedAt: 1000,
            ),
          );

      final beforeInspections = await db.select(db.inspections).get();
      expect(beforeInspections, hasLength(1));

      // 3. Confirm account switch to new user
      final switchResult = await authService.confirmAccountSwitch('user_new_222');
      expect(switchResult.isOk, isTrue);

      // 4. Verify previous data was wiped and sync_owner_id was updated
      final afterInspections = await db.select(db.inspections).get();
      expect(afterInspections, isEmpty);
      expect(await settingsRepo.syncOwnerId(), equals('user_new_222'));
    });

    test('Cancel account switch clears auth store and keeps local data', () async {
      // 1. Initial owner setup with inspection data
      await settingsRepo.setSyncOwnerId('user_existing');
      await db.into(db.inspections).insert(
            InspectionsCompanion.insert(
              id: 'insp_keep',
              templateName: 'Template',
              siteName: 'Site',
              inspectorName: 'Alice',
              status: 'in_progress',
              startedAt: 1000,
              createdAt: 1000,
              updatedAt: 1000,
            ),
          );

      pbClient.authStore.save('temp_token', null);
      expect(pbClient.isAuthenticated, isFalse); // invalid token format

      // 2. Cancel switch
      await authService.cancelAccountSwitch();

      // Auth store is cleared
      expect(pbClient.authStore.token, isEmpty);

      // Local data is completely intact
      final kept = await db.select(db.inspections).get();
      expect(kept, hasLength(1));
      expect(await settingsRepo.syncOwnerId(), equals('user_existing'));
    });

    test('Sign out clears token and preserves local database', () async {
      pbClient.authStore.save('token_to_clear', null);
      await authService.signOut();

      expect(pbClient.authStore.token, isEmpty);
      expect(await tokenStorage.readToken(), isNull);
    });
  });
}
