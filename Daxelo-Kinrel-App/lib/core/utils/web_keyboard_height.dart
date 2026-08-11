// lib/core/utils/web_keyboard_height.dart
//
// DAXELO KINREL — Web Keyboard Height Detector (v128)
//
// On Flutter Web, resizeToAvoidBottomInset does NOT reliably detect the
// mobile browser's virtual keyboard height. MediaQuery.viewInsets.bottom
// stays at 0 because the browser doesn't resize the layout viewport when
// the keyboard opens — it only changes the visualViewport.
//
// This file uses a conditional import to load the platform-specific
// implementation:
// - Web: uses dart:html's window.visualViewport API to detect keyboard height
// - Native: no-op (Scaffold's resizeToAvoidBottomInset handles it)
//
// Usage:
//   In a ConsumerStatefulWidget:
//   ```dart
//   double _webKeyboardHeight = 0;
//
//   @override
//   void initState() {
//     super.initState();
//     WebKeyboardHeight.instance.start();
//     WebKeyboardHeight.instance.addListener(() {
//       if (mounted) setState(() => _webKeyboardHeight = WebKeyboardHeight.instance.currentHeight);
//     });
//   }
//   ```

import 'package:flutter/foundation.dart' show kIsWeb, ChangeNotifier;

// Conditional import: on web, use the dart:html implementation;
// on native, use the no-op stub.
import 'web_keyboard_height_web.dart' if (dart.library.io) 'web_keyboard_height_native.dart'
    as platform;

/// Singleton that monitors the browser's visualViewport for keyboard
/// height changes on Flutter Web. On native platforms, it's a no-op.
class WebKeyboardHeight extends ChangeNotifier {
  WebKeyboardHeight._();
  static final WebKeyboardHeight instance = WebKeyboardHeight._();

  double _currentHeight = 0;
  bool _started = false;

  /// Current keyboard height in logical pixels (0 if closed or on native).
  double get currentHeight => _currentHeight;

  /// Whether a keyboard is currently visible (web only).
  bool get isKeyboardVisible => _currentHeight > 0;

  /// Start listening to the browser's visualViewport resize events.
  /// Only does something on web — on native, this is a no-op.
  void start() {
    if (!kIsWeb || _started) return;
    _started = true;

    platform.attachVisualViewportListener(_onViewportResize);
  }

  void _onViewportResize(double height, double offsetTop, double innerHeight) {
    // The keyboard height is the difference between the layout viewport
    // (window.innerHeight) and the visual viewport (height + offsetTop).
    final keyboardHeight = (innerHeight - height - offsetTop).clamp(0.0, innerHeight);

    // Only notify if the height actually changed (avoid spurious notifications).
    if ((keyboardHeight - _currentHeight).abs() > 1.0) {
      _currentHeight = keyboardHeight;
      notifyListeners();
    }
  }
}
