/// Injected time source. Never call [DateTime.now] outside this file.
abstract class Clock {
  DateTime now();
  int nowMillis() => now().millisecondsSinceEpoch;
}

class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();

  @override
  int nowMillis() => DateTime.now().millisecondsSinceEpoch;
}

/// Mutable clock for tests and deterministic simulations.
class FakeClock implements Clock {
  FakeClock([DateTime? initial])
      : _now = initial ?? DateTime.utc(2026, 11, 20, 12, 0, 0);

  DateTime _now;

  @override
  DateTime now() => _now;

  @override
  int nowMillis() => _now.millisecondsSinceEpoch;

  void setNow(DateTime value) => _now = value;

  void advance(Duration duration) => _now = _now.add(duration);

  void advanceMillis(int millis) =>
      _now = _now.add(Duration(milliseconds: millis));
}
