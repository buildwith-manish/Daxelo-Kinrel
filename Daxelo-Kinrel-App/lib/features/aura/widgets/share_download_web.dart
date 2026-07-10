// lib/features/aura/widgets/share_download_web.dart
//
// Web implementation of PNG download. Creates a Blob URL and triggers
// a synthetic <a download> click so the user gets a deterministic
// filename (instead of `share_plus`'s fallback of a random filename
// in the Downloads folder).
//
// This file is selected via the conditional import in
// aura_share_card.dart when dart:html is available (i.e., on web).

import 'dart:html' show Blob, Url, AnchorElement, document;
import 'dart:typed_data';

/// Trigger a browser download of the given PNG bytes with the given
/// filename. Always returns true on web (the download is fire-and-forget).
bool downloadPngOnWeb(Uint8List bytes, String filename) {
  try {
    final blob = Blob([bytes], 'image/png');
    final url = Url.createObjectUrlFromBlob(blob);
    final anchor = AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..style.display = 'none';
    document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    Url.revokeObjectUrl(url);
    return true;
  } catch (_) {
    return false;
  }
}
