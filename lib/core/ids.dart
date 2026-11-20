import 'dart:math';
import 'package:uuid/uuid.dart';

final _rand = Random.secure();
const _uuid = Uuid();

/// 15-char lowercase alphanumeric ID (PocketBase standard record ID format).
String newId() {
  const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final buf = StringBuffer();
  for (var i = 0; i < 15; i++) {
    buf.write(alphabet[_rand.nextInt(alphabet.length)]);
  }
  return buf.toString();
}

/// Standard UUIDv4 string.
String newUuid() => _uuid.v4();
