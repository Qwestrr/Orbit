/// A group of people sharing location with each other.
/// Firestore doc: groups/{groupId}
class FamilyGroup {
  final String id;
  final String name;
  final String inviteCode; // short human-shareable code, e.g. "7K2QRT"
  final String ownerUid;
  final List<String> memberUids;
  final Map<String, GroupMemberPermissions> memberPermissions;
  final DateTime createdAt;
  final GroupTheme theme;
  final String? groupPictureUrl; // Firebase Storage URL for group picture

  FamilyGroup({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.ownerUid,
    required this.memberUids,
    Map<String, GroupMemberPermissions>? memberPermissions,
    required this.createdAt,
    GroupTheme? theme,
    this.groupPictureUrl,
  })  : memberPermissions = memberPermissions ?? const {},
        theme = theme ?? GroupTheme.defaultTheme();

  factory FamilyGroup.fromMap(String id, Map<String, dynamic> map) {
    return FamilyGroup(
      id: id,
      name: map['name'] ?? 'My Group',
      inviteCode: map['inviteCode'] ?? '',
      ownerUid: map['ownerUid'] ?? '',
      memberUids: List<String>.from(map['memberUids'] ?? []),
        memberPermissions: _parseMemberPermissions(map['memberPermissions']),
      createdAt:
          DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
      theme: map['theme'] != null
          ? GroupTheme.fromMap(Map<String, dynamic>.from(map['theme']))
          : GroupTheme.defaultTheme(),
      groupPictureUrl: map['groupPictureUrl'],
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'inviteCode': inviteCode,
        'ownerUid': ownerUid,
        'memberUids': memberUids,
        'memberPermissions': memberPermissions
            .map((uid, p) => MapEntry(uid, p.toMap())),
        'createdAt': createdAt.toIso8601String(),
        'theme': theme.toMap(),
        'groupPictureUrl': groupPictureUrl,
      };

  bool isOwner(String uid) => ownerUid == uid;

  GroupMemberPermissions permissionsFor(String uid) {
    if (isOwner(uid)) return GroupMemberPermissions.ownerDefaults();
    return memberPermissions[uid] ?? GroupMemberPermissions.none();
  }

  bool canManagePlaces(String uid) => permissionsFor(uid).canManagePlaces;

  bool canEditPlaceDetails(String uid) => permissionsFor(uid).canEditPlaceDetails;

  static Map<String, GroupMemberPermissions> _parseMemberPermissions(
    dynamic raw,
  ) {
    if (raw is! Map) return const {};
    final out = <String, GroupMemberPermissions>{};
    raw.forEach((key, value) {
      if (key is String && value is Map<String, dynamic>) {
        out[key] = GroupMemberPermissions.fromMap(value);
      } else if (key is String && value is Map) {
        out[key] =
            GroupMemberPermissions.fromMap(Map<String, dynamic>.from(value));
      }
    });
    return out;
  }
}

class GroupMemberPermissions {
  final bool canManagePlaces;
  final bool canEditPlaceDetails;

  const GroupMemberPermissions({
    required this.canManagePlaces,
    required this.canEditPlaceDetails,
  });

  factory GroupMemberPermissions.none() => const GroupMemberPermissions(
        canManagePlaces: false,
        canEditPlaceDetails: false,
      );

  factory GroupMemberPermissions.ownerDefaults() =>
      const GroupMemberPermissions(
        canManagePlaces: true,
        canEditPlaceDetails: true,
      );

  factory GroupMemberPermissions.fromMap(Map<String, dynamic> map) =>
      GroupMemberPermissions(
        canManagePlaces: map['canManagePlaces'] == true,
        canEditPlaceDetails: map['canEditPlaceDetails'] == true,
      );

  Map<String, dynamic> toMap() => {
        'canManagePlaces': canManagePlaces,
        'canEditPlaceDetails': canEditPlaceDetails,
      };

  GroupMemberPermissions copyWith({
    bool? canManagePlaces,
    bool? canEditPlaceDetails,
  }) =>
      GroupMemberPermissions(
        canManagePlaces: canManagePlaces ?? this.canManagePlaces,
        canEditPlaceDetails: canEditPlaceDetails ?? this.canEditPlaceDetails,
      );
}

/// Per-group color scheme. Stored as plain ARGB ints so it round-trips
/// through Firestore cleanly; converted to Color in the UI layer.
/// Switching active groups swaps these in app-wide (see AppearanceProvider).
class GroupTheme {
  final int primaryColorArgb;      // group tab / accent color
  final int memberListTabColorArgb;
  final int buttonOutlineColorArgb;
  final int textColorArgb;

  GroupTheme({
    required this.primaryColorArgb,
    required this.memberListTabColorArgb,
    required this.buttonOutlineColorArgb,
    required this.textColorArgb,
  });

  factory GroupTheme.defaultTheme() => GroupTheme(
        primaryColorArgb: 0xFF3F51B5, // indigo
        memberListTabColorArgb: 0xFF3F51B5,
        buttonOutlineColorArgb: 0xFF3F51B5,
        textColorArgb: 0xFF000000,
      );

  factory GroupTheme.fromMap(Map<String, dynamic> map) => GroupTheme(
        primaryColorArgb: map['primaryColorArgb'] ?? 0xFF3F51B5,
        memberListTabColorArgb: map['memberListTabColorArgb'] ?? 0xFF3F51B5,
        buttonOutlineColorArgb: map['buttonOutlineColorArgb'] ?? 0xFF3F51B5,
        textColorArgb: map['textColorArgb'] ?? 0xFF000000,
      );

  Map<String, dynamic> toMap() => {
        'primaryColorArgb': primaryColorArgb,
        'memberListTabColorArgb': memberListTabColorArgb,
        'buttonOutlineColorArgb': buttonOutlineColorArgb,
        'textColorArgb': textColorArgb,
      };

  GroupTheme copyWith({
    int? primaryColorArgb,
    int? memberListTabColorArgb,
    int? buttonOutlineColorArgb,
    int? textColorArgb,
  }) =>
      GroupTheme(
        primaryColorArgb: primaryColorArgb ?? this.primaryColorArgb,
        memberListTabColorArgb:
            memberListTabColorArgb ?? this.memberListTabColorArgb,
        buttonOutlineColorArgb:
            buttonOutlineColorArgb ?? this.buttonOutlineColorArgb,
        textColorArgb: textColorArgb ?? this.textColorArgb,
      );
}
