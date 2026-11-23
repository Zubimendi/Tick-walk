import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../../domain/models.dart';
import 'capture_pipeline.dart';

/// Abstract adapter for platform geolocation to enable deterministic unit tests.
abstract class LocationPlatformAdapter {
  Future<bool> isLocationServiceEnabled();
  Future<LocationPermission> checkPermission();
  Future<LocationPermission> requestPermission();
  Future<Position?> getLastKnownPosition();
  Stream<Position> getPositionStream({required LocationSettings locationSettings});
}

/// Geolocator production adapter.
class GeolocatorAdapter implements LocationPlatformAdapter {
  const GeolocatorAdapter();

  @override
  Future<bool> isLocationServiceEnabled() => Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

  @override
  Future<LocationPermission> requestPermission() => Geolocator.requestPermission();

  @override
  Future<Position?> getLastKnownPosition() => Geolocator.getLastKnownPosition();

  @override
  Stream<Position> getPositionStream({required LocationSettings locationSettings}) =>
      Geolocator.getPositionStream(locationSettings: locationSettings);
}

/// Production GPS service implementing Rule 6:
/// - 10 s limit
/// - Accept first fix with accuracy <= 50 m
/// - Otherwise best fix at the 10 s limit
/// - If none, use last known and mark 'stale'
/// - If permission denied, mark 'denied'
/// - If no fix, mark 'none'
/// - Never block beyond 10 s and never throw or fail capture because of GPS.
class GpsService implements GpsFixProvider {
  GpsService({
    LocationPlatformAdapter? adapter,
    Duration? timeout,
  })  : _adapter = adapter ?? const GeolocatorAdapter(),
        _timeoutLimit = timeout ?? const Duration(seconds: 10);

  final LocationPlatformAdapter _adapter;
  final Duration _timeoutLimit;

  static const double targetAccuracyMeters = 50.0;

  /// Requests location permission contextually (Rule 6).
  Future<LocationPermission> requestPermissionContextual() async {
    try {
      final current = await _adapter.checkPermission();
      if (current == LocationPermission.denied) {
        return await _adapter.requestPermission();
      }
      return current;
    } catch (_) {
      return LocationPermission.denied;
    }
  }

  @override
  Future<GpsFixResult> obtainFix() async {
    try {
      // 1. Permission check
      final permission = await _adapter.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return const GpsFixResult(status: GpsFixStatus.denied);
      }

      // 2. Service check
      final isServiceEnabled = await _adapter.isLocationServiceEnabled();
      if (!isServiceEnabled) {
        return await _fallbackToLastKnown();
      }

      // 3. Obtain fix with 10s ceiling and early exit on <= 50m accuracy
      final completer = Completer<GpsFixResult>();
      StreamSubscription<Position>? subscription;
      Timer? timer;
      Position? bestPosition;

      void finishWith(GpsFixResult result) {
        if (!completer.isCompleted) {
          timer?.cancel();
          subscription?.cancel();
          completer.complete(result);
        }
      }

      timer = Timer(_timeoutLimit, () async {
        if (bestPosition != null) {
          finishWith(GpsFixResult(
            lat: bestPosition!.latitude,
            lng: bestPosition!.longitude,
            accuracyM: bestPosition!.accuracy,
            status: GpsFixStatus.fix,
            timestampMillis: bestPosition!.timestamp.millisecondsSinceEpoch,
          ));
        } else {
          final fallback = await _fallbackToLastKnown();
          finishWith(fallback);
        }
      });

      subscription = _adapter
          .getPositionStream(
            locationSettings: LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: _timeoutLimit,
            ),
          )
          .listen(
            (position) {
              // Update best position seen so far
              if (bestPosition == null || position.accuracy < bestPosition!.accuracy) {
                bestPosition = position;
              }

              // Accept immediately if accuracy <= 50 m
              if (position.accuracy <= targetAccuracyMeters) {
                finishWith(GpsFixResult(
                  lat: position.latitude,
                  lng: position.longitude,
                  accuracyM: position.accuracy,
                  status: GpsFixStatus.fix,
                  timestampMillis: position.timestamp.millisecondsSinceEpoch,
                ));
              }
            },
            onError: (Object error) async {
              if (bestPosition != null) {
                finishWith(GpsFixResult(
                  lat: bestPosition!.latitude,
                  lng: bestPosition!.longitude,
                  accuracyM: bestPosition!.accuracy,
                  status: GpsFixStatus.fix,
                  timestampMillis: bestPosition!.timestamp.millisecondsSinceEpoch,
                ));
              } else {
                final fallback = await _fallbackToLastKnown();
                finishWith(fallback);
              }
            },
          );

      return await completer.future;
    } catch (_) {
      // Invariant: capture must never block on GPS and never fail because of it
      return await _fallbackToLastKnown();
    }
  }

  Future<GpsFixResult> _fallbackToLastKnown() async {
    try {
      final lastKnown = await _adapter.getLastKnownPosition();
      if (lastKnown != null) {
        return GpsFixResult(
          lat: lastKnown.latitude,
          lng: lastKnown.longitude,
          accuracyM: lastKnown.accuracy,
          status: GpsFixStatus.stale,
          timestampMillis: lastKnown.timestamp.millisecondsSinceEpoch,
        );
      }
    } catch (_) {}

    return const GpsFixResult(status: GpsFixStatus.none);
  }
}
