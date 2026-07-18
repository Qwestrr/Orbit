import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

/// A compact live readout of current speed + running top speed, shown
/// as an overlay on the map while a trip is being recorded.
class SpeedDisplay extends StatelessWidget {
  const SpeedDisplay({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _Stat(
            label: 'SPEED',
            value: '${appState.location.currentAvgSpeedMph.round()}',
            unit: 'mph',
            big: true,
          ),
          _Stat(
            label: 'TOP SPEED',
            value: '${appState.location.currentTopSpeedMph.round()}',
            unit: 'mph',
          ),
          _Stat(
            label: 'DISTANCE',
            value: appState.location.currentDistanceMiles.toStringAsFixed(1),
            unit: 'mi',
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final bool big;
  const _Stat(
      {required this.label, required this.value, required this.unit, this.big = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1)),
        Text('$value $unit',
            style: TextStyle(
              color: Colors.white,
              fontSize: big ? 24 : 16,
              fontWeight: FontWeight.bold,
            )),
      ],
    );
  }
}
