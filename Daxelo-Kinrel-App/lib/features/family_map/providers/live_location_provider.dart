// lib/features/family_map/providers/live_location_provider.dart
//
// DAXELO KINREL — Live Location Provider
//
// Three-tier location merge for family map pins:
//   1. Live broadcast (Supabase Realtime Broadcast, ephemeral, every
//      few seconds) — freshest, wins if received within 2 minutes.
//   2. Last-known persisted (MemberLocation table) — read on load /
//      reconnect, wins if within 60 minutes.
//   3. City fallback (kCityCoordinates lookup) — always available as
//      a last resort; the default for members who never shared GPS.
//
// Broadcast channel: family-map:{familyId}
//   Event: location_move
//   Payload: { personId, lat, lng, ts }
//
// Privacy: location sharing is OFF by default. The user must toggle
// "Share my location with family" in settings. When off, no broadcast
// is sent and the MemberLocation row's isSharing is set to false.
//
// Staleness tiers (§4.6 of the spec):
//   0-2 min   → LIVE (pulsing ring)
//   2-15 min  → RECENT (solid ring)
//   15-60 min → STALE (dimmed ring)
//   >60 min   → CITY_FALLBACK (standard pin, no live indicator)

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../l10n/app_localizations.dart';
// StateNotifier is re-exported by flutter_riverpod in 2.x

// ═══════════════════════════════════════════════════════════════════════
// STALENESS TIER
// ═══════════════════════════════════════════════════════════════════════

/// How fresh a location update is. Drives pin visual treatment.
enum LocationTier {
  /// 0-2 min: pulsing teal/orange ring, labeled "Live • now"
  live,
  /// 2-15 min: solid ring, labeled "Updated Xm ago"
  recent,
  /// 15-60 min: dimmed ring, labeled "Updated Xm ago"
  stale,
  /// >60 min or city-only: standard pin, labeled "Last known" / city name
  cityFallback,
}

/// Compute the staleness tier from a timestamp.
/// [lastUpdated] is the UTC timestamp of the last location update.
LocationTier computeTier(DateTime? lastUpdated) {
  if (lastUpdated == null) return LocationTier.cityFallback;
  final age = DateTime.now().toUtc().difference(lastUpdated);
  if (age.inMinutes < 2) return LocationTier.live;
  if (age.inMinutes < 15) return LocationTier.recent;
  if (age.inMinutes < 60) return LocationTier.stale;
  return LocationTier.cityFallback;
}

/// Human-readable label for a tier, e.g. "Live • now" or "Updated 5m ago".
///
/// §10 — Returns a hardcoded English string. Use [tierLabelLocalized] when
/// a localized [S] instance is available so the label respects the user's
/// locale. Kept for backward-compatibility with non-context callers (e.g.
/// debug logs, tests).
String tierLabel(LocationTier tier, DateTime? lastUpdated) {
  switch (tier) {
    case LocationTier.live:
      return 'Live • now';
    case LocationTier.recent:
    case LocationTier.stale:
      if (lastUpdated == null) return 'Updated recently';
      final mins = DateTime.now().toUtc().difference(lastUpdated).inMinutes;
      if (mins < 1) return 'Updated just now';
      return 'Updated ${mins}m ago';
    case LocationTier.cityFallback:
      return 'Last known';
  }
}

