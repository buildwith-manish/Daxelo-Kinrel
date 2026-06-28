// lib/core/utils/window_manager_stub.dart
//
// Web stub for window_manager — provides the same API surface as
// package:window_manager/window_manager.dart but as no-ops so the app
// can import it on web without crashing.
//
// Used via conditional import in main.dart:
//   import 'package:window_manager/window_manager.dart'
//       if (dart.library.html) '../utils/window_manager_stub.dart';
//
// Only the methods actually called from main.dart are stubbed here.

class WindowOptions {
  final dynamic size;
  final dynamic minimumSize;
  final bool center;
  final String title;
  final dynamic titleBarStyle;

  const WindowOptions({
    this.size,
    this.minimumSize,
    this.center = false,
    this.title = '',
    this.titleBarStyle,
  });
}

// Match the real TitleBarStyle enum values
class TitleBarStyle {
  static const normal = 'normal';
}

class WindowManager {
  static final WindowManager instance = WindowManager._();
  WindowManager._();

  Future<void> ensureInitialized() async {}
  Future<void> waitUntilReadyToShow(
      WindowOptions options, Function() callback) async {
    await callback();
  }

  Future<void> show() async {}
  Future<void> focus() async {}
}

final windowManager = WindowManager.instance;
