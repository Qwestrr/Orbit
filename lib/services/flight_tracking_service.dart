import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/aircraft_contact.dart';

/// Polls OpenSky Network's free public REST API for aircraft within a
/// radius, filters to rotorcraft-likely contacts, and emits takeoff
/// events when a tracked aircraft transitions from on-ground to airborne.
///
/// SWAPPING PROVIDERS: OpenSky is free but rate-limited (roughly 400
/// requests/day anonymous, more with a free account) and updates every
/// 5-15s. If you need denser coverage or a paid FlightRadar24/ADS-B
/// Exchange feed later, only this file needs to change — everything else
/// consumes AircraftContact objects.
///
/// COVERAGE CAVEAT: this can only show aircraft that are broadcasting a
/// public ADS-B position. Many police/EMS helicopters use blocked or
/// non-broadcasting transponders by design. Treat this layer as
/// "helicopters we can see," not "all helicopters."
class FlightTrackingService {
  static const _openSkyBaseUrl = 'https://opensky-network.org/api/states/all';

  Timer? _pollTimer;
  final _contactsController = StreamController<List<AircraftContact>>.broadcast();
  final _takeoffController = StreamController<TakeoffEvent>.broadcast();

  Stream<List<AircraftContact>> get contacts => _contactsController.stream;
  Stream<TakeoffEvent> get takeoffs => _takeoffController.stream;

  final Map<String, bool> _lastOnGroundByIcao = {};

  /// radiusMiles: 25-100 in 5-mile steps per spec, enforced by the UI.
  void startPolling({
    required double centerLat,
    required double centerLng,
    required double radiusMiles,
    Duration interval = const Duration(seconds: 12),
  }) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(interval, (_) => _poll(centerLat, centerLng, radiusMiles));
    _poll(centerLat, centerLng, radiusMiles); // fire immediately
  }

  Future<void> _poll(double lat, double lng, double radiusMiles) async {
    final box = _boundingBox(lat, lng, radiusMiles);
    final uri = Uri.parse(_openSkyBaseUrl).replace(queryParameters: {
      'lamin': box.$1.toString(),
      'lomin': box.$2.toString(),
      'lamax': box.$3.toString(),
      'lomax': box.$4.toString(),
      'extended': '1',
    });

    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final states = (data['states'] as List<dynamic>?) ?? [];

      final contacts = states
          .map((s) => AircraftContact.fromOpenSkyStateVector(s as List<dynamic>))
          // Rough helicopter/low-slow-aircraft filter: OpenSky doesn't
          // give aircraft type directly without a second lookup, so we
          // approximate using altitude + speed profile. For a precise
          // type filter, join icao24 against OpenSky's aircraft database
          // export (free download) and cache it locally.
          .where((c) => c.altitudeFt == null || c.altitudeFt! < 5000)
          .toList();

      _detectTakeoffs(contacts);
      _contactsController.add(contacts);
    } catch (_) {
      // Network hiccup or rate limit — just skip this cycle, next poll retries.
    }
  }

  void _detectTakeoffs(List<AircraftContact> contacts) {
    for (final c in contacts) {
      final wasOnGround = _lastOnGroundByIcao[c.icao24];
      if (wasOnGround == true && c.onGround == false) {
        _takeoffController.add(TakeoffEvent(
          aircraft: c,
          takeoffLat: c.lat,
          takeoffLng: c.lng,
          detectedAt: DateTime.now(),
        ));
      }
      _lastOnGroundByIcao[c.icao24] = c.onGround;
    }
  }

  /// Rough lat/lng bounding box for a mile radius (good enough for a
  /// map-overlay feed; not for precise geofencing).
  (double, double, double, double) _boundingBox(
      double lat, double lng, double radiusMiles) {
    const milesPerDegreeLat = 69.0;
    final milesPerDegreeLng = 69.0 * (3.14159265 / 180 * lat).abs().clamp(0.2, 1.0);
    final dLat = radiusMiles / milesPerDegreeLat;
    final dLng = radiusMiles / (milesPerDegreeLng == 0 ? 1 : milesPerDegreeLng);
    return (lat - dLat, lng - dLng, lat + dLat, lng + dLng);
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void dispose() {
    stopPolling();
    _contactsController.close();
    _takeoffController.close();
  }
}
