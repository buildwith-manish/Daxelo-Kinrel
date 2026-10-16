// lib/core/network/realtime_channel_registry.dart
//
// ════════════════════════════════════════════════════════════════════════════
//  DAXELO KINREL — Central Realtime Channel Lifecycle Manager
// ════════════════════════════════════════════════════════════════════════════
//
//  PURPOSE:
//  Tracks every active Realtime channel subscription in the app by a
//  string key. On app background (AppLifecycleState.paused/inactive),
//  unsubscribes all channels to save WebSocket connection costs. On
//  app resume, re-subscribes every channel that was suspended.
//
//  ACTIVE-GAME GRACE PERIOD:
//  Channels flagged as `isLiveGame: true` (Tug of War, Ghost Painter,
//  Stickman Heist, any live-sync multiplayer game) get a 30-second
//  grace period before being unsubscribed on background. This prevents
//  dropping a player mid-match on a brief app-switch (e.g., checking
//  a message then returning). If the app is still backgrounded after
//  30 seconds, the game channel is unsubscribed — the match continues
//  server-side, and the player can reconnect on resume.
//
//  SCREEN-SCOPE:
//  Each screen that creates a channel registers it via
//  `registry.register(key, channel, resubscribe, isLiveGame)` and
//  unregisters it in `dispose()` via `registry.unregister(key)`.
//  This ensures channels don't survive after the user navigates away
//  from the screen that created them, even without app backgrounding.
//
//  This service is the single source of truth for "which channels
//  are open right now". Supabase bills concurrent Realtime connections;
//  this registry minimizes that cost.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A registered Realtime channel with its resubscribe callback.
class _RegisteredChannel {
  _RegisteredChannel({
    required this.channel,
    required this.resubscribe,
    this.isLiveGame = false,
    // PERF (Phase 3 — realtime leak fix): optional dispose callback
    // that fully evicts the channel from the Supabase client's
    // `channels` list. When provided, the registry calls this
    // INSTEAD OF (or in addition to) `channel.unsubscribe()` so the
    // channel's Hook/Push/Binding objects are released. Callers
    // that have a SupabaseClient ref should pass
    // `() => client.removeChannel(channel)`.
    this.disposeChannel,
  });

  RealtimeChannel? channel;
  final VoidCallback resubscribe;
  final bool isLiveGame;
  final void Function(RealtimeChannel)? disposeChannel;
  bool isSuspended = false;
}

/// Central registry for all Realtime channel subscriptions.
///
/// Usage:
/// 1. Call `register(key, channel, resubscribe, isLiveGame)` when
///    subscribing to a channel.
/// 2. Call `unregister(key)` when the screen that owns the channel
///    is disposed.
/// 3. Call `suspendAll()` on app background.
/// 4. Call `resumeAll()` on app resume.
class RealtimeChannelRegistry {
  final Map<String, _RegisteredChannel> _channels = {};

  // Timer for the live-game grace period.
  Timer? _gracePeriodTimer;
  static const Duration _gracePeriod = Duration(seconds: 30);

  /// Number of currently active (non-suspended) channels.
  int get activeCount =>
      _channels.values.where((c) => !c.isSuspended).length;

  /// Number of currently suspended channels.
  int get suspendedCount =>
      _channels.values.where((c) => c.isSuspended).length;

  /// Total registered channels (active + suspended).
  int get totalCount => _channels.length;

  /// Register a channel. [key] must be unique per channel.
  /// [resubscribe] is called on app resume to re-create the channel
  /// after it was suspended.
  /// [isLiveGame] if true, the channel gets a 30s grace period on
  /// background before being suspended (prevents dropping a player
  /// mid-match on a brief app-switch).
  ///
  /// PERF (Phase 3 — realtime leak fix): [disposeChannel] is an
  /// optional callback that fully evicts the channel from the
  /// Supabase client's `channels` list. When provided, the registry
  /// calls `disposeChannel!(channel)` INSTEAD of the default
  /// `channel.unsubscribe()` on unregister / suspend / dispose — so
  /// the channel's Hook/Push/Binding objects are released. Callers
  /// that have a SupabaseClient ref should pass
  /// `disposeChannel: (ch) => client.removeChannel(ch)`.
  void register(
    String key,
    RealtimeChannel channel,
    VoidCallback resubscribe, {
    bool isLiveGame = false,
    void Function(RealtimeChannel)? disposeChannel,
  }) {
    // If a channel with this key already exists (e.g., screen re-creating
    // a channel), unsubscribe the old one first to prevent leaks.
    final existing = _channels[key];
    if (existing != null && existing.channel != null) {
      _disposeChannelEntry(existing);
    }
    _channels[key] = _RegisteredChannel(
      channel: channel,
      resubscribe: resubscribe,
      isLiveGame: isLiveGame,
      disposeChannel: disposeChannel,
    );
    _logActiveChannelCount('register:$key');
  }

