// lib/features/kinrel_intelligence/widgets/share_download_stub.dart
//
// Stub for non-web platforms. The web download helper is a no-op on
// mobile/desktop because those platforms use the native share sheet
// via `share_plus`.
//
// This file is selected when dart:html is NOT available (i.e., on
// native platforms). On web, share_download_web.dart is selected
// instead via the conditional import in kinrel_share_card.dart.

import 'dart:typed_data';

/// Trigger a browser download of the given PNG bytes with the given
/// filename. On native platforms this is a no-op (returns false) —
/// the caller should use `share_plus` instead.
bool downloadPngOnWeb(Uint8List bytes, String filename) {
  // No-op on native platforms.
  return false;
}
