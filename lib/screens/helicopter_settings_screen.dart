import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../providers/appearance_provider.dart';

/// Radius control for the air-traffic overlay: 25-100 miles in
/// 5-mile steps, per spec. The "which aircraft to show" toggle lives
/// here too (see honesty note in FlightTrackingService about why we
/// can't reliably filter by aircraft type with the free OpenSky feed).
class HelicopterSettingsScreen extends StatelessWidget {
  const HelicopterSettingsScreen({super.key});

  static const double _minMiles = 25;
  static const double _maxMiles = 100;
  static const double _stepMiles = 5;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final appearance = context.watch<AppearanceProvider>();
    final divisions = ((_maxMiles - _minMiles) / _stepMiles).round();

    return Scaffold(
      appBar: AppBar(title: const Text('Air Traffic')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SwitchListTile(
            title: const Text('Show air traffic on map'),
            value: appearance.showHelicoptersOnMap,
            onChanged: (v) => appearance.setLayerVisibility(helicopters: v),
          ),
          const SizedBox(height: 16),
          Text('Search radius: ${appState.helicopterRadiusMiles.round()} miles',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          Slider(
            value: appState.helicopterRadiusMiles,
            min: _minMiles,
            max: _maxMiles,
            divisions: divisions,
            label: '${appState.helicopterRadiusMiles.round()} mi',
            onChanged: (v) => appState.setHelicopterRadius(v),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: const Text(
              'This overlay shows aircraft currently broadcasting a public '
              'ADS-B position via OpenSky Network. Many police, EMS, and '
              'military helicopters intentionally don\'t broadcast a public '
              'position, so this will never show every helicopter in the '
              'air — only the ones that are publicly visible.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(height: 24),
          const Text('Notify me when new air traffic takes off nearby',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
            'A temporary banner appears top-right; tap it to jump to the '
            'takeoff location on the map.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
