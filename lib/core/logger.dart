import 'package:flutter/foundation.dart';

/// Structured logger.
/// Rule 16 invariant: Never log notes, captions, site names, coordinates,
/// file paths or emails. Log entity IDs, counts and error classes only.
abstract class Logger {
  void debug(String message, {Map<String, Object?>? data});
  void info(String message, {Map<String, Object?>? data});
  void warn(String message, {Map<String, Object?>? data});
  void error(String message, {Object? error, StackTrace? stack});
}

class ConsoleLogger implements Logger {
  const ConsoleLogger();

  void _log(String level, String message, {Map<String, Object?>? data}) {
    if (kDebugMode) {
      final extra = data == null ? '' : ' $data';
      // ignore: avoid_print
      print('[$level] $message$extra');
    }
  }

  @override
  void debug(String message, {Map<String, Object?>? data}) =>
      _log('DEBUG', message, data: data);

  @override
  void info(String message, {Map<String, Object?>? data}) =>
      _log('INFO', message, data: data);

  @override
  void warn(String message, {Map<String, Object?>? data}) =>
      _log('WARN', message, data: data);

  @override
  void error(String message, {Object? error, StackTrace? stack}) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[ERROR] $message error=$error');
      if (stack != null) {
        // ignore: avoid_print
        print(stack);
      }
    }
  }
}

class NoOpLogger implements Logger {
  const NoOpLogger();

  @override
  void debug(String message, {Map<String, Object?>? data}) {}

  @override
  void info(String message, {Map<String, Object?>? data}) {}

  @override
  void warn(String message, {Map<String, Object?>? data}) {}

  @override
  void error(String message, {Object? error, StackTrace? stack}) {}
}
