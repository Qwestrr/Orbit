// GENERATED PLACEHOLDER — replace this whole file by running:
//
//   dart pub global activate flutterfire_cli
//   flutterfire configure
//
// from the project root, after creating a free Firebase project at
// https://console.firebase.google.com. That command detects your app's
// bundle IDs and writes the real API keys/project IDs into this file
// automatically — you should not hand-edit them.

import 'package:firebase_core/firebase_core.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'Run `flutterfire configure` to generate web options if you plan to '
        'support Flutter web.',
      );
    }
    switch (Platform.operatingSystem) {
      case 'android':
        return android;
      case 'ios':
        return ios;
      default:
        throw UnsupportedError(
          '${Platform.operatingSystem} is not supported by this template yet.',
        );
    }
  }

  static const android = FirebaseOptions(
    apiKey: 'AIzaSyCfql6PNMM7_k9wIy5JozHzB9pz6PPUyXw',
    appId: '1:1060740195756:android:1ed218da3212fed46cc609',
    messagingSenderId: '1060740195756',
    projectId: 'orbit-v2-265dd',
    storageBucket: 'orbit-v2-265dd.firebasestorage.app',
  );

  static const ios = FirebaseOptions(
    apiKey: 'AIzaSyCfql6PNMM7_k9wIy5JozHzB9pz6PPUyXw',
    appId: '1:1060740195756:ios:1ed218da3212fed46cc609',
    messagingSenderId: '1060740195756',
    projectId: 'orbit-v2-265dd',
    storageBucket: 'orbit-v2-265dd.firebasestorage.app',
    iosBundleId: 'com.example.circle_map',
  );
}
