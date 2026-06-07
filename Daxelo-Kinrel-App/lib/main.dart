// lib/main.dart
//
// DAXELO KINREL — Application Entry Point

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'app.dart';
import 'core/bootstrap/app_initializer.dart';
import 'core/services/push_notification_service.dart';
import 'firebase_options.dart';

Future<void> main() async {
  // Ensure Flutter bindings — fast, non-blocking.
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase BEFORE registering the background message handler.
  // The background handler requires Firebase to be ready first.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Fire-and-forget: AppInitializer runs in the background while
  // the first frame paints. No await = no blocking the main thread.
  AppInitializer.initialize();

  // Render immediately.
  runApp(const KinrelApp());
}
