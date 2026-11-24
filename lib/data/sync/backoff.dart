import 'dart:math';

/// Pure domain exponential backoff calculator with jitter and caps.
/// Invariant: Pure domain logic without platform or Flutter dependencies.
class BackoffConfig {
  const BackoffConfig({
    required this.base,
    required this.cap,
    this.factor = 2.0,
    this.jitterRatio = 0.20, // ±20%
  });

  final Duration base;
  final Duration cap;
  final double factor;
  final double jitterRatio;

  /// Lane 1 (records): base 2s, factor 2, cap 5 min (Rule 7)
  static const records = BackoffConfig(
    base: Duration(seconds: 2),
    cap: Duration(minutes: 5),
    factor: 2.0,
    jitterRatio: 0.20,
  );

  /// Lane 2 (media): base 5s, factor 2, cap 15 min (Rule 7)
  static const media = BackoffConfig(
    base: Duration(seconds: 5),
    cap: Duration(minutes: 15),
    factor: 2.0,
    jitterRatio: 0.20,
  );
}

/// Computes the backoff duration for a given [attempt] (0-indexed or 1-indexed).
/// Uses optional [randomValue] in [0.0, 1.0] to test deterministic jitter.
Duration computeBackoff({
  required int attempt,
  required BackoffConfig config,
  double? randomValue,
}) {
  if (attempt <= 0) {
    return Duration.zero;
  }

  // Calculate exponential component: base * (factor ^ (attempt - 1))
  final exponent = attempt - 1;
  final expMultiplier = pow(config.factor, exponent).toDouble();
  final expMs = config.base.inMilliseconds * expMultiplier;

  // Cap at maximum configured duration
  final cappedMs = min(expMs, config.cap.inMilliseconds.toDouble());

  // Apply jitter ±jitterRatio
  final rand = randomValue ?? Random().nextDouble();
  // Jitter range from -jitterRatio to +jitterRatio
  final jitterMultiplier = 1.0 + (config.jitterRatio * (2.0 * rand - 1.0));
  final finalMs = (cappedMs * jitterMultiplier).round();

  return Duration(milliseconds: max(0, finalMs));
}
