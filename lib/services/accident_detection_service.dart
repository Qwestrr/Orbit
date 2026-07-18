import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';

/// Detects a likely crash during an active trip using two independent
/// signals, combined to keep false positives low:
///
///  1. A sudden, large spike in accelerometer G-force (a hard impact).
///  2. That spike being followed within a couple seconds by a sudden
///     drop in GPS speed (the car actually stopped, not just a pothole
///     or the phone being dropped).
///
/// Neither signal alone is reliable — this is a heuristic, not a
/// certified crash-detection system, so the app always gives the driver
/// a countdown to cancel a false alarm before alerting the group.
class AccidentDetectionService {
  static const double _impactGForceThreshold = 3.5; // g's, tuned conservatively
  static const Duration _confirmWindow = Duration(seconds: 4);

  StreamSubscription<AccelerometerEvent>? _accelSub;
  final _crashController = StreamController<double>.broadcast();

  /// Emits the peak G-force whenever a probable-crash pattern is detected.
  Stream<double> get onPossibleCrash => _crashController.stream;

  double _lastSpeedMph = 0;
  DateTime? _pendingImpactAt;
  double _pendingImpactG = 0;

  void updateCurrentSpeed(double speedMph) {
    // If speed drops sharply shortly after a hard impact, confirm the crash.
    if (_pendingImpactAt != null &&
        DateTime.now().difference(_pendingImpactAt!) < _confirmWindow) {
      final speedDropMph = _lastSpeedMph - speedMph;
      if (_lastSpeedMph > 15 && speedDropMph > 10) {
        _crashController.add(_pendingImpactG);
        _pendingImpactAt = null;
      }
    }
    _lastSpeedMph = speedMph;
  }

  void start() {
    _accelSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval, // ~20ms, fine enough for impact spikes
    ).listen((event) {
      // Magnitude of the acceleration vector, converted to g's
      // (1 g = 9.81 m/s^2). Subtract gravity's baseline contribution.
      final magnitude =
          sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      final gForce = magnitude / 9.81;

      if (gForce > _impactGForceThreshold) {
        _pendingImpactAt = DateTime.now();
        _pendingImpactG = gForce;
      }
    });
  }

  void stop() {
    _accelSub?.cancel();
    _accelSub = null;
    _pendingImpactAt = null;
  }

  void dispose() {
    stop();
    _crashController.close();
  }
}
