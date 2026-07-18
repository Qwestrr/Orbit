import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../services/storage_service.dart';

/// Change display name and profile picture (imported from the photo
/// library). No payment fields, no plan selector — there isn't one.
class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final _nameController = TextEditingController();
  final _garageController = TextEditingController();
  final _storage = StorageService();
  final List<String> _garageVehicles = <String>[];
  File? _pickedImage;
  bool _saving = false;
  bool _didEditGarage = false;

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    final user = appState.auth.currentUser;
    _nameController.text = user?.displayName ?? '';
    final me = appState.groupMembers.where((m) => m.uid == user?.uid).toList();
    if (me.isNotEmpty) {
      _garageVehicles
        ..clear()
        ..addAll(me.first.garageVehicles);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _garageController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) {
      setState(() => _pickedImage = File(picked.path));
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final appState = context.read<AppState>();
      final uid = appState.auth.currentUser!.uid;

      String? photoUrl;
      if (_pickedImage != null) {
        photoUrl = await _storage.uploadProfilePhoto(uid, _pickedImage!);
      }

      final newName = _nameController.text.trim();
      await appState.auth.currentUser?.updateDisplayName(newName);
      // Mirror into the Firestore user doc so group members see the
      // update without needing Firebase Auth read access to each other.
      await appState.firestore.updateProfile(
        uid: uid,
        displayName: newName,
        photoUrl: photoUrl,
        garageVehicles: _didEditGarage ? _garageVehicles : null,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Could not save account changes: $error'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _addGarageVehicle() {
    final value = _garageController.text.trim();
    if (value.isEmpty) return;
    final exists = _garageVehicles.any(
      (vehicle) => vehicle.toLowerCase() == value.toLowerCase(),
    );
    if (exists) {
      _garageController.clear();
      return;
    }
    setState(() {
      _didEditGarage = true;
      _garageVehicles.add(value);
      _garageController.clear();
    });
  }

  void _removeGarageVehicle(String vehicle) {
    setState(() {
      _didEditGarage = true;
      _garageVehicles.remove(vehicle);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: GestureDetector(
              onTap: _pickPhoto,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundImage: _pickedImage != null ? FileImage(_pickedImage!) : null,
                    child: _pickedImage == null ? const Icon(Icons.person, size: 48) : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: _pickPhoto,
              child: const Text('Import from photo library'),
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Display name'),
          ),
          const SizedBox(height: 20),
          const Text(
            'Garage',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _garageController,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _addGarageVehicle(),
                  decoration: const InputDecoration(
                    labelText: 'Add vehicle',
                    hintText: 'e.g. 2022 Ford F-150',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Add vehicle',
                onPressed: _addGarageVehicle,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_garageVehicles.isEmpty)
            const Text(
              'No vehicles in your garage yet.',
              style: TextStyle(color: Colors.grey),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _garageVehicles
                  .map(
                    (vehicle) => InputChip(
                      label: Text(vehicle),
                      onDeleted: () => _removeGarageVehicle(vehicle),
                    ),
                  )
                  .toList(),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator())
                : const Text('Save'),
          ),
        ],
      ),
    );
  }
}
