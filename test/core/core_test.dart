import 'package:flutter_test/flutter_test.dart';
import 'package:tickwalk/core/clock.dart';
import 'package:tickwalk/core/dates.dart';
import 'package:tickwalk/core/errors.dart';
import 'package:tickwalk/core/ids.dart';
import 'package:tickwalk/core/logger.dart';
import 'package:tickwalk/core/result.dart';

void main() {
  group('Core Utilities', () {
    test('Clock implementations provide time and allow advance', () {
      const sys = SystemClock();
      expect(sys.now(), isA<DateTime>());
      expect(sys.nowMillis(), isPositive);

      final initial = DateTime.utc(2026, 11, 20, 10, 0, 0);
      final fake = FakeClock(initial);
      expect(fake.now(), equals(initial));
      expect(fake.nowMillis(), equals(initial.millisecondsSinceEpoch));

      fake.advance(const Duration(minutes: 15));
      expect(fake.now(), equals(initial.add(const Duration(minutes: 15))));

      fake.advanceMillis(500);
      expect(fake.nowMillis(), equals(initial.millisecondsSinceEpoch + (15 * 60 * 1000) + 500));
    });

    test('Result pattern matching and transformations', () {
      const Result<int> ok = Ok(42);
      expect(ok.isOk, isTrue);
      expect(ok.isErr, isFalse);
      expect(ok.valueOrNull, equals(42));
      expect(ok.errorOrNull, isNull);
      expect(ok.when(ok: (v) => v * 2, err: (_) => 0), equals(84));
      expect(ok.map((v) => 'num: $v').valueOrNull, equals('num: 42'));

      const Result<int> err = Err(AppError(
        klass: ErrorClass.network,
        message: 'Connection timed out',
        code: 'TIMED_OUT',
      ));
      expect(err.isOk, isFalse);
      expect(err.isErr, isTrue);
      expect(err.valueOrNull, isNull);
      expect(err.errorOrNull?.klass, equals(ErrorClass.network));
      expect(err.when(ok: (_) => 'ok', err: (e) => e.message), equals('Connection timed out'));
      expect(err.map((v) => 'num: $v').isErr, isTrue);
    });

    test('IDs generator produces valid 15-char PB IDs and UUIDs', () {
      final id1 = newId();
      final id2 = newId();
      expect(id1.length, equals(15));
      expect(id2.length, equals(15));
      expect(id1, isNot(equals(id2)));
      expect(RegExp(r'^[a-z0-9]{15}$').hasMatch(id1), isTrue);

      final uuid = newUuid();
      expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(uuid), isTrue);
    });

    test('Logger logs safely without errors', () {
      const logger = ConsoleLogger();
      logger.debug('test debug', data: {'count': 1});
      logger.info('test info');
      logger.warn('test warn');
      logger.error('test error', error: 'sample err');

      const noop = NoOpLogger();
      noop.debug('msg');
      noop.info('msg');
      noop.warn('msg');
      noop.error('msg');
    });

    test('Date formatting and elapsed calculations', () {
      final dt = DateTime(2026, 11, 20, 14, 30);
      expect(formatDate(dt), equals('2026-11-20'));
      expect(formatDateTime(dt), equals('2026-11-20 14:30'));
      expect(formatTime(dt), equals('14:30'));
      expect(formatMillis(dt.millisecondsSinceEpoch), equals('2026-11-20 14:30'));

      final now = DateTime(2026, 11, 20, 15, 0);
      expect(formatElapsed(now.subtract(const Duration(seconds: 45)), now), equals('45s ago'));
      expect(formatElapsed(now.subtract(const Duration(minutes: 10)), now), equals('10m ago'));
      expect(formatElapsed(now.subtract(const Duration(hours: 3)), now), equals('3h ago'));
      expect(formatElapsed(now.subtract(const Duration(days: 3)), now), equals('3d ago'));
      expect(formatElapsed(now.subtract(const Duration(days: 10)), now), equals('2026-11-10'));
    });
  });
}
