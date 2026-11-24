import '../../core/errors.dart';
import '../../core/result.dart';
import '../db/app_database.dart';
import '../repositories/settings_repository.dart';
import 'error_mapper.dart';
import 'pb_client.dart';

/// Result of an authentication attempt.
sealed class AuthResult {
  const AuthResult();
}

/// Sign in successful and account guard verified.
class AuthSuccess extends AuthResult {
  const AuthSuccess({required this.userId, required this.email});

  final String userId;
  final String email;
}

/// A different account than sync_owner_id was used.
/// Triggers user prompt: "Replace local data or cancel" (Rule 7 & T18).
class DifferentAccountDetected extends AuthResult {
  const DifferentAccountDetected({
    required this.previousOwnerId,
    required this.newOwnerId,
    required this.newEmail,
  });

  final String previousOwnerId;
  final String newOwnerId;
  final String newEmail;
}

/// Authentication service orchestrating PocketBase auth with the owner guard.
class AuthService {
  AuthService({
    required PbClient pbClient,
    required SettingsRepository settingsRepository,
    required AppDatabase db,
  })  : _pbClient = pbClient,
        _settings = settingsRepository,
        _db = db;

  final PbClient _pbClient;
  final SettingsRepository _settings;
  final AppDatabase _db;

  bool get isSignedIn => _pbClient.isAuthenticated;
  String? get currentUserId => _pbClient.currentUserId;
  String? get currentEmail =>
      _pbClient.authStore.record?.getStringValue('email');

  /// Authenticates with PocketBase and enforces the Account Guard.
  Future<Result<AuthResult>> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final authData = await _pbClient.pb
          .collection('users')
          .authWithPassword(email.trim(), password);

      final newUserId = authData.record.id;
      final newEmail = authData.record.getStringValue('email');

      final previousOwnerId = await _settings.syncOwnerId();

      // Account Guard (Rule 7 & T18)
      if (previousOwnerId == null || previousOwnerId.isEmpty) {
        // First account binding on this device
        await _settings.setSyncOwnerId(newUserId);
        return Ok(AuthSuccess(userId: newUserId, email: newEmail));
      }

      if (previousOwnerId == newUserId) {
        // Same account returning
        return Ok(AuthSuccess(userId: newUserId, email: newEmail));
      }

      // Different account detected!
      return Ok(DifferentAccountDetected(
        previousOwnerId: previousOwnerId,
        newOwnerId: newUserId,
        newEmail: newEmail,
      ));
    } on Object catch (e, stack) {
      return Err(mapClientError(e, stack));
    }
  }

  /// User confirmed "Replace local data" on different account prompt.
  /// Wipes previous owner's local data and binds sync_owner_id to the new account.
  Future<Result<void>> confirmAccountSwitch(String newOwnerId) async {
    try {
      await _db.transaction(() async {
        // 1. Wipe local sync data
        await _db.delete(_db.outbox).go();
        await _db.delete(_db.attachments).go();
        await _db.delete(_db.inspectionItems).go();
        await _db.delete(_db.inspections).go();

        // 2. Set new sync owner
        await _settings.setSyncOwnerId(newOwnerId);
      });

      return const Ok(null);
    } on Object catch (e, stack) {
      return Err(mapClientError(e, stack));
    }
  }

  /// User chose "Cancel" on different account prompt.
  /// Reverts auth session and preserves local data intact.
  Future<void> cancelAccountSwitch() async {
    _pbClient.authStore.clear();
  }

  /// Signs out of the cloud account. Local database remains intact (Rule 13).
  Future<void> signOut() async {
    _pbClient.authStore.clear();
  }

  /// Refreshes the existing session token.
  Future<Result<void>> refreshSession() async {
    if (!isSignedIn) {
      return const Err(AppError(
        klass: ErrorClass.auth,
        message: 'Not signed in',
      ));
    }

    try {
      await _pbClient.pb.collection('users').authRefresh();
      return const Ok(null);
    } on Object catch (e, stack) {
      return Err(mapClientError(e, stack));
    }
  }
}
