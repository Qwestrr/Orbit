/// Represents a member of a group. Mirrors a document in
/// Firestore: users/{uid}
class AppUser {
  final String uid;
  final String displayName;
  final String? photoUrl;
  final List<String> garageVehicles;
  final double? lat;
  final double? lng;
  final double? headingDegrees;
  final double? speedMph;
  final DateTime? lastUpdated;
  final double batteryLevel; // 0-100
  final bool locationSharingEnabled;
  final DateTime? arrivedAtCurrentLocation; // for "here for 2h 15m" display
  final String? currentLocationLabel;

  AppUser({
    required this.uid,
    required this.displayName,
    this.photoUrl,
    this.garageVehicles = const [],
    this.lat,
    this.lng,
    this.headingDegrees,
    this.speedMph,
    this.lastUpdated,
    this.batteryLevel = 100,
    this.locationSharingEnabled = true,
    this.arrivedAtCurrentLocation,
    this.currentLocationLabel,
  });

  factory AppUser.fromMap(String uid, Map<String, dynamic> map) {
    return AppUser(
      uid: uid,
      displayName: map['displayName'] ?? 'Unknown',
      photoUrl: map['photoUrl'],
        garageVehicles: (map['garageVehicles'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .map((v) => v.trim())
          .where((v) => v.isNotEmpty)
          .toList(),
      lat: (map['lat'] as num?)?.toDouble(),
      lng: (map['lng'] as num?)?.toDouble(),
      headingDegrees: (map['headingDegrees'] as num?)?.toDouble(),
      speedMph: (map['speedMph'] as num?)?.toDouble(),
      lastUpdated: map['lastUpdated'] != null
          ? DateTime.tryParse(map['lastUpdated'])
          : null,
      batteryLevel: (map['batteryLevel'] as num?)?.toDouble() ?? 100,
      locationSharingEnabled: map['locationSharingEnabled'] ?? true,
      arrivedAtCurrentLocation: map['arrivedAtCurrentLocation'] != null
          ? DateTime.tryParse(map['arrivedAtCurrentLocation'])
          : null,
      currentLocationLabel: map['currentLocationLabel'],
    );
  }

  Map<String, dynamic> toMap() => {
        'displayName': displayName,
        'photoUrl': photoUrl,
      'garageVehicles': garageVehicles,
        'lat': lat,
        'lng': lng,
        'headingDegrees': headingDegrees,
        'speedMph': speedMph,
        'lastUpdated': (lastUpdated ?? DateTime.now()).toIso8601String(),
        'batteryLevel': batteryLevel,
        'locationSharingEnabled': locationSharingEnabled,
        'arrivedAtCurrentLocation':
            arrivedAtCurrentLocation?.toIso8601String(),
          'currentLocationLabel': currentLocationLabel,
      };
}
