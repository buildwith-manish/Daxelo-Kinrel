// lib/main.dart
//
// DAXELO KINREL — Application Entry Point

import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'app.dart';
import 'core/bootstrap/app_initializer.dart';
import 'core/services/push_notification_service.dart';

void main() {
  // Ensure Flutter bindings — fast, non-blocking.
  WidgetsFlutterBinding.ensureInitialized();

  // Register FCM background handler BEFORE runApp() per Firebase docs.
  // Must be a top-level call — moving it after runApp() causes ANR
  // because the background isolate can't find the handler in time.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Fire-and-forget: AppInitializer runs in the background while
  // the first frame paints. No await = no blocking the main thread.
  AppInitializer.initialize();

  // Render immediately.
  runApp(const KinrelApp());
}
