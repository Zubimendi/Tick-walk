import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';

import 'package:pocketbase/pocketbase.dart';
import 'package:tickwalk/background/upload_worker.dart';
import 'package:tickwalk/core/clock.dart';
import 'package:tickwalk/data/api/pb_client.dart';
import 'package:tickwalk/data/api/token_storage.dart';
import 'package:tickwalk/data/db/app_database.dart' as db;

class MemoryTokenStorage implements TokenStorage {
  String? _token;

  @override
  Future<String?> readToken() async => _token;

  @override
  Future<void> writeToken(String token) async => _token = token;

  @override
  Future<void> deleteToken() async => _token = null;
}

String createMockJwt() {
  final header = base64Url.encode(utf8.encode(jsonEncode({'alg': 'HS256', 'typ': 'JWT'})));
  final payload = base64Url.encode(utf8.encode(jsonEncode({
    'id': 'user_worker',
    'exp': (DateTime.now().millisecondsSinceEpoch ~/ 1000) + 86400,
  })));
  return '$header.$payload.signature';
}

void main() {
  late db.AppDatabase database;
  late FakeClock clock;
  late MemoryTokenStorage tokenStorage;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() async {
    database = db.AppDatabase(NativeDatabase.memory());
    clock = FakeClock();
    tokenStorage = MemoryTokenStorage();

    await database.into(database.settings).insertOnConflictUpdate(
          db.SettingsCompanion.insert(key: 'wifi_only', value: 'false'),
        );
  });

  tearDown(() async {
    await database.close();
  });

  group('UploadWorker (T23)', () {
    test('exits gracefully when user is not signed in', () async {
      final pbClient = PbClient(
        baseUrl: 'http://127.0.0.1:8090',
        tokenStorage: tokenStorage,
      );

      final worker = UploadWorker(
        db: database,
        clock: clock,
        pbClient: pbClient,
      );

      final result = await worker.run();
      expect(result, isTrue);
    });

    test('drains records and attempts media batches when signed in', () async {
      final token = createMockJwt();
      await tokenStorage.writeToken(token);

      await database.into(database.settings).insertOnConflictUpdate(
            db.SettingsCompanion.insert(key: 'sync_owner_id', value: 'user_worker'),
          );

      // Insert an inspection and an outbox record
      final now = clock.nowMillis();
      await database.into(database.inspections).insert(
            db.InspectionsCompanion.insert(
              id: 'insp_w1',
              templateName: 'Worker Template',
              siteName: 'Site Worker',
              inspectorName: 'Worker Inspector',
              status: 'in_progress',
              startedAt: now,
              createdAt: now,
              updatedAt: now,
            ),
          );

      await database.into(database.outbox).insert(
            db.OutboxCompanion.insert(
              entity: 'inspection',
              entityId: 'insp_w1',
              op: 'create',
              payload: jsonEncode({
                'id': 'insp_w1',
                'site_name': 'Site Worker',
                'inspector_name': 'Worker Inspector',
              }),
              lane: const Value('records'),
              status: const Value('pending'),
              createdAt: now,
            ),
          );

      // Mock HTTP client that handles create & pull
      final mockHttpClient = MockClient((request) async {
        if (request.method == 'POST' && request.url.path.contains('/inspections')) {
          return http.Response(
            jsonEncode({'id': 'insp_w1', 'site_name': 'Site Worker'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'page': 1,
              'perPage': 200,
              'totalItems': 0,
              'totalPages': 1,
              'items': <Map<String, dynamic>>[],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 200, headers: {'content-type': 'application/json'});
      });

      final customPb = PocketBase(
        'http://127.0.0.1:8090',
        httpClientFactory: () => mockHttpClient,
      );

      final pbClient = PbClient(
        baseUrl: 'http://127.0.0.1:8090',
        tokenStorage: tokenStorage,
        customPb: customPb,
      );
      pbClient.authStore.save(token, null);

      final worker = UploadWorker(
        db: database,
        clock: clock,
        pbClient: pbClient,
        maxRuntime: const Duration(seconds: 5),
      );

      final success = await worker.run();
      expect(success, isTrue);

      // Verify outbox record was drained
      final remainingOutbox = await database.select(database.outbox).get();
      expect(remainingOutbox, isEmpty);
    });
  });
}
