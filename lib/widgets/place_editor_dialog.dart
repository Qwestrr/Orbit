import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../models/place.dart';
import '../services/firestore_service.dart';
import '../services/storage_service.dart';

/// Add or edit a place: name, an icon (choose from the built-in set or
/// import a photo from the library), and a geofence radius from 50ft to
/// 1000ft in 10ft steps, plus arrival/departure notification toggles.
class PlaceEditorDialog extends StatefulWidget {
  final String groupId;
  final double initialLat;
  final double initialLng;
  final String createdByUid;
  final Place? existing;
  final bool restrictToNameAndRadius;

  const PlaceEditorDialog({
    super.key,
    required this.groupId,
    required this.initialLat,
    required this.initialLng,
    required this.createdByUid,
    this.existing,
    this.restrictToNameAndRadius = false,
  });

  @override
  State<PlaceEditorDialog> createState() => _PlaceEditorDialogState();
}

class _PlaceEditorDialogState extends State<PlaceEditorDialog> {
  final _nameController = TextEditingController();
  final _firestore = FirestoreService();
  final _storage = StorageService();

  String _selectedIcon = 'pin';
  File? _customIconFile;
  String? _existingCustomIconUrl;
  double _radiusFeet = 150;
  bool _notifyArrival = true;
  bool _notifyDeparture = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final p = widget.existing!;
      _nameController.text = p.name;
      _selectedIcon = p.icon;
      _existingCustomIconUrl = p.customIconUrl;
      _radiusFeet = metersToFeet(p.radiusMeters).clamp(kPlaceMinRadiusFeet, kPlaceMaxRadiusFeet);
      _notifyArrival = p.notifyOnArrival;
      _notifyDeparture = p.notifyOnDeparture;
    }
  }

  Future<void> _importIconFromPhotos() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) {
      setState(() {
        _customIconFile = File(picked.path);
        _existingCustomIconUrl = null; // replaced by the new pick
      });
    }
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      String? customIconUrl = _existingCustomIconUrl;
      if (_customIconFile != null) {
        customIconUrl = await _storage.uploadPlaceIcon(widget.groupId, _customIconFile!);
      }

      final place = Place(
        id: widget.existing?.id ?? const Uuid().v4(),
        name: _nameController.text.trim(),
        icon: _selectedIcon,
        customIconUrl: customIconUrl,
        lat: widget.existing?.lat ?? widget.initialLat,
        lng: widget.existing?.lng ?? widget.initialLng,
        radiusMeters: feetToMeters(_radiusFeet),
        notifyOnArrival: _notifyArrival,
        notifyOnDeparture: _notifyDeparture,
        createdByUid: widget.createdByUid,
      );
      await _firestore.addPlace(widget.groupId, place); // set() upserts by id
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final divisions =
        ((kPlaceMaxRadiusFeet - kPlaceMinRadiusFeet) / kPlaceRadiusStepFeet).round();

    return AlertDialog(
      title: Text(widget.existing == null ? 'Add place' : 'Edit place'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name (e.g. Home, School)'),
            ),
            if (!widget.restrictToNameAndRadius) ...[
              const SizedBox(height: 16),
              const Text('Icon', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ...kBuiltInPlaceIcons.keys.map((key) => _IconChoice(
                        selected: _selectedIcon == key && _customIconFile == null && _existingCustomIconUrl == null,
                        icon: _iconFor(key),
                        onTap: () => setState(() {
                          _selectedIcon = key;
                          _customIconFile = null;
                          _existingCustomIconUrl = null;
                        }),
                      )),
                  GestureDetector(
                    onTap: _importIconFromPhotos,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _customIconFile != null || _existingCustomIconUrl != null
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey.shade400,
                          width: 2,
                        ),
                        image: _customIconFile != null
                            ? DecorationImage(image: FileImage(_customIconFile!), fit: BoxFit.cover)
                            : _existingCustomIconUrl != null
                                ? DecorationImage(image: NetworkImage(_existingCustomIconUrl!), fit: BoxFit.cover)
                                : null,
                      ),
                      child: (_customIconFile == null && _existingCustomIconUrl == null)
                          ? const Icon(Icons.add_photo_alternate_outlined, size: 20)
                          : null,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            Text('Radius: ${_radiusFeet.round()} ft', style: const TextStyle(fontWeight: FontWeight.bold)),
            Slider(
              value: _radiusFeet,
              min: kPlaceMinRadiusFeet,
              max: kPlaceMaxRadiusFeet,
              divisions: divisions,
              label: '${_radiusFeet.round()} ft',
              onChanged: (v) => setState(() => _radiusFeet = v),
            ),
            if (!widget.restrictToNameAndRadius) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Notify on arrival'),
                value: _notifyArrival,
                onChanged: (v) => setState(() => _notifyArrival = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Notify on departure'),
                value: _notifyDeparture,
                onChanged: (v) => setState(() => _notifyDeparture = v),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator())
              : const Text('Save'),
        ),
      ],
    );
  }

  IconData _iconFor(String key) {
    switch (key) {
      case 'home':
        return Icons.home;
      case 'school':
        return Icons.school;
      case 'work':
        return Icons.work;
      case 'gym':
        return Icons.fitness_center;
      case 'store':
        return Icons.store;
      case 'restaurant':
        return Icons.restaurant;
      case 'hospital':
        return Icons.local_hospital;
      default:
        return Icons.place;
    }
  }
}

class _IconChoice extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final VoidCallback onTap;
  const _IconChoice({required this.selected, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
          border: Border.all(
            color: selected ? Theme.of(context).colorScheme.primary : Colors.grey.shade400,
            width: 2,
          ),
        ),
        child: Icon(icon),
      ),
    );
  }
}
