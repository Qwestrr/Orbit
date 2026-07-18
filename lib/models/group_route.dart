class RouteEndpoint {
  final String label;
  final double lat;
  final double lng;
  final double? radiusMeters;

  const RouteEndpoint({
    required this.label,
    required this.lat,
    required this.lng,
    this.radiusMeters,
  });

  factory RouteEndpoint.fromMap(Map<String, dynamic> map) {
    return RouteEndpoint(
      label: map['label'] as String? ?? 'Location',
      lat: (map['lat'] as num?)?.toDouble() ?? 0,
      lng: (map['lng'] as num?)?.toDouble() ?? 0,
      radiusMeters: (map['radiusMeters'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'label': label,
      'lat': lat,
      'lng': lng,
      if (radiusMeters != null) 'radiusMeters': radiusMeters,
    };
  }
}

class GroupRouteParticipant {
  final String uid;
  final String displayName;
  final double topSpeedMph;
  final DateTime? arrivedAt;

  const GroupRouteParticipant({
    required this.uid,
    required this.displayName,
    required this.topSpeedMph,
    this.arrivedAt,
  });

  factory GroupRouteParticipant.fromMap(String uid, Map<String, dynamic> map) {
    return GroupRouteParticipant(
      uid: uid,
      displayName: map['displayName'] as String? ?? 'Member',
      topSpeedMph: (map['topSpeedMph'] as num?)?.toDouble() ?? 0,
      arrivedAt: map['arrivedAt'] != null
          ? DateTime.tryParse(map['arrivedAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'displayName': displayName,
      'topSpeedMph': topSpeedMph,
      if (arrivedAt != null) 'arrivedAt': arrivedAt!.toIso8601String(),
    };
  }
}

class GroupRoute {
  final String id;
  final String groupId;
  final String createdByUid;
  final String createdByName;
  final RouteEndpoint start;
  final RouteEndpoint destination;
  final List<String> visibleMemberUids;
  final DateTime createdAt;
  final DateTime? completedAt;
  final bool isCompleted;
  final Map<String, GroupRouteParticipant> participantStats;

  const GroupRoute({
    required this.id,
    required this.groupId,
    required this.createdByUid,
    required this.createdByName,
    required this.start,
    required this.destination,
    required this.visibleMemberUids,
    required this.createdAt,
    required this.completedAt,
    required this.isCompleted,
    required this.participantStats,
  });

  factory GroupRoute.fromMap(
      String id, String groupId, Map<String, dynamic> map) {
    final rawParticipants = map['participantStats'];
    final participants = <String, GroupRouteParticipant>{};
    if (rawParticipants is Map) {
      rawParticipants.forEach((key, value) {
        if (key is String && value is Map<String, dynamic>) {
          participants[key] = GroupRouteParticipant.fromMap(key, value);
        } else if (key is String && value is Map) {
          participants[key] = GroupRouteParticipant.fromMap(
              key, Map<String, dynamic>.from(value));
        }
      });
    }

    return GroupRoute(
      id: id,
      groupId: groupId,
      createdByUid: map['createdByUid'] as String? ?? '',
      createdByName: map['createdByName'] as String? ?? 'Member',
      start: RouteEndpoint.fromMap(
        Map<String, dynamic>.from(map['start'] as Map? ?? const {}),
      ),
      destination: RouteEndpoint.fromMap(
        Map<String, dynamic>.from(map['destination'] as Map? ?? const {}),
      ),
      visibleMemberUids:
          List<String>.from(map['visibleMemberUids'] as List? ?? const []),
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ??
          DateTime.now(),
      completedAt: map['completedAt'] != null
          ? DateTime.tryParse(map['completedAt'] as String)
          : null,
      isCompleted: map['isCompleted'] == true,
      participantStats: participants,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'createdByUid': createdByUid,
      'createdByName': createdByName,
      'start': start.toMap(),
      'destination': destination.toMap(),
      'visibleMemberUids': visibleMemberUids,
      'createdAt': createdAt.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'isCompleted': isCompleted,
      'participantStats':
          participantStats.map((k, v) => MapEntry(k, v.toMap())),
    };
  }

  bool canView(String uid) => visibleMemberUids.contains(uid);

  bool get allVisibleMembersArrived {
    if (visibleMemberUids.isEmpty) return false;
    for (final uid in visibleMemberUids) {
      final p = participantStats[uid];
      if (p == null || p.arrivedAt == null) return false;
    }
    return true;
  }
}
