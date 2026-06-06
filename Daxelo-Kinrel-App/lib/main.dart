// lib/main.dart
//
// DAXELO KINREL — Application Entry Point
//
// This file is intentionally minimal (~20 lines). All initialization
// logic lives in core/bootstrap/, and the app widget lives in app.dart.
// See CQ-01 (split main.dart) for the rationale.

import 'package:flutter/material.dart';
import 'app.dart';
import 'core/bootstrap/app_initializer.dart';

void main() async {
  await AppInitializer.initialize();
  runApp(const KinrelApp());
}
