import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:tickwalk/capture/gps_service.dart';
import 'package:tickwalk/domain/models.dart';

class FakeLocationPlatformAdapter implements LocationPlatformAdapter {
  bool serviceEnabled = true;
  LocationPermission permission = LocationPermission.whileInUse;
  Position? lastKnownPosition;
  final StreamController<Position> positionStreamController =
      StreamController<Position>.broadcast();

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async => permission;

  @override
  Future<Position?> getLastKnownPosition() async => lastKnownPosition;

  @override
  Stream<Position> getPositionStream({required LocationSettings locationSettings}) =>
      positionStreamController.stream;
}

Position createFakePosition({
  required double latitude,
  required double longitude,
  required double accuracy,
  DateTime? timestamp,
}) {
  return Position(
    latitude: latitude,
    longitude: longitude,
    timestamp: timestamp ?? DateTime.utc(2026, 11, 20, 10, 0, 0),
    accuracy: accuracy,
    altitude: 10.0,
    altitudeAccuracy: 1.0,
    heading: 0.0,
    headingAccuracy: 1.0,
    speed: 0.0,
    speedAccuracy: 0.0,
  );
}

void main() {
  late FakeLocationPlatformAdapter adapter;
  late GpsService gpsService;

  setUp(() {
    adapter = FakeLocationPlatformAdapter();
    gpsService = GpsService(
      adapter: adapter,
      timeout: const Duration(milliseconds: 200),
    );
  });

  tearDown(() {
    adapter.positionStreamController.close();
  });

  group('GPS Service Status Model (T14 - All 4 Statuses Reachable)', () {
    test('1. DENIED status reached when permission is denied or deniedForever', () async {
      adapter.permission = LocationPermission.denied;

      final result = await gpsService.obtainFix();

      expect(result.status, equals(GpsFixStatus.denied));
      expect(result.lat, isNull);
      expect(result.lng, isNull);
    });

    test('2. FIX status reached immediately when accuracy <= 50m', () async {
      adapter.permission = LocationPermission.whileInUse;

      final fixFuture = gpsService.obtainFix();
      // Allow async permission checks to complete before emitting
      await Future<void>.delayed(Duration.zero);

      // Emit high-accuracy position (12m <= 50m)
      adapter.positionStreamController.add(createFakePosition(
        latitude: 37.7749,
        longitude: -122.4194,
        accuracy: 12.0,
      ));

      final result = await fixFuture;

      expect(result.status, equals(GpsFixStatus.fix));
      expect(result.lat, equals(37.7749));
      expect(result.lng, equals(-122.4194));
      expect(result.accuracyM, equals(12.0));
    });

    test('2b. FIX status takes best position on timeout if no <=50m accuracy arrived', () async {
      adapter.permission = LocationPermission.whileInUse;

      final fixFuture = gpsService.obtainFix();
      await Future<void>.delayed(Duration.zero);

      // Emit moderate-accuracy position (75m > 50m)
      adapter.positionStreamController.add(createFakePosition(
        latitude: 37.7749,
        longitude: -122.4194,
        accuracy: 75.0,
      ));

      // Wait for 200ms timeout to trigger
      final result = await fixFuture;

      expect(result.status, equals(GpsFixStatus.fix));
      expect(result.accuracyM, equals(75.0));
    });

    test('3. STALE status reached when no fresh fix but last known position exists', () async {
      adapter.serviceEnabled = false; // GPS disabled
      adapter.lastKnownPosition = createFakePosition(
        latitude: 40.7128,
        longitude: -74.0060,
        accuracy: 100.0,
      );

      final result = await gpsService.obtainFix();

      expect(result.status, equals(GpsFixStatus.stale));
      expect(result.lat, equals(40.7128));
      expect(result.lng, equals(-74.0060));
      expect(result.accuracyM, equals(100.0));
    });

    test('4. NONE status reached when no fresh fix and no last known position exists', () async {
      adapter.serviceEnabled = false; // GPS disabled
      adapter.lastKnownPosition = null;

      final result = await gpsService.obtainFix();

      expect(result.status, equals(GpsFixStatus.none));
      expect(result.lat, isNull);
      expect(result.lng, isNull);
    });

    test('Contextual permission request handles flow', () async {
      adapter.permission = LocationPermission.denied;
      final perm = await gpsService.requestPermissionContextual();
      expect(perm, equals(LocationPermission.denied));
    });

    test('Service never throws on unexpected platform stream error', () async {
      adapter.permission = LocationPermission.always;
      adapter.lastKnownPosition = null;

      final fixFuture = gpsService.obtainFix();
      await Future<void>.delayed(Duration.zero);
      adapter.positionStreamController.addError(Exception('Platform GPS failure'));

      final result = await fixFuture;
      expect(result.status, equals(GpsFixStatus.none));
    });
  });
}
