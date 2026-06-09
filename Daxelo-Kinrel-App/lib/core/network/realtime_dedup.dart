// lib/core/network/realtime_dedup.dart
//
// DAXELO KINREL — Realtime Event Deduplication
//
// Prevents duplicate realtime events from being processed.
// Keeps track of the last 100 event IDs and skips duplicates.

import 'dart:collection';

/// Deduplication helper for Supabase Realtime events.
/// Tracks recent event IDs and filters out duplicates within
/// the cache window. Uses LinkedHashSet for predictable
/// insertion-order-based eviction.
class RealtimeDedup {
  final _recentEventIds = LinkedHashSet<String>();
  static const _maxCacheSize = 100;

  /// Check if an event with the given ID is a duplicate.
  /// Returns `true` if the event was already seen (duplicate),
  /// `false` if this is a new event.
  bool isDuplicate(String eventId) {
    if (_recentEventIds.contains(eventId)) return true;
    _recentEventIds.add(eventId);
    if (_recentEventIds.length > _maxCacheSize) {
      // LinkedHashSet preserves insertion order, so .first returns
      // the oldest entry — remove it to maintain the cache window.
      final oldest = _recentEventIds.first;
      _recentEventIds.remove(oldest);
    }
    return false;
  }

  /// Clear the dedup cache.
  void clear() => _recentEventIds.clear();

  /// Get the current cache size (for debugging).
  int get cacheSize => _recentEventIds.length;
}
