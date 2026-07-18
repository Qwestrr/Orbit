import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/app_user.dart';
import '../models/group.dart';
import '../models/place.dart';
import '../models/trip.dart';
import '../models/hazard_report.dart';
import '../models/group_route.dart';

/// All reads/writes to Firestore live here so the rest of the app never
/// touches the database directly. Free-tier friendly: we batch location
/// writes (see LocationService) instead of writing on every GPS tick.
class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ---------------- Users ----------------

  Stream<AppUser> watchUser(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((doc) => AppUser.fromMap(uid, doc.data() ?? {}));
  }

  Future<void> updateMyLocation({
    required String uid,
    required double lat,
    required double lng,
    required double headingDegrees,
    required double speedMph,
    required double batteryLevel,
    DateTime? arrivedAtCurrentLocation,
    String? currentLocationLabel,
  }) {
    final updates = <String, dynamic>{
      'lat': lat,
      'lng': lng,
      'headingDegrees': headingDegrees,
      'speedMph': speedMph,
      'batteryLevel': batteryLevel,
      'lastUpdated': DateTime.now().toIso8601String(),
    };
    if (arrivedAtCurrentLocation != null) {
      updates['arrivedAtCurrentLocation'] =
          arrivedAtCurrentLocation.toIso8601String();
    }
    if (currentLocationLabel != null && currentLocationLabel.isNotEmpty) {
      updates['currentLocationLabel'] = currentLocationLabel;
    }
    return _db.collection('users').doc(uid).update(updates);
  }

  Future<void> setLocationSharing(String uid, bool enabled) {
    return _db
        .collection('users')
        .doc(uid)
        .update({'locationSharingEnabled': enabled});
  }

  /// Updates the user's display name and/or photo on their Firestore
  /// profile doc, so group members see the change without needing
  /// Firebase Auth read access to each other. Pass null for a field to
  /// leave it unchanged.
  Future<void> updateProfile({
    required String uid,
    String? displayName,
    String? photoUrl,
    List<String>? garageVehicles,
  }) {
    final updates = <String, dynamic>{};
    if (displayName != null) updates['displayName'] = displayName;
    if (photoUrl != null) updates['photoUrl'] = photoUrl;
    if (garageVehicles != null) updates['garageVehicles'] = garageVehicles;
    if (updates.isEmpty) return Future.value();
    return _db.collection('users').doc(uid).set(updates, SetOptions(merge: true));
  }

  // ---------------- Groups ----------------

  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no ambiguous chars
    final rand = Random.secure();
    return List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  Future<FamilyGroup> createGroup({
    required String name,
    required String ownerUid,
    String? groupPictureUrl,
  }) async {
    final code = _generateInviteCode();
    final doc = _db.collection('groups').doc();
    final group = FamilyGroup(
      id: doc.id,
      name: name,
      inviteCode: code,
      ownerUid: ownerUid,
      memberUids: [ownerUid],
      memberPermissions: {
        ownerUid: GroupMemberPermissions.ownerDefaults(),
      },
      createdAt: DateTime.now(),
      groupPictureUrl: groupPictureUrl,
    );
    await doc.set(group.toMap());
    return group;
  }

  Future<FamilyGroup?> joinGroupByInviteCode({
    required String inviteCode,
    required String uid,
  }) async {
    final query = await _db
        .collection('groups')
        .where('inviteCode', isEqualTo: inviteCode.toUpperCase())
        .limit(1)
        .get();
    if (query.docs.isEmpty) return null;

    final doc = query.docs.first;
    await doc.reference.update({
      'memberUids': FieldValue.arrayUnion([uid])
    });
    final updated = await doc.reference.get();
    return FamilyGroup.fromMap(updated.id, updated.data()!);
  }

  Future<void> leaveGroup({required String groupId, required String uid}) {
    return _db.collection('groups').doc(groupId).update({
      'memberUids': FieldValue.arrayRemove([uid]),
      'memberPermissions.$uid': FieldValue.delete(),
    });
  }

  Future<void> setMemberPermissions({
    required String groupId,
    required String memberUid,
    required GroupMemberPermissions permissions,
  }) {
    return _db.collection('groups').doc(groupId).update({
      'memberPermissions.$memberUid': permissions.toMap(),
    });
  }

  Future<void> transferGroupOwnership({
    required String groupId,
    required String newOwnerUid,
  }) async {
    final ref = _db.collection('groups').doc(groupId);
    await _db.runTransaction((txn) async {
      final snap = await txn.get(ref);
      final data = snap.data();
      if (data == null) {
        throw StateError('Group not found');
      }
      final members = List<String>.from(data['memberUids'] ?? const []);
      if (!members.contains(newOwnerUid)) {
        throw StateError('New owner must be a group member');
      }
      txn.update(ref, {
        'ownerUid': newOwnerUid,
        'memberPermissions.$newOwnerUid':
            GroupMemberPermissions.ownerDefaults().toMap(),
      });
    });
  }

  Stream<List<FamilyGroup>> watchMyGroups(String uid) {
    return _db
        .collection('groups')
        .where('memberUids', arrayContains: uid)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => FamilyGroup.fromMap(d.id, d.data())).toList());
  }

  Future<void> updateGroupTheme(String groupId, GroupTheme theme) {
    return _db
        .collection('groups')
        .doc(groupId)
        .update({'theme': theme.toMap()});
  }

  Stream<List<AppUser>> watchGroupMembers(List<String> uids) {
    if (uids.isEmpty) return Stream.value([]);
    // Firestore 'whereIn' caps at 30 - fine for a family/friend group.
    return _db
        .collection('users')
        .where(FieldPath.documentId, whereIn: uids)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => AppUser.fromMap(d.id, d.data())).toList());
  }

  // ---------------- Places ----------------

  Future<void> addPlace(String groupId, Place place) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('places')
        .doc(place.id)
        .set(place.toMap());
  }

  Future<void> deletePlace(String groupId, String placeId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('places')
        .doc(placeId)
        .delete();
  }

  Stream<List<Place>> watchPlaces(String groupId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('places')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => Place.fromMap(d.id, d.data())).toList());
  }

  // ---------------- Trips ----------------

  Future<String> startTrip(String groupId, Trip trip) async {
    final ref = _db.collection('groups').doc(groupId).collection('trips').doc();
    await ref.set(trip.toMap());
    return ref.id;
  }

  Future<void> appendTripPoints(
    String groupId,
    String tripId,
    List<TripPoint> points,
  ) async {
    final batch = _db.batch();
    final pointsRef = _db
        .collection('groups')
        .doc(groupId)
        .collection('trips')
        .doc(tripId)
        .collection('points');
    for (final p in points) {
      batch.set(pointsRef.doc(), p.toMap());
    }
    await batch.commit();
  }

  Future<void> finishTrip({
    required String groupId,
    required String tripId,
    required double distanceMiles,
    required double topSpeedMph,
    required double avgSpeedMph,
    required bool possibleAccidentDetected,
    double? maxImpactGForce,
    String? endAddress,
  }) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('trips')
        .doc(tripId)
        .update({
      'endTime': DateTime.now().toIso8601String(),
      'distanceMiles': distanceMiles,
      'topSpeedMph': topSpeedMph,
      'avgSpeedMph': avgSpeedMph,
      'possibleAccidentDetected': possibleAccidentDetected,
      'maxImpactGForce': maxImpactGForce,
      'endAddress': endAddress,
    });
  }

  Stream<List<Trip>> watchTrips(String groupId, {String? driverUid}) {
    Query<Map<String, dynamic>> q = _db
        .collection('groups')
        .doc(groupId)
        .collection('trips')
        .orderBy('startTime', descending: true)
        .limit(100);
    if (driverUid != null) {
      q = q.where('driverUid', isEqualTo: driverUid);
    }
    return q.snapshots().map(
        (snap) => snap.docs.map((d) => Trip.fromMap(d.id, d.data())).toList());
  }

  Stream<List<TripPoint>> watchTripPoints(String groupId, String tripId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('trips')
        .doc(tripId)
        .collection('points')
        .orderBy('timestamp')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => TripPoint.fromMap(d.data())).toList());
  }

  // ---------------- Hazard reports (Waze-style) ----------------

  Future<void> reportHazard(String groupId, HazardReport report) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('hazards')
        .doc(report.id)
        .set(report.toMap());
  }

  Future<void> reportHazardToGroups(
      List<String> groupIds, HazardReport report) async {
    if (groupIds.isEmpty) return;
    final batch = _db.batch();
    final uniqueIds = groupIds.toSet();
    for (final groupId in uniqueIds) {
      final ref = _db
          .collection('groups')
          .doc(groupId)
          .collection('hazards')
          .doc(report.id);
      batch.set(ref, report.toMap());
    }
    await batch.commit();
  }

  Future<void> confirmHazard(String groupId, String hazardId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('hazards')
        .doc(hazardId)
        .update({'confirmCount': FieldValue.increment(1)});
  }

  Future<void> deleteHazard(String groupId, String hazardId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('hazards')
        .doc(hazardId)
        .delete();
  }

  /// Live hazards for a group. Expired reports are filtered client-side;
  /// pair this with a scheduled Cloud Function (or a periodic client
  /// sweep) to actually delete stale docs and keep reads cheap.
  Stream<List<HazardReport>> watchHazards(String groupId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('hazards')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => HazardReport.fromMap(d.id, d.data()))
            .where((h) => !h.isExpired)
            .toList());
  }

  // ---------------- Per-user notification preferences ----------------
  // Stored at users/{uid}/groupPrefs/{groupId} so each member controls
  // their own alert settings without needing write access to the group.

  Future<void> setNotificationPrefs({
    required String uid,
    required String groupId,
    required int lowBatteryThresholdPercent,
    required List<String> batteryAlertMemberUids,
  }) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('groupPrefs')
        .doc(groupId)
        .set({
      'lowBatteryThresholdPercent': lowBatteryThresholdPercent,
      'batteryAlertMemberUids': batteryAlertMemberUids,
    });
  }

  Future<Map<String, dynamic>?> getNotificationPrefs({
    required String uid,
    required String groupId,
  }) async {
    final doc = await _db
        .collection('users')
        .doc(uid)
        .collection('groupPrefs')
        .doc(groupId)
        .get();
    return doc.data();
  }

  // ---------------- Member custom notifications ----------------

  Future<void> sendGroupMemberNotification({
    required String groupId,
    required String fromUid,
    required String fromName,
    required String toUid,
    required String toName,
    required String label,
    required String message,
    required bool isExplicit,
  }) {
    final ref = _db
        .collection('groups')
        .doc(groupId)
        .collection('memberNotifications')
        .doc();

    return ref.set({
      'id': ref.id,
      'fromUid': fromUid,
      'fromName': fromName,
      'toUid': toUid,
      'toName': toName,
      'label': label,
      'message': message,
      'isExplicit': isExplicit,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  Stream<List<Map<String, dynamic>>> watchIncomingMemberNotifications({
    required String groupId,
    required String toUid,
  }) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('memberNotifications')
        .where('toUid', isEqualTo: toUid)
        .limit(50)
        .snapshots()
        .map((snap) {
      final items = snap.docs
          .map((d) => {
                'id': d.id,
                ...d.data(),
              })
          .toList();

      items.sort((a, b) {
        final aTime = DateTime.tryParse((a['createdAt'] ?? '') as String) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = DateTime.tryParse((b['createdAt'] ?? '') as String) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });
      return items;
    });
  }

  // ---------------- Group routes ----------------

  Future<String> createGroupRoute({
    required String groupId,
    required GroupRoute route,
  }) async {
    final ref =
        _db.collection('groups').doc(groupId).collection('groupRoutes').doc();
    await ref.set(route.toMap());
    return ref.id;
  }

  Stream<List<GroupRoute>> watchGroupRoutes(String groupId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('groupRoutes')
        .orderBy('createdAt', descending: true)
        .limit(30)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => GroupRoute.fromMap(d.id, groupId, d.data()))
            .toList());
  }

  Future<void> updateGroupRouteParticipant({
    required String groupId,
    required String routeId,
    required String uid,
    required String displayName,
    required double topSpeedMph,
    DateTime? arrivedAt,
  }) {
    final updates = <String, dynamic>{
      'participantStats.$uid.displayName': displayName,
      'participantStats.$uid.topSpeedMph': topSpeedMph,
    };
    if (arrivedAt != null) {
      updates['participantStats.$uid.arrivedAt'] = arrivedAt.toIso8601String();
    }

    return _db
        .collection('groups')
        .doc(groupId)
        .collection('groupRoutes')
        .doc(routeId)
        .update(updates);
  }

  Future<void> finishGroupRoute({
    required String groupId,
    required String routeId,
  }) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('groupRoutes')
        .doc(routeId)
        .update({
      'isCompleted': true,
      'completedAt': DateTime.now().toIso8601String(),
    });
  }
}
