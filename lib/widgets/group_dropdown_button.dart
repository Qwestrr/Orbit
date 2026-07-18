import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../providers/appearance_provider.dart';
import 'action_result_feedback.dart';
import 'group_creation_dialog.dart';

/// The pill button centered at the top of the map that drops down the
/// list of groups the user belongs to. Selecting one switches the map's
/// active group (and, via AppearanceProvider.applyGroupTheme, the app's
/// accent colors) instantly.
class GroupDropdownButton extends StatelessWidget {
  const GroupDropdownButton({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final appearance = context.watch<AppearanceProvider>();
    final buttonColor = appearance.buttonColor;
    final textColor = appearance.textColor;
    final iconColor = appearance.groupTabColor == buttonColor
        ? textColor
        : appearance.groupTabColor;

    return Center(
      child: Material(
        color: buttonColor,
        elevation: 3,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showGroupPicker(context, appState, appearance),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: buttonColor, width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.groups, size: 18, color: iconColor),
                const SizedBox(width: 8),
                Text(
                  appState.activeGroup?.name ?? 'Select group',
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.keyboard_arrow_down, size: 18, color: textColor),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showGroupPicker(
      BuildContext context, AppState appState, AppearanceProvider appearance) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Your groups', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            ...appState.myGroups.map((g) => ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Color(g.theme.primaryColorArgb),
                    radius: 10,
                  ),
                  title: Text(g.name),
                  trailing: appState.activeGroup?.id == g.id
                      ? const Icon(Icons.check, color: Colors.green)
                      : null,
                  onTap: () {
                    appState.setActiveGroup(g);
                    appearance.applyGroupTheme(g.theme);
                    Navigator.of(context).pop();
                  },
                )),
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Create a group'),
              onTap: () async {
                Navigator.of(context).pop();
                await showSuccessForResult(
                  context: context,
                  result: showDialog<bool>(
                    context: context,
                    builder: (_) => GroupCreationDialog(uid: appState.auth.currentUser!.uid),
                  ),
                  message: 'Group created successfully!',
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.group_add_outlined),
              title: const Text('Join with invite code'),
              onTap: () {
                Navigator.of(context).pop();
                _showJoinGroupDialog(context, appState, appearance);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _showJoinGroupDialog(
    BuildContext context,
    AppState appState,
    AppearanceProvider appearance,
  ) async {
    final controller = TextEditingController();
    bool joining = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Join group'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Invite code',
              hintText: 'Enter 6-character code',
            ),
          ),
          actions: [
            TextButton(
              onPressed: joining ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: joining
                  ? null
                  : () async {
                      final code = controller.text.trim().toUpperCase();
                      if (code.isEmpty) return;
                      setState(() => joining = true);

                      final joined = await appState.firestore.joinGroupByInviteCode(
                        inviteCode: code,
                        uid: appState.auth.currentUser!.uid,
                      );

                      if (!context.mounted) return;
                      setState(() => joining = false);

                      if (joined == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Invite code not found')),
                        );
                        return;
                      }

                      appState.setActiveGroup(joined);
                      appearance.applyGroupTheme(joined.theme);
                      Navigator.of(dialogContext).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Joined ${joined.name}')),
                      );
                    },
              child: joining
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Join'),
            ),
          ],
        ),
      ),
    );
  }
}

