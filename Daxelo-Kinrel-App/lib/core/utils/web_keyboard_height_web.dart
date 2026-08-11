// lib/core/utils/web_keyboard_height_web.dart
//
// Web implementation of the visualViewport keyboard height detector.
// Uses dart:html to access window.visualViewport directly.

import 'dart:html' as html;

void attachVisualViewportListener(
  void Function(double height, double offsetTop, double innerHeight) callback,
) {
  final visualViewport = html.window.visualViewport;
  if (visualViewport == null) return;

  void onResize(html.Event _) {
    callback(
      visualViewport.height,
      visualViewport.offsetTop,
      html.window.innerHeight.toDouble(),
    );
  }

  visualViewport.onResize.listen(onResize);
  // Also listen to scroll, as some browsers fire scroll instead of resize
  // when the keyboard animates.
  visualViewport.onScroll.listen(onResize);
}
