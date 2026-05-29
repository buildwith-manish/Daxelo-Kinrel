// lib/core/network/realtime_dedup.dart
//
// DAXELO KINREL — Realtime Event Deduplication
//
// Prevents duplicate realtime events from being processed.
// Keeps track of the last 100 event IDs and skips duplicates.

/// Deduplication helper for Supabase Realtime events.
/// Tracks recent event IDs and filters out duplicates within
/// the cache window.
class RealtimeDedup {
  final _recentEventIds = <String>{};
  static const _maxCacheSize = 100;

  /// Check if an event with the given ID is a duplicate.
  /// Returns `true` if the event was already seen (duplicate),
  /// `false` if this is a new event.
  bool isDuplicate(String eventId) {
    if (_recentEventIds.contains(eventId)) return true;
    _recentEventIds.add(eventId);
    if (_recentEventIds.length > _maxCacheSize) {
      // Remove the oldest entry (first inserted).
      // Since Set doesn't preserve order, we convert to list.
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
