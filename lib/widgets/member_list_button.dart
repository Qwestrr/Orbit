import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:provider/provider.dart';
import '../models/app_user.dart';
import '../models/place.dart';
import '../providers/app_state.dart';
import '../providers/appearance_provider.dart';
import '../screens/member_detail_screen.dart';

/// The pill button centered at the bottom of the map. Tapping it opens a
/// sheet listing every member of the active group; tapping a member pans
/// the map to them, and their info button opens the full detail screen
/// (time at location, battery, trip history + route).
enum RouteTargetKind { myLocation, member, place, address }

class RouteTargetOption {
  final RouteTargetKind kind;
  final String id;
  final String label;
  final double lat;
  final double lng;
  final double? radiusMeters;

  const RouteTargetOption({
    required this.kind,
    required this.id,
    required this.label,
    required this.lat,
    required this.lng,
    this.radiusMeters,
  });
}

class RouteSetupRequest {
  final RouteTargetOption start;
  final RouteTargetOption destination;
  final bool isGroupRoute;

  const RouteSetupRequest({
    required this.start,
    required this.destination,
    required this.isGroupRoute,
  });
}

class MemberListButton extends StatelessWidget {
  final void Function(AppUser member) onFocusMember;
  final void Function(Place place) onFocusPlace;
  final List<Place> places;
  final Future<void> Function(RouteSetupRequest request) onSubmitRouteSetup;

  const MemberListButton({
    super.key,
    required this.onFocusMember,
    required this.onFocusPlace,
    required this.places,
    required this.onSubmitRouteSetup,
  });

  @override
  Widget build(BuildContext context) {
    final appearance = context.watch<AppearanceProvider>();
    final appState = context.watch<AppState>();
    final memberCount = appState.groupMembers.length;
    final buttonColor = appearance.buttonColor;
    final textColor = appearance.textColor;
    final iconColor = appearance.memberListTabColor == buttonColor
        ? textColor
        : appearance.memberListTabColor;

    return Center(
      child: Material(
        color: buttonColor,
        elevation: 3,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showMemberSheet(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: buttonColor, width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.people_alt, size: 18, color: iconColor),
                const SizedBox(width: 8),
                Text(
                  memberCount > 0 ? 'Members ($memberCount)' : 'Members',
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showMemberSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => _MemberPlacesSheet(
          scrollController: scrollController,
          places: places,
          onFocusMember: onFocusMember,
          onFocusPlace: onFocusPlace,
          onSubmitRouteSetup: onSubmitRouteSetup,
        ),
      ),
    );
  }
}

class _MemberPlacesSheet extends StatefulWidget {
  final ScrollController scrollController;
  final List<Place> places;
  final void Function(AppUser member) onFocusMember;
  final void Function(Place place) onFocusPlace;
  final Future<void> Function(RouteSetupRequest request) onSubmitRouteSetup;

  const _MemberPlacesSheet({
    required this.scrollController,
    required this.places,
    required this.onFocusMember,
    required this.onFocusPlace,
    required this.onSubmitRouteSetup,
  });

  @override
  State<_MemberPlacesSheet> createState() => _MemberPlacesSheetState();
}

class _MemberPlacesSheetState extends State<_MemberPlacesSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String _placeQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final members = [...appState.groupMembers]..sort((a, b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));

