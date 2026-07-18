/// A Waze-style crowd-sourced report: police, hazard, or a custom object,
/// pinned by a group member. Auto-expires so stale reports don't linger.
/// Firestore doc: groups/{groupId}/hazards/{hazardId}
enum HazardType { police, hazardObject, accident, custom }

class HazardReport {
  final String id;
  final HazardType type;
  final String label; // e.g. "Speed trap", user text for HazardType.custom
  final double lat;
  final double lng;
  final String reportedByUid;
  final String reportedByName;
  final DateTime reportedAt;
  final DateTime expiresAt;
  final int confirmCount; // other members who tapped "still there"

  HazardReport({
    required this.id,
    required this.type,
    required this.label,
    required this.lat,
    required this.lng,
    required this.reportedByUid,
    required this.reportedByName,
    required this.reportedAt,
    required this.expiresAt,
    this.confirmCount = 0,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  factory HazardReport.fromMap(String id, Map<String, dynamic> map) {
    return HazardReport(
      id: id,
      type: HazardType.values.firstWhere(
          (t) => t.name == map['type'],
          orElse: () => HazardType.custom),
      label: map['label'] ?? '',
      lat: (map['lat'] as num).toDouble(),
      lng: (map['lng'] as num).toDouble(),
      reportedByUid: map['reportedByUid'] ?? '',
      reportedByName: map['reportedByName'] ?? 'Someone',
      reportedAt: DateTime.parse(map['reportedAt']),
      expiresAt: DateTime.parse(map['expiresAt']),
      confirmCount: (map['confirmCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'type': type.name,
        'label': label,
        'lat': lat,
        'lng': lng,
        'reportedByUid': reportedByUid,
        'reportedByName': reportedByName,
        'reportedAt': reportedAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'confirmCount': confirmCount,
      };

  /// Default lifetime before a report is filtered out client-side and
  /// eligible for cleanup. Police/accident reports age out faster than
  /// generic hazards since they're more time-sensitive.
  static Duration defaultLifetime(HazardType type) {
    switch (type) {
      case HazardType.police:
        return const Duration(hours: 2);
      case HazardType.accident:
        return const Duration(hours: 4);
      default:
        return const Duration(hours: 8);
    }
  }
}
