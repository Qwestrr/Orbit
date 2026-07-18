import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/group.dart';

/// Drives everything under Settings -> App Settings -> Appearance:
/// light/dark mode, text color, button color, and which map
/// layers (cops, helicopters, people, places) are visible. Persisted
/// locally via SharedPreferences since these are device preferences,
/// not tracking data.
///
/// Per-group colors (group tab / member list tab accent) live on the
/// FamilyGroup.theme itself in Firestore (see models/group.dart) so they
/// sync across the member's devices and are visible to explain "why does
/// the app look different in this group" — switching activeGroup in
/// AppState should call applyGroupTheme() here.
class AppearanceProvider extends ChangeNotifier {
  bool isDarkMode = false;
  Color textColor = Colors.black;
  Color buttonColor = const Color(0xFF3F51B5);
  GroupTheme? _activeGroupTheme;

  bool showCopsOnMap = true;
  bool showHelicoptersOnMap = true;
  bool showPeopleOnMap = true;
  bool showPlacesOnMap = true;

  Color get groupTabColor =>
      _activeGroupTheme != null ? Color(_activeGroupTheme!.primaryColorArgb) : buttonColor;
  Color get memberListTabColor =>
      _activeGroupTheme != null ? Color(_activeGroupTheme!.memberListTabColorArgb) : buttonColor;

  Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    isDarkMode = prefs.getBool('isDarkMode') ?? false;
    textColor = Color(prefs.getInt('textColor') ?? Colors.black.toARGB32());
    buttonColor = Color(
      prefs.getInt('buttonColor') ??
        prefs.getInt('buttonOutlineColor') ??
        const Color(0xFF3F51B5).toARGB32(),
    );
    showCopsOnMap = prefs.getBool('showCopsOnMap') ?? true;
    showHelicoptersOnMap = prefs.getBool('showHelicoptersOnMap') ?? true;
    showPeopleOnMap = prefs.getBool('showPeopleOnMap') ?? true;
    showPlacesOnMap = prefs.getBool('showPlacesOnMap') ?? true;
    notifyListeners();
  }

  Future<void> _persist(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) await prefs.setBool(key, value);
    if (value is int) await prefs.setInt(key, value);
  }

  void setDarkMode(bool value) {
    isDarkMode = value;
    _persist('isDarkMode', value);
    notifyListeners();
  }

  void setTextColor(Color c) {
    textColor = c;
    _persist('textColor', c.toARGB32());
    notifyListeners();
  }

  void setButtonColor(Color c) {
    buttonColor = c;
    _persist('buttonColor', c.toARGB32());
    notifyListeners();
  }

  void setLayerVisibility({
    bool? cops,
    bool? helicopters,
    bool? people,
    bool? places,
  }) {
    if (cops != null) {
      showCopsOnMap = cops;
      _persist('showCopsOnMap', cops);
    }
    if (helicopters != null) {
      showHelicoptersOnMap = helicopters;
      _persist('showHelicoptersOnMap', helicopters);
    }
    if (people != null) {
      showPeopleOnMap = people;
      _persist('showPeopleOnMap', people);
    }
    if (places != null) {
      showPlacesOnMap = places;
      _persist('showPlacesOnMap', places);
    }
    notifyListeners();
  }

  /// Called by AppState whenever the active group changes, so the group
  /// tab / member list tab colors follow the group automatically.
  void applyGroupTheme(GroupTheme theme) {
    _activeGroupTheme = theme;
    notifyListeners();
  }
}