    final filteredPlaces = widget.places
        .where((p) => p.name.toLowerCase().contains(_placeQuery.toLowerCase()))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade400,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Members',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              TextButton.icon(
                onPressed: () =>
                    _openRouteSetupDialog(context, appState, members),
                icon: const Icon(Icons.route, size: 18),
                label: const Text('Set Route'),
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Members'),
            Tab(text: 'Places'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              ListView.builder(
                controller: widget.scrollController,
                itemCount: members.length,
                itemBuilder: (context, i) => _MemberRow(
                  member: members[i],
                  index: i + 1,
                  onTapRow: () {
                    Navigator.of(context).pop();
                    widget.onFocusMember(members[i]);
                  },
                  onTapInfo: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) =>
                              MemberDetailScreen(member: members[i])),
                    );
                  },
                  onTapRoute: () {
                    final me = _myLocationOption(appState, members);
                    final destination = _memberToTarget(members[i]);
                    if (me == null || destination == null) return;
                    Navigator.of(context).pop();
                    widget.onSubmitRouteSetup(
                      RouteSetupRequest(
                        start: me,
                        destination: destination,
                        isGroupRoute: false,
                      ),
                    );
                  },
                ),
              ),
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Search places',
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                      ),
                      onChanged: (value) {
                        setState(() {
                          _placeQuery = value;
                        });
                      },
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: widget.scrollController,
                      itemCount: filteredPlaces.length,
                      itemBuilder: (context, i) {
                        final place = filteredPlaces[i];
                        return ListTile(
                          leading: const Icon(Icons.place_outlined),
                          title: Text(place.name),
                          subtitle: Text(
                            '${place.lat.toStringAsFixed(4)}, ${place.lng.toStringAsFixed(4)}',
                          ),
                          onTap: () {
                            Navigator.of(context).pop();
                            widget.onFocusPlace(place);
                          },
                          trailing: IconButton(
                            icon: const Icon(Icons.route),
                            onPressed: () {
                              final me = _myLocationOption(appState, members);
                              if (me == null) return;
                              Navigator.of(context).pop();
                              widget.onSubmitRouteSetup(
                                RouteSetupRequest(
                                  start: me,
                                  destination: _placeToTarget(place),
                                  isGroupRoute: false,
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  RouteTargetOption? _myLocationOption(
      AppState appState, List<AppUser> members) {
    final me = members.where((m) => m.uid == appState.auth.currentUser?.uid);
    if (me.isEmpty) return null;
    if (me.first.lat == null || me.first.lng == null) return null;
    return RouteTargetOption(
      kind: RouteTargetKind.myLocation,
      id: 'me',
      label: 'My location',
      lat: me.first.lat!,
      lng: me.first.lng!,
    );
  }

  RouteTargetOption? _memberToTarget(AppUser member) {
    if (member.lat == null || member.lng == null) return null;
    return RouteTargetOption(
      kind: RouteTargetKind.member,
      id: member.uid,
      label: member.displayName,
      lat: member.lat!,
      lng: member.lng!,
    );
  }

  RouteTargetOption _placeToTarget(Place place) {
    return RouteTargetOption(
      kind: RouteTargetKind.place,
      id: place.id,
      label: place.name,
      lat: place.lat,
      lng: place.lng,
      radiusMeters: place.radiusMeters,
    );
  }

  Future<void> _openRouteSetupDialog(
    BuildContext context,
    AppState appState,
    List<AppUser> members,
  ) async {
    final me = _myLocationOption(appState, members);
    final routeOptions = <RouteTargetOption>[
      if (me != null) me,
      ...members.map(_memberToTarget).whereType<RouteTargetOption>(),
      ...widget.places.map(_placeToTarget),
    ];

    RouteTargetOption? start = me;
    RouteTargetOption? destination;
    bool isGroupRoute = false;
    bool resolvingAddress = false;
    bool showDestinationRequiredError = false;
    final startAddressController = TextEditingController();
    final destinationAddressController = TextEditingController();

    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Set route'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (routeOptions.isNotEmpty)
                      DropdownButtonFormField<RouteTargetOption>(
                        initialValue: start,
                        decoration: const InputDecoration(labelText: 'Start'),
                        items: routeOptions
                            .map(
                              (o) => DropdownMenuItem(
                                value: o,
                                child: Text(o.label),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            start = value;
                          });
                        },
                      )
                    else
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'No map targets available. Enter addresses below.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: startAddressController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Start address (optional)',
                        hintText: '123 Main St, Dallas TX',
                        prefixIcon: Icon(Icons.edit_location_alt_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (routeOptions.isNotEmpty)
                      DropdownButtonFormField<RouteTargetOption>(
                        initialValue: destination,
                        decoration:
                            const InputDecoration(labelText: 'Destination'),
                        items: routeOptions
                            .map(
                              (o) => DropdownMenuItem(
                                value: o,
                                child: Text(o.label),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            destination = value;
                            showDestinationRequiredError = false;
                          });
                        },
                      ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: destinationAddressController,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: 'Destination address *',
                        hintText: 'Anywhere you want to go',
                        prefixIcon: const Icon(Icons.flag_outlined),
                        errorText: showDestinationRequiredError
                            ? 'Destination is required.'
                            : null,
                      ),
                      onChanged: (value) {
                        if (value.trim().isNotEmpty) {
                          setState(() {
                            showDestinationRequiredError = false;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Make this a group route'),
                      value: isGroupRoute,
                      onChanged: (value) {
                        setState(() {
                          isGroupRoute = value;
                        });
                      },
                    ),
                    if (isGroupRoute)
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Group routes can use saved places or typed addresses.\n'
                          'Typed destinations use proximity-based arrival detection (about 80 meters).',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: resolvingAddress
                      ? null
                      : () async {
                          setState(() {
                            resolvingAddress = true;
                          });

                          RouteTargetOption? resolvedStart = start;
                          RouteTargetOption? resolvedDestination = destination;

                          final typedStart = startAddressController.text.trim();
                          final typedDestination =
                              destinationAddressController.text.trim();

                          if (typedStart.isNotEmpty) {
                            resolvedStart = await _addressToTarget(typedStart);
                            if (resolvedStart == null) {
                              if (!dialogContext.mounted) return;
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Could not find "$typedStart". Try a fuller address.',
                                  ),
                                ),
                              );
                              setState(() {
                                resolvingAddress = false;
                              });
                              return;
                            }
                          }

                          // Match standard GPS behavior: if no explicit start is
                          // chosen, use current location when available.
                          resolvedStart ??= me;

                          if (typedDestination.isNotEmpty) {
                            resolvedDestination =
                                await _addressToTarget(typedDestination);
                            if (resolvedDestination == null) {
                              if (!dialogContext.mounted) return;
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Could not find "$typedDestination". Try a fuller address.',
                                  ),
                                ),
                              );
                              setState(() {
                                resolvingAddress = false;
                              });
                              return;
                            }
                          }

                          if (resolvedDestination == null) {
                            setState(() {
                              showDestinationRequiredError = true;
                              resolvingAddress = false;
                            });
                            return;
                          }

                          if (resolvedStart == null) {
                            if (!dialogContext.mounted) return;
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Start location unavailable. Enter a start address.',
                                ),
                              ),
                            );
                            setState(() {
                              resolvingAddress = false;
                            });
                            return;
                          }

                          if (resolvedStart.id == resolvedDestination.id &&
                              resolvedStart.kind == resolvedDestination.kind) {
                            if (!dialogContext.mounted) return;
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Choose different start and destination.',
                                ),
                              ),
                            );
                            setState(() {
                              resolvingAddress = false;
                            });
                            return;
                          }

                          start = resolvedStart;
                          destination = resolvedDestination;

                          if (!dialogContext.mounted) return;
                          Navigator.of(dialogContext).pop(true);
                        },
                  child: resolvingAddress
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Continue'),
                ),
              ],
            );
          },
        );
      },
    );

    startAddressController.dispose();
    destinationAddressController.dispose();

    if (submitted != true || !context.mounted) return;
    if (start == null || destination == null) return;

    Navigator.of(context).pop();
    await widget.onSubmitRouteSetup(
      RouteSetupRequest(
        start: start!,
        destination: destination!,
        isGroupRoute: isGroupRoute,
      ),
    );
  }

  Future<RouteTargetOption?> _addressToTarget(String address) async {
    try {
      final locations = await locationFromAddress(address);
      if (locations.isEmpty) return null;
      final first = locations.first;
      return RouteTargetOption(
        kind: RouteTargetKind.address,
        id: 'address:${address.trim().toLowerCase()}',
        label: address.trim(),
        lat: first.latitude,
        lng: first.longitude,
      );
    } catch (_) {
      return null;
    }
  }
}

