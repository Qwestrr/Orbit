import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:latlong2/latlong.dart' as ll;
import 'package:platform_maps_flutter/platform_maps_flutter.dart' as pm;
import 'package:provider/provider.dart';
import '../models/app_user.dart';
import '../models/place.dart';
import '../models/hazard_report.dart';
import '../models/aircraft_contact.dart';
import '../models/group_route.dart';
import '../models/custom_quick_notification_template.dart';
import '../providers/app_state.dart';
import '../providers/appearance_provider.dart';
import '../services/local_notification_service.dart';
import '../widgets/group_dropdown_button.dart';
import '../widgets/member_list_button.dart';
import '../widgets/accident_alert_dialog.dart';
import '../widgets/speed_display.dart';
import '../widgets/hazard_report_dialog.dart';
import '../widgets/takeoff_notification_banner.dart';
import 'settings_menu_screen.dart';
import 'member_detail_screen.dart';
import 'group_route_menu_screen.dart';

/// The single, deliberately minimal home screen: a full-bleed map, a
/// small settings icon top-left, a group-picker pill top-center, and a
/// members pill bottom-center. Everything else (places, hazards,
/// helicopters) renders as map layers so the chrome stays out of the way.
class HomeMapScreen extends StatefulWidget {
  const HomeMapScreen({super.key});

  @override
  State<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends State<HomeMapScreen>
    with WidgetsBindingObserver {
  final fm.MapController _fallbackMapController = fm.MapController();
  gm.GoogleMapController? _googleMapController;
  pm.PlatformMapController? _platformMapController;
  bool _crashDialogShowing = false;
  final List<_ActiveTopBanner> _activeTopBanners = [];
  StreamSubscription<List<HazardReport>>? _hazardsSub;
  StreamSubscription<List<GroupRoute>>? _groupRoutesSub;
  StreamSubscription<List<Map<String, dynamic>>>?
      _incomingMemberNotificationsSub;
  StreamSubscription<LocalNotificationTapEvent>? _localTapSub;
  AppState? _appState;
  String? _subscribedHazardGroupId;
  String? _subscribedBatteryGroupId;
  bool _hazardsPrimed = false;
  Set<String> _knownHazardIds = <String>{};
  final Map<String, bool> _batteryAlertActiveByUid = <String, bool>{};
  Set<String> _batteryAlertMemberUids = <String>{};
  int _batteryAlertThresholdPercent = 20;
  final Map<String, HazardReport> _latestHazardsById = <String, HazardReport>{};
  final Map<String, bool> _hazardProximityAlertActiveById = <String, bool>{};
  final Map<String, GroupRoute> _latestGroupRoutesById = <String, GroupRoute>{};
  final Set<String> _notifiedCompletedGroupRouteIds = <String>{};
  final Map<String, DateTime> _lastRouteProgressUpdateByRoute =
      <String, DateTime>{};
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  int _bannerIdCounter = 0;
  String? _subscribedGroupRouteGroupId;
  String? _subscribedIncomingMemberNotificationsGroupId;
  bool _incomingMemberNotificationsPrimed = false;
  Set<String> _knownIncomingMemberNotificationIds = <String>{};
  _RouteOverlay? _activeRouteOverlay;
  String? _selectedMemberUid;
  Timer? _hazardFocusTimer;
  final Map<HazardType, gm.BitmapDescriptor> _googleHazardSymbolIcons =
      <HazardType, gm.BitmapDescriptor>{};
  final Map<HazardType, pm.BitmapDescriptor> _platformHazardSymbolIcons =
      <HazardType, pm.BitmapDescriptor>{};

  static const List<_QuickMemberNotificationTemplate>
      _quickMemberNotificationTemplates = [
    _QuickMemberNotificationTemplate(
      id: 'eta_check',
      label: 'ETA?',
      messageTemplate: 'What is your ETA?',
      icon: Icons.schedule,
      accent: Colors.lightBlueAccent,
      isExplicit: false,
    ),
    _QuickMemberNotificationTemplate(
      id: 'drive_safe',
      label: 'Drive safe',
      messageTemplate: 'Drive safe.',
      icon: Icons.shield_outlined,
      accent: Colors.greenAccent,
      isExplicit: false,
    ),
    _QuickMemberNotificationTemplate(
      id: 'arrive_ping',
      label: 'Ping me when there',
      messageTemplate: 'Text me when you get there.',
      icon: Icons.chat_bubble_outline,
      accent: Colors.amberAccent,
      isExplicit: false,
    ),
    _QuickMemberNotificationTemplate(
      id: 'where_are_you',
      label: 'Where are you?',
      messageTemplate: 'Where are you right now?',
      icon: Icons.location_searching,
      accent: Colors.orangeAccent,
      isExplicit: false,
    ),
    _QuickMemberNotificationTemplate(
      id: 'explicit_hurry',
      label: 'Hurry up (Explicit)',
      messageTemplate: 'Hurry up and get home, no BS on the road.',
      icon: Icons.priority_high,
      accent: Colors.redAccent,
      isExplicit: true,
    ),
  ];

  static const double _metersPerMile = 1609.344;
  static const double _proximityResetBufferMeters = 120;

  bool get _useGoogleAndroidMap {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android;
  }

  bool get _useAppleIosMap {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final appState = context.read<AppState>();
    _appState = appState;
    appState.addListener(_handleAppStateChanged);
    _syncHazardSubscription();
    _syncGroupRouteSubscription();
    _syncBatteryAlertPrefs();
    _syncIncomingMemberNotificationSubscription();
    _prepareHazardSymbolMarkerIcons();

    _localTapSub = LocalNotificationService.instance.tapEvents.listen(
      _handleLocalNotificationTap,
    );
    for (final event
        in LocalNotificationService.instance.drainPendingTapEvents()) {
      _handleLocalNotificationTap(event);
    }

    appState.crashAlertController.stream.listen((gForce) {
      if (!_crashDialogShowing && mounted) {
        _crashDialogShowing = true;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AccidentAlertDialog(
            peakGForce: gForce,
            onResolved: () => _crashDialogShowing = false,
          ),
        );
      }
    });

    appState.takeoffAlertController.stream.listen((event) {
      if (!mounted) return;
      final kindLabel = event.aircraft.estimatedKindLabel;
      final tailNumber = event.aircraft.tailNumberLabel;
      final title = 'Air traffic alert';
      final message = tailNumber.isNotEmpty
          ? '$kindLabel $tailNumber taking off nearby'
          : '$kindLabel taking off nearby';

      if (_shouldUseSystemNotifications) {
        LocalNotificationService.instance.showTakeoffNotification(
          title: title,
          message: message,
          lat: event.takeoffLat,
          lng: event.takeoffLng,
        );
      } else {
        _enqueueTopBanner(
          _ActiveTopBanner.takeoff(
            id: _nextBannerId(),
            event: event,
            title: title,
            message: message,
          ),
        );
      }
    });
  }

