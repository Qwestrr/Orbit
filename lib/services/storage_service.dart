import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

/// Uploads images picked from the photo library (profile pictures, custom
/// place icons) to Firebase Storage and returns a public download URL to
/// store on the relevant Firestore doc.
class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  Future<String> uploadProfilePhoto(String uid, File imageFile) async {
    final ref = _storage.ref('profile_photos/$uid.jpg');
    await ref.putFile(imageFile);
    return ref.getDownloadURL();
  }

  Future<String> uploadPlaceIcon(String groupId, File imageFile) async {
    final id = const Uuid().v4();
    final ref = _storage.ref('place_icons/$groupId/$id.jpg');
    await ref.putFile(imageFile);
    return ref.getDownloadURL();
  }

  Future<String> uploadGroupPicture(File imageFile) async {
    final id = const Uuid().v4();
    final ref = _storage.ref('group_pictures/$id.jpg');
    await ref.putFile(imageFile);
    return ref.getDownloadURL();
  }
}
