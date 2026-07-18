import 'package:flutter/material.dart';
import '../widgets/action_result_feedback.dart';
import 'app_settings_screen.dart';
import 'account_settings_screen.dart';
import 'appearance_settings_screen.dart';
import 'custom_quick_notifications_screen.dart';
import 'group_management_screen.dart';
import 'helicopter_settings_screen.dart';

/// The screen behind the top-left menu button. Three entry points, per
/// spec: App Settings (appearance + map layers + air traffic), Account
/// Customization (name, photo), and Group Management (places, hazards,
/// battery-alert prefs).
class SettingsMenuScreen extends StatelessWidget {
  const SettingsMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeader('App Settings'),
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('App settings'),
            subtitle:
                const Text('Notifications, privacy, and common preferences'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AppSettingsScreen())),
          ),
          const Divider(),
          const _SectionHeader('Quick Access'),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Appearance'),
            subtitle: const Text('Colors, dark mode, map layers'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const AppearanceSettingsScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.flight_takeoff),
            title: const Text('Air Traffic'),
            subtitle: const Text('Radius and visibility'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const HelicopterSettingsScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.quickreply_outlined),
            title: const Text('Quick notifications'),
            subtitle: const Text('Create and filter custom quick actions'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const CustomQuickNotificationsScreen(),
              ),
            ),
          ),
          const Divider(),
          const _SectionHeader('Account'),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Account customization'),
            subtitle: const Text('Name, profile picture'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showSuccessForResult(
              context: context,
              result: Navigator.of(context).push<bool>(MaterialPageRoute(
                  builder: (_) => const AccountSettingsScreen())),
              message: 'Saved',
            ),
          ),
          const Divider(),
          const _SectionHeader('Group Management'),
          ListTile(
            leading: const Icon(Icons.groups_outlined),
            title: const Text('Places, hazards & alerts'),
            subtitle: const Text('Edit places, mark hazards, battery alerts'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const GroupManagementScreen())),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title,
          style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary)),
    );
  }
}
