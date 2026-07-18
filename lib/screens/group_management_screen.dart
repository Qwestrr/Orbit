import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/group.dart';
import '../models/place.dart';
import '../providers/app_state.dart';
import '../widgets/action_result_feedback.dart';
import '../widgets/place_editor_dialog.dart';
import '../widgets/battery_alert_prefs.dart';

/// Everything under Settings -> Group Management: edit places (name,
/// icon, radius), mark where cops/hazards are (Waze-style — the actual
/// pin-dropping happens on the map itself; see hazard_report_button.dart
/// on the home screen), and configure who gets low-battery alerts.
class GroupManagementScreen extends StatefulWidget {
  const GroupManagementScreen({super.key});

  @override
  State<GroupManagementScreen> createState() => _GroupManagementScreenState();
}

class _GroupManagementScreenState extends State<GroupManagementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final group = appState.activeGroup;
    final currentUid = appState.auth.currentUser?.uid;

    if (group == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Group Management')),
        body: const Center(child: Text('Select a group on the map first.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(group.name),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Members'),
            Tab(text: 'Places'),
            Tab(text: 'Hazards'),
            Tab(text: 'Battery alerts'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _MembersTab(group: group),
          _PlacesTab(
            group: group,
            currentUid: currentUid ?? '',
          ),
          const _HazardsInfoTab(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: BatteryAlertPrefs(
              uid: currentUid ?? '',
              groupId: group.id,
              members: appState.groupMembers,
            ),
          ),
        ],
      ),
    );
  }
}

class _MembersTab extends StatefulWidget {
  final FamilyGroup group;
  const _MembersTab({required this.group});

