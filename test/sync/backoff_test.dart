import 'package:flutter_test/flutter_test.dart';
import 'package:tickwalk/data/sync/backoff.dart';

void main() {
  group('computeBackoff', () {
    test('returns zero for attempt <= 0', () {
      expect(computeBackoff(attempt: 0, config: BackoffConfig.records), Duration.zero);
      expect(computeBackoff(attempt: -1, config: BackoffConfig.records), Duration.zero);
    });

    test('records lane follows exponential curve with caps', () {
      const config = BackoffConfig.records; // base 2s, factor 2, cap 5 min

      // Attempt 1: 2s * 2^0 = 2s, with 0 jitter
      final attempt1 = computeBackoff(attempt: 1, config: config, randomValue: 0.5);
      expect(attempt1.inSeconds, 2);

      // Attempt 2: 2s * 2^1 = 4s, with 0 jitter
      final attempt2 = computeBackoff(attempt: 2, config: config, randomValue: 0.5);
      expect(attempt2.inSeconds, 4);

      // Attempt 3: 2s * 2^2 = 8s, with 0 jitter
      final attempt3 = computeBackoff(attempt: 3, config: config, randomValue: 0.5);
      expect(attempt3.inSeconds, 8);

      // Attempt 10: would be 1024s, capped at 300s (5 min)
      final attempt10 = computeBackoff(attempt: 10, config: config, randomValue: 0.5);
      expect(attempt10.inSeconds, 300);
    });

    test('media lane follows exponential curve with 15 min cap', () {
      const config = BackoffConfig.media; // base 5s, factor 2, cap 15 min

      // Attempt 1: 5s
      final attempt1 = computeBackoff(attempt: 1, config: config, randomValue: 0.5);
      expect(attempt1.inSeconds, 5);

      // Attempt 2: 10s
      final attempt2 = computeBackoff(attempt: 2, config: config, randomValue: 0.5);
      expect(attempt2.inSeconds, 10);

      // Attempt 20: capped at 15 min (900s)
      final attempt20 = computeBackoff(attempt: 20, config: config, randomValue: 0.5);
      expect(attempt20.inSeconds, 900);
    });

    test('jitter applies ±20% range', () {
      const config = BackoffConfig.records; // base 2000 ms

      // Min jitter (randomValue = 0.0) -> -20% -> 1600 ms
      final minJitter = computeBackoff(attempt: 1, config: config, randomValue: 0.0);
      expect(minJitter.inMilliseconds, 1600);

      // Max jitter (randomValue = 1.0) -> +20% -> 2400 ms
      final maxJitter = computeBackoff(attempt: 1, config: config, randomValue: 1.0);
      expect(maxJitter.inMilliseconds, 2400);
    });
  });
}
