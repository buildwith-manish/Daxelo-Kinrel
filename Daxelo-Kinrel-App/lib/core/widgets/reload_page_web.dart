// lib/core/widgets/reload_page_web.dart
//
// Web implementation of page reload. Calls `window.location.reload()`
// via the dart:html API.
//
// This file is selected via the conditional import in
// global_error_widget.dart when dart:html is available (i.e., on web).

import 'dart:html' show window;

/// Reload the current page by calling `window.location.reload()`.
/// On web, this is the equivalent of "restart the app" — it clears
/// any stale in-memory state and re-fetches all assets.
void reloadCurrentPage() {
  try {
    window.location.reload();
  } catch (_) {
    // Last-resort fallback: assign to href to force a navigation.
    try {
      window.location.href = window.location.href;
    } catch (_) {}
  }
}
