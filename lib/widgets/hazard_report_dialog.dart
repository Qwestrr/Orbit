import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/hazard_report.dart';
import '../services/firestore_service.dart';

/// Waze-style report picker shown when the user long-presses the map.
class HazardReportDialog extends StatelessWidget {
  final String groupId;
  final List<String> groupIds;
  final double lat;
  final double lng;
  final String reportedByUid;
  final String reportedByName;

  const HazardReportDialog({
    super.key,
    required this.groupId,
    this.groupIds = const [],
    required this.lat,
    required this.lng,
    required this.reportedByUid,
    required this.reportedByName,
  });

  Future<void> _submit(BuildContext context, HazardType type, String label) async {
    final report = HazardReport(
      id: const Uuid().v4(),
      type: type,
      label: label,
      lat: lat,
      lng: lng,
      reportedByUid: reportedByUid,
      reportedByName: reportedByName,
      reportedAt: DateTime.now(),
      expiresAt: DateTime.now().add(HazardReport.defaultLifetime(type)),
    );
    final targetGroupIds = groupIds.isEmpty ? <String>[groupId] : groupIds;
    await FirestoreService().reportHazardToGroups(targetGroupIds, report);
    if (!context.mounted) return;
    final groupCount = targetGroupIds.toSet().length;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          groupCount == 1
              ? '$label reported to 1 group'
              : '$label reported to $groupCount groups',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Report something here', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          ListTile(
            leading: const Icon(Icons.local_police, color: Colors.blue),
            title: const Text('Police'),
            onTap: () => _submit(context, HazardType.police, 'Police'),
          ),
          ListTile(
            leading: const Icon(Icons.car_crash, color: Colors.red),
            title: const Text('Accident'),
            onTap: () => _submit(context, HazardType.accident, 'Accident'),
          ),
          ListTile(
            leading: const Icon(Icons.warning_amber, color: Colors.orange),
            title: const Text('Hazard / object in road'),
            onTap: () => _submit(context, HazardType.hazardObject, 'Hazard'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
