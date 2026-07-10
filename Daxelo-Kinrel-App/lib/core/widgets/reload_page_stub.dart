// lib/core/widgets/reload_page_stub.dart
//
// Stub for non-web platforms. The reload function is a no-op on
// Android/iOS/desktop because there's no "page" to reload — the
// user must restart the app manually.
//
// This file is selected when dart:html is NOT available (i.e., on
// native platforms). On web, reload_page_web.dart is selected instead
// via the conditional import in global_error_widget.dart.

/// Reload the current page. On web, calls `window.location.reload()`.
/// On native platforms, this is a no-op (returns without doing anything).
void reloadCurrentPage() {
  // No-op on native platforms.
}
