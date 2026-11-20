import 'package:intl/intl.dart';

final _dateFormatter = DateFormat('yyyy-MM-dd');
final _dateTimeFormatter = DateFormat('yyyy-MM-dd HH:mm');
final _timeFormatter = DateFormat('HH:mm');

/// Format DateTime to 'YYYY-MM-DD'
String formatDate(DateTime dt) => _dateFormatter.format(dt);

/// Format DateTime to 'YYYY-MM-DD HH:mm'
String formatDateTime(DateTime dt) => _dateTimeFormatter.format(dt);

/// Format DateTime to 'HH:mm'
String formatTime(DateTime dt) => _timeFormatter.format(dt);

/// Format millisecond timestamp to 'YYYY-MM-DD HH:mm'
String formatMillis(int millis) =>
    formatDateTime(DateTime.fromMillisecondsSinceEpoch(millis));

/// Parse ISO 8601 string
DateTime parseIso(String iso) => DateTime.parse(iso);

/// Format DateTime to ISO 8601 string in UTC
String formatIsoUtc(DateTime dt) => dt.toUtc().toIso8601String();

/// Human-readable elapsed time relative to [now]
String formatElapsed(DateTime past, DateTime now) {
  final diff = now.difference(past);
  if (diff.isNegative) return 'just now';
  if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return formatDate(past);
}