  @override
  State<_MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends State<_MembersTab> {
  final Set<String> _savingMemberUids = <String>{};

  Future<void> _copyInviteCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invite code copied')),
    );
  }

  Future<void> _updatePermissions({
    required String memberUid,
    required GroupMemberPermissions permissions,
  }) async {
    setState(() => _savingMemberUids.add(memberUid));
    final appState = context.read<AppState>();
    try {
      await appState.firestore.setMemberPermissions(
        groupId: widget.group.id,
        memberUid: memberUid,
        permissions: permissions,
      );
    } finally {
      if (mounted) setState(() => _savingMemberUids.remove(memberUid));
    }
  }

  Future<void> _removeMember({
    required String memberUid,
    required String displayName,
  }) async {
    final appState = context.read<AppState>();
    final currentUid = appState.auth.currentUser?.uid ?? '';
    final isOwner = widget.group.isOwner(currentUid);
    final nonOwnerMembers = appState.groupMembers
        .where((m) => m.uid != widget.group.ownerUid)
        .toList();

    // Prevent owner from removing the last remaining non-owner member.
    if (isOwner && nonOwnerMembers.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'You cannot remove the last member. Invite or transfer ownership first.',
          ),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove member'),
        content: Text('Remove $displayName from this group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _savingMemberUids.add(memberUid));
    try {
      await appState.firestore.leaveGroup(
        groupId: widget.group.id,
        uid: memberUid,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$displayName removed from group')),
      );
    } finally {
      if (mounted) setState(() => _savingMemberUids.remove(memberUid));
    }
  }

  Future<void> _leaveGroup() async {
    final appState = context.read<AppState>();
    final currentUid = appState.auth.currentUser?.uid ?? '';
    if (currentUid.isEmpty) return;

    final isOwner = widget.group.isOwner(currentUid);
    final otherMembers =
        appState.groupMembers.where((m) => m.uid != currentUid).toList();

    if (isOwner && otherMembers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'You are the only member. Invite someone first so ownership can be transferred.',
          ),
        ),
      );
      return;
    }

    String? selectedNewOwnerUid;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        if (!isOwner) {
          return AlertDialog(
            title: const Text('Leave group'),
            content: Text('Leave ${widget.group.name}?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Leave'),
              ),
            ],
          );
        }

        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Transfer ownership & leave'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Pick a new owner before leaving this group.'),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedNewOwnerUid,
                  decoration: const InputDecoration(labelText: 'New owner'),
                  items: otherMembers
                      .map(
                        (m) => DropdownMenuItem<String>(
                          value: m.uid,
                          child: Text(m.displayName),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => selectedNewOwnerUid = v),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: selectedNewOwnerUid == null
                    ? null
                    : () => Navigator.of(dialogContext).pop(true),
                child: const Text('Transfer & leave'),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed != true) return;

    setState(() => _savingMemberUids.add(currentUid));
    try {
      if (isOwner && selectedNewOwnerUid != null) {
        await appState.firestore.transferGroupOwnership(
          groupId: widget.group.id,
          newOwnerUid: selectedNewOwnerUid!,
        );
      }
      await appState.firestore.leaveGroup(
        groupId: widget.group.id,
        uid: currentUid,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('You left ${widget.group.name}')),
      );
    } finally {
      if (mounted) setState(() => _savingMemberUids.remove(currentUid));
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final currentUid = appState.auth.currentUser?.uid ?? '';
    final isOwner = widget.group.isOwner(currentUid);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Invite members',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Share this code so other people can join this group from their app.',
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        widget.group.inviteCode,
                        style: const TextStyle(
                          fontSize: 24,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy code',
                      icon: const Icon(Icons.copy_outlined),
                      onPressed: () => _copyInviteCode(widget.group.inviteCode),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          isOwner
              ? 'Member permissions'
              : 'Only the group owner can change member permissions.',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        ...appState.groupMembers.map((member) {
          final isMemberOwner = widget.group.ownerUid == member.uid;
          final perms = widget.group.permissionsFor(member.uid);
          final saving = _savingMemberUids.contains(member.uid);

          return Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundImage: member.photoUrl != null
                          ? NetworkImage(member.photoUrl!)
                          : null,
                      child: member.photoUrl == null
                          ? Text(member.displayName.isNotEmpty
                              ? member.displayName[0]
                              : '?')
                          : null,
                    ),
                    title: Text(member.displayName),
                    subtitle: Text(isMemberOwner ? 'Owner' : 'Member'),
                    trailing: saving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                  ),
                  if (isOwner && !isMemberOwner) ...[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('Can add/remove places'),
                      value: perms.canManagePlaces,
                      onChanged: saving
                          ? null
                          : (v) => _updatePermissions(
                                memberUid: member.uid,
                                permissions: perms.copyWith(canManagePlaces: v),
                              ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('Can edit place names/radius'),
                      value: perms.canEditPlaceDetails,
                      onChanged: saving
                          ? null
                          : (v) => _updatePermissions(
                                memberUid: member.uid,
                                permissions:
                                    perms.copyWith(canEditPlaceDetails: v),
                              ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: saving
                            ? null
                            : () => _removeMember(
                                  memberUid: member.uid,
                                  displayName: member.displayName,
                                ),
                        icon: const Icon(Icons.person_remove_outlined),
                        label: const Text('Remove member'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed:
              _savingMemberUids.contains(currentUid) ? null : _leaveGroup,
          icon: const Icon(Icons.exit_to_app),
          label: Text(isOwner ? 'Transfer ownership and leave' : 'Leave group'),
        ),
      ],
    );
  }
}

class _PlacesTab extends StatelessWidget {
  final FamilyGroup group;
  final String currentUid;

  const _PlacesTab({required this.group, required this.currentUid});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final canManagePlaces = group.canManagePlaces(currentUid);
    final canEditPlaceDetails = group.canEditPlaceDetails(currentUid);

    return StreamBuilder<List<Place>>(
      stream: appState.firestore.watchPlaces(group.id),
      builder: (context, snapshot) {
        final places = snapshot.data ?? [];
        return Column(
          children: [
            if (!canManagePlaces && !canEditPlaceDetails)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  'You do not currently have permission to manage places in this group.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            Expanded(
              child: places.isEmpty
                  ? const Center(child: Text('No places yet.'))
                  : ListView(
                      children: places
                          .map((p) => ListTile(
                                leading: p.customIconUrl != null
                                    ? CircleAvatar(
                                        backgroundImage:
                                            NetworkImage(p.customIconUrl!))
                                    : const CircleAvatar(
                                        child: Icon(Icons.place)),
                                title: Text(p.name),
                                subtitle: Text(
                                    '${(p.radiusMeters / 0.3048).round()} ft radius'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: canEditPlaceDetails
                                          ? () => showSuccessForResult(
                                                context: context,
                                                result: showDialog<bool>(
                                                  context: context,
                                                  builder: (_) =>
                                                      PlaceEditorDialog(
                                                    groupId: group.id,
                                                    initialLat: p.lat,
                                                    initialLng: p.lng,
                                                    createdByUid:
                                                        p.createdByUid,
                                                    existing: p,
                                                    restrictToNameAndRadius:
                                                        !canManagePlaces,
                                                  ),
                                                ),
                                                message: 'Place saved',
                                              )
                                          : null,
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: canManagePlaces
                                          ? () => appState.firestore
                                              .deletePlace(group.id, p.id)
                                          : null,
                                    ),
                                  ],
                                ),
                              ))
                          .toList(),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: canManagePlaces
                    ? () async {
                        final me = appState.groupMembers.where(
                            (m) => m.uid == appState.auth.currentUser?.uid);
                        final lat = me.isNotEmpty ? me.first.lat ?? 0 : 0.0;
                        final lng = me.isNotEmpty ? me.first.lng ?? 0 : 0.0;
                        await showSuccessForResult(
                          context: context,
                          result: showDialog<bool>(
                            context: context,
                            builder: (_) => PlaceEditorDialog(
                              groupId: group.id,
                              initialLat: lat,
                              initialLng: lng,
                              createdByUid: appState.auth.currentUser!.uid,
                            ),
                          ),
                          message: 'Place saved',
                        );
                      }
                    : null,
                icon: const Icon(Icons.add_location_alt),
                label: const Text('Add a place'),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _HazardsInfoTab extends StatelessWidget {
  const _HazardsInfoTab();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reporting police & hazards',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          SizedBox(height: 12),
          Text(
            'Tap the hazard button on the main map (long-press anywhere on '
            'the map, or use the report button in the map toolbar) to drop '
            'a pin for police, an accident, or a custom hazard. Everyone in '
            'this group sees it instantly and reports expire automatically '
            '(2-8 hours depending on type) so the map doesn\'t get cluttered '
            'with stale reports.',
          ),
          SizedBox(height: 16),
          Text(
            'Toggle whether hazard pins show on your map at all under '
            'Settings -> Appearance -> Show on map.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
