/// A single GPS sample captured during a trip.
class TripPoint {
  final double lat;
  final double lng;
  final double speedMph;
  final DateTime timestamp;

  TripPoint({
    required this.lat,
    required this.lng,
    required this.speedMph,
    required this.timestamp,
  });

  factory TripPoint.fromMap(Map<String, dynamic> map) => TripPoint(
        lat: (map['lat'] as num).toDouble(),
        lng: (map['lng'] as num).toDouble(),
        speedMph: (map['speedMph'] as num).toDouble(),
        timestamp: DateTime.parse(map['timestamp']),
      );

  Map<String, dynamic> toMap() => {
        'lat': lat,
        'lng': lng,
        'speedMph': speedMph,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// A recorded trip: start to end, with the full speed/GPS trace.
/// Firestore doc: groups/{groupId}/trips/{tripId}
/// Points are stored as a subcollection (trips/{tripId}/points) to keep
/// the parent doc small and support very long trips.
class Trip {
  final String id;
  final String driverUid;
  final String driverName;
  final DateTime startTime;
  final DateTime? endTime;
  final double distanceMiles;
  final double topSpeedMph;
  final double avgSpeedMph;
  final bool possibleAccidentDetected;
  final double? maxImpactGForce;
  final String? startAddress;
  final String? endAddress;

  Trip({
    required this.id,
    required this.driverUid,
    required this.driverName,
    required this.startTime,
    this.endTime,
    this.distanceMiles = 0,
    this.topSpeedMph = 0,
    this.avgSpeedMph = 0,
    this.possibleAccidentDetected = false,
    this.maxImpactGForce,
    this.startAddress,
    this.endAddress,
  });

  Duration get duration =>
      (endTime ?? DateTime.now()).difference(startTime);

  factory Trip.fromMap(String id, Map<String, dynamic> map) {
    return Trip(
      id: id,
      driverUid: map['driverUid'] ?? '',
      driverName: map['driverName'] ?? 'Unknown',
      startTime: DateTime.parse(map['startTime']),
      endTime:
          map['endTime'] != null ? DateTime.parse(map['endTime']) : null,
      distanceMiles: (map['distanceMiles'] as num?)?.toDouble() ?? 0,
      topSpeedMph: (map['topSpeedMph'] as num?)?.toDouble() ?? 0,
      avgSpeedMph: (map['avgSpeedMph'] as num?)?.toDouble() ?? 0,
      possibleAccidentDetected: map['possibleAccidentDetected'] ?? false,
      maxImpactGForce: (map['maxImpactGForce'] as num?)?.toDouble(),
      startAddress: map['startAddress'],
      endAddress: map['endAddress'],
    );
  }

  Map<String, dynamic> toMap() => {
        'driverUid': driverUid,
        'driverName': driverName,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime?.toIso8601String(),
        'distanceMiles': distanceMiles,
        'topSpeedMph': topSpeedMph,
        'avgSpeedMph': avgSpeedMph,
        'possibleAccidentDetected': possibleAccidentDetected,
        'maxImpactGForce': maxImpactGForce,
        'startAddress': startAddress,
        'endAddress': endAddress,
      };
}
