import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/app_user.dart';
import '../services/firestore_service.dart';

/// Lets the current user set the battery percentage that triggers a
/// low-battery alert, and choose exactly which group members they want
/// those alerts for — with a select-all shortcut, per spec. This is a
/// personal preference (stored under the user's own doc), not a
/// group-wide setting, since different members may want different
/// thresholds or subsets.
class BatteryAlertPrefs extends StatefulWidget {
  final String uid;
  final String groupId;
  final List<AppUser> members;
  const BatteryAlertPrefs({
    super.key,
    required this.uid,
    required this.groupId,
    required this.members,
  });

  @override
  State<BatteryAlertPrefs> createState() => _BatteryAlertPrefsState();
}

class _BatteryAlertPrefsState extends State<BatteryAlertPrefs> {
  final _firestore = FirestoreService();
  int _threshold = 20;
  Set<String> _selectedUids = {};
  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final prefs = await _withFirestoreRetry(
        () => _firestore.getNotificationPrefs(uid: widget.uid, groupId: widget.groupId),
      );
      if (!mounted) return;
      setState(() {
        _threshold = prefs?['lowBatteryThresholdPercent'] ?? 20;
        _selectedUids = Set<String>.from(
          prefs?['batteryAlertMemberUids'] ?? widget.members.map((m) => m.uid),
        ); // default: everyone
        _loading = false;
      });
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = _firestoreErrorMessage(e);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Unable to load battery alert settings right now. Please try again.';
      });
    }
  }

  Future<void> _persist() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _withFirestoreRetry(
        () => _firestore.setNotificationPrefs(
          uid: widget.uid,
          groupId: widget.groupId,
          lowBatteryThresholdPercent: _threshold,
          batteryAlertMemberUids: _selectedUids.toList(),
        ),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(_firestoreErrorMessage(e)),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Could not save changes right now. Please try again.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<T> _withFirestoreRetry<T>(Future<T> Function() action) async {
    const maxAttempts = 3;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await action();
      } on FirebaseException catch (e) {
        final retryable = e.code == 'unavailable' ||
            e.code == 'aborted' ||
            e.code == 'deadline-exceeded';
        final isLast = attempt == maxAttempts;
        if (!retryable || isLast) rethrow;
        await Future.delayed(Duration(milliseconds: 400 * attempt * attempt));
      }
    }
    throw StateError('Retry loop exited unexpectedly');
  }

  String _firestoreErrorMessage(FirebaseException e) {
    if (e.code == 'unavailable') {
      return 'Cloud sync is temporarily unavailable. Please try again in a moment.';
    }
    if (e.code == 'deadline-exceeded') {
      return 'Cloud request timed out. Check your connection and try again.';
    }
    return e.message ?? 'A cloud sync error occurred.';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 34),
            const SizedBox(height: 12),
            Text(
              _loadError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final allSelected = _selectedUids.length == widget.members.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Alert me when battery drops below $_threshold%',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        Slider(
          value: _threshold.toDouble(),
          min: 5,
          max: 50,
          divisions: 9,
          label: '$_threshold%',
          onChanged: _saving ? null : (v) => setState(() => _threshold = v.round()),
          onChangeEnd: _saving ? null : (_) => _persist(),
        ),
        const SizedBox(height: 8),
        if (_saving)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Get alerts for', style: TextStyle(fontWeight: FontWeight.bold)),
            TextButton(
              onPressed: _saving
                  ? null
                  : () {
                setState(() {
                  _selectedUids = allSelected
                      ? {}
                      : widget.members.map((m) => m.uid).toSet();
                });
                _persist();
              },
              child: Text(allSelected ? 'Deselect all' : 'Select all'),
            ),
          ],
        ),
        ...widget.members.map((m) => CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(m.displayName),
              value: _selectedUids.contains(m.uid),
              onChanged: _saving
                  ? null
                  : (checked) {
                setState(() {
                  if (checked == true) {
                    _selectedUids.add(m.uid);
                  } else {
                    _selectedUids.remove(m.uid);
                  }
                });
                _persist();
              },
            )),
      ],
    );
  }
}
