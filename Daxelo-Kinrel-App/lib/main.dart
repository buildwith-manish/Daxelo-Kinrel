// lib/main.dart
//
// DAXELO KINREL — Application Entry Point
//
// ARCHITECTURE: This file does exactly 4 things and nothing else:
//   1. WidgetsFlutterBinding.ensureInitialized()
//   2. Firebase.initializeApp()
//   3. FirebaseMessaging.onBackgroundMessage()
//   4. runApp()
//
// ALL other initialization (Drift, Supabase, Crashlytics, etc.)
// runs in the background via appInitProvider, triggered by
// KinrelApp's postFrameCallback. The splash screen NEVER awaits
// any initialization — it shows animation for 2s then navigates.

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'app.dart';
import 'core/services/push_notification_service.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  runApp(const KinrelApp());
}
