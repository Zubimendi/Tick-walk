import 'package:pocketbase/pocketbase.dart';

import 'token_storage.dart';

/// AuthStore that persists token exclusively via TokenStorage (Rule 10).
class SecureAuthStore extends AuthStore {
  SecureAuthStore(this._tokenStorage);

  final TokenStorage _tokenStorage;

  Future<void> loadToken() async {
    final token = await _tokenStorage.readToken();
    if (token != null && token.isNotEmpty) {
      save(token, null);
    }
  }

  @override
  void save(String newToken, RecordModel? newRecord) {
    super.save(newToken, newRecord);
    _tokenStorage.writeToken(newToken);
  }

  @override
  void clear() {
    super.clear();
    _tokenStorage.deleteToken();
  }
}

/// PocketBase client wrapper for Tickwalk.
class PbClient {
  PbClient({
    String? baseUrl,
    TokenStorage? tokenStorage,
    PocketBase? customPb,
  })  : _baseUrl = baseUrl ?? defaultBaseUrl,
        _authStore = SecureAuthStore(tokenStorage ?? const SecureTokenStorage()) {
    _pb = customPb ?? PocketBase(_baseUrl, authStore: _authStore);
  }

  final String _baseUrl;
  final SecureAuthStore _authStore;
  late final PocketBase _pb;

  static const String defaultBaseUrl = 'http://127.0.0.1:8090';

  PocketBase get pb => _pb;
  SecureAuthStore get authStore => _authStore;
  String get baseUrl => _baseUrl;

  /// Loads token on application start.
  Future<void> init() async {
    await _authStore.loadToken();
  }

  bool get isAuthenticated => _authStore.isValid;
  String? get currentUserId => _authStore.record?.id;
}
