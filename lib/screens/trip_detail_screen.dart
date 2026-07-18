import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../models/trip.dart';
import '../providers/app_state.dart';
import '../services/speed_limit_service.dart';

/// Full breakdown of one trip: top speed, average speed, distance,
/// duration, and a speed-over-time graph built from every recorded
/// GPS point (see FirestoreService.watchTripPoints).
class TripDetailScreen extends StatelessWidget {
  final String groupId;
  final Trip trip;
  const TripDetailScreen({super.key, required this.groupId, required this.trip});

  static final SpeedLimitService _speedLimitService = SpeedLimitService();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: Text('${trip.driverName}\'s trip')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (trip.possibleAccidentDetected)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red),
                  SizedBox(width: 8),
                  Expanded(
                      child: Text('A possible accident was detected during this trip.')),
                ],
              ),
            ),
          Row(
            children: [
              _StatCard(label: 'Top Speed', value: '${trip.topSpeedMph.round()} mph'),
              const SizedBox(width: 12),
              _StatCard(label: 'Avg Speed', value: '${trip.avgSpeedMph.round()} mph'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatCard(
                  label: 'Distance', value: '${trip.distanceMiles.toStringAsFixed(1)} mi'),
              const SizedBox(width: 12),
              _StatCard(label: 'Duration', value: _formatDuration(trip.duration)),
            ],
          ),
          const SizedBox(height: 24),
          const Text('Route', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: StreamBuilder<List<TripPoint>>(
              stream: appState.firestore.watchTripPoints(groupId, trip.id),
              builder: (context, snapshot) {
                final points = snapshot.data ?? [];
                if (points.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                final latLngs = points.map((p) => LatLng(p.lat, p.lng)).toList();
                return FutureBuilder<Set<Polyline>>(
                  future: _buildSpeedLimitAwarePolylines(points),
                  builder: (context, polylineSnap) {
                    if (!polylineSnap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: GoogleMap(
                        initialCameraPosition: CameraPosition(target: latLngs.first, zoom: 13),
                        polylines: polylineSnap.data!,
                        markers: {
                          Marker(
                            markerId: const MarkerId('start'),
                            position: latLngs.first,
                            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                          ),
                          Marker(
                            markerId: const MarkerId('end'),
                            position: latLngs.last,
                            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                          ),
                        },
                        zoomControlsEnabled: false,
                        myLocationButtonEnabled: false,
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          const _SpeedLegend(),
          const SizedBox(height: 24),
          const Text('Speed over time', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: StreamBuilder<List<TripPoint>>(
              stream: appState.firestore.watchTripPoints(groupId, trip.id),
              builder: (context, snapshot) {
                final points = snapshot.data ?? [];
                if (points.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                return LineChart(
                  LineChartData(
                    gridData: const FlGridData(show: true),
                    titlesData: const FlTitlesData(
                      topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: [
                          for (int i = 0; i < points.length; i++)
                            FlSpot(i.toDouble(), points[i].speedMph),
                        ],
                        isCurved: true,
                        dotData: const FlDotData(show: false),
                        barWidth: 3,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  Future<Set<Polyline>> _buildSpeedLimitAwarePolylines(List<TripPoint> points) async {
    if (points.length < 2) return {};

    final anchorIndices = <int>[];
    for (int i = 0; i < points.length - 1; i += 3) {
      anchorIndices.add(i);
    }

    final anchorLimits = <int, double>{};
    final limitFutures = anchorIndices.map((index) async {
      final p = points[index];
      final limit = await _speedLimitService.getSpeedLimitMph(p.lat, p.lng);
      anchorLimits[index] = limit;
    }).toList();
    await Future.wait(limitFutures);

    final polylines = <Polyline>{};
    for (int i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      final avgSegmentSpeed = (a.speedMph + b.speedMph) / 2;
      final anchorIndex = (i ~/ 3) * 3;
      final speedLimit = anchorLimits[anchorIndex] ?? 35;
      final overLimitMph = avgSegmentSpeed - speedLimit;
      polylines.add(
        Polyline(
          polylineId: PolylineId('speed_segment_$i'),
          points: [LatLng(a.lat, a.lng), LatLng(b.lat, b.lng)],
          width: 5,
          color: _overLimitColor(overLimitMph),
        ),
      );
    }
    return polylines;
  }

  Color _overLimitColor(double overLimitMph) {
    if (overLimitMph >= 25) return const Color(0xFF8B0000); // dark red
    if (overLimitMph >= 20) return const Color(0xFFE53935); // red
    if (overLimitMph >= 15) return const Color(0xFFFB8C00); // orange
    if (overLimitMph >= 10) return const Color(0xFFFDD835); // yellow
    return const Color(0xFF00C853); // at limit / below +10
  }
}

class _SpeedLegend extends StatelessWidget {
  const _SpeedLegend();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: const [
        _LegendDot(color: Color(0xFF00C853), label: 'Below +10 mph'),
        _LegendDot(color: Color(0xFFFDD835), label: '+10 to +15 mph'),
        _LegendDot(color: Color(0xFFFB8C00), label: '+15 to +20 mph'),
        _LegendDot(color: Color(0xFFE53935), label: '+20 to +25 mph'),
        _LegendDot(color: Color(0xFF8B0000), label: '+25 mph and up'),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