  /// Unregister a channel and unsubscribe it immediately.
  /// Called from screen `dispose()` to ensure the channel doesn't
  /// survive after the user navigates away.
  void unregister(String key) {
    final entry = _channels.remove(key);
    if (entry?.channel != null) {
      _disposeChannelEntry(entry!);
    }
    _logActiveChannelCount('unregister:$key');
  }

  /// Suspend all channels on app background.
  ///
  /// Non-game channels are suspended immediately. Game channels
  /// get a 30-second grace period — if the app is still backgrounded
  /// after 30s, they're suspended too. This prevents dropping a
  /// player mid-match on a brief app-switch.
  void suspendAll() {
    // Cancel any previous grace-period timer (e.g., if the app was
    // briefly resumed then backgrounded again).
    _gracePeriodTimer?.cancel();

    // Suspend all non-game channels immediately.
    for (final entry in _channels.values) {
      if (entry.isSuspended) continue;
      if (!entry.isLiveGame) {
        _suspendChannel(entry);
      }
    }

    // For game channels, start the grace period timer.
    final hasGameChannels =
        _channels.values.any((c) => c.isLiveGame && !c.isSuspended);
    if (hasGameChannels) {
      _gracePeriodTimer = Timer(_gracePeriod, () {
        for (final entry in _channels.values) {
          if (entry.isSuspended) continue;
          if (entry.isLiveGame) {
            _suspendChannel(entry);
          }
        }
      });
    }
  }

  void _suspendChannel(_RegisteredChannel entry) {
    if (entry.channel != null) {
      _disposeChannelEntry(entry);
    }
    entry.channel = null;
    entry.isSuspended = true;
  }

  /// PERF (Phase 3 — realtime leak fix): disposes a single channel
  /// entry. When [entry.disposeChannel] is provided (production
  /// callers that pass a SupabaseClient-backed `removeChannel`), it
  /// is called INSTEAD of the default `channel.unsubscribe()` — so
  /// the channel is fully evicted from the Supabase client's
  /// `channels` list (freeing its Hook/Push/Binding objects). Falls
  /// back to `channel.unsubscribe()` for legacy callers that don't
  /// pass a dispose callback.
  void _disposeChannelEntry(_RegisteredChannel entry) {
    final ch = entry.channel;
    if (ch == null) return;
    try {
      if (entry.disposeChannel != null) {
        entry.disposeChannel!(ch);
      } else {
        ch.unsubscribe();
      }
    } catch (_) {}
  }

  /// Resume all suspended channels on app resume.
  /// Calls the stored `resubscribe` callback for each suspended
  /// channel to re-create the channel and re-subscribe.
  void resumeAll() {
    _gracePeriodTimer?.cancel();
    _gracePeriodTimer = null;

    for (final entry in _channels.values) {
      if (!entry.isSuspended) continue;
      try {
        entry.resubscribe();
        entry.isSuspended = false;
      } catch (e) {
        debugPrint('[RealtimeRegistry] resume $e');
      }
    }
  }

  /// Dispose all channels and clear the registry.
  void dispose() {
    _gracePeriodTimer?.cancel();
    for (final entry in _channels.values) {
      if (entry.channel != null) {
        _disposeChannelEntry(entry);
      }
    }
    _channels.clear();
    _logActiveChannelCount('dispose');
  }

  /// PERF (Phase 3 — Task 6): debug-only log of active realtime
  /// channel count. Prints whenever a channel is registered or
  /// unregistered so the developer can verify the count stays small
  /// in DevTools. In release builds this is a no-op (kDebugMode is
  /// false).
  void _logActiveChannelCount(String operation) {
    if (!kDebugMode) return;
    debugPrint(
      '[RealtimeRegistry] channels=${_channels.length} '
      '(after $operation) — expected to stay small',
    );
  }
}

/// Riverpod provider for the RealtimeChannelRegistry singleton.
///
/// PERF (Phase 3 — realtime leak fix): the registry now registers a
/// `ref.onDispose` callback so when the provider is disposed (e.g.
/// on app shutdown / Riverpod container disposal), the registry's
/// `dispose()` is called — fully evicting every registered channel
/// from the Supabase client's `channels` list. The previous provider
/// had NO `ref.onDispose`, so the registry's channels leaked on
/// container disposal.
final realtimeChannelRegistryProvider = Provider<RealtimeChannelRegistry>(
  (ref) {
    final registry = RealtimeChannelRegistry();
    ref.onDispose(registry.dispose);
    return registry;
  },
);
