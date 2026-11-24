import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tickwalk/data/sync/outbox_coalescing.dart';
import 'package:tickwalk/domain/models.dart';

void main() {
  group('outbox coalescing', () {
    test('create then update collapses to one create with merged payload', () {
      final entries = [
        OutboxEntry(
          seq: 1,
          entity: OutboxEntity.inspection,
          entityId: 'insp1',
          op: OutboxOp.create,
          payload: jsonEncode({'id': 'insp1', 'site_name': 'Site A', 'status': 'in_progress'}),
          lane: OutboxLane.records,
          createdAt: 100,
        ),
        OutboxEntry(
          seq: 2,
          entity: OutboxEntity.inspection,
          entityId: 'insp1',
          op: OutboxOp.update,
          payload: jsonEncode({'site_name': 'Site B'}),
          lane: OutboxLane.records,
          createdAt: 200,
        ),
      ];

      final coalesced = coalesceOutbox(entries);
      expect(coalesced.length, 1);
      expect(coalesced.first.seq, 1);
      expect(coalesced.first.op, OutboxOp.create);
      final payload = jsonDecode(coalesced.first.payload) as Map<String, dynamic>;
      expect(payload['site_name'], 'Site B');
      expect(payload['status'], 'in_progress');
    });

    test('update then update collapses to one update with latest values', () {
      final entries = [
        OutboxEntry(
          seq: 1,
          entity: OutboxEntity.inspectionItem,
          entityId: 'item1',
          op: OutboxOp.update,
          payload: jsonEncode({'response': 'pass', 'note': 'All good'}),
          lane: OutboxLane.records,
          createdAt: 100,
        ),
        OutboxEntry(
          seq: 2,
          entity: OutboxEntity.inspectionItem,
          entityId: 'item1',
          op: OutboxOp.update,
          payload: jsonEncode({'response': 'fail', 'severity': 'major'}),
          lane: OutboxLane.records,
          createdAt: 200,
        ),
      ];

      final coalesced = coalesceOutbox(entries);
      expect(coalesced.length, 1);
      expect(coalesced.first.seq, 1);
      expect(coalesced.first.op, OutboxOp.update);
      final payload = jsonDecode(coalesced.first.payload) as Map<String, dynamic>;
      expect(payload['response'], 'fail');
      expect(payload['severity'], 'major');
      expect(payload['note'], 'All good');
    });

    test('create then delete (never synced) drops both ops and cancels media upload', () {
      final entries = [
        OutboxEntry(
          seq: 1,
          entity: OutboxEntity.attachment,
          entityId: 'att1',
          op: OutboxOp.create,
          payload: jsonEncode({'id': 'att1', 'kind': 'photo'}),
          lane: OutboxLane.media,
          createdAt: 100,
        ),
        OutboxEntry(
          seq: 2,
          entity: OutboxEntity.attachment,
          entityId: 'att1',
          op: OutboxOp.create,
          payload: jsonEncode({'id': 'att1'}),
          lane: OutboxLane.records,
          createdAt: 100,
        ),
        OutboxEntry(
          seq: 3,
          entity: OutboxEntity.attachment,
          entityId: 'att1',
          op: OutboxOp.delete,
          payload: jsonEncode({'deleted_at': 200}),
          lane: OutboxLane.records,
          createdAt: 200,
        ),
      ];

      final coalesced = coalesceOutbox(entries);
      expect(coalesced, isEmpty);
    });

    test('update then delete collapses to one delete', () {
      final entries = [
        OutboxEntry(
          seq: 1,
          entity: OutboxEntity.template,
          entityId: 'tpl1',
          op: OutboxOp.update,
          payload: jsonEncode({'name': 'Updated Name'}),
          lane: OutboxLane.records,
          createdAt: 100,
        ),
        OutboxEntry(
          seq: 2,
          entity: OutboxEntity.template,
          entityId: 'tpl1',
          op: OutboxOp.delete,
          payload: jsonEncode({'deleted_at': 200}),
          lane: OutboxLane.records,
          createdAt: 200,
        ),
      ];

      final coalesced = coalesceOutbox(entries);
      expect(coalesced.length, 1);
      expect(coalesced.first.seq, 1);
      expect(coalesced.first.op, OutboxOp.delete);
    });

    test('preserves ordering across different entities', () {
      final entries = [
        OutboxEntry(
          seq: 1,
          entity: OutboxEntity.inspection,
          entityId: 'insp1',
          op: OutboxOp.create,
          payload: jsonEncode({'id': 'insp1'}),
          lane: OutboxLane.records,
          createdAt: 100,
        ),
        OutboxEntry(
          seq: 2,
          entity: OutboxEntity.inspectionItem,
          entityId: 'item1',
          op: OutboxOp.create,
          payload: jsonEncode({'id': 'item1', 'inspection': 'insp1'}),
          lane: OutboxLane.records,
          createdAt: 101,
        ),
        OutboxEntry(
          seq: 3,
          entity: OutboxEntity.inspectionItem,
          entityId: 'item1',
          op: OutboxOp.update,
          payload: jsonEncode({'response': 'pass'}),
          lane: OutboxLane.records,
          createdAt: 102,
        ),
      ];

      final coalesced = coalesceOutbox(entries);
      expect(coalesced.length, 2);
      expect(coalesced[0].entity, OutboxEntity.inspection);
      expect(coalesced[1].entity, OutboxEntity.inspectionItem);
      expect(coalesced[1].op, OutboxOp.create);
      final itemPayload = jsonDecode(coalesced[1].payload) as Map<String, dynamic>;
      expect(itemPayload['response'], 'pass');
    });
  });
}
