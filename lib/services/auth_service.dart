import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Thin wrapper around Firebase Auth. Email/password keeps this free and
/// simple to self-host; swap in Google/Apple sign-in later if you want.
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserCredential> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    await cred.user?.updateDisplayName(displayName);
    await _ensureUserProfile(cred.user!, fallbackDisplayName: displayName);

    return cred;
  }

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<UserCredential> signInWithGoogle() async {
    late final UserCredential credential;
    if (kIsWeb) {
      credential = await _auth.signInWithPopup(GoogleAuthProvider());
    } else {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        throw FirebaseAuthException(
          code: 'aborted-by-user',
          message: 'Google sign in was canceled.',
        );
      }

      final googleAuth = await googleUser.authentication;
      final authCredential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      credential = await _auth.signInWithCredential(authCredential);
    }

    if (credential.user != null) {
      await _ensureUserProfile(credential.user!);
    }
    return credential;
  }

  Future<UserCredential> signInWithApple() async {
    late final UserCredential credential;
    AuthorizationCredentialAppleID? appleCredential;
    if (kIsWeb) {
      credential = await _auth.signInWithPopup(AppleAuthProvider());
    } else {
      appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );
      credential = await _auth.signInWithCredential(oauthCredential);
    }

    final user = credential.user;
    if (user != null) {
      final fullName = [
        appleCredential?.givenName,
        appleCredential?.familyName,
      ].whereType<String>().where((p) => p.trim().isNotEmpty).join(' ').trim();

      if (fullName.isNotEmpty && (user.displayName == null || user.displayName!.trim().isEmpty)) {
        await user.updateDisplayName(fullName);
      }
      await _ensureUserProfile(user, fallbackDisplayName: fullName.isEmpty ? null : fullName);
    }

    return credential;
  }

  Future<void> _ensureUserProfile(User user, {String? fallbackDisplayName}) async {
    final docRef = _db.collection('users').doc(user.uid);
    final existing = await docRef.get();
    if (existing.exists) return;

    await docRef.set({
      'displayName': _resolveDisplayName(user, fallbackDisplayName),
      'photoUrl': user.photoURL,
      'garageVehicles': const <String>[],
      'lat': null,
      'lng': null,
      'headingDegrees': null,
      'speedMph': null,
      'lastUpdated': DateTime.now().toIso8601String(),
      'batteryLevel': 100,
      'locationSharingEnabled': true,
    });
  }

  String _resolveDisplayName(User user, String? fallbackDisplayName) {
    final preferred = user.displayName?.trim();
    if (preferred != null && preferred.isNotEmpty) return preferred;

    final fallback = fallbackDisplayName?.trim();
    if (fallback != null && fallback.isNotEmpty) return fallback;

    final email = user.email?.trim();
    if (email != null && email.contains('@')) {
      return email.split('@').first;
    }

    return 'Circle Map User';
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email);
}
