import 'package:flutter_test/flutter_test.dart';
import 'package:tickwalk/data/sync/upload_scheduler.dart';

void main() {
  group('UploadScheduler (pure)', () {
    const candidate1 = UploadCandidate(
      outboxSeq: 1,
      attachmentId: 'att1',
      inspectionId: 'insp1',
      itemId: 'item1',
      localPath: '/data/att1.jpg',
      fileExists: true,
    );

    const candidate2 = UploadCandidate(
      outboxSeq: 2,
      attachmentId: 'att2',
      inspectionId: 'insp1',
      itemId: 'item1',
      localPath: '/data/att2.jpg',
      fileExists: true,
    );

    const candidate3 = UploadCandidate(
      outboxSeq: 3,
      attachmentId: 'att3',
      inspectionId: 'insp1',
      itemId: 'item1',
      localPath: '/data/att3.jpg',
      fileExists: true,
    );

    test('limits to concurrency of 2', () {
      final res = nextUploads(
        queue: [candidate1, candidate2, candidate3],
        now: 1000,
        inFlight: {},
        concurrency: 2,
        wifiOnly: false,
        connection: NetworkConnectionType.wifi,
        pendingRecordEntityIds: {},
      );

      expect(res.toUpload.length, 2);
      expect(res.toUpload[0].attachmentId, 'att1');
      expect(res.toUpload[1].attachmentId, 'att2');
      expect(res.waitingReasons['att3'], UploadWaitingReason.concurrencyLimit);
    });

    test('respects inFlight count in concurrency limit', () {
      final res = nextUploads(
        queue: [candidate1, candidate2, candidate3],
        now: 1000,
        inFlight: {'att1'},
        concurrency: 2,
        wifiOnly: false,
        connection: NetworkConnectionType.wifi,
        pendingRecordEntityIds: {},
      );

      expect(res.toUpload.length, 1);
      expect(res.toUpload.first.attachmentId, 'att2');
      expect(res.waitingReasons['att1'], UploadWaitingReason.inFlight);
      expect(res.waitingReasons['att3'], UploadWaitingReason.concurrencyLimit);
    });

    test('per-op backoff holds candidate until nextAttemptAt', () {
      const candidateWaiting = UploadCandidate(
        outboxSeq: 1,
        attachmentId: 'att1',
        inspectionId: 'insp1',
        localPath: '/data/att1.jpg',
        fileExists: true,
        nextAttemptAt: 2000,
      );

      final resBefore = nextUploads(
        queue: [candidateWaiting, candidate2],
        now: 1500,
        inFlight: {},
        wifiOnly: false,
        connection: NetworkConnectionType.wifi,
        pendingRecordEntityIds: {},
      );

      expect(resBefore.waitingReasons['att1'], UploadWaitingReason.backoff);
      expect(resBefore.toUpload.map((c) => c.attachmentId), ['att2']);

      final resAfter = nextUploads(
        queue: [candidateWaiting, candidate2],
        now: 2000,
        inFlight: {},
        wifiOnly: false,
        connection: NetworkConnectionType.wifi,
        pendingRecordEntityIds: {},
      );

      expect(resAfter.toUpload.map((c) => c.attachmentId), ['att1', 'att2']);
    });

    test('Wi-Fi only blocks cellular unless oneBatchOverride is true', () {
      final blocked = nextUploads(
        queue: [candidate1],
        now: 1000,
        inFlight: {},
        wifiOnly: true,
        connection: NetworkConnectionType.cellular,
        pendingRecordEntityIds: {},
      );
      expect(blocked.toUpload, isEmpty);
      expect(blocked.waitingReasons['att1'], UploadWaitingReason.waitingForWifi);

      final allowed = nextUploads(
        queue: [candidate1],
        now: 1000,
        inFlight: {},
        wifiOnly: true,
        connection: NetworkConnectionType.cellular,
        oneBatchOverride: true,
        pendingRecordEntityIds: {},
      );
      expect(allowed.toUpload.length, 1);
    });

    test('offline connection marks all as offline', () {
      final res = nextUploads(
        queue: [candidate1, candidate2],
        now: 1000,
        inFlight: {},
        wifiOnly: false,
        connection: NetworkConnectionType.none,
        pendingRecordEntityIds: {},
      );

      expect(res.toUpload, isEmpty);
      expect(res.waitingReasons['att1'], UploadWaitingReason.offline);
      expect(res.waitingReasons['att2'], UploadWaitingReason.offline);
    });

    test('parent-first ordering blocks upload if parent inspection or item is pending in outbox', () {
      final resInspPending = nextUploads(
        queue: [candidate1],
        now: 1000,
        inFlight: {},
        wifiOnly: false,
        connection: NetworkConnectionType.wifi,
        pendingRecordEntityIds: {'insp1'},
      );
      expect(resInspPending.toUpload, isEmpty);
      expect(resInspPending.waitingReasons['att1'], UploadWaitingReason.waitingForParent);

      final resItemPending = nextUploads(
        queue: [candidate1],
        now: 1000,
        inFlight: {},
        wifiOnly: false,
        connection: NetworkConnectionType.wifi,
        pendingRecordEntityIds: {'item1'},
      );
      expect(resItemPending.toUpload, isEmpty);
      expect(resItemPending.waitingReasons['att1'], UploadWaitingReason.waitingForParent);
    });

    test('missing local file marks as fileMissing', () {
      const missingFileCandidate = UploadCandidate(
        outboxSeq: 1,
        attachmentId: 'att-missing',
        inspectionId: 'insp1',
        localPath: '/data/missing.jpg',
        fileExists: false,
      );

      final res = nextUploads(
        queue: [missingFileCandidate],
        now: 1000,
        inFlight: {},
        wifiOnly: false,
        connection: NetworkConnectionType.wifi,
        pendingRecordEntityIds: {},
      );

      expect(res.toUpload, isEmpty);
      expect(res.waitingReasons['att-missing'], UploadWaitingReason.fileMissing);
    });
  });
}
