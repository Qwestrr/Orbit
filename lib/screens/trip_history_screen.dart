import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/trip.dart';
import '../providers/app_state.dart';
import 'trip_detail_screen.dart';

/// Full list of past trips for the active group, newest first. Each row
/// surfaces the two numbers people care about most at a glance: top
/// speed and duration.
class TripHistoryScreen extends StatelessWidget {
  const TripHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final groupId = appState.activeGroup?.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Trip History')),
      body: groupId == null
          ? const Center(child: Text('Join a group to see trips.'))
          : StreamBuilder<List<Trip>>(
              stream: appState.firestore.watchTrips(groupId),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final trips = snapshot.data!;
                if (trips.isEmpty) {
                  return const Center(child: Text('No trips recorded yet.'));
                }
                return ListView.separated(
                  itemCount: trips.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final trip = trips[i];
                    return ListTile(
                      leading: CircleIcon(accident: trip.possibleAccidentDetected),
                      title: Text(
                          '${trip.driverName} \u2022 ${trip.distanceMiles.toStringAsFixed(1)} mi'),
                      subtitle: Text(
                          '${DateFormat.MMMd().add_jm().format(trip.startTime)} \u2022 '
                          '${_formatDuration(trip.duration)}'),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('${trip.topSpeedMph.round()} mph',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          const Text('top speed',
                              style: TextStyle(fontSize: 10, color: Colors.grey)),
                        ],
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TripDetailScreen(groupId: groupId, trip: trip),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }
}

class CircleIcon extends StatelessWidget {
  final bool accident;
  const CircleIcon({super.key, required this.accident});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      backgroundColor: accident ? Colors.red.shade100 : Colors.blue.shade50,
      child: Icon(
        accident ? Icons.warning_amber_rounded : Icons.directions_car,
        color: accident ? Colors.red : Colors.blueGrey,
      ),
    );
  }
}
