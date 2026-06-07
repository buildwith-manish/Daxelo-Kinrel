// lib/main.dart
//
// DAXELO KINREL — Application Entry Point
//
// ANR FIX (Issue #6bba884050263fdff281a8bc49a85b9b):
// Firebase.initializeApp() MUST be awaited before calling
// FirebaseMessaging.onBackgroundMessage(). Calling onBackgroundMessage()
// before Firebase is initialized spawns a background isolate that tries
// to initialize Firebase independently, causing native CountDownLatch
// blocking on the Android platform thread → ANR on cold start.
// Confirmed by Crashlytics ANR trace: main thread blocked in
// MessageQueue.nativePollOnce with an active DartWorker at startup.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'app.dart';
import 'core/bootstrap/app_initializer.dart';
import 'core/services/push_notification_service.dart';
import 'firebase_options.dart';

Future<void> main() async {
  // Ensure Flutter bindings — must be first.
  WidgetsFlutterBinding.ensureInitialized();

  // ── ANR FIX: Initialize Firebase BEFORE registering background handler ──
  // FirebaseMessaging.onBackgroundMessage() spawns a background Dart isolate.
  // If Firebase is not initialized yet, that isolate races to initialize it
  // via the native SDK, which uses CountDownLatch.await() on the Android
  // platform thread. This blocks touch/lifecycle event delivery for >5 s → ANR.
  // Solution: fully initialize Firebase on the main isolate first, so the
  // background isolate finds it already initialized and returns immediately.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('✅ Firebase pre-initialized in main()');
  } catch (e) {
    // Likely already initialized (hot restart) — safe to continue.
    debugPrint('⚠️ Firebase pre-init in main() failed (may already be initialized): $e');
  }

  // ── Firebase Crashlytics: enable automatic error collection ──
  // Pass all uncaught Flutter errors to Crashlytics so they appear in
  // the Firebase console. In debug/profile builds, collection is disabled
  // to avoid noise during development.
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };
  // Disable Crashlytics collection in debug mode to keep the console clean.
  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);

  // Register FCM background handler AFTER Firebase is initialized.
  // Must be a top-level call per Firebase docs — not a class method or closure.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Fire-and-forget: AppInitializer runs in the background while
  // the first frame paints. No await = no blocking the main thread.
  AppInitializer.initialize();

  // Render immediately.
  runApp(const KinrelApp());
}
