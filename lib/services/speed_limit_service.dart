import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

class SpeedLimitService {
  final Map<String, double> _cacheMphByCell = {};

  Future<double> getSpeedLimitMph(double lat, double lng) async {
    final key = _gridKey(lat, lng);
    final cached = _cacheMphByCell[key];
    if (cached != null) return cached;

    final query = '''
[out:json][timeout:25];
way(around:90,$lat,$lng)[highway];
out tags center 20;
''';

    final uri = Uri.parse('https://overpass-api.de/api/interpreter')
        .replace(queryParameters: {'data': query});

    try {
      final response = await http.get(uri, headers: {'Accept': 'application/json'});
      if (response.statusCode != 200) {
        return _cacheAndReturn(key, 35);
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final elements = (decoded['elements'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (elements.isEmpty) return _cacheAndReturn(key, 35);

      double? bestLimit;
      double bestDistance = double.infinity;

      for (final e in elements) {
        final center = e['center'] as Map<String, dynamic>?;
        final tags = e['tags'] as Map<String, dynamic>?;
        if (center == null || tags == null) continue;

        final cLat = (center['lat'] as num?)?.toDouble();
        final cLng = (center['lon'] as num?)?.toDouble();
        if (cLat == null || cLng == null) continue;

        final distance = _distanceMeters(lat, lng, cLat, cLng);
        final limit = _parseSpeedLimitMph(tags['maxspeed']?.toString()) ??
            _defaultHighwaySpeedMph(tags['highway']?.toString());

        if (limit == null) continue;
        if (distance < bestDistance) {
          bestDistance = distance;
          bestLimit = limit;
        }
      }

      return _cacheAndReturn(key, bestLimit ?? 35);
    } catch (_) {
      return _cacheAndReturn(key, 35);
    }
  }

  double _cacheAndReturn(String key, double value) {
    _cacheMphByCell[key] = value;
    return value;
  }

  String _gridKey(double lat, double lng) =>
      '${lat.toStringAsFixed(3)},${lng.toStringAsFixed(3)}';

  double? _parseSpeedLimitMph(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final lower = raw.toLowerCase();
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(lower);
    if (match == null) return null;
    final value = double.tryParse(match.group(1)!);
    if (value == null) return null;
    if (lower.contains('km')) return value * 0.621371;
    return value;
  }

  double? _defaultHighwaySpeedMph(String? highway) {
    switch (highway) {
      case 'motorway':
        return 65;
      case 'trunk':
        return 55;
      case 'primary':
        return 45;
      case 'secondary':
        return 40;
      case 'tertiary':
        return 35;
      case 'residential':
      case 'living_street':
        return 25;
      case 'service':
        return 20;
      default:
        return null;
    }
  }

  double _distanceMeters(double lat1, double lon1, double lat2, double lon2) {
    const metersPerDegreeLat = 111320.0;
    final metersPerDegreeLon = metersPerDegreeLat * _cosDegrees((lat1 + lat2) / 2);
    final dx = (lon2 - lon1) * metersPerDegreeLon;
    final dy = (lat2 - lat1) * metersPerDegreeLat;
    return math.sqrt(dx * dx + dy * dy);
  }

  double _cosDegrees(double degrees) {
    final radians = degrees * 0.017453292519943295;
    return math.cos(radians);
  }
}
