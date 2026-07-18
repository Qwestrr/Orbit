import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

/// Shown when the accident heuristic fires. Gives the driver a visible,
/// hard-to-miss countdown to cancel (pothole, dropped phone, hard brake)
/// before the group is notified — avoiding alarm fatigue from false
/// positives while still alerting fast in a real emergency.
class AccidentAlertDialog extends StatefulWidget {
  final double peakGForce;
  final VoidCallback onResolved;
  const AccidentAlertDialog(
      {super.key, required this.peakGForce, required this.onResolved});

  @override
  State<AccidentAlertDialog> createState() => _AccidentAlertDialogState();
}

class _AccidentAlertDialogState extends State<AccidentAlertDialog> {
  int _secondsLeft = 20;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        t.cancel();
        _confirmAndAlertGroup();
      }
    });
  }

  void _confirmAndAlertGroup() {
    // In the full build this writes possibleAccidentDetected=true on the
    // active trip and triggers a push notification (Cloud Function
    // listening for that field) to every group member with the driver's
    // last known location.
    context.read<AppState>().endTrip(accidentConfirmed: true);
    Navigator.of(context).pop();
    widget.onResolved();
  }

  void _cancel() {
    _timer?.cancel();
    Navigator.of(context).pop();
    widget.onResolved();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 32),
            SizedBox(width: 8),
            Text('Possible crash detected'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'We detected a sudden impact (${widget.peakGForce.toStringAsFixed(1)}g) '
              'followed by a rapid stop. Alerting your group in:',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text('$_secondsLeft',
                style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          Center(
            child: FilledButton(
              onPressed: _cancel,
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
              child: const Text("I'm okay — cancel alert"),
            ),
          ),
        ],
      ),
    );
  }
}
