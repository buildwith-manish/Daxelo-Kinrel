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
  });

  RealtimeChannel? channel;
  final VoidCallback resubscribe;
  final bool isLiveGame;
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
  void register(
    String key,
    RealtimeChannel channel,
    VoidCallback resubscribe, {
    bool isLiveGame = false,
  }) {
    // If a channel with this key already exists (e.g., screen re-creating
    // a channel), unsubscribe the old one first to prevent leaks.
    final existing = _channels[key];
    if (existing != null && existing.channel != null) {
      try {
        existing.channel!.unsubscribe();
      } catch (_) {}
    }
    _channels[key] = _RegisteredChannel(
      channel: channel,
      resubscribe: resubscribe,
      isLiveGame: isLiveGame,
    );
  }

  /// Unregister a channel and unsubscribe it immediately.
  /// Called from screen `dispose()` to ensure the channel doesn't
  /// survive after the user navigates away.
  void unregister(String key) {
    final entry = _channels.remove(key);
    if (entry?.channel != null) {
      try {
        entry!.channel!.unsubscribe();
      } catch (_) {}
    }
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
      try {
        entry.channel!.unsubscribe();
      } catch (_) {}
    }
    entry.channel = null;
    entry.isSuspended = true;
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
        try {
          entry.channel!.unsubscribe();
        } catch (_) {}
      }
    }
    _channels.clear();
  }
}

/// Riverpod provider for the RealtimeChannelRegistry singleton.
final realtimeChannelRegistryProvider = Provider<RealtimeChannelRegistry>(
  (ref) => RealtimeChannelRegistry(),
);
