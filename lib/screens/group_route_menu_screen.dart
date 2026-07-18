import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/group_route.dart';
import '../models/trip.dart';
import '../providers/app_state.dart';

class GroupRouteMenuScreen extends StatefulWidget {
  final String groupId;
  final String groupName;

  const GroupRouteMenuScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<GroupRouteMenuScreen> createState() => _GroupRouteMenuScreenState();
}

class _GroupRouteMenuScreenState extends State<GroupRouteMenuScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.groupName} Routes'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Route History'),
            Tab(text: 'Daily Top Speed'),
            Tab(text: 'Weekly Top Speed'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _RouteHistoryTab(groupId: widget.groupId),
          _TopSpeedTab(
            groupId: widget.groupId,
            title: 'Daily Top Speed',
            windowStartBuilder: () {
              final now = DateTime.now();
              return DateTime(now.year, now.month, now.day);
            },
          ),
          _TopSpeedTab(
            groupId: widget.groupId,
            title: 'Weekly Top Speed',
            windowStartBuilder: () => DateTime.now().subtract(
              const Duration(days: 7),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteHistoryTab extends StatelessWidget {
  final String groupId;

  const _RouteHistoryTab({required this.groupId});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return StreamBuilder<List<GroupRoute>>(
      stream: appState.firestore.watchGroupRoutes(groupId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final allRoutes = snapshot.data ?? const <GroupRoute>[];
        final routes = allRoutes
            .where((r) => r.visibleMemberUids.toSet().length >= 2)
            .toList();

        if (routes.isEmpty) {
          return const Center(
            child: Text('No group route history yet.'),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
          itemCount: routes.length,
          itemBuilder: (context, index) {
            final route = routes[index];
            final speedTop = route.participantStats.values.toList()
              ..sort((a, b) => b.topSpeedMph.compareTo(a.topSpeedMph));

            final arrivalTop = route.participantStats.values
                .where((p) => p.arrivedAt != null)
                .toList()
              ..sort(
                (a, b) => a.arrivedAt!
                    .difference(route.createdAt)
                    .compareTo(b.arrivedAt!.difference(route.createdAt)),
              );

            final statusText = route.isCompleted ? 'Completed' : 'Active';

            return Card(
              child: ExpansionTile(
                title:
                    Text('${route.start.label} to ${route.destination.label}'),
                subtitle: Text(
                  '${_formatDateTime(route.createdAt)}  |  $statusText',
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Top Speed',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (speedTop.isEmpty)
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('No speed data'),
                    )
                  else
                    ...speedTop.take(3).toList().asMap().entries.map((entry) {
                      final rank = entry.key + 1;
                      final p = entry.value;
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '$rank. ${p.displayName} - ${p.topSpeedMph.round()} mph',
                        ),
                      );
                    }),
                  const SizedBox(height: 12),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Arrival Time',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (arrivalTop.isEmpty)
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('No arrivals yet'),
                    )
                  else
                    ...arrivalTop.take(3).toList().asMap().entries.map((entry) {
                      final rank = entry.key + 1;
                      final p = entry.value;
                      final travel = p.arrivedAt!.difference(route.createdAt);
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '$rank. ${p.displayName} - ${_formatDuration(travel)}',
                        ),
                      );
                    }),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _TopSpeedTab extends StatelessWidget {
  final String groupId;
  final String title;
  final DateTime Function() windowStartBuilder;

  const _TopSpeedTab({
    required this.groupId,
    required this.title,
    required this.windowStartBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return StreamBuilder<List<Trip>>(
      stream: appState.firestore.watchTrips(groupId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final start = windowStartBuilder();
        final trips = snapshot.data ?? const <Trip>[];
        final filtered =
            trips.where((t) => !t.startTime.isBefore(start)).toList();

        final bestByUid = <String, double>{
          for (final member in appState.groupMembers) member.uid: 0,
        };
        final nameByUid = <String, String>{
          for (final member in appState.groupMembers)
            member.uid: member.displayName,
        };

        for (final trip in filtered) {
          final current = bestByUid[trip.driverUid] ?? 0;
          if (trip.topSpeedMph > current) {
            bestByUid[trip.driverUid] = trip.topSpeedMph;
          }
          nameByUid.putIfAbsent(trip.driverUid, () => trip.driverName);
        }

        final rows = bestByUid.entries
            .map(
              (e) => _SpeedRow(
                uid: e.key,
                name: nameByUid[e.key] ?? 'Member',
                topSpeedMph: e.value,
              ),
            )
            .toList()
          ..sort((a, b) {
            final speedCompare = b.topSpeedMph.compareTo(a.topSpeedMph);
            if (speedCompare != 0) return speedCompare;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });

        if (rows.isEmpty) {
          return Center(child: Text('No members available for $title.'));
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            final rank = index + 1;
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  child: Text('$rank'),
                ),
                title: Text(row.name),
                subtitle: Text(
                  row.topSpeedMph > 0
                      ? '${row.topSpeedMph.round()} mph'
                      : 'No trip speed yet',
                ),
                trailing: row.topSpeedMph > 0
                    ? const Icon(Icons.speed)
                    : const Icon(Icons.remove),
              ),
            );
          },
        );
      },
    );
  }
}

class _SpeedRow {
  final String uid;
  final String name;
  final double topSpeedMph;

  const _SpeedRow({
    required this.uid,
    required this.name,
    required this.topSpeedMph,
  });
}

String _formatDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60);

  if (hours > 0) return '${hours}h ${minutes}m ${seconds}s';
  return '${minutes}m ${seconds}s';
}

String _formatDateTime(DateTime dt) {
  final month = dt.month.toString().padLeft(2, '0');
  final day = dt.day.toString().padLeft(2, '0');
  final hour = dt.hour.toString().padLeft(2, '0');
  final minute = dt.minute.toString().padLeft(2, '0');
  return '$month/$day $hour:$minute';
}
