import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import '../models/app_user.dart';
import '../models/custom_quick_notification_template.dart';
import '../models/group.dart';
import '../models/trip.dart';
import '../models/aircraft_contact.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/location_service.dart';
import '../services/accident_detection_service.dart';
import '../services/flight_tracking_service.dart';

/// Central app state: current user, active group, live member locations,
/// the currently-recording trip (if any), and the live helicopter feed.
/// Screens read from this via Provider instead of talking to services
/// directly.
class AppState extends ChangeNotifier {
  static const String _customQuickNotificationsPrefsKey =
      'appSettings.customQuickNotifications';

  final AuthService auth = AuthService();
  final FirestoreService firestore = FirestoreService();
  final LocationService location = LocationService();
  final AccidentDetectionService accidentDetection = AccidentDetectionService();
  final FlightTrackingService flightTracking = FlightTrackingService();
  final Battery _battery = Battery();

  FamilyGroup? activeGroup;
  List<FamilyGroup> myGroups = [];
  List<AppUser> groupMembers = [];

  bool isTripActive = false;
  String? _activeTripId;
  Timer? _tripFlushTimer;
  StreamSubscription? _tripPointSub;
  StreamSubscription? _crashSub;
  StreamSubscription<BatteryState>? _batterySub;

  // ---------------- Helicopter overlay ----------------
  List<AircraftContact> aircraft = [];
  double helicopterRadiusMiles = 25; // spec: 25-100mi, 5mi steps
  StreamSubscription? _aircraftSub;
  StreamSubscription<TakeoffEvent>? _takeoffSub;

  /// Fired when a new takeoff is detected; the UI shows a dismissible
  /// top-right banner and can pan the map to the event's location.
  final takeoffAlertController = StreamController<TakeoffEvent>.broadcast();

  /// Fired when the accident heuristic fires, so the UI can show the
  /// cancel-countdown dialog. Value is peak G-force for context.
  final crashAlertController = StreamController<double>.broadcast();

  StreamSubscription? _groupsSub;
  StreamSubscription? _membersSub;
  Position? _lastUploadedPosition;
  DateTime _arrivedAtCurrentLocation = DateTime.now();
  DateTime? _lastGeocodeAt;
  String? _cachedLocationLabel;

  bool _notificationsEnabled = true;
  bool _helicopterAlertsEnabled = true;
  bool _policeAlertsEnabled = true;
  bool _accidentAlertsEnabled = true;
  bool _roadHazardAlertsEnabled = true;
  bool _batteryAlertsEnabled = true;
  bool _crashDetectionEnabled = true;
  bool _customInAppNotificationsEnabled = true;
  bool _allowExplicitCustomNotifications = false;
  List<CustomQuickNotificationTemplate> _customQuickNotificationTemplates =
      <CustomQuickNotificationTemplate>[];
  String? _selectedGroupId;

  static const double _arrivalResetDistanceMeters = 80;
  static const double _reverseGeocodeDistanceMeters = 120;
  static const Duration _reverseGeocodeMaxAge = Duration(minutes: 4);

  bool get notificationsEnabled => _notificationsEnabled;
  bool get helicopterAlertsEnabled => _helicopterAlertsEnabled;
  bool get policeAlertsEnabled => _policeAlertsEnabled;
  bool get accidentAlertsEnabled => _accidentAlertsEnabled;
  bool get roadHazardAlertsEnabled => _roadHazardAlertsEnabled;
  bool get batteryAlertsEnabled => _batteryAlertsEnabled;
  bool get crashDetectionEnabled => _crashDetectionEnabled;
  bool get customInAppNotificationsEnabled => _customInAppNotificationsEnabled;
  bool get allowExplicitCustomNotifications =>
      _allowExplicitCustomNotifications;
    List<CustomQuickNotificationTemplate> get customQuickNotificationTemplates =>
      List.unmodifiable(_customQuickNotificationTemplates);

