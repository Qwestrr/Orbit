import 'dart:async';
import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/hazard_report.dart';

const String _channelIdAlerts = 'orbit_alerts';

@pragma('vm:entry-point')
void onDidReceiveBackgroundNotificationResponse(NotificationResponse response) {
  LocalNotificationService.instance.emitTapEventFromPayload(response.payload);
}

class LocalNotificationTapEvent {
  final String type;
  final String? groupId;
  final String? routeId;
  final String? hazardId;
  final String? memberUid;
  final double? lat;
  final double? lng;

  const LocalNotificationTapEvent({
    required this.type,
    this.groupId,
    this.routeId,
    this.hazardId,
    this.memberUid,
    this.lat,
    this.lng,
  });

  factory LocalNotificationTapEvent.fromMap(Map<String, dynamic> map) {
    return LocalNotificationTapEvent(
      type: map['type'] as String? ?? '',
      groupId: map['groupId'] as String?,
      routeId: map['routeId'] as String?,
      hazardId: map['hazardId'] as String?,
      memberUid: map['memberUid'] as String?,
      lat: (map['lat'] as num?)?.toDouble(),
      lng: (map['lng'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      if (groupId != null) 'groupId': groupId,
      if (routeId != null) 'routeId': routeId,
      if (hazardId != null) 'hazardId': hazardId,
      if (memberUid != null) 'memberUid': memberUid,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
    };
  }
}

class LocalNotificationService {
  LocalNotificationService._();

  static final LocalNotificationService instance = LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  final StreamController<LocalNotificationTapEvent> _tapEventsController =
      StreamController<LocalNotificationTapEvent>.broadcast();
  final List<LocalNotificationTapEvent> _pendingTapEvents =
      <LocalNotificationTapEvent>[];

  bool _initialized = false;
  int _nextNotificationId = 5000;

  Stream<LocalNotificationTapEvent> get tapEvents =>
      _tapEventsController.stream;

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onDidReceiveResponse,
      onDidReceiveBackgroundNotificationResponse:
          onDidReceiveBackgroundNotificationResponse,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelIdAlerts,
            'Orbit Alerts',
            description: 'Hazard and aircraft alerts',
            importance: Importance.high,
          ),
        );

    _initialized = true;
  }

  List<LocalNotificationTapEvent> drainPendingTapEvents() {
    final events = List<LocalNotificationTapEvent>.from(_pendingTapEvents);
    _pendingTapEvents.clear();
    return events;
  }

  Future<void> showTakeoffNotification({
    required String title,
    required String message,
    required double lat,
    required double lng,
  }) async {
    if (!await _notificationsAllowed()) return;

    await _show(
      title: title,
      message: message,
      payload: LocalNotificationTapEvent(
        type: 'takeoff',
        lat: lat,
        lng: lng,
      ).toMap(),
    );
  }

  Future<void> showHazardNotification({
    required HazardReport hazard,
    required String groupId,
    required String title,
    required String message,
  }) async {
    if (!await _notificationsAllowed()) return;

    await _show(
      title: title,
      message: message,
      payload: LocalNotificationTapEvent(
        type: 'hazard',
        groupId: groupId,
        hazardId: hazard.id,
        lat: hazard.lat,
        lng: hazard.lng,
      ).toMap(),
    );
  }

  Future<void> showBatteryNotification({
    required String title,
    required String message,
    required String memberUid,
    double? lat,
    double? lng,
  }) async {
    if (!await _notificationsAllowed()) return;

    await _show(
      title: title,
      message: message,
      payload: LocalNotificationTapEvent(
        type: 'battery',
        memberUid: memberUid,
        lat: lat,
        lng: lng,
      ).toMap(),
    );
  }

  Future<void> showGroupRouteFinishedNotification({
    required String title,
    required String message,
    required String groupId,
    required String routeId,
  }) async {
    if (!await _notificationsAllowed()) return;

    await _show(
      title: title,
      message: message,
      payload: LocalNotificationTapEvent(
        type: 'group_route_finished',
        groupId: groupId,
        routeId: routeId,
      ).toMap(),
    );
  }

  Future<void> _show({
    required String title,
    required String message,
    required Map<String, dynamic> payload,
  }) async {
    await initialize();

    final prefs = await SharedPreferences.getInstance();
    final soundEnabled = prefs.getBool('appSettings.notificationSound') ?? true;
    final vibrationEnabled =
        prefs.getBool('appSettings.notificationVibration') ?? true;

    final androidDetails = AndroidNotificationDetails(
      _channelIdAlerts,
      'Orbit Alerts',
      channelDescription: 'Hazard and aircraft alerts',
      importance: Importance.high,
      priority: Priority.high,
      playSound: soundEnabled,
      enableVibration: vibrationEnabled,
      ticker: 'Orbit alert',
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: soundEnabled,
    );

    await _plugin.show(
      _nextNotificationId++,
      title,
      message,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: jsonEncode(payload),
    );
  }

  Future<bool> _notificationsAllowed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('appSettings.notificationsEnabled') ?? true;
  }

  void _onDidReceiveResponse(NotificationResponse response) {
    emitTapEventFromPayload(response.payload);
  }

  void emitTapEventFromPayload(String? payloadJson) {
    if (payloadJson == null || payloadJson.isEmpty) return;

    try {
      final decoded = jsonDecode(payloadJson);
      if (decoded is! Map<String, dynamic>) return;
      final event = LocalNotificationTapEvent.fromMap(decoded);
      _pendingTapEvents.add(event);
      _tapEventsController.add(event);
    } catch (_) {
      // Ignore malformed payloads.
    }
  }
}
