import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/app_state.dart';
import '../providers/appearance_provider.dart';
import 'appearance_settings_screen.dart';
import 'helicopter_settings_screen.dart';

class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  bool _loading = true;

  bool _notificationsEnabled = true;
  bool _helicopterAlerts = true;
  bool _policeAlerts = true;
  bool _accidentAlerts = true;
  bool _hazardAlerts = true;
  bool _batteryAlerts = true;
  bool _customInAppNotifications = true;
  bool _allowExplicitCustomNotifications = false;
  bool _notificationSound = true;
  bool _notificationVibration = true;
  bool _quietHours = false;

  bool _preciseLocation = true;
  bool _backgroundLocation = true;
  bool _crashDetection = true;
  bool _shareDiagnostics = false;

  bool _useMetricUnits = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    setState(() {
      _notificationsEnabled =
          prefs.getBool('appSettings.notificationsEnabled') ?? true;
      _helicopterAlerts = prefs.getBool('appSettings.helicopterAlerts') ?? true;
      _policeAlerts = prefs.getBool('appSettings.policeAlerts') ?? true;
      _accidentAlerts = prefs.getBool('appSettings.accidentAlerts') ?? true;
      _hazardAlerts = prefs.getBool('appSettings.hazardAlerts') ?? true;
      _batteryAlerts = prefs.getBool('appSettings.batteryAlerts') ?? true;
        _customInAppNotifications =
          prefs.getBool('appSettings.customInAppNotifications') ?? true;
        _allowExplicitCustomNotifications =
          prefs.getBool('appSettings.allowExplicitCustomNotifications') ??
            false;
      _notificationSound =
          prefs.getBool('appSettings.notificationSound') ?? true;
      _notificationVibration =
          prefs.getBool('appSettings.notificationVibration') ?? true;
      _quietHours = prefs.getBool('appSettings.quietHours') ?? false;

      _preciseLocation = prefs.getBool('appSettings.preciseLocation') ?? true;
      _backgroundLocation =
          prefs.getBool('appSettings.backgroundLocation') ?? true;
      _crashDetection = prefs.getBool('appSettings.crashDetection') ?? true;
      _shareDiagnostics =
          prefs.getBool('appSettings.shareDiagnostics') ?? false;

      _useMetricUnits = prefs.getBool('appSettings.useMetricUnits') ?? false;
      _reduceMotion = prefs.getBool('appSettings.reduceMotion') ?? false;
      _loading = false;
    });
  }

  Future<void> _persistBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _setNotificationMaster(bool enabled) async {
    final appState = context.read<AppState>();

    if (enabled) {
      final status = await Permission.notification.request();
      if (!status.isGranted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                  'Notification permission is off. Enable it in system settings.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        setState(() => _notificationsEnabled = false);
        await appState.setNotificationsEnabled(false);
        return;
      }
    }

    setState(() => _notificationsEnabled = enabled);
    await appState.setNotificationsEnabled(enabled);
  }

  Future<void> _setBackgroundLocation(bool enabled) async {
    if (enabled) {
      final status = await Permission.locationAlways.request();
      if (!status.isGranted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                  'Background location is off. Enable it in system settings.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        setState(() => _backgroundLocation = false);
        await _persistBool('appSettings.backgroundLocation', false);
        return;
      }
    }

    setState(() => _backgroundLocation = enabled);
    await _persistBool('appSettings.backgroundLocation', enabled);
  }

  Future<void> _resetToDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset app settings?'),
        content: const Text(
            'This will restore all app settings on this device to defaults.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final appState = context.read<AppState>();
    final appearance = context.read<AppearanceProvider>();
    final prefs = await SharedPreferences.getInstance();

    const bool defaultNotificationsEnabled = true;
    const bool defaultHelicopterAlerts = true;
    const bool defaultPoliceAlerts = true;
    const bool defaultAccidentAlerts = true;
    const bool defaultHazardAlerts = true;
    const bool defaultBatteryAlerts = true;
    const bool defaultCustomInAppNotifications = true;
    const bool defaultAllowExplicitCustomNotifications = false;
    const bool defaultNotificationSound = true;
    const bool defaultNotificationVibration = true;
    const bool defaultQuietHours = false;
    const bool defaultPreciseLocation = true;
    const bool defaultBackgroundLocation = true;
    const bool defaultCrashDetection = true;
    const bool defaultShareDiagnostics = false;
    const bool defaultUseMetricUnits = false;
    const bool defaultReduceMotion = false;

    await prefs.setBool(
        'appSettings.notificationsEnabled', defaultNotificationsEnabled);
    await prefs.setBool(
        'appSettings.helicopterAlerts', defaultHelicopterAlerts);
    await prefs.setBool('appSettings.policeAlerts', defaultPoliceAlerts);
    await prefs.setBool('appSettings.accidentAlerts', defaultAccidentAlerts);
    await prefs.setBool('appSettings.hazardAlerts', defaultHazardAlerts);
    await prefs.setBool('appSettings.batteryAlerts', defaultBatteryAlerts);
    await prefs.setBool('appSettings.customInAppNotifications',
      defaultCustomInAppNotifications);
    await prefs.setBool('appSettings.allowExplicitCustomNotifications',
      defaultAllowExplicitCustomNotifications);
    await prefs.setBool(
        'appSettings.notificationSound', defaultNotificationSound);
    await prefs.setBool(
        'appSettings.notificationVibration', defaultNotificationVibration);
    await prefs.setBool('appSettings.quietHours', defaultQuietHours);
    await prefs.setBool('appSettings.preciseLocation', defaultPreciseLocation);
    await prefs.setBool(
        'appSettings.backgroundLocation', defaultBackgroundLocation);
    await prefs.setBool('appSettings.crashDetection', defaultCrashDetection);
    await prefs.setBool(
        'appSettings.shareDiagnostics', defaultShareDiagnostics);
    await prefs.setBool('appSettings.useMetricUnits', defaultUseMetricUnits);
    await prefs.setBool('appSettings.reduceMotion', defaultReduceMotion);

    await appState.setNotificationsEnabled(defaultNotificationsEnabled);
    await appState.setHelicopterAlertsEnabled(defaultHelicopterAlerts);
    await appState.setPoliceAlertsEnabled(defaultPoliceAlerts);
    await appState.setAccidentAlertsEnabled(defaultAccidentAlerts);
    await appState.setRoadHazardAlertsEnabled(defaultHazardAlerts);
    await appState.setBatteryAlertsEnabled(defaultBatteryAlerts);
    await appState.setCrashDetectionEnabled(defaultCrashDetection);
    await appState
      .setCustomInAppNotificationsEnabled(defaultCustomInAppNotifications);
    await appState.setAllowExplicitCustomNotifications(
      defaultAllowExplicitCustomNotifications);

    appearance.setDarkMode(false);
    appearance.setTextColor(Colors.black);
    appearance.setButtonColor(const Color(0xFF3F51B5));
    appearance.setLayerVisibility(
        cops: true, helicopters: true, people: true, places: true);
    await appState.clearCustomQuickNotificationTemplates();
    await prefs.remove('appSettings.customQuickNotifications');

    if (!mounted) return;
    setState(() {
      _notificationsEnabled = defaultNotificationsEnabled;
      _helicopterAlerts = defaultHelicopterAlerts;
      _policeAlerts = defaultPoliceAlerts;
      _accidentAlerts = defaultAccidentAlerts;
      _hazardAlerts = defaultHazardAlerts;
      _batteryAlerts = defaultBatteryAlerts;
        _customInAppNotifications = defaultCustomInAppNotifications;
        _allowExplicitCustomNotifications =
          defaultAllowExplicitCustomNotifications;
      _notificationSound = defaultNotificationSound;
      _notificationVibration = defaultNotificationVibration;
      _quietHours = defaultQuietHours;
      _preciseLocation = defaultPreciseLocation;
      _backgroundLocation = defaultBackgroundLocation;
      _crashDetection = defaultCrashDetection;
      _shareDiagnostics = defaultShareDiagnostics;
      _useMetricUnits = defaultUseMetricUnits;
      _reduceMotion = defaultReduceMotion;
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('App settings reset to defaults.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final appearance = context.watch<AppearanceProvider>();
    final appState = context.watch<AppState>();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('App Settings'),
          actions: [
            IconButton(
              tooltip: 'Reset to defaults',
              onPressed: _resetToDefaults,
              icon: const Icon(Icons.restart_alt),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'General'),
              Tab(text: 'Notifications'),
              Tab(text: 'Privacy'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            ListView(
              children: [
                SwitchListTile(
                  title: const Text('Dark mode'),
                  subtitle: const Text('Use a dark app appearance.'),
                  value: appearance.isDarkMode,
                  onChanged: appearance.setDarkMode,
                ),
                SwitchListTile(
                  title: const Text('Use metric units'),
                  subtitle: const Text('Show distance and speed in km/kmh.'),
                  value: _useMetricUnits,
                  onChanged: (v) {
                    setState(() => _useMetricUnits = v);
                    _persistBool('appSettings.useMetricUnits', v);
                  },
                ),
                SwitchListTile(
                  title: const Text('Reduce motion'),
                  subtitle:
                      const Text('Minimize animation throughout the app.'),
                  value: _reduceMotion,
                  onChanged: (v) {
                    setState(() => _reduceMotion = v);
                    _persistBool('appSettings.reduceMotion', v);
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('Appearance details'),
                  subtitle:
                      const Text('Colors, map layers, and per-group theme.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const AppearanceSettingsScreen())),
                ),
                ListTile(
                  leading: const Icon(Icons.flight_takeoff),
                  title: const Text('Air traffic settings'),
                  subtitle: const Text('Overlay visibility and search radius.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const HelicopterSettingsScreen())),
                ),
              ],
            ),
            ListView(
              children: [
                SwitchListTile(
                  title: const Text('Enable notifications'),
                  subtitle: const Text('Master switch for app notifications.'),
                  value: _notificationsEnabled,
                  onChanged: _setNotificationMaster,
                ),
                SwitchListTile(
                  title: const Text('Air traffic alerts'),
                  subtitle: const Text(
                      'Notify when aircraft activity appears nearby.'),
                  value: _helicopterAlerts,
                  onChanged: _notificationsEnabled
                      ? (v) {
                          setState(() => _helicopterAlerts = v);
                          appState.setHelicopterAlertsEnabled(v);
                        }
                      : null,
                ),
                SwitchListTile(
                  title: const Text('Police alerts'),
                  subtitle: const Text(
                      'Notify when police are reported in your group.'),
                  value: _policeAlerts,
                  onChanged: _notificationsEnabled
                      ? (v) {
                          setState(() => _policeAlerts = v);
                          appState.setPoliceAlertsEnabled(v);
                        }
                      : null,
                ),
                SwitchListTile(
                  title: const Text('Accident alerts'),
                  subtitle: const Text(
                      'Notify when accidents are reported in your group.'),
                  value: _accidentAlerts,
                  onChanged: _notificationsEnabled
                      ? (v) {
                          setState(() => _accidentAlerts = v);
                          appState.setAccidentAlertsEnabled(v);
                        }
                      : null,
                ),
                SwitchListTile(
                  title: const Text('Road hazard alerts'),
                  subtitle: const Text(
                      'Notify when hazards/objects are reported in your group.'),
                  value: _hazardAlerts,
                  onChanged: _notificationsEnabled
                      ? (v) {
                          setState(() => _hazardAlerts = v);
                          appState.setRoadHazardAlertsEnabled(v);
                        }
                      : null,
                ),
                SwitchListTile(
                  title: const Text('Battery alerts'),
                  subtitle: const Text('Notify when member battery gets low.'),
                  value: _batteryAlerts,
                  onChanged: _notificationsEnabled
                      ? (v) {
                          setState(() => _batteryAlerts = v);
                          appState.setBatteryAlertsEnabled(v);
                        }
                      : null,
                ),
                SwitchListTile(
                  title: const Text('Custom in-app notifications'),
                  subtitle: const Text(
                      'Show ETA / Drive Safe quick actions for selected members.'),
                  value: _customInAppNotifications,
                  onChanged: _notificationsEnabled
                      ? (v) {
                          setState(() => _customInAppNotifications = v);
                          appState.setCustomInAppNotificationsEnabled(v);
                        }
                      : null,
                ),
                SwitchListTile(
                  title: const Text('Allow explicit custom notifications'),
                  subtitle: const Text(
                      'When off, explicit quick messages are hidden.'),
                  value: _allowExplicitCustomNotifications,
                  onChanged:
                      _notificationsEnabled && _customInAppNotifications
                          ? (v) {
                              setState(
                                  () => _allowExplicitCustomNotifications = v);
                              appState.setAllowExplicitCustomNotifications(v);
                            }
                          : null,
                ),
                const Divider(),
                SwitchListTile(
                  title: const Text('Notification sounds'),
                  value: _notificationSound,
                  onChanged: _notificationsEnabled
                      ? (v) {
                          setState(() => _notificationSound = v);
                          _persistBool('appSettings.notificationSound', v);
                        }
                      : null,
                ),
                SwitchListTile(
                  title: const Text('Vibrate on notification'),
                  value: _notificationVibration,
                  onChanged: _notificationsEnabled
                      ? (v) {
                          setState(() => _notificationVibration = v);
                          _persistBool('appSettings.notificationVibration', v);
                        }
                      : null,
                ),
                SwitchListTile(
                  title: const Text('Quiet hours'),
                  subtitle:
                      const Text('Silence non-critical alerts while enabled.'),
                  value: _quietHours,
                  onChanged: _notificationsEnabled
                      ? (v) {
                          setState(() => _quietHours = v);
                          _persistBool('appSettings.quietHours', v);
                        }
                      : null,
                ),
                ListTile(
                  leading: const Icon(Icons.settings),
                  title: const Text('Open system notification settings'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: openAppSettings,
                ),
              ],
            ),
            ListView(
              children: [
                SwitchListTile(
                  title: const Text('Precise location'),
                  subtitle: const Text('Allow high-accuracy GPS location.'),
                  value: _preciseLocation,
                  onChanged: (v) {
                    setState(() => _preciseLocation = v);
                    _persistBool('appSettings.preciseLocation', v);
                  },
                ),
                SwitchListTile(
                  title: const Text('Background location'),
                  subtitle:
                      const Text('Share location while app is backgrounded.'),
                  value: _backgroundLocation,
                  onChanged: _setBackgroundLocation,
                ),
                SwitchListTile(
                  title: const Text('Crash detection'),
                  subtitle:
                      const Text('Use motion sensors to detect major impacts.'),
                  value: _crashDetection,
                  onChanged: (v) {
                    setState(() => _crashDetection = v);
                    appState.setCrashDetectionEnabled(v);
                  },
                ),
                SwitchListTile(
                  title: const Text('Share anonymous diagnostics'),
                  subtitle: const Text(
                      'Help improve reliability with crash analytics.'),
                  value: _shareDiagnostics,
                  onChanged: (v) {
                    setState(() => _shareDiagnostics = v);
                    _persistBool('appSettings.shareDiagnostics', v);
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.settings),
                  title: const Text('Open app permissions'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: openAppSettings,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