  bool get _shouldUseSystemNotifications {
    return _lifecycleState != AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    if (state == AppLifecycleState.resumed) {
      _syncBatteryAlertPrefs(force: true);
      _checkLowBatteryAlerts();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _appState?.removeListener(_handleAppStateChanged);
    _hazardsSub?.cancel();
    _groupRoutesSub?.cancel();
    _incomingMemberNotificationsSub?.cancel();
    _localTapSub?.cancel();
    _hazardFocusTimer?.cancel();
    super.dispose();
  }

  void _handleLocalNotificationTap(LocalNotificationTapEvent event) {
    if (!mounted) return;

    if (event.type == 'takeoff' && event.lat != null && event.lng != null) {
      _panTo(event.lat!, event.lng!, zoom: 13);
      return;
    }

    if (event.type == 'hazard' &&
        event.groupId != null &&
        event.hazardId != null &&
        _latestHazardsById[event.hazardId!] != null) {
      _promptHazardVerification(
        groupId: event.groupId!,
        hazard: _latestHazardsById[event.hazardId!]!,
      );
      return;
    }

    if (event.type == 'battery') {
      if (event.memberUid != null &&
          _openMemberDetailsByUid(event.memberUid!)) {
        return;
      }
      if (event.lat != null && event.lng != null) {
        _panTo(event.lat!, event.lng!, zoom: 14);
      }
      return;
    }

    if (event.type == 'group_route_finished' && event.routeId != null) {
      _showGroupRouteLeaderboard(event.routeId!);
      return;
    }

    if (event.lat != null && event.lng != null) {
      _panTo(event.lat!, event.lng!, zoom: 15);
    }
  }

  bool _openMemberDetailsByUid(String uid) {
    final appState = _appState;
    if (appState == null) return false;

    final matches = appState.groupMembers.where((m) => m.uid == uid);
    if (matches.isEmpty) return false;

    final member = matches.first;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MemberDetailScreen(member: member)),
    );
    return true;
  }

  Future<void> _prepareHazardSymbolMarkerIcons() async {
    try {
      final google = <HazardType, gm.BitmapDescriptor>{};
      final platform = <HazardType, pm.BitmapDescriptor>{};

      for (final type in HazardType.values) {
        final bytes = await _buildHazardSymbolMarkerPng(
          icon: _hazardIcon(type),
          background: _hazardAccent(type),
        );
        google[type] = gm.BitmapDescriptor.bytes(bytes);
        platform[type] = pm.BitmapDescriptor.fromBytes(bytes);
      }

      if (!mounted) return;
      setState(() {
        _googleHazardSymbolIcons
          ..clear()
          ..addAll(google);
        _platformHazardSymbolIcons
          ..clear()
          ..addAll(platform);
      });
    } catch (_) {
      // Keep safe defaults if icon generation fails on any platform.
    }
  }

  Future<Uint8List> _buildHazardSymbolMarkerPng({
    required IconData icon,
    required Color background,
  }) async {
    const double size = 92;
    const double borderWidth = 6;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = const Offset(size / 2, size / 2);

    canvas.drawCircle(
      center,
      (size / 2) - 1,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      center,
      (size / 2) - borderWidth,
      Paint()..color = background,
    );

    final textPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: 44,
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset((size - textPainter.width) / 2, (size - textPainter.height) / 2),
    );

    final image =
        await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  void _selectMember(String uid) {
    if (!mounted || _selectedMemberUid == uid) return;
    setState(() {
      _selectedMemberUid = uid;
    });
  }

  void _clearSelectedMember() {
    if (!mounted || _selectedMemberUid == null) return;
    setState(() {
      _selectedMemberUid = null;
    });
  }

  List<_QuickMemberNotificationTemplate> _visibleQuickNotificationTemplates(
      AppState appState) {
    final templates = <_QuickMemberNotificationTemplate>[
      ..._quickMemberNotificationTemplates,
      ...appState.customQuickNotificationTemplates
          .map(_quickTemplateFromCustom),
    ];

    if (!appState.allowExplicitCustomNotifications) {
      templates.removeWhere((template) => template.isExplicit);
    }

    return templates;
  }

  _QuickMemberNotificationTemplate _quickTemplateFromCustom(
    CustomQuickNotificationTemplate template,
  ) {
    return _QuickMemberNotificationTemplate(
      id: template.id,
      label: template.label,
      messageTemplate: template.messageTemplate,
      icon: template.icon,
      accent: template.accentColor,
      isExplicit: template.isExplicit,
    );
  }

  AppUser? _selectedMember(AppState appState) {
    final uid = _selectedMemberUid;
    if (uid == null) return null;
    final matches = appState.groupMembers.where((m) => m.uid == uid);
    if (matches.isEmpty) return null;
    return matches.first;
  }

  void _sendQuickMemberNotification({
    required AppUser member,
    required _QuickMemberNotificationTemplate template,
  }) async {
    final appState = _appState;
    if (appState == null || !appState.notificationsEnabled) return;
    if (!appState.customInAppNotificationsEnabled) return;
    if (template.isExplicit && !appState.allowExplicitCustomNotifications) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content:
                Text('Explicit quick notifications are disabled in settings.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }

    final currentUid = appState.auth.currentUser?.uid;
    if (currentUid == null || appState.activeGroup == null) {
      return;
    }

    final me = appState.groupMembers.where((m) => m.uid == currentUid).toList();
    final fromName = me.isNotEmpty
        ? me.first.displayName
        : (appState.auth.currentUser?.displayName ?? 'Member');

    try {
      await appState.firestore.sendGroupMemberNotification(
        groupId: appState.activeGroup!.id,
        fromUid: currentUid,
        fromName: fromName,
        toUid: member.uid,
        toName: member.displayName,
        label: template.label,
        message: template.messageTemplate,
        isExplicit: template.isExplicit,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Could not send notification right now.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }

    if (!mounted) return;

    final title = 'To ${member.displayName}';
    final message = template.messageTemplate;

    _enqueueTopBanner(
      _ActiveTopBanner.customMember(
        id: _nextBannerId(),
        memberUid: member.uid,
        title: title,
        message: message,
        icon: template.icon,
        accentColor: template.accent,
        isExplicit: template.isExplicit,
        lat: member.lat,
        lng: member.lng,
      ),
    );

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Sent to ${member.displayName}: ${template.label}'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _handleAppStateChanged() {
    final appState = _appState;
    if (appState != null && _selectedMemberUid != null) {
      final exists =
          appState.groupMembers.any((m) => m.uid == _selectedMemberUid);
      if (!exists) {
        _selectedMemberUid = null;
      }
    }
    _filterTopBannersForSettings();
    _syncHazardSubscription();
    _syncGroupRouteSubscription();
    _syncBatteryAlertPrefs();
    _syncIncomingMemberNotificationSubscription();
    _checkLowBatteryAlerts();
    final groupId = _appState?.activeGroup?.id;
    if (groupId != null) {
      _checkHazardProximityAlerts(
        _latestHazardsById.values.toList(),
        groupId,
      );
    }
    _syncMyGroupRouteProgress();
  }

  void _syncIncomingMemberNotificationSubscription() {
    final appState = _appState;
    final groupId = appState?.activeGroup?.id;
    final uid = appState?.auth.currentUser?.uid;

    if (appState == null || groupId == null || uid == null) {
      _incomingMemberNotificationsSub?.cancel();
      _incomingMemberNotificationsSub = null;
      _subscribedIncomingMemberNotificationsGroupId = null;
      _incomingMemberNotificationsPrimed = false;
      _knownIncomingMemberNotificationIds = <String>{};
      return;
    }

    if (groupId == _subscribedIncomingMemberNotificationsGroupId) {
      return;
    }

    _incomingMemberNotificationsSub?.cancel();
    _incomingMemberNotificationsSub = null;
    _subscribedIncomingMemberNotificationsGroupId = groupId;
    _incomingMemberNotificationsPrimed = false;
    _knownIncomingMemberNotificationIds = <String>{};

    _incomingMemberNotificationsSub = appState.firestore
        .watchIncomingMemberNotifications(groupId: groupId, toUid: uid)
        .listen((items) {
      if (!mounted) return;

      final currentIds =
          items.map((item) => (item['id'] ?? '').toString()).toSet();

      if (!_incomingMemberNotificationsPrimed) {
        _knownIncomingMemberNotificationIds = currentIds;
        _incomingMemberNotificationsPrimed = true;
        return;
      }

      final freshItems = items.where((item) {
        final id = (item['id'] ?? '').toString();
        return id.isNotEmpty &&
            !_knownIncomingMemberNotificationIds.contains(id);
      }).toList();

      _knownIncomingMemberNotificationIds = currentIds;

      for (final item in freshItems) {
        if (!appState.notificationsEnabled ||
            !appState.customInAppNotificationsEnabled) {
          continue;
        }

        final isExplicit = item['isExplicit'] == true;
        if (isExplicit && !appState.allowExplicitCustomNotifications) {
          continue;
        }

        final fromUid = (item['fromUid'] ?? '').toString();
        final fromName = (item['fromName'] ?? 'Group member').toString();
        final message = (item['message'] ?? '').toString();
        if (message.isEmpty) continue;

        _enqueueTopBanner(
          _ActiveTopBanner.customMember(
            id: _nextBannerId(),
            memberUid: fromUid,
            title: 'From $fromName',
            message: message,
            icon: isExplicit ? Icons.priority_high : Icons.notifications_active,
            accentColor: isExplicit ? Colors.redAccent : Colors.lightBlueAccent,
            isExplicit: isExplicit,
          ),
        );
      }
    });
  }

  void _filterTopBannersForSettings() {
    final appState = _appState;
    if (appState == null || !mounted) return;

    final filtered = _activeTopBanners.where((banner) {
      if (!appState.notificationsEnabled) return false;
      switch (banner.kind) {
        case _TopBannerKind.takeoff:
          return appState.helicopterAlertsEnabled;
        case _TopBannerKind.hazard:
          final hazard = banner.hazard;
          if (hazard == null) return false;
          switch (hazard.type) {
            case HazardType.police:
              return appState.policeAlertsEnabled;
            case HazardType.accident:
              return appState.accidentAlertsEnabled;
            case HazardType.hazardObject:
            case HazardType.custom:
              return appState.roadHazardAlertsEnabled;
          }
        case _TopBannerKind.battery:
          return appState.batteryAlertsEnabled;
        case _TopBannerKind.groupRouteFinished:
          return true;
        case _TopBannerKind.customMember:
          if (!appState.customInAppNotificationsEnabled) return false;
          if (banner.isExplicit && !appState.allowExplicitCustomNotifications) {
            return false;
          }
          return true;
      }
    }).toList();

    if (filtered.length != _activeTopBanners.length) {
      setState(() {
        _activeTopBanners
          ..clear()
          ..addAll(filtered);
      });
    }
  }

  int _nextBannerId() {
    _bannerIdCounter += 1;
    return _bannerIdCounter;
  }

  void _enqueueTopBanner(_ActiveTopBanner banner) {
    if (!mounted) return;
    setState(() {
      _activeTopBanners.insert(0, banner);
      if (_activeTopBanners.length > 3) {
        _activeTopBanners.removeLast();
      }
    });
  }

  void _dismissTopBannerById(int id) {
    if (!mounted) return;
    setState(() {
      _activeTopBanners.removeWhere((banner) => banner.id == id);
    });
  }

  bool _isNotificationHazard(HazardReport hazard) {
    final appState = _appState;
    if (appState == null || !appState.notificationsEnabled) return false;

    switch (hazard.type) {
      case HazardType.police:
        return appState.policeAlertsEnabled;
      case HazardType.accident:
        return appState.accidentAlertsEnabled;
      case HazardType.hazardObject:
      case HazardType.custom:
        return appState.roadHazardAlertsEnabled;
    }
  }

  Future<void> _syncBatteryAlertPrefs({bool force = false}) async {
    final appState = _appState;
    final groupId = appState?.activeGroup?.id;
    final uid = appState?.auth.currentUser?.uid;

    if (appState == null || groupId == null || uid == null) {
      _subscribedBatteryGroupId = null;
      _batteryAlertMemberUids = <String>{};
      _batteryAlertActiveByUid.clear();
      return;
    }

    if (!force && groupId == _subscribedBatteryGroupId) {
      return;
    }

    _subscribedBatteryGroupId = groupId;
    _batteryAlertActiveByUid.clear();

    try {
      final prefs = await appState.firestore.getNotificationPrefs(
        uid: uid,
        groupId: groupId,
      );
      if (!mounted) return;

      final threshold = (prefs?['lowBatteryThresholdPercent'] as num?)?.toInt();
      final selected = prefs?['batteryAlertMemberUids'];

      _batteryAlertThresholdPercent = threshold ?? 20;
      if (selected is List) {
        _batteryAlertMemberUids = selected.whereType<String>().toSet();
      } else {
        _batteryAlertMemberUids =
            appState.groupMembers.map((m) => m.uid).toSet();
      }

      _checkLowBatteryAlerts();
    } catch (_) {
      _batteryAlertThresholdPercent = 20;
      _batteryAlertMemberUids = appState.groupMembers.map((m) => m.uid).toSet();
    }
  }

  void _checkLowBatteryAlerts() {
    final appState = _appState;
    if (appState == null) {
      return;
    }
    if (!appState.notificationsEnabled || !appState.batteryAlertsEnabled) {
      return;
    }

    final watchedUids = _batteryAlertMemberUids;
    if (watchedUids.isEmpty) {
      return;
    }

    for (final member in appState.groupMembers) {
      if (!watchedUids.contains(member.uid)) continue;

      final batteryPercent = member.batteryLevel.round();
      final isLow = batteryPercent <= _batteryAlertThresholdPercent;
      final wasLow = _batteryAlertActiveByUid[member.uid] ?? false;

      if (isLow && !wasLow) {
        _batteryAlertActiveByUid[member.uid] = true;
        _emitLowBatteryAlert(member, batteryPercent);
        continue;
      }

      if (!isLow &&
          wasLow &&
          batteryPercent >= _batteryAlertThresholdPercent + 3) {
        _batteryAlertActiveByUid[member.uid] = false;
      }
    }
  }

  double _hazardRadiusMeters(HazardType type) {
    switch (type) {
      case HazardType.police:
        return 1 * _metersPerMile;
      case HazardType.accident:
        return 2 * _metersPerMile;
      case HazardType.hazardObject:
      case HazardType.custom:
        return 1 * _metersPerMile;
    }
  }

  String _hazardRadiusLabel(HazardType type) {
    switch (type) {
      case HazardType.police:
        return '1 mi';
      case HazardType.accident:
        return '2 mi';
      case HazardType.hazardObject:
      case HazardType.custom:
        return '1 mi';
    }
  }

  void _checkHazardProximityAlerts(
    List<HazardReport> hazards,
    String groupId,
  ) {
    final appState = _appState;
    if (appState == null) return;
    if (!appState.notificationsEnabled) return;

    final myUid = appState.auth.currentUser?.uid;
    if (myUid == null) return;

    final me = appState.groupMembers.where((m) => m.uid == myUid).toList();
    if (me.isEmpty || me.first.lat == null || me.first.lng == null) return;

    final myLat = me.first.lat!;
    final myLng = me.first.lng!;

    final activeHazardIds = hazards.map((h) => h.id).toSet();
    _hazardProximityAlertActiveById.removeWhere(
      (hazardId, _) => !activeHazardIds.contains(hazardId),
    );

    for (final hazard in hazards) {
      if (!_isNotificationHazard(hazard)) continue;

      final radiusMeters = _hazardRadiusMeters(hazard.type);
      final distanceMeters = ll.Distance().as(
        ll.LengthUnit.Meter,
        ll.LatLng(myLat, myLng),
        ll.LatLng(hazard.lat, hazard.lng),
      );

      final isInside = distanceMeters <= radiusMeters;
      final wasInside = _hazardProximityAlertActiveById[hazard.id] ?? false;

      if (isInside && !wasInside) {
        _hazardProximityAlertActiveById[hazard.id] = true;
        final title = '${_hazardTitle(hazard.type)} nearby';
        final message =
            '${hazard.label} within ${_hazardRadiusLabel(hazard.type)}';

        if (_shouldUseSystemNotifications) {
          LocalNotificationService.instance.showHazardNotification(
            hazard: hazard,
            groupId: groupId,
            title: title,
            message: message,
          );
        } else {
          _enqueueTopBanner(
            _ActiveTopBanner.hazard(
              id: _nextBannerId(),
              groupId: groupId,
              hazard: hazard,
              title: title,
              message: message,
              icon: _hazardIcon(hazard.type),
              accentColor: _hazardAccent(hazard.type),
            ),
          );
          _focusHazardThenRecenterToMember(hazard);
        }
        continue;
      }

      if (!isInside &&
          wasInside &&
          distanceMeters >= radiusMeters + _proximityResetBufferMeters) {
        _hazardProximityAlertActiveById[hazard.id] = false;
      }
    }
  }

  void _focusHazardThenRecenterToMember(HazardReport hazard) {
    if (!mounted) return;

    _hazardFocusTimer?.cancel();
    _panTo(hazard.lat, hazard.lng, zoom: 15);

    _hazardFocusTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      final appState = _appState;
      final uid = appState?.auth.currentUser?.uid;
      if (appState == null || uid == null) return;

      final me = appState.groupMembers.where((m) => m.uid == uid).toList();
      if (me.isEmpty || me.first.lat == null || me.first.lng == null) return;

      _panTo(me.first.lat!, me.first.lng!, zoom: 14);
    });
  }

  void _emitLowBatteryAlert(AppUser member, int batteryPercent) {
    final title = 'Low battery alert';
    final message = '${member.displayName} is at $batteryPercent% battery';

    if (_shouldUseSystemNotifications) {
      LocalNotificationService.instance.showBatteryNotification(
        title: title,
        message: message,
        memberUid: member.uid,
        lat: member.lat,
        lng: member.lng,
      );
      return;
    }

    _enqueueTopBanner(
      _ActiveTopBanner.battery(
        id: _nextBannerId(),
        memberUid: member.uid,
        lat: member.lat,
        lng: member.lng,
        title: title,
        message: message,
      ),
    );
  }

  IconData _hazardIcon(HazardType type) {
    switch (type) {
      case HazardType.police:
        return Icons.local_police;
      case HazardType.accident:
        return Icons.car_crash;
      case HazardType.hazardObject:
      case HazardType.custom:
        return Icons.warning_amber_rounded;
    }
  }

  String _hazardMarkerEmoji(HazardType type) {
    switch (type) {
      case HazardType.police:
        return '👮';
      case HazardType.accident:
        return '🚨';
      case HazardType.hazardObject:
      case HazardType.custom:
        return '⚠️';
    }
  }

  String _hazardTitle(HazardType type) {
    switch (type) {
      case HazardType.police:
        return '👮 Police reported';
      case HazardType.accident:
        return '🚨 Accident reported';
      case HazardType.hazardObject:
      case HazardType.custom:
        return '⚠️ Hazard reported';
    }
  }

  Color _hazardAccent(HazardType type) {
    switch (type) {
      case HazardType.police:
        return Colors.blueAccent;
      case HazardType.accident:
        return Colors.redAccent;
      case HazardType.hazardObject:
      case HazardType.custom:
        return Colors.orangeAccent;
    }
  }

  double _googleHazardHue(HazardType type) {
    switch (type) {
      case HazardType.police:
        return gm.BitmapDescriptor.hueAzure;
      case HazardType.accident:
        return gm.BitmapDescriptor.hueRed;
      case HazardType.hazardObject:
      case HazardType.custom:
        return gm.BitmapDescriptor.hueOrange;
    }
  }

  Future<void> _promptHazardVerification({
    required String groupId,
    required HazardReport hazard,
  }) async {
    if (!mounted) return;

    _panTo(hazard.lat, hazard.lng, zoom: 15);

    final stillThere = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(_hazardTitle(hazard.type)),
          content: Text('Is this ${hazard.label.toLowerCase()} still there?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Not now'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('No, it is gone'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Yes, still there'),
            ),
          ],
        );
      },
    );

    if (stillThere == null || !mounted) return;

    if (stillThere) {
      await _appState!.firestore.confirmHazard(groupId, hazard.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Thanks for confirming this report.'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      return;
    }

    await _appState!.firestore.deleteHazard(groupId, hazard.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Report removed. Thanks for the update.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
  }

  void _syncHazardSubscription() {
    final appState = _appState;
    if (appState == null) return;
    final groupId = appState.activeGroup?.id;

    if (groupId == _subscribedHazardGroupId) return;

    _hazardsSub?.cancel();
    _hazardsSub = null;
    _subscribedHazardGroupId = groupId;
    _hazardsPrimed = false;
    _knownHazardIds = <String>{};

    if (groupId == null) return;

    _hazardsSub = appState.firestore.watchHazards(groupId).listen((hazards) {
      if (!mounted) return;
      _latestHazardsById
        ..clear()
        ..addEntries(hazards.map((h) => MapEntry(h.id, h)));

      _checkHazardProximityAlerts(hazards, groupId);

      final currentIds = hazards.map((h) => h.id).toSet();

      if (!_hazardsPrimed) {
        _knownHazardIds = currentIds;
        _hazardsPrimed = true;
        return;
      }

      final newHazards = hazards
          .where((h) => !_knownHazardIds.contains(h.id))
          .where(_isNotificationHazard)
          .toList();

      _knownHazardIds = currentIds;

      for (final hazard in newHazards) {
        final title = _hazardTitle(hazard.type);
        final message =
            '${_hazardMarkerEmoji(hazard.type)} ${hazard.label} reported by ${hazard.reportedByName}';

        if (_shouldUseSystemNotifications) {
          LocalNotificationService.instance.showHazardNotification(
            hazard: hazard,
            groupId: groupId,
            title: title,
            message: message,
          );
        } else {
          _enqueueTopBanner(
            _ActiveTopBanner.hazard(
              id: _nextBannerId(),
              groupId: groupId,
              hazard: hazard,
              title: title,
              message: message,
              icon: _hazardIcon(hazard.type),
              accentColor: _hazardAccent(hazard.type),
            ),
          );
        }
      }
    });
  }

  void _syncGroupRouteSubscription() {
    final appState = _appState;
    if (appState == null) return;
    final groupId = appState.activeGroup?.id;

    if (groupId == _subscribedGroupRouteGroupId) {
      return;
    }

    _groupRoutesSub?.cancel();
    _groupRoutesSub = null;
    _latestGroupRoutesById.clear();
    _subscribedGroupRouteGroupId = groupId;

    if (groupId == null) return;

    _groupRoutesSub =
        appState.firestore.watchGroupRoutes(groupId).listen((routes) {
      if (!mounted) return;
      final myUid = appState.auth.currentUser?.uid;

      _latestGroupRoutesById
        ..clear()
        ..addEntries(routes.map((r) => MapEntry(r.id, r)));

      if (myUid != null) {
        for (final route in routes) {
          if (!route.canView(myUid) || !route.isCompleted) continue;
          if (_notifiedCompletedGroupRouteIds.contains(route.id)) continue;

          _notifiedCompletedGroupRouteIds.add(route.id);
          _notifyGroupRouteFinished(route);
        }
      }

      _syncMyGroupRouteProgress();
    });
  }

  void _notifyGroupRouteFinished(GroupRoute route) {
    final title = 'Group route finished';
    final message =
        '${route.start.label} to ${route.destination.label} is complete';

    if (_shouldUseSystemNotifications) {
      LocalNotificationService.instance.showGroupRouteFinishedNotification(
        title: title,
        message: message,
        groupId: route.groupId,
        routeId: route.id,
      );
      return;
    }

    _enqueueTopBanner(
      _ActiveTopBanner.groupRouteFinished(
        id: _nextBannerId(),
        routeId: route.id,
        title: title,
        message: message,
      ),
    );
  }

  void _syncMyGroupRouteProgress() {
    final appState = _appState;
    final uid = appState?.auth.currentUser?.uid;
    final groupId = appState?.activeGroup?.id;
    if (appState == null || uid == null || groupId == null) return;

    final me = appState.groupMembers.where((m) => m.uid == uid).toList();
    if (me.isEmpty || me.first.lat == null || me.first.lng == null) return;

    final myMember = me.first;
    final now = DateTime.now();
    final currentSpeed = (myMember.speedMph ?? 0).clamp(0, 220).toDouble();

    for (final route in _latestGroupRoutesById.values) {
      if (route.groupId != groupId || route.isCompleted) continue;
      if (!route.visibleMemberUids.contains(uid)) continue;

      final existing = route.participantStats[uid];
      final updatedTopSpeed = currentSpeed > (existing?.topSpeedMph ?? 0)
          ? currentSpeed
          : (existing?.topSpeedMph ?? 0);

      final arrivalRadius = route.destination.radiusMeters ?? 80;
      final distanceMeters = ll.Distance().as(
        ll.LengthUnit.Meter,
        ll.LatLng(myMember.lat!, myMember.lng!),
        ll.LatLng(route.destination.lat, route.destination.lng),
      );
      final justArrived =
          distanceMeters <= arrivalRadius && existing?.arrivedAt == null;

      final lastSync = _lastRouteProgressUpdateByRoute[route.id];
      final isThrottled = lastSync != null &&
          now.difference(lastSync) < const Duration(seconds: 15);
      final shouldSync = justArrived ||
          existing == null ||
          updatedTopSpeed >= (existing.topSpeedMph + 1) ||
          !isThrottled;

      if (!shouldSync) continue;

      _lastRouteProgressUpdateByRoute[route.id] = now;
      appState.firestore.updateGroupRouteParticipant(
        groupId: groupId,
        routeId: route.id,
        uid: uid,
        displayName: myMember.displayName,
        topSpeedMph: updatedTopSpeed,
        arrivedAt: justArrived ? now : null,
      );

      final everyoneArrived = route.visibleMemberUids.every((memberUid) {
        if (memberUid == uid && justArrived) return true;
        return route.participantStats[memberUid]?.arrivedAt != null;
      });

      if (everyoneArrived && route.createdByUid == uid) {
        appState.firestore
            .finishGroupRoute(groupId: groupId, routeId: route.id);
      }
    }
  }

  Future<void> _showGroupRouteLeaderboard(String routeId) async {
    final route = _latestGroupRoutesById[routeId];
    if (route == null || !mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Route results are loading. Try again in a second.')),
      );
      return;
    }

    final speedLeaders = route.participantStats.values.toList()
      ..sort((a, b) => b.topSpeedMph.compareTo(a.topSpeedMph));

    final arrivalLeaders =
        route.participantStats.values.where((p) => p.arrivedAt != null).toList()
          ..sort(
            (a, b) => a.arrivedAt!
                .difference(route.createdAt)
                .compareTo(b.arrivedAt!.difference(route.createdAt)),
          );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Group route leaderboard'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${route.start.label} to ${route.destination.label}'),
                const SizedBox(height: 16),
                const Text(
                  'Top Speed',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (speedLeaders.isEmpty)
                  const Text('No speed data yet.')
                else
                  ...speedLeaders.take(3).toList().asMap().entries.map(
                    (entry) {
                      final rank = entry.key + 1;
                      final p = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                            '$rank. ${p.displayName} - ${p.topSpeedMph.round()} mph'),
                      );
                    },
                  ),
                const SizedBox(height: 14),
                const Text(
                  'Arrival Time',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (arrivalLeaders.isEmpty)
                  const Text('No one has arrived yet.')
                else
                  ...arrivalLeaders.take(3).toList().asMap().entries.map(
                    (entry) {
                      final rank = entry.key + 1;
                      final p = entry.value;
                      final travel = p.arrivedAt!.difference(route.createdAt);
                      final minutes = travel.inMinutes;
                      final seconds = travel.inSeconds.remainder(60);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '$rank. ${p.displayName} - ${minutes}m ${seconds}s',
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _panTo(double lat, double lng, {double zoom = 15}) {
    if (_useGoogleAndroidMap) {
      _googleMapController?.animateCamera(
        gm.CameraUpdate.newLatLngZoom(gm.LatLng(lat, lng), zoom),
      );
      return;
    }

    if (_useAppleIosMap) {
      _platformMapController?.animateCamera(
        pm.CameraUpdate.newLatLngZoom(pm.LatLng(lat, lng), zoom),
      );
      return;
    }
    _fallbackMapController.move(ll.LatLng(lat, lng), zoom);
  }

  Set<gm.Marker> _googleMemberMarkers(
      AppState appState, AppearanceProvider appearance) {
    if (!appearance.showPeopleOnMap) return const {};
    return appState.groupMembers
        .where((m) => m.lat != null && m.lng != null)
        .map(
          (m) => gm.Marker(
            markerId: gm.MarkerId('member_${m.uid}'),
            position: gm.LatLng(m.lat!, m.lng!),
            icon: gm.BitmapDescriptor.defaultMarkerWithHue(
                gm.BitmapDescriptor.hueBlue),
          ),
        )
        .toSet();
  }

  String _timeAtLocation(AppUser member) {
    final arrivedAt = member.arrivedAtCurrentLocation;
    if (arrivedAt == null) return 'time at location unavailable';
    final d = DateTime.now().difference(arrivedAt);
    if (d.inMinutes < 1) return 'just arrived';
    if (d.inHours < 1) return 'here for ${d.inMinutes}m';
    return 'here for ${d.inHours}h ${d.inMinutes.remainder(60)}m';
  }

  String _locationLabel(AppUser member) {
    if (member.currentLocationLabel != null &&
        member.currentLocationLabel!.trim().isNotEmpty) {
      return member.currentLocationLabel!;
    }
    if (member.lat != null && member.lng != null) {
      return '${member.lat!.toStringAsFixed(4)}, ${member.lng!.toStringAsFixed(4)}';
    }
    return 'location unavailable';
  }

  List<fm.Marker> _memberMarkers(
      AppState appState, AppearanceProvider appearance) {
    if (!appearance.showPeopleOnMap) return const [];
    return appState.groupMembers
        .where((m) => m.lat != null && m.lng != null)
        .map((m) => fm.Marker(
              point: ll.LatLng(m.lat!, m.lng!),
              width: 32,
              height: 32,
              child: const Icon(Icons.person_pin_circle,
                  color: Colors.blue, size: 32),
            ))
        .toList();
  }

  Set<pm.Marker> _nativeMemberMarkers(
      AppState appState, AppearanceProvider appearance) {
    if (!appearance.showPeopleOnMap) return const {};
    return appState.groupMembers
        .where((m) => m.lat != null && m.lng != null)
        .map(
          (m) => pm.Marker(
            markerId: pm.MarkerId('member_${m.uid}'),
            position: pm.LatLng(m.lat!, m.lng!),
          ),
        )
        .toSet();
  }

  List<fm.CircleMarker> _placeCircles(
      List<Place> places, AppearanceProvider appearance) {
    if (!appearance.showPlacesOnMap) return const [];
    return places
        .map((p) => fm.CircleMarker(
              point: ll.LatLng(p.lat, p.lng),
              radius: p.radiusMeters / 1000,
              color: Colors.deepPurple.withValues(alpha: 0.10),
              borderColor: Colors.deepPurple.withValues(alpha: 0.6),
              borderStrokeWidth: 2,
            ))
        .toList();
  }

  Set<pm.Circle> _nativePlaceCircles(
      List<Place> places, AppearanceProvider appearance) {
    if (!appearance.showPlacesOnMap) return const {};
    return places
        .map(
          (p) => pm.Circle(
            circleId: pm.CircleId('place_${p.id}'),
            center: pm.LatLng(p.lat, p.lng),
            radius: p.radiusMeters,
            fillColor: Colors.deepPurple.withValues(alpha: 0.10),
            strokeColor: Colors.deepPurple.withValues(alpha: 0.6),
            strokeWidth: 2,
          ),
        )
        .toSet();
  }

  Set<gm.Circle> _googlePlaceCircles(
      List<Place> places, AppearanceProvider appearance) {
    if (!appearance.showPlacesOnMap) return const {};
    return places
        .map(
          (p) => gm.Circle(
            circleId: gm.CircleId('place_${p.id}'),
            center: gm.LatLng(p.lat, p.lng),
            radius: p.radiusMeters,
            fillColor: Colors.deepPurple.withValues(alpha: 0.10),
            strokeColor: Colors.deepPurple.withValues(alpha: 0.6),
            strokeWidth: 2,
          ),
        )
        .toSet();
  }

  List<fm.Marker> _hazardMarkers(
      List<HazardReport> hazards, AppearanceProvider appearance) {
    if (!appearance.showCopsOnMap) return const [];
    return hazards
        .map((h) => fm.Marker(
              point: ll.LatLng(h.lat, h.lng),
              width: 28,
              height: 28,
              child: Icon(
                _hazardIcon(h.type),
                color: _hazardAccent(h.type),
                size: 28,
              ),
            ))
        .toList();
  }

  Set<pm.Marker> _nativeHazardMarkers(
      List<HazardReport> hazards, AppearanceProvider appearance) {
    if (!appearance.showCopsOnMap) return const {};
    return hazards
        .map(
          (h) => pm.Marker(
            markerId: pm.MarkerId('hazard_${h.id}'),
            position: pm.LatLng(h.lat, h.lng),
            icon: _platformHazardSymbolIcons[h.type],
            infoWindow: pm.InfoWindow(
              title: '${_hazardMarkerEmoji(h.type)} ${h.label}',
              snippet: 'Reported by ${h.reportedByName}',
            ),
          ),
        )
        .toSet();
  }

  Set<gm.Marker> _googleHazardMarkers(
      List<HazardReport> hazards, AppearanceProvider appearance) {
    if (!appearance.showCopsOnMap) return const {};
    return hazards
        .map(
          (h) => gm.Marker(
            markerId: gm.MarkerId('hazard_${h.id}'),
            position: gm.LatLng(h.lat, h.lng),
            infoWindow: gm.InfoWindow(
              title: '${_hazardMarkerEmoji(h.type)} ${h.label}',
              snippet: 'Reported by ${h.reportedByName}',
            ),
            icon: _googleHazardSymbolIcons[h.type] ??
                gm.BitmapDescriptor.defaultMarkerWithHue(
                  _googleHazardHue(h.type),
                ),
          ),
        )
        .toSet();
  }

  List<fm.Marker> _aircraftMarkers(
      AppState appState, AppearanceProvider appearance) {
    if (!appearance.showHelicoptersOnMap) return const [];
    return appState.aircraft
        .map((a) => fm.Marker(
              point: ll.LatLng(a.lat, a.lng),
              width: 24,
              height: 24,
              child: const Icon(Icons.airplanemode_active,
                  color: Colors.amber, size: 24),
            ))
        .toList();
  }

  Set<pm.Marker> _nativeAircraftMarkers(
      AppState appState, AppearanceProvider appearance) {
    if (!appearance.showHelicoptersOnMap) return const {};
    return appState.aircraft
        .map(
          (a) => pm.Marker(
            markerId: pm.MarkerId('aircraft_${a.icao24}'),
            position: pm.LatLng(a.lat, a.lng),
          ),
        )
        .toSet();
  }

  Set<gm.Marker> _googleAircraftMarkers(
      AppState appState, AppearanceProvider appearance) {
    if (!appearance.showHelicoptersOnMap) return const {};
    return appState.aircraft
        .map(
          (a) => gm.Marker(
            markerId: gm.MarkerId('aircraft_${a.icao24}'),
            position: gm.LatLng(a.lat, a.lng),
            icon: gm.BitmapDescriptor.defaultMarkerWithHue(
                gm.BitmapDescriptor.hueYellow),
          ),
        )
        .toSet();
  }

  Widget _buildFallbackMap({
    required AppState appState,
    required AppearanceProvider appearance,
    required String? groupId,
    required List<String> allGroupIds,
    required ll.LatLng myLatLng,
    required List<Place> places,
    required List<HazardReport> hazards,
  }) {
    return fm.FlutterMap(
      mapController: _fallbackMapController,
      options: fm.MapOptions(
        initialCenter: myLatLng,
        initialZoom: 14,
        onLongPress: groupId == null
            ? null
            : (tapPosition, point) => showModalBottomSheet(
                  context: context,
                  shape: const RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  builder: (_) => HazardReportDialog(
                    groupId: groupId,
                    groupIds: allGroupIds,
                    lat: point.latitude,
                    lng: point.longitude,
                    reportedByUid: appState.auth.currentUser!.uid,
                    reportedByName:
                        appState.auth.currentUser!.displayName ?? 'Someone',
                  ),
                ),
      ),
      children: [
        fm.TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.circle_map',
        ),
        fm.MarkerLayer(
          markers: [
            ..._memberMarkers(appState, appearance),
            ..._hazardMarkers(hazards, appearance),
            ..._aircraftMarkers(appState, appearance),
          ],
        ),
        fm.CircleLayer(
          circles: _placeCircles(places, appearance),
        ),
        if (_activeRouteOverlay != null)
          fm.PolylineLayer(
            polylines: [
              fm.Polyline(
                points: [
                  ll.LatLng(_activeRouteOverlay!.startLat,
                      _activeRouteOverlay!.startLng),
                  ll.LatLng(_activeRouteOverlay!.destinationLat,
                      _activeRouteOverlay!.destinationLng),
                ],
                color: _activeRouteOverlay!.isGroupRoute
                    ? Colors.green.shade700
                    : Colors.blue.shade700,
                strokeWidth: 5,
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildNativePlatformMap({
    required AppState appState,
    required AppearanceProvider appearance,
    required String? groupId,
    required List<String> allGroupIds,
    required pm.LatLng myLatLng,
    required List<Place> places,
    required List<HazardReport> hazards,
  }) {
    return pm.PlatformMap(
      initialCameraPosition: pm.CameraPosition(target: myLatLng, zoom: 14),
      zoomControlsEnabled: false,
      myLocationButtonEnabled: false,
      onMapCreated: (controller) => _platformMapController = controller,
      onLongPress: groupId == null
          ? null
          : (point) => showModalBottomSheet(
                context: context,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                builder: (_) => HazardReportDialog(
                  groupId: groupId,
                  groupIds: allGroupIds,
                  lat: point.latitude,
                  lng: point.longitude,
                  reportedByUid: appState.auth.currentUser!.uid,
                  reportedByName:
                      appState.auth.currentUser!.displayName ?? 'Someone',
                ),
              ),
      markers: {
        ..._nativeMemberMarkers(appState, appearance),
        ..._nativeHazardMarkers(hazards, appearance),
        ..._nativeAircraftMarkers(appState, appearance),
      },
      circles: {
        ..._nativePlaceCircles(places, appearance),
      },
      polylines: _activeRouteOverlay == null
          ? const {}
          : {
              pm.Polyline(
                polylineId: pm.PolylineId('active_route'),
                points: [
                  pm.LatLng(_activeRouteOverlay!.startLat,
                      _activeRouteOverlay!.startLng),
                  pm.LatLng(
                    _activeRouteOverlay!.destinationLat,
                    _activeRouteOverlay!.destinationLng,
                  ),
                ],
                color: _activeRouteOverlay!.isGroupRoute
                    ? Colors.green.shade700
                    : Colors.blue.shade700,
                width: 5,
              ),
            },
    );
  }

  Widget _buildGoogleAndroidMap({
    required AppState appState,
    required AppearanceProvider appearance,
    required String? groupId,
    required List<String> allGroupIds,
    required gm.LatLng myLatLng,
    required List<Place> places,
    required List<HazardReport> hazards,
  }) {
    return gm.GoogleMap(
      initialCameraPosition: gm.CameraPosition(target: myLatLng, zoom: 14),
      zoomControlsEnabled: false,
      myLocationButtonEnabled: false,
      onMapCreated: (controller) => _googleMapController = controller,
      onLongPress: groupId == null
          ? null
          : (point) => showModalBottomSheet(
                context: context,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                builder: (_) => HazardReportDialog(
                  groupId: groupId,
                  groupIds: allGroupIds,
                  lat: point.latitude,
                  lng: point.longitude,
                  reportedByUid: appState.auth.currentUser!.uid,
                  reportedByName:
                      appState.auth.currentUser!.displayName ?? 'Someone',
                ),
              ),
      markers: {
        ..._googleMemberMarkers(appState, appearance),
        ..._googleHazardMarkers(hazards, appearance),
        ..._googleAircraftMarkers(appState, appearance),
      },
      circles: {
        ..._googlePlaceCircles(places, appearance),
      },
      polylines: _activeRouteOverlay == null
          ? const {}
          : {
              gm.Polyline(
                polylineId: const gm.PolylineId('active_route'),
                points: [
                  gm.LatLng(_activeRouteOverlay!.startLat,
                      _activeRouteOverlay!.startLng),
                  gm.LatLng(
                    _activeRouteOverlay!.destinationLat,
                    _activeRouteOverlay!.destinationLng,
                  ),
                ],
                color: _activeRouteOverlay!.isGroupRoute
                    ? Colors.green.shade700
                    : Colors.blue.shade700,
                width: 6,
              ),
            },
    );
  }

  void _applyRouteOverlay({
    required RouteTargetOption start,
    required RouteTargetOption destination,
    required bool isGroupRoute,
  }) {
    setState(() {
      _activeRouteOverlay = _RouteOverlay(
        startLat: start.lat,
        startLng: start.lng,
        destinationLat: destination.lat,
        destinationLng: destination.lng,
        startLabel: start.label,
        destinationLabel: destination.label,
        isGroupRoute: isGroupRoute,
      );
    });

    _panTo(destination.lat, destination.lng, zoom: 14);
  }

  Future<List<AppUser>?> _pickGroupRouteMembers(List<AppUser> members) async {
    final selected = members.map((m) => m.uid).toSet();

    return showModalBottomSheet<List<AppUser>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.72,
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Select members for group route',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        children: members.map((member) {
                          final isChecked = selected.contains(member.uid);
                          return CheckboxListTile(
                            title: Text(member.displayName),
                            subtitle:
                                Text('${member.batteryLevel.round()}% battery'),
                            value: isChecked,
                            onChanged: (value) {
                              setSheetState(() {
                                if (value == true) {
                                  selected.add(member.uid);
                                } else {
                                  selected.remove(member.uid);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(sheetContext).pop(),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: selected.isEmpty
                                  ? null
                                  : () {
                                      Navigator.of(sheetContext).pop(
                                        members
                                            .where(
                                                (m) => selected.contains(m.uid))
                                            .toList(),
                                      );
                                    },
                              child: const Text('Use selected'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _handleRouteSetupRequest(
    RouteSetupRequest request,
  ) async {
    final appState = _appState;
    final group = appState?.activeGroup;
    final me = appState?.auth.currentUser;

    if (appState == null || group == null || me == null) {
      return;
    }

    _applyRouteOverlay(
      start: request.start,
      destination: request.destination,
      isGroupRoute: request.isGroupRoute,
    );

    if (!request.isGroupRoute) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Route ready: ${request.start.label} to ${request.destination.label}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final selectedMembers = await _pickGroupRouteMembers(appState.groupMembers);
    if (selectedMembers == null || selectedMembers.isEmpty || !mounted) {
      return;
    }

    final route = GroupRoute(
      id: '',
      groupId: group.id,
      createdByUid: me.uid,
      createdByName: me.displayName ?? 'Member',
      start: RouteEndpoint(
        label: request.start.label,
        lat: request.start.lat,
        lng: request.start.lng,
        radiusMeters: request.start.radiusMeters,
      ),
      destination: RouteEndpoint(
        label: request.destination.label,
        lat: request.destination.lat,
        lng: request.destination.lng,
        radiusMeters: request.destination.radiusMeters,
      ),
      visibleMemberUids: selectedMembers.map((m) => m.uid).toList(),
      createdAt: DateTime.now(),
      completedAt: null,
      isCompleted: false,
      participantStats: {
        for (final m in selectedMembers)
          m.uid: GroupRouteParticipant(
            uid: m.uid,
            displayName: m.displayName,
            topSpeedMph: 0,
            arrivedAt: null,
          ),
      },
    );

    final routeId = await appState.firestore.createGroupRoute(
      groupId: group.id,
      route: route,
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Group route started for ${selectedMembers.length} member(s).',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );

    final cached = GroupRoute(
      id: routeId,
      groupId: route.groupId,
      createdByUid: route.createdByUid,
      createdByName: route.createdByName,
      start: route.start,
      destination: route.destination,
      visibleMemberUids: route.visibleMemberUids,
      createdAt: route.createdAt,
      completedAt: null,
      isCompleted: false,
      participantStats: route.participantStats,
    );
    _latestGroupRoutesById[routeId] = cached;
    _syncMyGroupRouteProgress();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final appearance = context.watch<AppearanceProvider>();
    final groupId = appState.activeGroup?.id;
    final allGroupIds = appState.myGroups.map((g) => g.id).toList();

    final me = appState.groupMembers
        .where((m) => m.uid == appState.auth.currentUser?.uid)
        .toList();
    final myLatLng = me.isNotEmpty && me.first.lat != null
        ? pm.LatLng(me.first.lat!, me.first.lng!)
        : const pm.LatLng(37.7749, -122.4194);

    final myGoogleLatLng = me.isNotEmpty && me.first.lat != null
        ? gm.LatLng(me.first.lat!, me.first.lng!)
        : const gm.LatLng(37.7749, -122.4194);

    final myFallbackLatLng = me.isNotEmpty && me.first.lat != null
        ? ll.LatLng(me.first.lat!, me.first.lng!)
        : ll.LatLng(37.7749, -122.4194);
    final selectedMember = _selectedMember(appState);

    return Scaffold(
      body: Stack(
        children: [
          StreamBuilder<List<Place>>(
            stream: groupId == null
                ? const Stream.empty()
                : appState.firestore.watchPlaces(groupId),
            builder: (context, placeSnap) {
              return StreamBuilder<List<HazardReport>>(
                stream: groupId == null
                    ? const Stream.empty()
                    : appState.firestore.watchHazards(groupId),
                builder: (context, hazardSnap) {
                  final places = placeSnap.data ?? const <Place>[];
                  final hazards = hazardSnap.data ?? const <HazardReport>[];
                  return SizedBox.expand(
                    child: _useGoogleAndroidMap
                        ? _buildGoogleAndroidMap(
                            appState: appState,
                            appearance: appearance,
                            groupId: groupId,
                            allGroupIds: allGroupIds,
                            myLatLng: myGoogleLatLng,
                            places: places,
                            hazards: hazards,
                          )
                        : _useAppleIosMap
                            ? _buildNativePlatformMap(
                                appState: appState,
                                appearance: appearance,
                                groupId: groupId,
                                allGroupIds: allGroupIds,
                                myLatLng: myLatLng,
                                places: places,
                                hazards: hazards,
                              )
                            : _buildFallbackMap(
                                appState: appState,
                                appearance: appearance,
                                groupId: groupId,
                                allGroupIds: allGroupIds,
                                myLatLng: myFallbackLatLng,
                                places: places,
                                hazards: hazards,
                              ),
                  );
                },
              );
            },
          ),

          // Top-left: settings menu entry point.
          Positioned(
            top: 48,
            left: 16,
            child: _RoundIconButton(
              icon: Icons.menu,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const SettingsMenuScreen())),
            ),
          ),

          // Top-center: group dropdown.
          const Positioned(
              top: 44, left: 72, right: 72, child: GroupDropdownButton()),

          // Top-right: open full-screen group route menu.
          Positioned(
            top: 48,
            right: 16,
            child: _RoundIconButton(
              icon: Icons.leaderboard,
              onTap: () {
                final activeGroup = appState.activeGroup;
                if (activeGroup == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Select a group first.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }

                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GroupRouteMenuScreen(
                      groupId: activeGroup.id,
                      groupName: activeGroup.name,
                    ),
                  ),
                );
              },
            ),
          ),

          // Live speed readout while a trip is recording.
          if (appState.isTripActive)
            const Positioned(
                top: 100, left: 16, right: 16, child: SpeedDisplay()),

          // Top-right: temporary takeoff notification stack.
          Positioned(
            top: 4,
            left: 8,
            right: 8,
            child: SafeArea(
              bottom: false,
              child: Column(
                children: _activeTopBanners
                    .map(
                      (banner) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InAppNotificationBanner(
                          icon: banner.icon,
                          accentColor: banner.accentColor,
                          title: banner.title,
                          message: banner.message,
                          onTap: () async {
                            switch (banner.kind) {
                              case _TopBannerKind.takeoff:
                                final event = banner.takeoffEvent;
                                if (event != null) {
                                  _panTo(event.takeoffLat, event.takeoffLng,
                                      zoom: 13);
                                }
                                break;
                              case _TopBannerKind.hazard:
                                final groupId = banner.groupId;
                                final hazard = banner.hazard;
                                if (groupId != null && hazard != null) {
                                  await _promptHazardVerification(
                                    groupId: groupId,
                                    hazard: hazard,
                                  );
                                }
                                break;
                              case _TopBannerKind.battery:
                                if (banner.memberUid != null &&
                                    _openMemberDetailsByUid(
                                        banner.memberUid!)) {
                                  break;
                                }
                                if (banner.lat != null && banner.lng != null) {
                                  _panTo(banner.lat!, banner.lng!, zoom: 14);
                                }
                                break;
                              case _TopBannerKind.groupRouteFinished:
                                if (banner.routeId != null) {
                                  await _showGroupRouteLeaderboard(
                                      banner.routeId!);
                                }
                                break;
                              case _TopBannerKind.customMember:
                                if (banner.memberUid != null &&
                                    _openMemberDetailsByUid(
                                        banner.memberUid!)) {
                                  break;
                                }
                                if (banner.lat != null && banner.lng != null) {
                                  _panTo(banner.lat!, banner.lng!, zoom: 14);
                                }
                                break;
                            }
                          },
                          onDismiss: () => _dismissTopBannerById(banner.id),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),

          // Recenter button, tucked above the member pill.
          Positioned(
            right: 16,
            bottom: 150,
            child: FloatingActionButton.small(
              heroTag: 'recenter',
              backgroundColor: Theme.of(context).colorScheme.surface,
              onPressed: () {
                if (me.isNotEmpty && me.first.lat != null) {
                  _panTo(me.first.lat!, me.first.lng!);
                }
              },
              child: const Icon(Icons.my_location),
            ),
          ),

          // Always-visible horizontal member strip for quick focus.
          Positioned(
            left: 12,
            right: 12,
            bottom: selectedMember == null ? 78 : 144,
            child: _MemberQuickStrip(
              members: appState.groupMembers,
              onFocusMember: (member) {
                _selectMember(member.uid);
                if (member.lat == null || member.lng == null) return;
                _panTo(member.lat!, member.lng!);
                final message =
                    '${member.displayName} • ${_locationLabel(member)} • ${_timeAtLocation(member)} • ${member.batteryLevel.round()}%';
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(
                      content: Text(message,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 3),
                    ),
                  );
              },
              onOpenMemberInfo: (member) {
                _selectMember(member.uid);
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => MemberDetailScreen(member: member)),
                );
              },
            ),
          ),

          if (selectedMember != null &&
              appState.notificationsEnabled &&
              appState.customInAppNotificationsEnabled)
            Positioned(
              left: 12,
              right: 12,
              bottom: 86,
              child: _SelectedMemberNotificationStrip(
                member: selectedMember,
                templates: _visibleQuickNotificationTemplates(appState),
                onClearSelection: _clearSelectedMember,
                onSend: (template) => _sendQuickMemberNotification(
                  member: selectedMember,
                  template: template,
                ),
              ),
            ),

          // Bottom-center: member list.
          Positioned(
            bottom: 24,
            left: 24,
            right: 24,
            child: StreamBuilder<List<Place>>(
              stream: groupId == null
                  ? const Stream.empty()
                  : appState.firestore.watchPlaces(groupId),
              builder: (context, placeSnap) {
                final places = placeSnap.data ?? const <Place>[];
                return MemberListButton(
                  places: places,
                  onFocusMember: (AppUser member) {
                    _selectMember(member.uid);
                    if (member.lat != null && member.lng != null) {
                      _panTo(member.lat!, member.lng!);
                      final message =
                          '${member.displayName} • ${_locationLabel(member)} • ${_timeAtLocation(member)} • ${member.batteryLevel.round()}%';
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(
                            content: Text(message,
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 3),
                          ),
                        );
                    }
                  },
                  onFocusPlace: (place) {
                    _panTo(place.lat, place.lng, zoom: 15);
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(
                          content: Text('Focused place: ${place.name}'),
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                  },
                  onSubmitRouteSetup: _handleRouteSetupRequest,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final appearance = context.watch<AppearanceProvider>();
    final buttonColor = appearance.buttonColor;
    final iconColor = appearance.textColor;
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    return Material(
      color: buttonColor,
      shape: shape,
      elevation: 3,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        splashColor: Colors.black12,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, color: iconColor),
        ),
      ),
    );
  }
}

class _MemberQuickStrip extends StatelessWidget {
  final List<AppUser> members;
  final void Function(AppUser member) onFocusMember;
  final void Function(AppUser member) onOpenMemberInfo;

  const _MemberQuickStrip({
    required this.members,
    required this.onFocusMember,
    required this.onOpenMemberInfo,
  });

  @override
  Widget build(BuildContext context) {
    final sortedMembers = [...members]..sort((a, b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));

    if (sortedMembers.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 60,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: sortedMembers.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final member = sortedMembers[index];
          return Material(
            color:
                Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(22),
            elevation: 2,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => onFocusMember(member),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundImage: member.photoUrl != null
                          ? NetworkImage(member.photoUrl!)
                          : null,
                      child: member.photoUrl == null
                          ? Text(
                              member.displayName.isNotEmpty
                                  ? member.displayName[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(fontSize: 12),
                            )
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          member.displayName,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${member.batteryLevel.round()}%',
                          style: TextStyle(
                            fontSize: 11,
                            color: member.batteryLevel <= 20
                                ? Colors.red
                                : Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      onPressed: () => onOpenMemberInfo(member),
                      icon: const Icon(Icons.info_outline, size: 18),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minHeight: 28, minWidth: 28),
                      splashRadius: 16,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

enum _TopBannerKind {
  takeoff,
  hazard,
  battery,
  groupRouteFinished,
  customMember,
}

class _ActiveTopBanner {
  final int id;
  final _TopBannerKind kind;
  final String title;
  final String message;
  final IconData icon;
  final Color accentColor;
  final TakeoffEvent? takeoffEvent;
  final HazardReport? hazard;
  final String? groupId;
  final String? memberUid;
  final String? routeId;
  final bool isExplicit;
  final double? lat;
  final double? lng;

  const _ActiveTopBanner._({
    required this.id,
    required this.kind,
    required this.title,
    required this.message,
    required this.icon,
    required this.accentColor,
    this.takeoffEvent,
    this.hazard,
    this.groupId,
    this.memberUid,
    this.routeId,
    this.isExplicit = false,
    this.lat,
    this.lng,
  });

  factory _ActiveTopBanner.takeoff({
    required int id,
    required TakeoffEvent event,
    required String title,
    required String message,
  }) {
    return _ActiveTopBanner._(
      id: id,
      kind: _TopBannerKind.takeoff,
      title: title,
      message: message,
      icon: Icons.flight_takeoff,
      accentColor: Colors.amberAccent,
      takeoffEvent: event,
    );
  }

  factory _ActiveTopBanner.hazard({
    required int id,
    required String groupId,
    required HazardReport hazard,
    required String title,
    required String message,
    required IconData icon,
    required Color accentColor,
  }) {
    return _ActiveTopBanner._(
      id: id,
      kind: _TopBannerKind.hazard,
      title: title,
      message: message,
      icon: icon,
      accentColor: accentColor,
      groupId: groupId,
      hazard: hazard,
    );
  }

  factory _ActiveTopBanner.battery({
    required int id,
    required String memberUid,
    required String title,
    required String message,
    double? lat,
    double? lng,
  }) {
    return _ActiveTopBanner._(
      id: id,
      kind: _TopBannerKind.battery,
      title: title,
      message: message,
      icon: Icons.battery_alert,
      accentColor: Colors.redAccent,
      memberUid: memberUid,
      lat: lat,
      lng: lng,
    );
  }

  factory _ActiveTopBanner.groupRouteFinished({
    required int id,
    required String routeId,
    required String title,
    required String message,
  }) {
    return _ActiveTopBanner._(
      id: id,
      kind: _TopBannerKind.groupRouteFinished,
      title: title,
      message: message,
      icon: Icons.emoji_events_outlined,
      accentColor: Colors.greenAccent,
      routeId: routeId,
    );
  }

  factory _ActiveTopBanner.customMember({
    required int id,
    required String memberUid,
    required String title,
    required String message,
    required IconData icon,
    required Color accentColor,
    required bool isExplicit,
    double? lat,
    double? lng,
  }) {
    return _ActiveTopBanner._(
      id: id,
      kind: _TopBannerKind.customMember,
      title: title,
      message: message,
      icon: icon,
      accentColor: accentColor,
      memberUid: memberUid,
      isExplicit: isExplicit,
      lat: lat,
      lng: lng,
    );
  }
}

class _QuickMemberNotificationTemplate {
  final String id;
  final String label;
  final String messageTemplate;
  final IconData icon;
  final Color accent;
  final bool isExplicit;

  const _QuickMemberNotificationTemplate({
    required this.id,
    required this.label,
    required this.messageTemplate,
    required this.icon,
    required this.accent,
    required this.isExplicit,
  });
}

class _SelectedMemberNotificationStrip extends StatelessWidget {
  final AppUser member;
  final List<_QuickMemberNotificationTemplate> templates;
  final ValueChanged<_QuickMemberNotificationTemplate> onSend;
  final VoidCallback onClearSelection;

  const _SelectedMemberNotificationStrip({
    required this.member,
    required this.templates,
    required this.onSend,
    required this.onClearSelection,
  });

  @override
  Widget build(BuildContext context) {
    if (templates.isEmpty) return const SizedBox.shrink();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Quick notify ${member.displayName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Clear selection',
                onPressed: onClearSelection,
                icon: const Icon(Icons.close, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minHeight: 24, minWidth: 24),
                splashRadius: 16,
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: templates.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final template = templates[index];
                return ActionChip(
                  avatar: Icon(template.icon, size: 16, color: Colors.black87),
                  label: Text(template.label),
                  backgroundColor: template.accent.withValues(alpha: 0.28),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(
                      color: template.accent.withValues(alpha: 0.58),
                    ),
                  ),
                  onPressed: () => onSend(template),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteOverlay {
  final double startLat;
  final double startLng;
  final double destinationLat;
  final double destinationLng;
  final String startLabel;
  final String destinationLabel;
  final bool isGroupRoute;

  const _RouteOverlay({
    required this.startLat,
    required this.startLng,
    required this.destinationLat,
    required this.destinationLng,
    required this.startLabel,
    required this.destinationLabel,
    required this.isGroupRoute,
  });
}
