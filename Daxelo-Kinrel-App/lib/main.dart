// lib/main.dart
//
// DAXELO KINREL — Application Entry Point
//
// ANR FIX: No blocking work before runApp(). All initialization
// happens AFTER the first frame renders inside the widget tree.

import 'package:flutter/material.dart';
import 'app.dart';

void main() {
  // Ensure Flutter bindings — fast, non-blocking.
  WidgetsFlutterBinding.ensureInitialized();

  // Render immediately. All heavy init happens in initState after
  // the first frame is painted, preventing the 5-second ANR.
  runApp(const KinrelApp());
}
