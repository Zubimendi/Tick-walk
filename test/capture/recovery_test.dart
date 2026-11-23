import 'package:flutter_test/flutter_test.dart';
import 'package:tickwalk/capture/recovery.dart';

void main() {
  group('CaptureRecovery evaluateRecovery (Pure Domain, T15)', () {
    final baseNow = DateTime.utc(2026, 11, 20, 10, 0, 0).millisecondsSinceEpoch;
    final recent = baseNow - const Duration(minutes: 5).inMilliseconds; // 5 min ago
    final expired = baseNow - const Duration(minutes: 35).inMilliseconds; // 35 min ago (> 30)

    const inspectionId = 'insp_abc';
    const itemId = 'item_xyz';

    String pendingJson({required String inspection, String? item, required int startedAt}) {
      return '{"inspectionId":"$inspection","itemId":"${item ?? ''}","startedAt":$startedAt}';
    }

    test('RecoveryNotRequired when no pending capture in settings', () {
      final decision = evaluateRecovery(
        pendingCaptureJson: null,
        lostFilePath: '/tmp/photo.jpg',
        nowMillis: baseNow,
      );
      expect(decision, isA<RecoveryNotRequired>());
    });

    test('RecoveryNotRequired when pending capture exists but no file returned', () {
      final decision = evaluateRecovery(
        pendingCaptureJson: pendingJson(
          inspection: inspectionId,
          item: itemId,
          startedAt: recent,
        ),
        lostFilePath: null,
        nowMillis: baseNow,
      );
      expect(decision, isA<RecoveryNotRequired>());
    });

    test('RecoveryExpired when pending capture is older than 30 minutes', () {
      final decision = evaluateRecovery(
        pendingCaptureJson: pendingJson(
          inspection: inspectionId,
          item: itemId,
          startedAt: expired,
        ),
        lostFilePath: '/tmp/photo.jpg',
        nowMillis: baseNow,
      );
      expect(decision, isA<RecoveryExpired>());
    });

    test('RecoveryRequired when recent pending capture and file is present', () {
      final decision = evaluateRecovery(
        pendingCaptureJson: pendingJson(
          inspection: inspectionId,
          item: itemId,
          startedAt: recent,
        ),
        lostFilePath: '/tmp/photo.jpg',
        nowMillis: baseNow,
      );
      expect(decision, isA<RecoveryRequired>());
      final req = decision as RecoveryRequired;
      expect(req.inspectionId, equals(inspectionId));
      expect(req.lostFilePath, equals('/tmp/photo.jpg'));
    });

    test('RecoveryNotRequired on malformed JSON', () {
      final decision = evaluateRecovery(
        pendingCaptureJson: '{broken json',
        lostFilePath: '/tmp/photo.jpg',
        nowMillis: baseNow,
      );
      expect(decision, isA<RecoveryNotRequired>());
    });

    test('RecoveryNotRequired on exactly 30 minutes (boundary — expired)', () {
      final exactly30 = baseNow - const Duration(minutes: 30).inMilliseconds - 1;
      final decision = evaluateRecovery(
        pendingCaptureJson: pendingJson(
          inspection: inspectionId,
          startedAt: exactly30,
        ),
        lostFilePath: '/tmp/photo.jpg',
        nowMillis: baseNow,
      );
      expect(decision, isA<RecoveryExpired>());
    });

    test('RecoveryRequired works without itemId (inspection-level capture)', () {
      final json = '{"inspectionId":"$inspectionId","startedAt":$recent}';
      final decision = evaluateRecovery(
        pendingCaptureJson: json,
        lostFilePath: '/tmp/photo.jpg',
        nowMillis: baseNow,
      );
      expect(decision, isA<RecoveryRequired>());
      final req = decision as RecoveryRequired;
      expect(req.itemId, isNull);
    });
  });
}
