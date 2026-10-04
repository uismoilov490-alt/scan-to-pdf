// File generated based on google-services.json
// ignore_for_file: lines_longer_than_80_chars, avoid_classes_with_only_static_members
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) throw UnsupportedError('Web platform not configured.');
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError('iOS platform not configured.');
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBs2WjDIfGEewVZLL7x47rRDA1nyUq1KD8',
    appId: '1:470242131721:android:8a96ef5662feb49dda9dd8',
    messagingSenderId: '470242131721',
    projectId: 'scan-to-pdf-7fdf1',
    storageBucket: 'scan-to-pdf-7fdf1.firebasestorage.app',
    androidClientId:
        '470242131721-0pr6r8abllps69o39uu762m53p5ukp89.apps.googleusercontent.com',
  );
}
