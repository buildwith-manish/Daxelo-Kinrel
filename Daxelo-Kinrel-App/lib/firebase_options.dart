// lib/firebase_options.dart
//
// DAXELO KINREL — Firebase Configuration
//
// Generated from Firebase project: daxelo-kinrel-d8ccf
// Project number: 643588134212
//
// ⚠️  This file contains real API keys. These are SAFE to commit because:
// - Android API key is restricted to com.daxelo.kinrel package + SHA-1
// - iOS API key is restricted to com.daxelo.kinrel bundle ID
// - Firebase enforces app-level restrictions server-side

import 'dart:io';
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (Platform.isAndroid) {
      return android;
    } else if (Platform.isIOS) {
      return ios;
    }
    throw UnsupportedError(
      'DefaultFirebaseOptions are not supported for this platform. '
      'Firebase Crashlytics only works on Android and iOS.',
    );
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBg29TMdNVuWlC09cMzUeYrFUF_8PrTY_A',
    appId: '1:643588134212:android:ee88b744fc8da5bcaf7311',
    messagingSenderId: '643588134212',
    projectId: 'daxelo-kinrel-d8ccf',
    storageBucket: 'daxelo-kinrel-d8ccf.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAMin2xC-B-Guvo9j-8nRR1dOtDZqfL314',
    appId: '1:643588134212:ios:f2bb83835ce63223af7311',
    messagingSenderId: '643588134212',
    projectId: 'daxelo-kinrel-d8ccf',
    storageBucket: 'daxelo-kinrel-d8ccf.firebasestorage.app',
    iosBundleId: 'com.daxelo.kinrel',
  );
}
