import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';

import 'package:tickwalk/core/clock.dart';
import 'package:tickwalk/domain/models.dart';
import 'package:tickwalk/data/api/pb_client.dart';
import 'package:tickwalk/data/api/token_storage.dart';
import 'package:tickwalk/data/db/app_database.dart' as db;
import 'package:tickwalk/data/repositories/outbox_repository.dart';
import 'package:tickwalk/data/repositories/settings_repository.dart';
import 'package:tickwalk/data/sync/media_lane.dart';
import 'package:tickwalk/data/sync/upload_scheduler.dart';

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
    'id': 'user1',
    'exp': (DateTime.now().millisecondsSinceEpoch ~/ 1000) + 86400,
  })));
  return '$header.$payload.signature';
}

void main() {
  late db.AppDatabase database;
  late FakeClock clock;
  late OutboxRepository outboxRepo;
  late SettingsRepository settingsRepo;
  late Directory tempDir;

  setUp(() async {
    database = db.AppDatabase(NativeDatabase.memory());
    clock = FakeClock();
    outboxRepo = OutboxRepository(database, clock);
    settingsRepo = SettingsRepository(database);
    tempDir = await Directory.systemTemp.createTemp('media_lane_test_');

    // Default settings
    await settingsRepo.setWifiOnly(false);
  });

  tearDown(() async {
    await database.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  PbClient createTestPbClient({
    required Future<http.Response> Function(http.Request request) handler,
    bool authenticated = true,
  }) {
    final tokenStorage = MemoryTokenStorage();
    final jwt = createMockJwt();
    if (authenticated) {
      tokenStorage._token = jwt;
    }

    final mockClient = MockClient((request) async {
      return handler(request);
    });

    final pb = PocketBase(
      'http://127.0.0.1:8090',
      authStore: AsyncAuthStore(
        save: (data) async => tokenStorage.writeToken(data),
        clear: () async => tokenStorage.deleteToken(),
        initial: authenticated ? '{"token":"$jwt","model":{"id":"user1"}}' : null,
      ),
      httpClientFactory: () => mockClient,
    );

    final client = PbClient(
      baseUrl: 'http://127.0.0.1:8090',
      tokenStorage: tokenStorage,
      customPb: pb,
    );

    if (authenticated) {
      client.authStore.save(jwt, RecordModel({'id': 'user1'}));
    }

    return client;
  }

  Future<String> createDummyPhotoFile(String name) async {
    final file = File('${tempDir.path}/$name.jpg');
    await file.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46]);
    return file.path;
  }

  Future<void> insertInspection(String inspectionId) async {
    final now = clock.nowMillis();
    await database.into(database.inspections).insert(
          db.InspectionsCompanion.insert(
            id: inspectionId,
            templateName: 'Template 1',
            siteName: 'Site 1',
            inspectorName: 'Inspector',
            status: 'in_progress',
            startedAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Future<void> insertAttachmentAndOutbox({
    required String id,
    required String inspectionId,
    String? itemId,
    required String? localPath,
  }) async {
    final now = clock.nowMillis();

    // Ensure parent inspection exists in DB (Foreign Key)
    final existingInsp = await (database.select(database.inspections)..where((t) => t.id.equals(inspectionId))).getSingleOrNull();
    if (existingInsp == null) {
      await insertInspection(inspectionId);
    }

    // 1. Insert attachment row
    await database.into(database.attachments).insert(
          db.AttachmentsCompanion.insert(
            id: id,
            inspectionId: inspectionId,
            itemId: Value(itemId),
            kind: 'photo',
            localPath: Value(localPath),
            sha256: 'fakehash',
            bytes: 10,
            capturedAt: now,
            gpsStatus: 'none',
            createdAt: now,
            updatedAt: now,
          ),
        );

    // 2. Insert outbox row for media
    await database.into(database.outbox).insert(
          db.OutboxCompanion.insert(
            entity: 'attachment',
            entityId: id,
            op: 'create',
            payload: jsonEncode({
              'id': id,
              'inspection': inspectionId,
              'item': itemId,
              'kind': 'photo',
            }),
            lane: const Value('media'),
            createdAt: now,
          ),
        );
  }

  group('MediaLane', () {
    test('uploads single attachment successfully and clears outbox', () async {
      final photoPath = await createDummyPhotoFile('photo1');
      await insertAttachmentAndOutbox(
        id: 'att1',
        inspectionId: 'insp1',
        localPath: photoPath,
      );

      final pbClient = createTestPbClient(handler: (request) async {
        expect(request.url.path, '/api/collections/attachments/records');
        return http.Response(
          jsonEncode({
            'id': 'att1',
            'received_at': 5555,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final mediaLane = MediaLane(
        pbClient: pbClient,
        db: database,
        outboxRepo: outboxRepo,
        settingsRepo: settingsRepo,
        clock: clock,
      );

      final result = await mediaLane.processNextBatch(connection: NetworkConnectionType.wifi);
      expect(result.isOk, true);
      expect(result.valueOrNull, 1);

      // Verify attachment row updated
      final att = await (database.select(database.attachments)..where((t) => t.id.equals('att1'))).getSingle();
      expect(att.uploadedAt, isNotNull);
      expect(att.serverReceivedAt, 5555);

      // Verify outbox row deleted
      final pending = await outboxRepo.getPendingEntries(lane: OutboxLane.media);
      expect(pending, isEmpty);
    });

    test('parks entry with fileMissing when file does not exist on disk', () async {
      await insertAttachmentAndOutbox(
        id: 'att-missing',
        inspectionId: 'insp1',
        localPath: '${tempDir.path}/nonexistent.jpg',
      );

      final pbClient = createTestPbClient(handler: (request) async {
        fail('Should not attempt network upload when file is missing');
      });

      final mediaLane = MediaLane(
        pbClient: pbClient,
        db: database,
        outboxRepo: outboxRepo,
        settingsRepo: settingsRepo,
        clock: clock,
      );

      final result = await mediaLane.processNextBatch(connection: NetworkConnectionType.wifi);
      expect(result.isOk, true);
      expect(result.valueOrNull, 0);

      // Verify outbox row is parked
      final allOutbox = await database.select(database.outbox).get();
      expect(allOutbox.first.status, 'parked');
      expect(allOutbox.first.lastError, 'File missing on this phone');
    });

    test('handles duplicate create by querying server record as success', () async {
      final photoPath = await createDummyPhotoFile('photo_dup');
      await insertAttachmentAndOutbox(
        id: 'att-dup',
        inspectionId: 'insp1',
        localPath: photoPath,
      );

      var getCount = 0;
      final pbClient = createTestPbClient(handler: (request) async {
        if (request.method == 'POST') {
          // Return 400 duplicate
          return http.Response(
            jsonEncode({'message': 'Value must be unique', 'data': {'id': {'code': 'validation_not_unique'}}}),
            400,
            headers: {'content-type': 'application/json'},
          );
        } else if (request.method == 'GET') {
          getCount++;
          return http.Response(
            jsonEncode({'id': 'att-dup', 'received_at': 7777}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final mediaLane = MediaLane(
        pbClient: pbClient,
        db: database,
        outboxRepo: outboxRepo,
        settingsRepo: settingsRepo,
        clock: clock,
      );

      final result = await mediaLane.processNextBatch(connection: NetworkConnectionType.wifi);
      expect(result.isOk, true);
      expect(result.valueOrNull, 1);
      expect(getCount, 1);

      // Verify attachment row marked uploaded
      final att = await (database.select(database.attachments)..where((t) => t.id.equals('att-dup'))).getSingle();
      expect(att.uploadedAt, isNotNull);
      expect(att.serverReceivedAt, 7777);

      // Outbox row deleted
      final pending = await outboxRepo.getPendingEntries(lane: OutboxLane.media);
      expect(pending, isEmpty);
    });

    test('transient network failure triggers exponential backoff on that file', () async {
      final photoPath = await createDummyPhotoFile('photo_fail');
      await insertAttachmentAndOutbox(
        id: 'att-fail',
        inspectionId: 'insp1',
        localPath: photoPath,
      );

      final pbClient = createTestPbClient(handler: (request) async {
        return http.Response(
          jsonEncode({'message': 'Internal Server Error'}),
          500,
          headers: {'content-type': 'application/json'},
        );
      });

      final mediaLane = MediaLane(
        pbClient: pbClient,
        db: database,
        outboxRepo: outboxRepo,
        settingsRepo: settingsRepo,
        clock: clock,
      );

      final result = await mediaLane.processNextBatch(connection: NetworkConnectionType.wifi);
      expect(result.isOk, true);
      expect(result.valueOrNull, 0); // 0 successful

      // Verify attempts incremented and nextAttemptAt updated
      final outbox = (await database.select(database.outbox).get()).first;
      expect(outbox.attempts, 1);
      expect(outbox.nextAttemptAt, greaterThan(clock.nowMillis()));
      expect(outbox.status, 'pending'); // not parked, pending retry
    });

    test('Wi-Fi only blocks cellular until oneBatchOverride is enabled', () async {
      await settingsRepo.setWifiOnly(true);
      final photoPath = await createDummyPhotoFile('photo_wifi');
      await insertAttachmentAndOutbox(
        id: 'att-wifi',
        inspectionId: 'insp1',
        localPath: photoPath,
      );

      final pbClient = createTestPbClient(handler: (request) async {
        return http.Response(
          jsonEncode({'id': 'att-wifi', 'received_at': 1111}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final mediaLane = MediaLane(
        pbClient: pbClient,
        db: database,
        outboxRepo: outboxRepo,
        settingsRepo: settingsRepo,
        clock: clock,
      );

      // 1. Process on cellular with wifiOnly: blocked
      final resBlocked = await mediaLane.processNextBatch(connection: NetworkConnectionType.cellular);
      expect(resBlocked.valueOrNull, 0);
      expect(mediaLane.waitingReasons['att-wifi'], UploadWaitingReason.waitingForWifi);

      // 2. Set oneBatchOverride: allowed!
      mediaLane.setOneBatchOverride(true);
      final resAllowed = await mediaLane.processNextBatch(connection: NetworkConnectionType.cellular);
      expect(resAllowed.valueOrNull, 1);
      expect(mediaLane.oneBatchOverride, false); // Resets after use
    });
  });
}
