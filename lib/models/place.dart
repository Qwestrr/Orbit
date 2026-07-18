/// A saved, named location with a geofence radius, e.g. "Home", "School".
/// Firestore doc: groups/{groupId}/places/{placeId}
/// Min/max place geofence radius, per spec: 50ft to 1000ft in 25ft steps.
const double kPlaceMinRadiusFeet = 50;
const double kPlaceMaxRadiusFeet = 1000;
const double kPlaceRadiusStepFeet = 25;

double feetToMeters(double feet) => feet * 0.3048;
double metersToFeet(double meters) => meters / 0.3048;

class Place {
  final String id;
  final String name;
  final String icon; // key into the built-in icon set, e.g. 'home', 'school'
  final String? customIconUrl; // Firebase Storage URL if imported from photos
  final double lat;
  final double lng;
  final double radiusMeters;
  final bool notifyOnArrival;
  final bool notifyOnDeparture;
  final String createdByUid;

  Place({
    required this.id,
    required this.name,
    required this.icon,
    this.customIconUrl,
    required this.lat,
    required this.lng,
    this.radiusMeters = 150,
    this.notifyOnArrival = true,
    this.notifyOnDeparture = true,
    required this.createdByUid,
  });

  factory Place.fromMap(String id, Map<String, dynamic> map) {
    return Place(
      id: id,
      name: map['name'] ?? 'Place',
      icon: map['icon'] ?? 'pin',
      customIconUrl: map['customIconUrl'],
      lat: (map['lat'] as num).toDouble(),
      lng: (map['lng'] as num).toDouble(),
      radiusMeters: (map['radiusMeters'] as num?)?.toDouble() ?? 150,
      notifyOnArrival: map['notifyOnArrival'] ?? true,
      notifyOnDeparture: map['notifyOnDeparture'] ?? true,
      createdByUid: map['createdByUid'] ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'icon': icon,
        'customIconUrl': customIconUrl,
        'lat': lat,
        'lng': lng,
        'radiusMeters': radiusMeters,
        'notifyOnArrival': notifyOnArrival,
        'notifyOnDeparture': notifyOnDeparture,
        'createdByUid': createdByUid,
      };
}

/// Built-in place icon choices, shown alongside "import from photos."
const Map<String, String> kBuiltInPlaceIcons = {
  'home': 'Home',
  'school': 'School',
  'work': 'Work',
  'gym': 'Gym',
  'store': 'Store',
  'restaurant': 'Restaurant',
  'hospital': 'Hospital',
  'pin': 'Other',
};