class _MemberRow extends StatelessWidget {
  final AppUser member;
  final int index;
  final VoidCallback onTapRow;
  final VoidCallback onTapInfo;
  final VoidCallback onTapRoute;
  const _MemberRow({
    required this.member,
    required this.index,
    required this.onTapRow,
    required this.onTapInfo,
    required this.onTapRoute,
  });

  String _timeAtLocation() {
    if (member.arrivedAtCurrentLocation == null) return '';
    final d = DateTime.now().difference(member.arrivedAtCurrentLocation!);
    if (d.inMinutes < 1) return 'Just arrived';
    if (d.inHours < 1) return 'Here for ${d.inMinutes}m';
    return 'Here for ${d.inHours}h ${d.inMinutes.remainder(60)}m';
  }

  String _locationText() {
    if (member.currentLocationLabel != null &&
        member.currentLocationLabel!.trim().isNotEmpty) {
      return member.currentLocationLabel!;
    }
    if (member.lat != null && member.lng != null) {
      return '${member.lat!.toStringAsFixed(4)}, ${member.lng!.toStringAsFixed(4)}';
    }
    return 'Location unavailable';
  }

  @override
  Widget build(BuildContext context) {
    final moving = member.speedMph != null && member.speedMph! > 3;
    return ListTile(
      onTap: onTapRow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        backgroundImage:
            member.photoUrl != null ? NetworkImage(member.photoUrl!) : null,
        child: member.photoUrl == null
            ? Text(member.displayName.isNotEmpty ? member.displayName[0] : '?')
            : null,
      ),
      title: Text(member.displayName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_locationText(), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(moving
              ? 'Driving • ${member.speedMph!.round()} mph'
              : _timeAtLocation()),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 11,
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Text('$index',
                style:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          Icon(
            member.batteryLevel <= 20 ? Icons.battery_alert : Icons.battery_std,
            size: 18,
            color: member.batteryLevel <= 20 ? Colors.red : Colors.grey,
          ),
          const SizedBox(width: 4),
          Text('${member.batteryLevel.round()}%'),
          IconButton(icon: const Icon(Icons.route), onPressed: onTapRoute),
          IconButton(
              icon: const Icon(Icons.info_outline), onPressed: onTapInfo),
        ],
      ),
    );
  }
}