  Future<void> _loadRuntimeSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _notificationsEnabled =
        prefs.getBool('appSettings.notificationsEnabled') ?? true;
    _helicopterAlertsEnabled =
        prefs.getBool('appSettings.helicopterAlerts') ?? true;
    _policeAlertsEnabled = prefs.getBool('appSettings.policeAlerts') ?? true;
    _accidentAlertsEnabled =
        prefs.getBool('appSettings.accidentAlerts') ?? true;
    _roadHazardAlertsEnabled =
        prefs.getBool('appSettings.hazardAlerts') ?? true;
    _batteryAlertsEnabled = prefs.getBool('appSettings.batteryAlerts') ?? true;
    _crashDetectionEnabled =
        prefs.getBool('appSettings.crashDetection') ?? true;
    _customInAppNotificationsEnabled =
      prefs.getBool('appSettings.customInAppNotifications') ?? true;
    _allowExplicitCustomNotifications =
      prefs.getBool('appSettings.allowExplicitCustomNotifications') ?? false;
    final storedTemplates = prefs.getStringList(_customQuickNotificationsPrefsKey) ??
        const <String>[];
    _customQuickNotificationTemplates = storedTemplates
        .map((entry) {
          final decoded = jsonDecode(entry);
          if (decoded is Map<String, dynamic>) {
            return CustomQuickNotificationTemplate.fromJson(decoded);
          }
          if (decoded is Map) {
            return CustomQuickNotificationTemplate.fromJson(
              Map<String, dynamic>.from(decoded),
            );
          }
          return null;
        })
        .whereType<CustomQuickNotificationTemplate>()
        .where((template) => template.id.isNotEmpty)
        .toList();
  }

  Future<void> _persistCustomQuickNotificationTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _customQuickNotificationsPrefsKey,
      _customQuickNotificationTemplates
          .map((template) => jsonEncode(template.toJson()))
          .toList(),
    );
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    _notificationsEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('appSettings.notificationsEnabled', enabled);
    notifyListeners();
  }

  Future<void> setHelicopterAlertsEnabled(bool enabled) async {
    _helicopterAlertsEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('appSettings.helicopterAlerts', enabled);
    notifyListeners();
  }

  Future<void> setPoliceAlertsEnabled(bool enabled) async {
    _policeAlertsEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('appSettings.policeAlerts', enabled);
    notifyListeners();
  }

  Future<void> setAccidentAlertsEnabled(bool enabled) async {
    _accidentAlertsEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('appSettings.accidentAlerts', enabled);
    notifyListeners();
  }

  Future<void> setRoadHazardAlertsEnabled(bool enabled) async {
    _roadHazardAlertsEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('appSettings.hazardAlerts', enabled);
    notifyListeners();
  }

  Future<void> setBatteryAlertsEnabled(bool enabled) async {
    _batteryAlertsEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('appSettings.batteryAlerts', enabled);
    notifyListeners();
  }

  Future<void> setCrashDetectionEnabled(bool enabled) async {
    _crashDetectionEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('appSettings.crashDetection', enabled);

    if (isTripActive) {
      if (enabled) {
        _startCrashMonitoringIfNeeded();
      } else {
        _stopCrashMonitoring();
      }
    }

    notifyListeners();
  }

  Future<void> setCustomInAppNotificationsEnabled(bool enabled) async {
    _customInAppNotificationsEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('appSettings.customInAppNotifications', enabled);
    notifyListeners();
  }

  Future<void> setAllowExplicitCustomNotifications(bool enabled) async {
    _allowExplicitCustomNotifications = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('appSettings.allowExplicitCustomNotifications', enabled);
    notifyListeners();
  }

  Future<void> setCustomQuickNotificationTemplates(
    List<CustomQuickNotificationTemplate> templates,
  ) async {
    _customQuickNotificationTemplates = List<CustomQuickNotificationTemplate>.from(templates);
    await _persistCustomQuickNotificationTemplates();
    notifyListeners();
  }

  Future<void> addCustomQuickNotificationTemplate(
    CustomQuickNotificationTemplate template,
  ) async {
    _customQuickNotificationTemplates = [
      ..._customQuickNotificationTemplates,
      template,
    ];
    await _persistCustomQuickNotificationTemplates();
    notifyListeners();
  }

  Future<void> updateCustomQuickNotificationTemplate(
    CustomQuickNotificationTemplate template,
  ) async {
    _customQuickNotificationTemplates = _customQuickNotificationTemplates
        .map((existing) => existing.id == template.id ? template : existing)
        .toList();
    await _persistCustomQuickNotificationTemplates();
    notifyListeners();
  }

  Future<void> removeCustomQuickNotificationTemplate(String id) async {
    _customQuickNotificationTemplates = _customQuickNotificationTemplates
        .where((template) => template.id != id)
        .toList();
    await _persistCustomQuickNotificationTemplates();
    notifyListeners();
  }

  Future<void> clearCustomQuickNotificationTemplates() async {
    _customQuickNotificationTemplates = <CustomQuickNotificationTemplate>[];
    await _persistCustomQuickNotificationTemplates();
    notifyListeners();
  }

  Future<void> initializeLocationAccess(BuildContext context) async {
    final status = await location.ensurePermissions(context: context);
    if (status != LocationAccessStatus.granted) {
      debugPrint('Location access not granted: $status');
    }
  }

  Future<void> initForUser(String uid) async {
    await _loadRuntimeSettings();
    final prefs = await SharedPreferences.getInstance();
    _selectedGroupId = prefs.getString(_selectedGroupPrefsKey(uid));

    _groupsSub?.cancel();
    _groupsSub = firestore.watchMyGroups(uid).listen(
      (groups) {
        myGroups = groups;
        if (activeGroup == null && groups.isNotEmpty) {
          final preferredGroup = _pickPreferredGroup(groups);
          if (preferredGroup != null) {
            setActiveGroup(preferredGroup);
          }
        } else if (activeGroup != null) {
          final refreshed = groups.where((g) => g.id == activeGroup!.id);
          if (refreshed.isNotEmpty) {
            activeGroup = refreshed.first;
          } else if (groups.isNotEmpty) {
            final preferredGroup = _pickPreferredGroup(groups);
            if (preferredGroup != null) {
              setActiveGroup(preferredGroup);
            }
          } else {
            activeGroup = null;
            _selectedGroupId = null;
            groupMembers = [];
            _membersSub?.cancel();
            _clearSelectedGroup(uid);
          }
        }
        notifyListeners();
      },
      onError: (error, stackTrace) {
        debugPrint('watchMyGroups error: $error');
      },
    );

    location.startLiveTracking();
    location.liveLocationStream.listen(
      (pos) async {
        final movedMeters = _lastUploadedPosition == null
            ? 0
            : Geolocator.distanceBetween(
                _lastUploadedPosition!.latitude,
                _lastUploadedPosition!.longitude,
                pos.latitude,
                pos.longitude,
              );

        if (_lastUploadedPosition == null ||
            movedMeters >= _arrivalResetDistanceMeters) {
          _arrivedAtCurrentLocation = DateTime.now();
        }

        final shouldGeocode = _cachedLocationLabel == null ||
            _lastGeocodeAt == null ||
            DateTime.now().difference(_lastGeocodeAt!) >
                _reverseGeocodeMaxAge ||
            movedMeters >= _reverseGeocodeDistanceMeters;

        if (shouldGeocode) {
          _cachedLocationLabel =
              await _resolveLocationLabel(pos.latitude, pos.longitude);
          _lastGeocodeAt = DateTime.now();
        }

        await firestore.updateMyLocation(
          uid: uid,
          lat: pos.latitude,
          lng: pos.longitude,
          headingDegrees: pos.heading,
          speedMph: metersPerSecondToMph(pos.speed),
          batteryLevel: _lastBatteryLevel.toDouble(),
          arrivedAtCurrentLocation: _arrivedAtCurrentLocation,
          currentLocationLabel: _cachedLocationLabel,
        );

        _lastUploadedPosition = pos;

        // Keep the helicopter feed centered on the user as they move.
        flightTracking.startPolling(
          centerLat: pos.latitude,
          centerLng: pos.longitude,
          radiusMiles: helicopterRadiusMiles,
        );
      },
      onError: (error, stackTrace) {
        debugPrint('liveLocationStream error: $error');
      },
    );

    _startBatteryMonitoring(uid);
    _startAircraftListeners();
  }

  int _lastBatteryLevel = 100;
  void _startBatteryMonitoring(String uid) async {
    try {
      _lastBatteryLevel = await _battery.batteryLevel;
    } catch (error) {
      debugPrint('batteryLevel error: $error');
      _lastBatteryLevel = 100;
    }

    _batterySub = _battery.onBatteryStateChanged.listen(
      (_) async {
        try {
          _lastBatteryLevel = await _battery.batteryLevel;
        } catch (error) {
          debugPrint('battery state change error: $error');
        }
      },
      onError: (error) {
        debugPrint('battery stream error: $error');
      },
    );
  }

  void _startAircraftListeners() {
    _aircraftSub = flightTracking.contacts.listen((contacts) {
      aircraft = contacts;
      notifyListeners();
    });
    _takeoffSub = flightTracking.takeoffs.listen((event) {
      if (_notificationsEnabled && _helicopterAlertsEnabled) {
        takeoffAlertController.add(event);
      }
    });
  }

  void _startCrashMonitoringIfNeeded() {
    if (_crashSub != null) return;
    accidentDetection.start();
    _crashSub = accidentDetection.onPossibleCrash.listen((gForce) {
      crashAlertController.add(gForce);
    });
  }

  void _stopCrashMonitoring() {
    _crashSub?.cancel();
    _crashSub = null;
    accidentDetection.stop();
  }

  Future<String> _resolveLocationLabel(double lat, double lng) async {
    try {
      final marks = await placemarkFromCoordinates(lat, lng);
      if (marks.isNotEmpty) {
        final p = marks.first;
        final pieces = <String>[
          if ((p.subLocality ?? '').trim().isNotEmpty) p.subLocality!.trim(),
          if ((p.locality ?? '').trim().isNotEmpty) p.locality!.trim(),
          if ((p.administrativeArea ?? '').trim().isNotEmpty)
            p.administrativeArea!.trim(),
        ];
        if (pieces.isNotEmpty) {
          return pieces.take(2).join(', ');
        }
      }
    } catch (error) {
      debugPrint('reverse geocode error: $error');
    }
    return '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
  }

  /// Called from Settings -> Helicopters. 25-100mi, 5mi increments,
  /// enforced by the slider UI.
  void setHelicopterRadius(double miles) {
    helicopterRadiusMiles = miles;
    notifyListeners();
    // Restart polling immediately at the new radius using the last known
    // position; the next live-location tick will also refresh it.
    final me = groupMembers.where((m) => m.uid == auth.currentUser?.uid);
    if (me.isNotEmpty && me.first.lat != null) {
      flightTracking.startPolling(
        centerLat: me.first.lat!,
        centerLng: me.first.lng!,
        radiusMiles: miles,
      );
    }
  }

  void setActiveGroup(FamilyGroup group) {
    activeGroup = group;
    _selectedGroupId = group.id;
    final uid = auth.currentUser?.uid;
    if (uid != null) {
      _persistSelectedGroup(uid, group.id);
    }
    _membersSub?.cancel();
    _membersSub =
        firestore.watchGroupMembers(group.memberUids).listen((members) {
      groupMembers = members;
      notifyListeners();
    });
    notifyListeners();
  }

  FamilyGroup? _pickPreferredGroup(List<FamilyGroup> groups) {
    if (groups.isEmpty) return null;
    if (_selectedGroupId == null) return groups.first;

    for (final group in groups) {
      if (group.id == _selectedGroupId) {
        return group;
      }
    }

    return groups.first;
  }

  String _selectedGroupPrefsKey(String uid) => 'appState.selectedGroupId.$uid';

  Future<void> _persistSelectedGroup(String uid, String groupId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedGroupPrefsKey(uid), groupId);
  }

  Future<void> _clearSelectedGroup(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_selectedGroupPrefsKey(uid));
  }

  // ---------------- Trip recording ----------------

  Future<void> startTrip(String driverUid, String driverName) async {
    if (activeGroup == null || isTripActive) return;

    final trip = Trip(
      id: const Uuid().v4(),
      driverUid: driverUid,
      driverName: driverName,
      startTime: DateTime.now(),
    );
    _activeTripId = await firestore.startTrip(activeGroup!.id, trip);
    isTripActive = true;

    final pointStream = location.startTripRecording();
    _tripPointSub = pointStream.listen((point) {
      accidentDetection.updateCurrentSpeed(point.speedMph);
    });

    if (_crashDetectionEnabled) {
      _startCrashMonitoringIfNeeded();
    }

    // Batch-write buffered GPS points every 10s instead of on every fix,
    // to stay well within the Firestore free-tier write quota.
    _tripFlushTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      final points = location.flushBufferedPoints();
      if (points.isNotEmpty && _activeTripId != null && activeGroup != null) {
        firestore.appendTripPoints(activeGroup!.id, _activeTripId!, points);
      }
    });

    notifyListeners();
  }

  Future<void> endTrip({bool accidentConfirmed = false}) async {
    if (!isTripActive || activeGroup == null || _activeTripId == null) return;

    _tripFlushTimer?.cancel();
    final remaining = location.flushBufferedPoints();
    if (remaining.isNotEmpty) {
      await firestore.appendTripPoints(
          activeGroup!.id, _activeTripId!, remaining);
    }

    await firestore.finishTrip(
      groupId: activeGroup!.id,
      tripId: _activeTripId!,
      distanceMiles: location.currentDistanceMiles,
      topSpeedMph: location.currentTopSpeedMph,
      avgSpeedMph: location.currentAvgSpeedMph,
      possibleAccidentDetected: accidentConfirmed,
    );

    location.stopTripRecording();
    _stopCrashMonitoring();
    _tripPointSub?.cancel();
    isTripActive = false;
    _activeTripId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _groupsSub?.cancel();
    _membersSub?.cancel();
    _tripFlushTimer?.cancel();
    _tripPointSub?.cancel();
    _stopCrashMonitoring();
    _batterySub?.cancel();
    _aircraftSub?.cancel();
    _takeoffSub?.cancel();
    location.dispose();
    accidentDetection.dispose();
    flightTracking.dispose();
    crashAlertController.close();
    takeoffAlertController.close();
    super.dispose();
  }
}
