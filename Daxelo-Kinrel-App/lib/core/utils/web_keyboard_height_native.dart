// lib/core/utils/web_keyboard_height_native.dart
//
// Native (non-web) stub for the visualViewport keyboard height detector.
// On native platforms, the Scaffold's resizeToAvoidBottomInset handles
// keyboard insets correctly, so this is a no-op.

void attachVisualViewportListener(
  void Function(double height, double offsetTop, double innerHeight) callback,
) {
  // No-op on native — resizeToAvoidBottomInset handles it.
}
