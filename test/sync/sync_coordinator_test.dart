import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tickwalk/core/result.dart';
import 'package:tickwalk/data/api/auth.dart';
import 'package:tickwalk/data/sync/connectivity.dart';
import 'package:tickwalk/data/sync/media_lane.dart';
import 'package:tickwalk/data/sync/record_lane.dart';
import 'package:tickwalk/data/sync/sync_coordinator.dart';
import 'package:tickwalk/data/sync/upload_scheduler.dart';

class FakeAuthService implements AuthService {
  bool signedIn = true;

  @override
  bool get isSignedIn => signedIn;

  @override
  String? get currentEmail => 'test@example.com';

  @override
  String? get currentUserId => 'user_1';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeConnectivityService implements ConnectivityService {
  NetworkConnectionType current = NetworkConnectionType.wifi;
  final StreamController<NetworkConnectionType> controller =
      StreamController<NetworkConnectionType>.broadcast();

  @override
  Future<NetworkConnectionType> check() async => current;

  @override
  Stream<NetworkConnectionType> watch() => controller.stream;
}

class FakeRecordLane implements RecordLane {
  int syncCalls = 0;
  Result<SyncReport> result = const Ok(SyncReport(pushed: 2, pulled: 1));

  @override
  Future<Result<SyncReport>> syncRecords() async {
    syncCalls++;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeMediaLane implements MediaLane {
  int batchCalls = 0;
  List<int> batchReturns = [1, 0]; // First batch uploads 1, second batch returns 0

  @override
  Future<Result<int>> processNextBatch({
    required NetworkConnectionType connection,
  }) async {
    final count = batchCalls < batchReturns.length ? batchReturns[batchCalls] : 0;
    batchCalls++;
    return Ok(count);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAuthService authService;
  late FakeConnectivityService connectivityService;
  late FakeRecordLane recordLane;
  late FakeMediaLane mediaLane;
  late SyncCoordinator coordinator;

  setUp(() {
    authService = FakeAuthService();
    connectivityService = FakeConnectivityService();
    recordLane = FakeRecordLane();
    mediaLane = FakeMediaLane();
    coordinator = SyncCoordinator(
      recordLane: recordLane,
      mediaLane: mediaLane,
      connectivityService: connectivityService,
      authService: authService,
      autoStart: false,
    );
  });

  tearDown(() {
    coordinator.dispose();
    connectivityService.controller.close();
  });

  group('SyncCoordinator (T22)', () {
    test('skips sync when user is not signed in', () async {
      authService.signedIn = false;

      final result = await coordinator.triggerSync();
      expect(result.isOk, isTrue);
      final report = result.valueOrNull!;
      expect(report.skipped, isTrue);
      expect(recordLane.syncCalls, 0);
      expect(mediaLane.batchCalls, 0);
    });

    test('returns offline when connectivity is none', () async {
      connectivityService.current = NetworkConnectionType.none;

      final result = await coordinator.triggerSync();
      expect(result.isOk, isTrue);
      final report = result.valueOrNull!;
      expect(report.offline, isTrue);
      expect(recordLane.syncCalls, 0);
      expect(mediaLane.batchCalls, 0);
    });

    test('runs records lane then media lane batches when connected', () async {
      final result = await coordinator.triggerSync();
      expect(result.isOk, isTrue);
      final report = result.valueOrNull!;
      expect(report.skipped, isFalse);
      expect(report.offline, isFalse);
      expect(report.recordReport?.pushed, 2);
      expect(report.recordReport?.pulled, 1);
      expect(report.mediaUploaded, 1);

      expect(recordLane.syncCalls, 1);
      expect(mediaLane.batchCalls, 2); // 1st batch uploaded 1, 2nd returned 0
    });

    test('prevents concurrent sync via re-entrancy guard', () async {
      final completer = Completer<Result<SyncReport>>();
      // Delay first record sync
      await recordLane.syncRecords(); // manual call to increment count

      // Replace recordLane with a delayed one
      final slowRecordLane = _DelayedRecordLane(completer.future);
      final customCoordinator = SyncCoordinator(
        recordLane: slowRecordLane,
        mediaLane: mediaLane,
        connectivityService: connectivityService,
        authService: authService,
        autoStart: false,
      );

      // Trigger first sync (will wait on completer)
      final future1 = customCoordinator.triggerSync();

      // Trigger concurrent second sync
      final future2 = customCoordinator.triggerSync();

      final res2 = await future2;
      expect(res2.isOk, isTrue);
      expect(res2.valueOrNull!.skipped, isTrue);

      // Complete the first sync
      completer.complete(const Ok(SyncReport(pushed: 0, pulled: 0)));
      final res1 = await future1;
      expect(res1.isOk, isTrue);
      expect(res1.valueOrNull!.skipped, isFalse);

      customCoordinator.dispose();
    });

    test('triggers sync on AppLifecycleState.resumed', () async {
      expect(recordLane.syncCalls, 0);

      coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(recordLane.syncCalls, 1);
      expect(mediaLane.batchCalls, 2);
    });

    test('does not trigger sync on other AppLifecycle states', () async {
      expect(recordLane.syncCalls, 0);

      coordinator.didChangeAppLifecycleState(AppLifecycleState.paused);
      coordinator.didChangeAppLifecycleState(AppLifecycleState.inactive);
      coordinator.didChangeAppLifecycleState(AppLifecycleState.detached);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(recordLane.syncCalls, 0);
    });

    test('triggers sync when connectivity is regained from none', () async {
      coordinator.start();

      // Start at none
      connectivityService.controller.add(NetworkConnectionType.none);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(recordLane.syncCalls, 0);

      // Regain connectivity to wifi
      connectivityService.controller.add(NetworkConnectionType.wifi);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(recordLane.syncCalls, 1);
    });
  });
}

class _DelayedRecordLane implements RecordLane {
  _DelayedRecordLane(this.future);

  final Future<Result<SyncReport>> future;

  @override
  Future<Result<SyncReport>> syncRecords() => future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
