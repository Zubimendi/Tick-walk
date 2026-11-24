import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pocketbase/pocketbase.dart';

import 'package:tickwalk/core/clock.dart';
import 'package:tickwalk/data/api/pb_client.dart';
import 'package:tickwalk/data/api/token_storage.dart';
import 'package:tickwalk/data/db/app_database.dart' as db;
import 'package:tickwalk/data/repositories/outbox_repository.dart';
import 'package:tickwalk/data/sync/record_lane.dart';
import 'package:tickwalk/domain/models.dart';
import 'package:drift/native.dart';

// Mocks for PocketBase collection service
class MockRecordService extends Mock implements RecordService {}

class FakeTokenStorage implements TokenStorage {
  @override
  Future<String?> readToken() async => null;
  @override
  Future<void> writeToken(String token) async {}
  @override
  Future<void> deleteToken() async {}
}

/// Helper: build an in-memory AppDatabase for testing
db.AppDatabase buildTestDb() {
  return db.AppDatabase(NativeDatabase.memory());
}

/// Helper: seeds a sync_owner_id so the repo thinks user is signed in
Future<void> signInDb(db.AppDatabase database, {String ownerId = 'owner1'}) async {
  await database.into(database.settings).insertOnConflictUpdate(
        db.SettingsCompanion.insert(key: 'sync_owner_id', value: ownerId),
      );
}

void main() {
  late db.AppDatabase database;
  late FakeClock clock;
  late OutboxRepository outboxRepo;

  setUp(() {
    database = buildTestDb();
    clock = FakeClock();
    outboxRepo = OutboxRepository(database, clock);
  });

  tearDown(() async {
    await database.close();
  });

  group('OutboxRepository', () {
    test('enqueue inserts pending row', () async {
      await outboxRepo.enqueue(
        entity: OutboxEntity.inspection,
        entityId: 'insp1',
        op: OutboxOp.create,
        payload: jsonEncode({'id': 'insp1', 'site_name': 'Test'}),
      );

      final pending = await outboxRepo.getPendingEntries();
      expect(pending.length, 1);
      expect(pending.first.entityId, 'insp1');
      expect(pending.first.op, OutboxOp.create);
      expect(pending.first.status, OutboxStatus.pending);
    });

    test('deleteEntry removes the row', () async {
      final seq = await outboxRepo.enqueue(
        entity: OutboxEntity.inspection,
        entityId: 'insp1',
        op: OutboxOp.create,
        payload: jsonEncode({'id': 'insp1'}),
      );

      await outboxRepo.deleteEntry(seq);
      final pending = await outboxRepo.getPendingEntries();
      expect(pending, isEmpty);
    });

    test('parkEntry sets status to parked', () async {
      final seq = await outboxRepo.enqueue(
        entity: OutboxEntity.template,
        entityId: 'tpl1',
        op: OutboxOp.update,
        payload: '{}',
      );

      await outboxRepo.parkEntry(seq: seq, reason: 'validation error');

      final pending = await outboxRepo.getPendingEntries();
      expect(pending, isEmpty); // parked entries excluded from pending

      // Check directly
      final all = await database.select(database.outbox).get();
      expect(all.first.status, 'parked');
      expect(all.first.lastError, 'validation error');
    });

    test('recordAttempt increments attempts and sets nextAttemptAt', () async {
      final seq = await outboxRepo.enqueue(
        entity: OutboxEntity.inspection,
        entityId: 'insp2',
        op: OutboxOp.update,
        payload: '{}',
      );

      await outboxRepo.recordAttempt(
        seq: seq,
        attempts: 2,
        nextAttemptAt: 5000,
        lastError: 'timeout',
      );

      final row = await (database.select(database.outbox)..where((t) => t.seq.equals(seq))).getSingleOrNull();
      expect(row?.attempts, 2);
      expect(row?.nextAttemptAt, 5000);
      expect(row?.lastError, 'timeout');
    });

    test('getPendingEntries ordered by seq ASC', () async {
      await outboxRepo.enqueue(
        entity: OutboxEntity.inspection,
        entityId: 'insp-b',
        op: OutboxOp.create,
        payload: '{}',
      );
      await outboxRepo.enqueue(
        entity: OutboxEntity.inspection,
        entityId: 'insp-a',
        op: OutboxOp.create,
        payload: '{}',
      );

      final pending = await outboxRepo.getPendingEntries();
      expect(pending.length, 2);
      expect(pending.first.entityId, 'insp-b');
      expect(pending.last.entityId, 'insp-a');
    });

    test('lane filter returns only matching lane', () async {
      await outboxRepo.enqueue(
        entity: OutboxEntity.inspection,
        entityId: 'insp1',
        op: OutboxOp.create,
        payload: '{}',
        lane: OutboxLane.records,
      );
      await outboxRepo.enqueue(
        entity: OutboxEntity.attachment,
        entityId: 'att1',
        op: OutboxOp.create,
        payload: '{}',
        lane: OutboxLane.media,
      );

      final recordsOnly = await outboxRepo.getPendingEntries(lane: OutboxLane.records);
      expect(recordsOnly.length, 1);
      expect(recordsOnly.first.entityId, 'insp1');

      final mediaOnly = await outboxRepo.getPendingEntries(lane: OutboxLane.media);
      expect(mediaOnly.length, 1);
      expect(mediaOnly.first.entityId, 'att1');
    });
  });

  group('RecordLane drain (not signed in)', () {
    test('returns Ok(0) when not authenticated', () async {
      // Build a PbClient with invalid auth so authStore.isValid is false
      final pbClient = PbClient(
        baseUrl: 'http://127.0.0.1:8090',
        tokenStorage: FakeTokenStorage(),
      );
      // authStore not loaded = invalid

      final lane = RecordLane(
        pbClient: pbClient,
        db: database,
        outboxRepo: outboxRepo,
        clock: clock,
      );

      await outboxRepo.enqueue(
        entity: OutboxEntity.inspection,
        entityId: 'insp1',
        op: OutboxOp.create,
        payload: jsonEncode({'id': 'insp1'}),
      );

      final result = await lane.drain();
      expect(result.isOk, true);
      expect(result.valueOrNull, 0);

      // Entry should still be pending (not drained)
      final pending = await outboxRepo.getPendingEntries();
      expect(pending.length, 1);
    });
  });

  group('RecordLane pull (not signed in)', () {
    test('returns Ok(0) when not authenticated', () async {
      final pbClient = PbClient(
        baseUrl: 'http://127.0.0.1:8090',
        tokenStorage: FakeTokenStorage(),
      );

      final lane = RecordLane(
        pbClient: pbClient,
        db: database,
        outboxRepo: outboxRepo,
        clock: clock,
      );

      final result = await lane.pull();
      expect(result.isOk, true);
      expect(result.valueOrNull, 0);
    });
  });

  group('RecordLane collectionFor', () {
    test('maps entities to correct collection names', () {
      expect(RecordLane.collectionFor(OutboxEntity.template), 'templates');
      expect(RecordLane.collectionFor(OutboxEntity.inspection), 'inspections');
      expect(RecordLane.collectionFor(OutboxEntity.inspectionItem), 'inspection_items');
      expect(RecordLane.collectionFor(OutboxEntity.attachment), 'attachments');
    });
  });
}
