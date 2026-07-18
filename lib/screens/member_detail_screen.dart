import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../models/app_user.dart';
import '../models/trip.dart';
import '../providers/app_state.dart';
import 'trip_detail_screen.dart';

/// Everything Life360 shows behind a member's "info" button, in one
/// place: current location + how long they've been there, live battery,
/// and a scrollable trip history where each trip opens into the full
/// speed graph + route (see TripDetailScreen).
class MemberDetailScreen extends StatelessWidget {
  final AppUser member;
  const MemberDetailScreen({super.key, required this.member});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final groupId = appState.activeGroup?.id;
    final liveMember = appState.groupMembers.where((m) => m.uid == member.uid).toList();
    final currentMember = liveMember.isNotEmpty ? liveMember.first : member;

    return Scaffold(
      appBar: AppBar(title: Text(currentMember.displayName)),
      body: ListView(
        children: [
          if (currentMember.lat != null && currentMember.lng != null)
            SizedBox(
              height: 220,
              child: GoogleMap(
                initialCameraPosition:
                    CameraPosition(target: LatLng(currentMember.lat!, currentMember.lng!), zoom: 15),
                markers: {
                  Marker(
                    markerId: const MarkerId('member'),
                    position: LatLng(currentMember.lat!, currentMember.lng!),
                  ),
                },
                zoomControlsEnabled: false,
                myLocationButtonEnabled: false,
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _StatTile(
                  icon: Icons.timer_outlined,
                  label: 'At location',
                  value: _timeAtLocation(currentMember),
                ),
                _StatTile(
                  icon: currentMember.batteryLevel <= 20 ? Icons.battery_alert : Icons.battery_std,
                  label: 'Battery',
                  value: '${currentMember.batteryLevel.round()}%',
                  valueColor: currentMember.batteryLevel <= 20 ? Colors.red : null,
                ),
                _StatTile(
                  icon: Icons.speed,
                  label: 'Speed',
                  value: currentMember.speedMph != null && currentMember.speedMph! > 3
                      ? '${currentMember.speedMph!.round()} mph'
                      : 'Stopped',
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('Garage', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          const SizedBox(height: 8),
          if (currentMember.garageVehicles.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('No vehicles listed.', style: TextStyle(color: Colors.grey)),
            )
          else
            ...currentMember.garageVehicles.map(
              (vehicle) => ListTile(
                dense: true,
                leading: const Icon(Icons.directions_car, size: 20),
                title: Text(vehicle),
              ),
            ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('Trip history', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          const SizedBox(height: 8),
          if (groupId == null)
            const Padding(padding: EdgeInsets.all(16), child: Text('No group selected.'))
          else
            StreamBuilder<List<Trip>>(
              stream: appState.firestore.watchTrips(groupId, driverUid: currentMember.uid),
              builder: (context, snapshot) {
                final trips = snapshot.data ?? [];
                if (trips.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No trips recorded yet.'),
                  );
                }
                return Column(
                  children: trips
                      .map((t) => ListTile(
                            leading: const Icon(Icons.directions_car),
                            title: Text(
                              '${t.distanceMiles.toStringAsFixed(1)} mi • Top speed ${t.topSpeedMph.round()} mph',
                            ),
                            subtitle: Text(_formatDate(t.startTime)),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => TripDetailScreen(groupId: groupId, trip: t),
                              ),
                            ),
                          ))
                      .toList(),
                );
              },
            ),
        ],
      ),
    );
  }

  String _timeAtLocation(AppUser user) {
    if (user.arrivedAtCurrentLocation == null) return 'Unknown';
    final d = DateTime.now().difference(user.arrivedAtCurrentLocation!);
    if (d.inMinutes < 1) return 'Just arrived';
    if (d.inHours < 1) return '${d.inMinutes} min';
    return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
  }

  String _formatDate(DateTime dt) =>
      '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  const _StatTile({required this.icon, required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: valueColor),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: valueColor)),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }
}
