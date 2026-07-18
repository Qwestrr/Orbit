import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/place.dart';
import '../providers/app_state.dart';
import '../services/firestore_service.dart';
import '../services/storage_service.dart';

/// Dialog to create a new group with customizable name, picture, and places.
/// Users can add places during group creation with customizable radius settings
/// (50-1000 feet in 25-foot increments).
class GroupCreationDialog extends StatefulWidget {
  final String uid;

  const GroupCreationDialog({super.key, required this.uid});

  @override
  State<GroupCreationDialog> createState() => _GroupCreationDialogState();
}

class _GroupCreationDialogState extends State<GroupCreationDialog> {
  final _groupNameController = TextEditingController();
  final _firestore = FirestoreService();
  final _storage = StorageService();

  File? _groupPictureFile;
  String? _groupPictureUrl;
  final List<_PlaceItem> _places = [];
  bool _creating = false;

  @override
  void dispose() {
    _groupNameController.dispose();
    super.dispose();
  }

  Future<void> _pickGroupPicture() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) {
      setState(() {
        _groupPictureFile = File(picked.path);
        _groupPictureUrl = null; // replaced by new pick
      });
    }
  }

  void _addPlace() {
    showDialog(
      context: context,
      builder: (_) => _PlaceEditorDialog(
        onSave: (name, radiusFeet, icon, customIconFile) {
          setState(() {
            _places.add(_PlaceItem(
              id: const Uuid().v4(),
              name: name,
              icon: icon,
              radiusFeet: radiusFeet,
              customIconFile: customIconFile,
            ));
          });
        },
      ),
    );
  }

  void _editPlace(int index) {
    final item = _places[index];
    showDialog(
      context: context,
      builder: (_) => _PlaceEditorDialog(
        initialName: item.name,
        initialIcon: item.icon,
        initialRadiusFeet: item.radiusFeet,
        initialCustomIconFile: item.customIconFile,
        onSave: (name, radiusFeet, icon, customIconFile) {
          setState(() {
            _places[index] = _PlaceItem(
              id: item.id,
              name: name,
              icon: icon,
              radiusFeet: radiusFeet,
              customIconFile: customIconFile,
            );
          });
        },
      ),
    );
  }

  void _removePlace(int index) {
    setState(() => _places.removeAt(index));
  }

  Future<void> _createGroup() async {
    if (_groupNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a group name')),
      );
      return;
    }

    setState(() => _creating = true);
    try {
      // Upload group picture if selected
      String? groupPictureUrl = _groupPictureUrl;
      if (_groupPictureFile != null) {
        groupPictureUrl = await _storage.uploadGroupPicture(_groupPictureFile!);
      }

      // Create the group
      final group = await _firestore.createGroup(
        name: _groupNameController.text.trim(),
        ownerUid: widget.uid,
        groupPictureUrl: groupPictureUrl,
      );

      // Upload custom place icons and add places
      for (final placeItem in _places) {
        String? customIconUrl;
        if (placeItem.customIconFile != null) {
          customIconUrl = await _storage.uploadPlaceIcon(group.id, placeItem.customIconFile!);
        }

        final place = Place(
          id: placeItem.id,
          name: placeItem.name,
          icon: placeItem.icon,
          customIconUrl: customIconUrl,
          lat: 0, // Will be set by user via map
          lng: 0, // Will be set by user via map
          radiusMeters: feetToMeters(placeItem.radiusFeet),
          createdByUid: widget.uid,
        );

        await _firestore.addPlace(group.id, place);
      }

      if (mounted) {
        // Update app state with new group
        final appState = context.read<AppState>();
        appState.setActiveGroup(group);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating group: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create a New Group'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Group Name
            TextField(
              controller: _groupNameController,
              decoration: const InputDecoration(labelText: 'Group Name (e.g., Family, Friends)'),
            ),
            const SizedBox(height: 20),

            // Group Picture
            const Text('Group Picture (optional)', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickGroupPicture,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _groupPictureFile != null || _groupPictureUrl != null
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey.shade400,
                    width: 2,
                  ),
                  image: _groupPictureFile != null
                      ? DecorationImage(image: FileImage(_groupPictureFile!), fit: BoxFit.cover)
                      : _groupPictureUrl != null
                          ? DecorationImage(image: NetworkImage(_groupPictureUrl!), fit: BoxFit.cover)
                          : null,
                ),
                child: (_groupPictureFile == null && _groupPictureUrl == null)
                    ? const Icon(Icons.add_photo_alternate_outlined, size: 40)
                    : null,
              ),
            ),
            const SizedBox(height: 20),

            // Places Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Places', style: TextStyle(fontWeight: FontWeight.bold)),
                TextButton.icon(
                  onPressed: _addPlace,
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ],
            ),
            if (_places.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No places yet', style: TextStyle(color: Colors.grey, fontSize: 12)),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _places.length,
                itemBuilder: (context, index) {
                  final place = _places[index];
                  return ListTile(
                    leading: place.customIconFile != null
                        ? CircleAvatar(
                            backgroundImage: FileImage(place.customIconFile!),
                          )
                        : CircleAvatar(
                            child: Icon(_iconFor(place.icon)),
                          ),
                    title: Text(place.name),
                    subtitle: Text('${place.radiusFeet.round()} ft radius'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: () => _editPlace(index),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () => _removePlace(index),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _creating ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _creating ? null : _createGroup,
          child: _creating
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Create Group'),
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

class _PlaceItem {
  final String id;
  final String name;
  final String icon;
  final double radiusFeet;
  final File? customIconFile;

  _PlaceItem({
    required this.id,
    required this.name,
    required this.icon,
    required this.radiusFeet,
    this.customIconFile,
  });
}

/// Dialog for editing a single place within group creation.
class _PlaceEditorDialog extends StatefulWidget {
  final String? initialName;
  final String? initialIcon;
  final double? initialRadiusFeet;
  final File? initialCustomIconFile;
  final void Function(String name, double radiusFeet, String icon, File? customIconFile) onSave;

  const _PlaceEditorDialog({
    required this.onSave,
    this.initialName,
    this.initialIcon,
    this.initialRadiusFeet,
    this.initialCustomIconFile,
  });

  @override
  State<_PlaceEditorDialog> createState() => _PlaceEditorDialogState();
}

class _PlaceEditorDialogState extends State<_PlaceEditorDialog> {
  late TextEditingController _nameController;
  late String _selectedIcon;
  late double _radiusFeet;
  File? _customIconFile;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName ?? '');
    _selectedIcon = widget.initialIcon ?? 'pin';
    _radiusFeet = widget.initialRadiusFeet ?? 150;
    _customIconFile = widget.initialCustomIconFile;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _importIconFromPhotos() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) {
      setState(() => _customIconFile = File(picked.path));
    }
  }

  @override
  Widget build(BuildContext context) {
    final divisions = ((kPlaceMaxRadiusFeet - kPlaceMinRadiusFeet) / kPlaceRadiusStepFeet).round();

    return AlertDialog(
      title: Text(widget.initialName != null ? 'Edit place' : 'Add place'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Place Name (e.g., Home, School)'),
            ),
            const SizedBox(height: 16),
            const Text('Icon', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...kBuiltInPlaceIcons.keys.map((key) => _IconChoice(
                      selected: _selectedIcon == key && _customIconFile == null,
                      icon: _iconFor(key),
                      onTap: () => setState(() {
                        _selectedIcon = key;
                        _customIconFile = null;
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
                        color: _customIconFile != null
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey.shade400,
                        width: 2,
                      ),
                      image: _customIconFile != null
                          ? DecorationImage(image: FileImage(_customIconFile!), fit: BoxFit.cover)
                          : null,
                    ),
                    child: _customIconFile == null ? const Icon(Icons.add_photo_alternate_outlined, size: 20) : null,
                  ),
                ),
              ],
            ),
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
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_nameController.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please enter a place name')),
              );
              return;
            }
            widget.onSave(
              _nameController.text.trim(),
              _radiusFeet,
              _selectedIcon,
              _customIconFile,
            );
            Navigator.pop(context);
          },
          child: const Text('Save'),
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