/// §10 — Localized version of [tierLabel]. Returns the same tier
/// description translated via the provided [S] instance. Falls back to
/// the English [tierLabel] when [l10n] is null (e.g. in tests).
String tierLabelLocalized(LocationTier tier, DateTime? lastUpdated, S? l10n) {
  if (l10n == null) return tierLabel(tier, lastUpdated);
  switch (tier) {
    case LocationTier.live:
      return l10n.familyMapTierLive;
    case LocationTier.recent:
    case LocationTier.stale:
      if (lastUpdated == null) return l10n.familyMapTierUpdatedRecently;
      final mins = DateTime.now().toUtc().difference(lastUpdated).inMinutes;
      if (mins < 1) return l10n.familyMapTierUpdatedJustNow;
      return l10n.familyMapTierUpdatedMinsAgo(mins);
    case LocationTier.cityFallback:
      return l10n.familyMapTierLastKnown;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// LIVE LOCATION MODEL
// ═══════════════════════════════════════════════════════════════════════

/// A single member's live or last-known location.
class LiveLocation {
  const LiveLocation({
    required this.personId,
    required this.lat,
    required this.lng,
    required this.isSharing,
    this.updatedAt,
  });

  final String personId;
  final double lat;
  final double lng;
  final bool isSharing;
  final DateTime? updatedAt;

  /// Current staleness tier based on [updatedAt].
  LocationTier get tier => computeTier(updatedAt);

  /// Whether this location is "live" (within 2 minutes).
  bool get isLive => tier == LocationTier.live;

  LiveLocation copyWith({
    double? lat,
    double? lng,
    bool? isSharing,
    DateTime? updatedAt,
  }) =>
      LiveLocation(
        personId: personId,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        isSharing: isSharing ?? this.isSharing,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

// ═══════════════════════════════════════════════════════════════════════
// LIVE LOCATION NOTIFIER
// ═══════════════════════════════════════════════════════════════════════

/// State for [LiveLocationNotifier].
class LiveLocationState {
  const LiveLocationState({
    this.locations = const {},
    this.isSharing = false,
    this.isLoading = false,
    this.error,
  });

  /// Map of personId → live/last-known location.
  final Map<String, LiveLocation> locations;

  /// Whether the current user is sharing their own location.
  final bool isSharing;

  /// Whether we're loading last-known positions from the DB.
  final bool isLoading;

  /// Error message if the initial load failed.
  final String? error;

  LiveLocationState copyWith({
    Map<String, LiveLocation>? locations,
    bool? isSharing,
    bool? isLoading,
    String? error,
  }) =>
      LiveLocationState(
        locations: locations ?? this.locations,
        isSharing: isSharing ?? this.isSharing,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

/// Manages live + last-known family member locations for a family map.
///
/// On [start]:
///   1. Reads the `MemberLocation` table for [familyId] (last-known
///      positions for all sharing members).
///   2. Subscribes to the `family-map:{familyId}` Broadcast channel
///      for ephemeral live movement.
///
/// On [stop]:
///   Unsubscribes from the channel. Last-known positions remain in
///   state for offline display.
///
/// The current user's own sharing toggle is managed via [setSharing].
/// When sharing is on, the caller (map screen) is responsible for
/// capturing GPS and calling [broadcastMyLocation] every few seconds,
/// and [upsertMyLocation] on the 30-60s throttle.
class LiveLocationNotifier extends StateNotifier<LiveLocationState> {
  LiveLocationNotifier(this._ref) : super(const LiveLocationState(isLoading: false));

  final Ref _ref;
  RealtimeChannel? _channel;
  Timer? _staleRefreshTimer;

  @override
  void dispose() {
    stop();
    super.dispose();
  }

  /// Start loading last-known locations + subscribing to live broadcasts.
  /// [familyId] is the family whose members' locations to track.
  Future<void> start(String familyId) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) {
        state = state.copyWith(isLoading: false, error: 'Not authenticated');
        return;
      }

      // ── Step 1: Read last-known locations from MemberLocation table ──
      final response = await client
          .from('MemberLocation')
          .select('personId, lat, lng, isSharing, updatedAt')
          .eq('familyId', familyId) as List<dynamic>;

      final locations = <String, LiveLocation>{};
      for (final row in response) {
        final map = row as Map<String, dynamic>;
        final personId = map['personId'] as String;
        final lat = (map['lat'] as num).toDouble();
        final lng = (map['lng'] as num).toDouble();
        final isSharing = map['isSharing'] as bool? ?? false;
        final updatedAtStr = map['updatedAt'] as String?;
        final updatedAt =
            updatedAtStr != null ? DateTime.tryParse(updatedAtStr)?.toUtc() : null;

        locations[personId] = LiveLocation(
          personId: personId,
          lat: lat,
          lng: lng,
          isSharing: isSharing,
          updatedAt: updatedAt,
        );
      }

      // ── Check current user's own sharing status ──
      final userId = client.auth.currentUser?.id;
      if (userId != null) {
        final myRow = await client
            .from('MemberLocation')
            .select('isSharing')
            .eq('userId', userId)
            .maybeSingle() as Map<String, dynamic>?;
        final mySharing = myRow?['isSharing'] as bool? ?? false;
        state = LiveLocationState(
          locations: locations,
          isSharing: mySharing,
          isLoading: false,
        );
      } else {
        state = LiveLocationState(
          locations: locations,
          isLoading: false,
        );
      }

      // ── Step 2: Subscribe to live broadcast channel ──
      _subscribeToChannel(familyId);

      // ── Step 3: Periodic staleness refresh ──
      // Every 30s, trigger a rebuild so tier labels stay current
      // ("Updated 5m ago" → "Updated 6m ago" without a new broadcast).
      _staleRefreshTimer?.cancel();
      _staleRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        // Force a rebuild by copying the state (new Map identity).
        state = state.copyWith(
          locations: Map<String, LiveLocation>.from(state.locations),
        );
      });
    } catch (e) {
      debugPrint('⚠️ LiveLocationNotifier.start failed: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Subscribe to the family-map:{familyId} Broadcast channel.
  void _subscribeToChannel(String familyId) {
    final client = _ref.read(supabaseProvider);
    if (client == null) return;

    _channel?.unsubscribe();
    _channel = client.channel('family-map:$familyId');

    _channel!.onBroadcast(event: 'location_move', callback: (payload) {
      final data = payload;

      final personId = data['personId'] as String?;
      final lat = (data['lat'] as num?)?.toDouble();
      final lng = (data['lng'] as num?)?.toDouble();
      final ts = data['ts'] as String?;

      if (personId == null || lat == null || lng == null) return;

      final updatedAt = ts != null ? DateTime.tryParse(ts)?.toUtc() : DateTime.now().toUtc();

      // Merge: update only this person's position, don't refetch the whole map.
      final existing = state.locations[personId];
      final updated = LiveLocation(
        personId: personId,
        lat: lat,
        lng: lng,
        isSharing: existing?.isSharing ?? true,
        updatedAt: updatedAt ?? DateTime.now().toUtc(),
      );

      final newLocations = Map<String, LiveLocation>.from(state.locations);
      newLocations[personId] = updated;
      state = state.copyWith(locations: newLocations);
    });

    _channel!.subscribe((status, error) {
      if (error != null) {
        debugPrint('⚠️ family-map channel error: $error');
      }
    });
  }

  /// Stop subscribing to live updates. Last-known positions stay in state.
  void stop() {
    _channel?.unsubscribe();
    _channel = null;
    _staleRefreshTimer?.cancel();
    _staleRefreshTimer = null;
  }

  /// Toggle the current user's location sharing.
  /// When [sharing] is true, the map screen should start capturing GPS
  /// and calling [broadcastMyLocation] + [upsertMyLocation].
  /// When [sharing] is false, immediately sets isSharing=false in the DB
  /// so old rows/state don't linger.
  Future<void> setSharing({
    required bool sharing,
    required String familyId,
    required String personId,
    required double lat,
    required double lng,
  }) async {
    final client = _ref.read(supabaseProvider);
    if (client == null) return;

    try {
      await client.from('MemberLocation').upsert({
        'familyId': familyId,
        'personId': personId,
        'userId': client.auth.currentUser!.id,
        'lat': lat,
        'lng': lng,
        'isSharing': sharing,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });

      state = state.copyWith(isSharing: sharing);
    } catch (e) {
      debugPrint('⚠️ setSharing failed: $e');
    }
  }

  /// Broadcast a live position update to the family channel.
  /// Called every few seconds by the map screen while sharing is on.
  /// Does NOT write to the DB — that's [upsertMyLocation].
  void broadcastMyLocation({
    required String familyId,
    required String personId,
    required double lat,
    required double lng,
  }) {
    final client = _ref.read(supabaseProvider);
    if (client == null || _channel == null) return;

    _channel!.sendBroadcastMessage(
      event: 'location_move',
      payload: {
        'personId': personId,
        'lat': lat,
        'lng': lng,
        'ts': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }

  /// Throttled write to MemberLocation (last-known persistence).
  /// Called every 30-60s or >50m moved by the map screen.
  Future<void> upsertMyLocation({
    required String familyId,
    required String personId,
    required double lat,
    required double lng,
  }) async {
    final client = _ref.read(supabaseProvider);
    if (client == null) return;

    try {
      await client.from('MemberLocation').upsert({
        'familyId': familyId,
        'personId': personId,
        'userId': client.auth.currentUser!.id,
        'lat': lat,
        'lng': lng,
        'isSharing': true,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('⚠️ upsertMyLocation failed: $e');
    }
  }
}

/// Family-scoped live location provider. Call `start(familyId)` when the
/// map screen mounts, `stop()` when it unmounts.
final liveLocationProvider =
    StateNotifierProvider.autoDispose<LiveLocationNotifier, LiveLocationState>(
  (ref) => LiveLocationNotifier(ref),
);
