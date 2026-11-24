import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Abstract interface for persisting auth token.
/// Invariant: Tokens live in secure storage only (Rule 10).
abstract class TokenStorage {
  Future<String?> readToken();
  Future<void> writeToken(String token);
  Future<void> deleteToken();
}

/// Production implementation using FlutterSecureStorage.
class SecureTokenStorage implements TokenStorage {
  const SecureTokenStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _tokenKey = 'pb_auth_token';

  @override
  Future<String?> readToken() => _storage.read(key: _tokenKey);

  @override
  Future<void> writeToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  @override
  Future<void> deleteToken() => _storage.delete(key: _tokenKey);
}

/// In-memory fake token storage for deterministic testing without platform channels.
class InMemoryTokenStorage implements TokenStorage {
  String? _token;

  @override
  Future<String?> readToken() async => _token;

  @override
  Future<void> writeToken(String token) async => _token = token;

  @override
  Future<void> deleteToken() async => _token = null;
}
