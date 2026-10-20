// lib/core/utils/dlog.dart
//
// DAXELO KINREL — Debug Logger (Phase 9)
//
// A zero-cost-in-release debug log helper. In debug mode, it calls
// debugPrint with the lazily-evaluated message. In release mode, it
// does nothing — the message closure is never called, so string
// interpolation is never executed.
//
// Usage in hot paths (build(), painters, scroll/gesture listeners):
//   dlog(() => 'Building node $id at $position');
//
// In release, this compiles to a no-op — the closure is never invoked,
// so the string interpolation `'$id at $position'` is never evaluated.
// This is cheaper than `debugPrint('...')` which always evaluates the
// string even when debugPrint is a no-op (the string is built before
// the function is called).

import 'package:flutter/foundation.dart';

/// Logs a debug message only in debug mode.
///
/// The [message] closure is ONLY called when `kDebugMode` is true.
/// In release mode, the closure is never invoked — zero cost.
///
/// Use this in hot paths (build, paint, scroll/gesture listeners, loops,
/// realtime/message handlers) where `debugPrint('...')` would waste CPU
/// on string interpolation even though the output is discarded.
///
/// Example:
///   dlog(() => 'Layout: ${positions.length} nodes in ${sw.elapsedMilliseconds}ms');
void dlog(String Function() message) {
  if (kDebugMode) {
    debugPrint(message());
  }
}
