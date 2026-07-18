import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/trip.dart';

/// Converts a raw Geolocator speed (m/s) into mph.
double metersPerSecondToMph(double mps) => mps * 2.23694;

enum LocationAccessStatus {
  granted,
  permissionDenied,
  permissionDeniedForever,
  servicesDisabled,
}

/// Handles all GPS access: permission requests, a live high-frequency
/// position stream for "where is everyone right now", and trip-mode
/// recording (start/stop driving + full speed trace).
///
/// Accuracy notes:
/// - We request LocationAccuracy.bestForNavigation, which on most devices
///   fuses GPS + GLONASS/Galileo + on-device sensors for sub-5m accuracy.
/// - distanceFilter is set low (5m) during an active trip so speed spikes
///   aren't missed, and higher (25m) in idle "just show me on the map"
///   mode to save battery.
class LocationService {
  StreamSubscription<Position>? _liveSub;
  StreamSubscription<Position>? _tripSub;

  final _liveController = StreamController<Position>.broadcast();
  Stream<Position> get liveLocationStream => _liveController.stream;

  final List<TripPoint> _currentTripBuffer = [];
  double _topSpeedMph = 0;
  double _distanceMiles = 0;
  Position? _lastTripPosition;
  bool get isRecordingTrip => _tripSub != null;

  static LocationAccessStatus evaluateAccessStatus({
    required LocationPermission permission,
    required bool serviceEnabled,
  }) {
    if (!serviceEnabled) return LocationAccessStatus.servicesDisabled;
    if (permission == LocationPermission.deniedForever) {
      return LocationAccessStatus.permissionDeniedForever;
    }
    if (permission == LocationPermission.denied) {
      return LocationAccessStatus.permissionDenied;
    }
    return LocationAccessStatus.granted;
  }

  Future<LocationAccessStatus> ensurePermissions({BuildContext? context}) async {
    var permission = await Geolocator.checkPermission();
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      if (context != null) {
        final opened = await Geolocator.openLocationSettings();
        if (!opened) {
          return LocationAccessStatus.servicesDisabled;
        }
      }
      return LocationAccessStatus.servicesDisabled;
    }

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      return LocationAccessStatus.permissionDeniedForever;
    }

    // Background/"always" permission is required so trips and group
    // location keep updating while the phone is locked or the app is
    // backgrounded — request it explicitly on Android/iOS.
    if (permission == LocationPermission.whileInUse) {
      permission = await Geolocator.requestPermission();
    }

    return evaluateAccessStatus(
      permission: permission,
      serviceEnabled: await Geolocator.isLocationServiceEnabled(),
    );
  }

  /// Starts the always-on "share my location with my group" stream.
  /// This is intentionally lower-frequency to conserve battery when the
  /// user isn't actively driving.
  void startLiveTracking() {
    _liveSub?.cancel();
    _liveSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 25, // meters
      ),
    ).listen(
      _liveController.add,
      onError: (error, stackTrace) => _liveController.addError(error, stackTrace),
    );
  }

  void stopLiveTracking() {
    _liveSub?.cancel();
    _liveSub = null;
  }

  /// Starts high-frequency, high-accuracy trip recording: every GPS fix
  /// is captured so we can compute an accurate top speed and full trace.
  Stream<TripPoint> startTripRecording() {
    _currentTripBuffer.clear();
    _topSpeedMph = 0;
    _distanceMiles = 0;
    _lastTripPosition = null;

    final controller = StreamController<TripPoint>.broadcast();

    _tripSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5, // meters - fine-grained for accurate top speed
      ),
    ).listen((pos) {
      // GPS speed is authoritative when accuracy is good; otherwise derive
      // speed from consecutive fixes as a fallback.
      double speedMph = metersPerSecondToMph(pos.speed);
      if (pos.speedAccuracy > 3 && _lastTripPosition != null) {
        final dtSeconds = pos.timestamp
                .difference(_lastTripPosition!.timestamp)
                .inMilliseconds /
            1000.0;
        if (dtSeconds > 0) {
          final distMeters = Geolocator.distanceBetween(
            _lastTripPosition!.latitude,
            _lastTripPosition!.longitude,
            pos.latitude,
            pos.longitude,
          );
          final derivedMps = distMeters / dtSeconds;
          // Ignore obvious GPS-jump noise (>200 mph) from the derived calc.
          if (derivedMps * 2.23694 < 200) {
            speedMph = derivedMps * 2.23694;
          }
        }
      }

      if (_lastTripPosition != null) {
        _distanceMiles += Geolocator.distanceBetween(
              _lastTripPosition!.latitude,
              _lastTripPosition!.longitude,
              pos.latitude,
              pos.longitude,
            ) /
            1609.34;
      }

      if (speedMph > _topSpeedMph) _topSpeedMph = speedMph;
      _lastTripPosition = pos;

      final point = TripPoint(
        lat: pos.latitude,
        lng: pos.longitude,
        speedMph: speedMph,
        timestamp: pos.timestamp,
      );
      _currentTripBuffer.add(point);
      controller.add(point);
    });

    return controller.stream;
  }

  double get currentTopSpeedMph => _topSpeedMph;
  double get currentDistanceMiles => _distanceMiles;
  double get currentAvgSpeedMph {
    if (_currentTripBuffer.length < 2) return 0;
    final elapsedHours = _currentTripBuffer.last.timestamp
            .difference(_currentTripBuffer.first.timestamp)
            .inSeconds /
        3600.0;
    if (elapsedHours <= 0) return 0;
    return _distanceMiles / elapsedHours;
  }

  /// Pulls and clears any points buffered since the last flush, so the
  /// caller can batch-write them to Firestore instead of one write per fix.
  List<TripPoint> flushBufferedPoints() {
    final copy = List<TripPoint>.from(_currentTripBuffer);
    _currentTripBuffer.clear();
    return copy;
  }

  void stopTripRecording() {
    _tripSub?.cancel();
    _tripSub = null;
  }

  Future<Position> getCurrentPositionOnce() {
    return Geolocator.getCurrentPosition(
      locationSettings:
          const LocationSettings(accuracy: LocationAccuracy.bestForNavigation),
    );
  }

  void dispose() {
    _liveSub?.cancel();
    _tripSub?.cancel();
    _liveController.close();
  }
}
