import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tickwalk/app_providers.dart';
import 'package:tickwalk/core/result.dart';
import 'package:tickwalk/data/api/auth.dart';
import 'package:tickwalk/data/api/pb_client.dart';
import 'package:tickwalk/data/api/token_storage.dart';
import 'package:tickwalk/data/db/app_database.dart';
import 'package:tickwalk/data/repositories/settings_repository.dart';
import 'package:tickwalk/features/account/account_screen.dart';
import 'package:tickwalk/ui/theme.dart';

class FakeAuthService extends AuthService {
  FakeAuthService({
    required super.pbClient,
    required super.settingsRepository,
    required super.db,
  });

  bool fakeIsSignedIn = false;
  String? fakeEmail;
  String? fakeUserId;
  AuthResult? resultToReturn;

  @override
  bool get isSignedIn => fakeIsSignedIn;

  @override
  String? get currentEmail => fakeEmail;

  @override
  String? get currentUserId => fakeUserId;

  @override
  Future<Result<AuthResult>> signIn({
    required String email,
    required String password,
  }) async {
    return Ok(resultToReturn ?? const AuthSuccess(userId: 'u1', email: 'test@example.com'));
  }

  @override
  Future<void> signOut() async {
    fakeIsSignedIn = false;
  }
}

void main() {
  late AppDatabase db;
  late SettingsRepository settingsRepo;
  late InMemoryTokenStorage tokenStorage;
  late PbClient pbClient;
  late FakeAuthService fakeAuth;

  setUp(() {
    db = AppDatabase.memory();
    settingsRepo = SettingsRepository(db);
    tokenStorage = InMemoryTokenStorage();
    pbClient = PbClient(tokenStorage: tokenStorage);
    fakeAuth = FakeAuthService(
      pbClient: pbClient,
      settingsRepository: settingsRepo,
      db: db,
    );
  });

  tearDown(() async {
    await db.close();
  });

  Widget buildTestScreen() {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        settingsRepositoryProvider.overrideWithValue(settingsRepo),
        authServiceProvider.overrideWithValue(fakeAuth),
      ],
      child: MaterialApp(
        theme: buildLightTheme(),
        home: const AccountScreen(),
      ),
    );
  }

  group('Account Screen & Account Guard Dialog (T18)', () {
    testWidgets('Renders sign-in form when signed out', (tester) async {
      fakeAuth.fakeIsSignedIn = false;

      await tester.pumpWidget(buildTestScreen());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Cloud Backup & Account'), findsOneWidget);
      expect(find.text('Optional Cloud Backup'), findsOneWidget);
      expect(find.byKey(const ValueKey('sign_in_button')), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('Renders profile card when signed in', (tester) async {
      fakeAuth.fakeIsSignedIn = true;
      fakeAuth.fakeEmail = 'inspector@safety.org';
      fakeAuth.fakeUserId = 'usr_abc123';

      await tester.pumpWidget(buildTestScreen());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('inspector@safety.org'), findsOneWidget);
      expect(find.text('User ID: usr_abc123'), findsOneWidget);
      expect(find.text('Sign Out'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('Prompts Replace local data or cancel on different account detected', (tester) async {
      fakeAuth.fakeIsSignedIn = false;
      fakeAuth.resultToReturn = const DifferentAccountDetected(
        previousOwnerId: 'user_first',
        newOwnerId: 'user_second',
        newEmail: 'second@safety.org',
      );

      await tester.pumpWidget(buildTestScreen());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Enter email & password
      await tester.enterText(find.byType(TextField).at(0), 'second@safety.org');
      await tester.enterText(find.byType(TextField).at(1), 'password123');

      // Tap Sign In
      await tester.tap(find.byKey(const ValueKey('sign_in_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Account Guard prompt appears
      expect(find.text('Different Account Detected'), findsOneWidget);
      expect(find.text('Replace Local Data'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Cancel button dismisses
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Different Account Detected'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
