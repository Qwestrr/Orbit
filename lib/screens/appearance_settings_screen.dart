import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:provider/provider.dart';
import '../models/group.dart';
import '../providers/app_state.dart';
import '../providers/appearance_provider.dart';

/// Covers the whole "App Appearance" section of the spec: light/dark
/// mode, text color, button color, per-group accent colors
/// (group tab + member list tab), and which map layers are visible
/// (cops, helicopters, people, places).
class AppearanceSettingsScreen extends StatelessWidget {
  const AppearanceSettingsScreen({super.key});

  Future<void> _pickColor(
      BuildContext context, Color current, void Function(Color) onPicked) async {
    Color picked = current;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose a color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: current,
            onColorChanged: (c) => picked = c,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              onPicked(picked);
              Navigator.pop(context);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appearance = context.watch<AppearanceProvider>();
    final appState = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Dark mode'),
            value: appearance.isDarkMode,
            onChanged: appearance.setDarkMode,
          ),
          ListTile(
            title: const Text('Text color'),
            trailing: _ColorSwatch(color: appearance.textColor),
            onTap: () => _pickColor(context, appearance.textColor, appearance.setTextColor),
          ),
          ListTile(
            title: const Text('Button color'),
            trailing: _ColorSwatch(color: appearance.buttonColor),
            onTap: () =>
                _pickColor(context, appearance.buttonColor, appearance.setButtonColor),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('Per-group colors', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              'These apply automatically whenever you switch to this group.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          if (appState.activeGroup != null)
            _GroupThemeEditor(group: appState.activeGroup!)
          else
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Select a group on the map first.'),
            ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('Show on map', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          SwitchListTile(
            title: const Text('People'),
            value: appearance.showPeopleOnMap,
            onChanged: (v) => appearance.setLayerVisibility(people: v),
          ),
          SwitchListTile(
            title: const Text('Places'),
            value: appearance.showPlacesOnMap,
            onChanged: (v) => appearance.setLayerVisibility(places: v),
          ),
          SwitchListTile(
            title: const Text('Cops / Hazards'),
            value: appearance.showCopsOnMap,
            onChanged: (v) => appearance.setLayerVisibility(cops: v),
          ),
          SwitchListTile(
            title: const Text('Air Traffic'),
            value: appearance.showHelicoptersOnMap,
            onChanged: (v) => appearance.setLayerVisibility(helicopters: v),
          ),
        ],
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  final Color color;
  const _ColorSwatch({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.grey.shade400),
      ),
    );
  }
}

class _GroupThemeEditor extends StatelessWidget {
  final FamilyGroup group;
  const _GroupThemeEditor({required this.group});

  Future<void> _pickAndSave(
      BuildContext context, Color current, GroupTheme Function(int) apply) async {
    Color picked = current;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose a color'),
        content: SingleChildScrollView(
          child: ColorPicker(pickerColor: current, onColorChanged: (c) => picked = c),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final newTheme = apply(picked.toARGB32());
              final appearance = context.read<AppearanceProvider>();
              await context
                  .read<AppState>()
                  .firestore
                  .updateGroupTheme(group.id, newTheme);
              appearance.applyGroupTheme(newTheme);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = group.theme;
    return Column(
      children: [
        ListTile(
          title: const Text('Group tab color'),
          trailing: _ColorSwatch(color: Color(theme.primaryColorArgb)),
          onTap: () => _pickAndSave(
              context, Color(theme.primaryColorArgb), (argb) => theme.copyWith(primaryColorArgb: argb)),
        ),
        ListTile(
          title: const Text('Member list tab color'),
          trailing: _ColorSwatch(color: Color(theme.memberListTabColorArgb)),
          onTap: () => _pickAndSave(context, Color(theme.memberListTabColorArgb),
              (argb) => theme.copyWith(memberListTabColorArgb: argb)),
        ),
      ],
    );
  }
}
