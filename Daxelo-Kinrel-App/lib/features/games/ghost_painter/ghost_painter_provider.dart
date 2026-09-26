// lib/features/games/ghost_painter/ghost_painter_provider.dart
//
// Ghost Painter — Riverpod state + Supabase Realtime + broadcast-first strokes.
//
// Architecture (perf/smoothness-pass-2 Step 2 — migrated from per-stroke
// DB inserts to Realtime Broadcast, mirroring the stickman_heist
// migration pattern from commit aa46b5a9):
//
//   • ghost_painter_rounds + ghost_painter_guesses remain DB-backed
//     for durable state (round lifecycle, guess records). These are
//     low-volume (one per round / one per guesser) and not hot-path.
//
//   • HOT PATH (active drawing, pure websocket — NO DB):
//       DRAWER client:
//         • On each onPanEnd, accumulates the new stroke into the
//           local `_pendingStrokes` buffer and broadcasts it
//           immediately via `sendBroadcastMessage(event: 'stroke',
//           payload: {points, sequenceOrder, ts})` — pure websocket.
//         • The drawer's own canvas already renders from the local
//           `_allStrokes` on the draw screen, so no local round-trip
//           is needed for self-render.
//         • On `transitionToGuessing()` (drawer taps Done), the
//           drawer makes ONE batch INSERT of all accumulated strokes
//           to `ghost_painter_strokes` for replay/history. This is
//           the ONLY DB write in the hot path — one call per round,
//           not one per stroke.
//         • Responds to `request_state` handshake with a one-time
//           snapshot of all accumulated strokes so late-joiners /
//           reconnecting spectators render immediately.
//       NON-DRAWER clients (guessers + spectators):
//         • Receive strokes via `onBroadcast(event: 'stroke')` and
//           append to `state.strokes` for the canvas to render.
//         • On subscribe, send `request_state` to ask the drawer for
//           a one-time snapshot (no waiting for the next stroke).
//
//   • DURABLE DB calls (event-driven, NOT per-stroke):
//       • startRound — one INSERT to ghost_painter_rounds (one-time
//         per round).
//       • transitionToGuessing — one UPDATE on ghost_painter_rounds
//         + ONE batch INSERT to ghost_painter_strokes (the durable
//         stroke history — one batch per round, not one per stroke).
//       • submitGuess — one INSERT to ghost_painter_guesses (one per
//         guesser per round, by constraint).
//       • endRound — one UPDATE on ghost_painter_rounds.
//
//   • The `1s _countdownTimer` (line 336) is a local tick that drives
//     the countdown UI; the round's `endsAt` is set ONCE at startRound
//     and the timer just decrements locally. LEFT ALONE per user
//     instruction.
//
//   • The `_roundWatchChannel` (Postgres Changes on
//     `ghost_painter_rounds` INSERT) is retained — it notifies
//     clients when a new round starts in their family (low-volume,
//     one-time per round). Not in the hot path.
//
//   • The durable Postgres Changes listener on
//     `ghost_painter_rounds` UPDATE is retained — it delivers the
//     status flip (drawing → guessing → completed) to all clients
//     durably. Not in the hot path.
//
//   • The Postgres Changes listener on `ghost_painter_strokes` INSERT
//     is REMOVED — strokes are now received via Broadcast. The
//     `ghost_painter_strokes` table is still written once at round
//     end for replay/history, but Realtime clients don't need to
//     listen to its INSERTs anymore.
//
//   • The Postgres Changes listener on `ghost_painter_guesses` INSERT
//     is RETAINED — guesses are still durable inserts (one per guesser
//     per round, by constraint), and the volume is low enough that
//     Postgres Changes is fine. Could also be migrated to Broadcast,
//     but that's a separate optimization.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/network/realtime_channel_registry.dart';
import 'ghost_painter_models.dart';

class GhostPainterState {
  const GhostPainterState({
    this.activeRound,
    this.strokes = const [],
    this.guesses = const [],
    this.myGuess,
    this.isLoading = false,
    this.isSubmitting = false,
    this.error,
  });
  final GhostPainterRound? activeRound;
  final List<GhostPainterStroke> strokes;
  final List<GhostPainterGuess> guesses;
  final GhostPainterGuess? myGuess;
  final bool isLoading;
  final bool isSubmitting;
  final String? error;

  bool get hasActiveRound => activeRound != null && activeRound!.isActive;
  bool get hasGuessed => myGuess != null;

  GhostPainterState copyWith({
    GhostPainterRound? activeRound,
    List<GhostPainterStroke>? strokes,
    List<GhostPainterGuess>? guesses,
    GhostPainterGuess? myGuess,
    bool? isLoading,
    bool? isSubmitting,
    String? error,
    bool clearError = false,
  }) => GhostPainterState(
    activeRound: activeRound ?? this.activeRound,
    strokes: strokes ?? this.strokes,
    guesses: guesses ?? this.guesses,
    myGuess: myGuess ?? this.myGuess,
    isLoading: isLoading ?? this.isLoading,
    isSubmitting: isSubmitting ?? this.isSubmitting,
    error: clearError ? null : (error ?? this.error),
  );
}

class GhostPainterNotifier extends StateNotifier<GhostPainterState> {
  GhostPainterNotifier(this._ref, this.familyId) : super(const GhostPainterState(isLoading: true));
  final Ref _ref;
  final String familyId;

  SupabaseClient? get _client => _ref.read(supabaseProvider);
  String? get _myId => _client?.auth.currentUser?.id;
  String get _myName => _client?.auth.currentUser?.userMetadata?['name'] as String? ?? 'Member';

  RealtimeChannel? _channel;
  RealtimeChannel? _roundWatchChannel; // Watches for NEW rounds (when no active round)
  Timer? _countdownTimer;

  // ── Receive-side throttle for stroke broadcasts ────────────────
  // Multiple stroke broadcasts arriving in the same frame are
  // coalesced into a single state emission. Without this, a drawer
  // doing 5 quick onPanEnd strokes in 1 second triggers 5 separate
  // state emissions on every receiver → 5 full canvas repaints of
  // the entire stroke history. We buffer incoming strokes and flush
  // them on the next event-loop turn via Timer.run, so any same-frame
  // broadcasts collapse into one rebuild.
  final List<GhostPainterStroke> _pendingStrokes = [];
  Timer? _strokeFlush;
  bool _disposed = false;

  /// Step 2 — broadcast-first stroke buffer. Drawer accumulates
  /// finished strokes here, broadcasts each immediately via
  /// `sendBroadcastMessage`, and persists them all at once when the
  /// round transitions to 'guessing'.
  final List<GhostPainterStroke> _broadcastStrokes = [];

  /// Cold-start retries: when the app is deep-linked straight onto the
  /// Ghost Painter screen, this notifier can be created BEFORE the
  /// Supabase client/session is wired into Riverpod. Without a retry
  /// the load bails once and the user is stranded on the start screen
  /// even though an active round exists.
  int _loadRetries = 0;

  Future<void> load() async {
    final client = _client;
    if (client == null) {
      if (_loadRetries < 6) {
        _loadRetries++;
        Future.delayed(const Duration(milliseconds: 900), () {
          if (mounted && state.activeRound == null) load();
        });
      } else {
        state = state.copyWith(isLoading: false, error: 'Not signed in');
      }
      return;
    }
    _loadRetries = 0;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      // Fetch active round
      final roundResp = await client
          .from('ghost_painter_rounds')
          .select()
          .eq('familyId', familyId)
          .inFilter('status', ['drawing', 'guessing'])
          .order('startedAt', ascending: false)
          .limit(1);
      if (roundResp.isEmpty) {
        state = const GhostPainterState(isLoading: false);
        // Subscribe to round-watch so the card updates live when someone
        // else in the family starts a round
        _subscribeToRoundWatch();
        return;
      }
      final round = GhostPainterRound.fromJson(roundResp.first);
      // Tier 1 #4 (Phase 0 verification) — parallelize the strokes and
      // guesses fetches (they both depend on round.id but not on each
      // other's results). Using Future.wait to reduce from 2 sequential
      // round-trips to 1 concurrent batch.
      final strokesFuture = client
          .from('ghost_painter_strokes')
          .select()
          .eq('roundId', round.id)
          .order('sequenceOrder', ascending: true);
      final guessesFuture = client
          .from('ghost_painter_guesses')
          .select()
          .eq('roundId', round.id)
          .order('guessedAt', ascending: true);
      final results = await Future.wait([strokesFuture, guessesFuture]);
      final strokes = results[0].map((s) => GhostPainterStroke.fromJson(s)).toList();
      // Step 2: if I'm the drawer and the round is still 'drawing',
      // re-seed my local broadcast accumulator from any strokes already
      // persisted (handles the reconnect-mid-draw case where I may
      // have already transitioned once and resumed).
      final myId = _myId;
      if (round.status == 'drawing' && round.drawerPersonId == myId) {
        _broadcastStrokes
          ..clear()
          ..addAll(strokes);
      }
      final guesses = results[1].map((g) => GhostPainterGuess.fromJson(g)).toList();
      // Latest guess (guesses are ordered by guessedAt ascending) — the
      // guess screen keeps the input visible until the latest guess is
      // correct, so this must not pin to the first-ever guess.
      final myGuess = guesses.where((g) => g.userId == myId).lastOrNull;
      state = GhostPainterState(activeRound: round, strokes: strokes, guesses: guesses, myGuess: myGuess, isLoading: false);
      _subscribeToRealtime(round.id);
      _startCountdownIfNeeded(round);
    } catch (e) {
      debugPrint('⚠️ GhostPainter load error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
    }
  }

  /// Subscribe to new rounds being created in this family
  /// (fires when another family member starts a round while we have none)
  void _subscribeToRoundWatch() {
    _roundWatchChannel?.unsubscribe();
    final client = _client;
    if (client == null) return;
    _roundWatchChannel = client.channel('ghost_painter_round_watch:$familyId')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'ghost_painter_rounds',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'familyId', value: familyId),
        callback: (payload) {
          // A new round was inserted — reload to pick it up
          debugPrint('🎲 GhostPainter: New round detected via Realtime, reloading...');
          load();
        },
      )
      .subscribe();
  }

  void _subscribeToRealtime(String roundId) {
    _channel?.unsubscribe();
    final client = _client;
    if (client == null) return;
    final myId = _myId;
    final isDrawer = state.activeRound?.drawerPersonId == myId;
    _channel = client.channel('ghost_painter:$roundId')
      // ── HOT-PATH BROADCAST LISTENERS (pure websocket, no DB) ──
      // These replace the previous per-stroke DB INSERT + Postgres
      // Changes pattern. Strokes now flow through the drawer's
      // broadcast only.
      .onBroadcast(
        event: 'stroke',
        callback: (payload) {
          // Non-drawer clients receive a new stroke from the drawer
          // and append to state.strokes for rendering. The drawer
          // ignores — drawer renders from its own local _allStrokes
          // on the draw screen, and accumulates into _broadcastStrokes
          // for the round-end persist.
          if (isDrawer) return;
          try {
            final map = Map<String, dynamic>.from(payload as Map);
            final stroke = _strokeFromBroadcast(map, roundId);
            if (stroke != null) {
              // Coalesce: buffer the stroke and flush on the next
              // event-loop turn. Multiple same-frame stroke broadcasts
              // collapse into one state emission + one canvas repaint.
              _pendingStrokes.add(stroke);
              _strokeFlush ??= Timer.run(_flushStrokes);
            }
          } catch (e) {
            debugPrint('[GhostPainter] onBroadcast(stroke) parse error: $e');
          }
        },
      )
      .onBroadcast(
        event: 'request_state',
        callback: (payload) {
          // A non-drawer (or spectator, or reconnecting player) joined
          // and is asking for a one-time snapshot of all accumulated
          // strokes so they can render immediately instead of waiting
          // for the next onPanEnd broadcast. Only drawer responds.
          if (!isDrawer) return;
          final channel = _channel;
          if (channel == null) return;
          try {
            // Send a 'state_snapshot' broadcast with the full stroke list.
            // Payload shape mirrors what the load() function returns
            // from the DB so the receiver can reuse fromJson.
            channel.sendBroadcastMessage(
              event: 'state_snapshot',
              payload: {
                'strokes': _broadcastStrokes
                    .map((s) => {
                          'id': s.id,
                          'roundId': s.roundId,
                          'strokeData': s.points.map((p) => p.toJson()).toList(),
                          'sequenceOrder': s.sequenceOrder,
                        })
                    .toList(),
                'ts': DateTime.now().toIso8601String(),
              },
            );
          } catch (e) {
            debugPrint('[GhostPainter] request_state response error: $e');
          }
        },
      )
      .onBroadcast(
        event: 'state_snapshot',
        callback: (payload) {
          // Non-drawer receives the full stroke list as a one-time
          // snapshot from the drawer (in response to its own
          // 'request_state'). Replace state.strokes entirely with the
          // snapshot so we don't double-add strokes that arrived both
          // via the snapshot AND via subsequent 'stroke' broadcasts.
          if (isDrawer) return;
          try {
            final map = Map<String, dynamic>.from(payload as Map);
            final strokesList = map['strokes'];
            if (strokesList is! List) return;
            final snapshots = <GhostPainterStroke>[];
            for (final item in strokesList) {
              if (item is Map) {
                final stroke = _strokeFromBroadcast(
                  Map<String, dynamic>.from(item),
                  roundId,
                );
                if (stroke != null) snapshots.add(stroke);
              }
            }
            // Sort by sequenceOrder so the canvas renders in order.
            snapshots.sort((a, b) => a.sequenceOrder.compareTo(b.sequenceOrder));
            // Dedupe by stroke id (in case a late 'stroke' broadcast
            // arrived before the snapshot response).
            final existingIds = state.strokes.map((s) => s.id).toSet();
            final merged = <GhostPainterStroke>[...state.strokes];
            for (final s in snapshots) {
              if (!existingIds.contains(s.id)) {
                merged.add(s);
              }
            }
            merged.sort((a, b) => a.sequenceOrder.compareTo(b.sequenceOrder));
            state = state.copyWith(strokes: merged);
          } catch (e) {
            debugPrint('[GhostPainter] onBroadcast(state_snapshot) parse error: $e');
          }
        },
      )
      // ── DURABLE POSTGRES CHANGES LISTENERS ──
      // Guesses remain Postgres-backed (low-volume, one per guesser
      // per round by constraint).
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'ghost_painter_guesses',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'roundId', value: roundId),
        callback: (payload) {
          final guess = GhostPainterGuess.fromJson(payload.newRecord);
          state = state.copyWith(guesses: [...state.guesses, guess]);
        },
      )
      // Round status flip (drawing → guessing → completed) is durable
      // and must survive disconnect/reload.
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'ghost_painter_rounds',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: roundId),
        callback: (payload) {
          final round = GhostPainterRound.fromJson(payload.newRecord);
          state = state.copyWith(activeRound: round);
          // The round left the drawing phase (guessed correctly / ended /
          // someone else transitioned it) — stop the local countdown so the
          // timer can never downgrade a completed round back to 'guessing'.
          if (round.status != 'drawing') {
            _countdownTimer?.cancel();
          }
        },
      )
      .subscribe();

    // Tier 1 #1 — register with the central registry. Live game —
    // 30s grace period on background.
    final registry = _ref.read(realtimeChannelRegistryProvider);
    registry.register(
      'ghost_painter:$roundId',
      _channel!,
      () => _subscribeToRealtime(roundId),
      isLiveGame: true,
    );

    // Spectator / reconnecting-player handshake: ask the drawer for a
    // one-time snapshot so we render all strokes that were drawn BEFORE
    // we joined. Small delay so the drawer's listener is wired first.
    if (!isDrawer) {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (!mounted || _channel == null) return;
        try {
          unawaited(_channel!.sendBroadcastMessage(
            event: 'request_state',
            payload: {'userId': myId, 'ts': DateTime.now().toIso8601String()},
          ));
        } catch (e) {
          debugPrint('[GhostPainter] request_state send error: $e');
        }
      });
    }
  }

  /// Build a GhostPainterStroke from a broadcast payload. Generates a
  /// stable-ish id from the sequenceOrder so dedupe-by-id works for
  /// the state_snapshot path.
  GhostPainterStroke? _strokeFromBroadcast(Map<String, dynamic> map, String roundId) {
    try {
      final rawPoints = map['strokeData'] ?? map['points'];
      if (rawPoints is! List) return null;
      final points = rawPoints
          .map((p) => OffsetPoint.fromJson(Map<String, dynamic>.from(p as Map)))
          .toList();
      final sequenceOrder = (map['sequenceOrder'] as num?)?.toInt() ?? 0;
      final id = map['id'] as String? ??
          'bc_${roundId}_$sequenceOrder'; // stable id for dedupe
      return GhostPainterStroke(
        id: id,
        roundId: roundId,
        points: points,
        sequenceOrder: sequenceOrder,
      );
    } catch (_) {
      return null;
    }
  }

  /// Start a new round — caller is the drawer
  Future<bool> startRound(String drawerPersonId, String drawerPersonName) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) return false;
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final prompt = ghostPainterPrompts[DateTime.now().millisecondsSinceEpoch % ghostPainterPrompts.length];
      final endsAt = DateTime.now().add(const Duration(seconds: 90));
      final resp = await client.from('ghost_painter_rounds').insert({
        'familyId': familyId,
        'drawerPersonId': drawerPersonId,
        'drawerPersonName': drawerPersonName,
        'promptWord': prompt,
        'status': 'drawing',
        'endsAt': endsAt.toIso8601String(),
      }).select().single();
      final round = GhostPainterRound.fromJson(resp);
      // Step 2: drawer starts with an empty broadcast accumulator.
      _broadcastStrokes.clear();
      state = GhostPainterState(activeRound: round, isLoading: false);
      _subscribeToRealtime(round.id);
      return true;
    } catch (e) {
      state = state.copyWith(isSubmitting: false, error: '$e');
      return false;
    }
  }

  /// Step 2 — stroke send via Realtime Broadcast (pure websocket, NO DB).
  /// Called from the draw screen on every onPanEnd. Accumulates the
  /// stroke locally for the round-end persist AND broadcasts it to all
  /// non-drawer clients immediately so their canvas renders in real
  /// time. Persists to Postgres only when the round transitions to
  /// 'guessing' (one batch INSERT per round, not per stroke).
  void queueStroke(List<OffsetPoint> points, int sequenceOrder) {
    if (points.isEmpty) return;
    // Only the round's drawer may author strokes — a guesser (or a
    // stale screen) can never write ink into someone else's round.
    final round = state.activeRound;
    final myId = _myId;
    if (round == null || myId == null || round.drawerPersonId != myId) return;

    // 1. Accumulate locally for the round-end batch INSERT.
    final stroke = GhostPainterStroke(
      id: 'bc_${round.id}_$sequenceOrder',
      roundId: round.id,
      points: points,
      sequenceOrder: sequenceOrder,
    );
    _broadcastStrokes.add(stroke);

    // 2. Broadcast to non-drawer clients (pure websocket, NO DB).
    final channel = _channel;
    if (channel != null) {
      try {
        unawaited(channel.sendBroadcastMessage(
          event: 'stroke',
          payload: {
            'id': stroke.id,
            'strokeData': points.map((p) => p.toJson()).toList(),
            'sequenceOrder': sequenceOrder,
            'ts': DateTime.now().toIso8601String(),
          },
        ));
      } catch (e) {
        debugPrint('[GhostPainter] queueStroke broadcast error: $e');
      }
    }
  }

  /// Step 2 — ONE batch INSERT of all accumulated strokes to
  /// `ghost_painter_strokes` for replay / history. Called from
  /// `transitionToGuessing()` (the only caller). One DB write per
  /// round, not one per stroke.
  Future<void> _persistAllStrokes(String roundId) async {
    final client = _client;
    if (client == null) return;
    if (_broadcastStrokes.isEmpty) return;
    final batch = _broadcastStrokes
        .map((s) => {
              'roundId': roundId,
              // Insert as a native jsonb ARRAY — jsonEncode would
              // store a string, which the readers (and SQL) then
              // have to unwrap.
              'strokeData': s.points.map((p) => p.toJson()).toList(),
              'sequenceOrder': s.sequenceOrder,
            })
        .toList();
    try {
      await client.from('ghost_painter_strokes').insert(batch);
      // Mirror the persisted strokes into state.strokes so any
      // future reload (e.g. via a re-fetch) sees the same set. We
      // use the locally-tracked ids to avoid duplicates if the
      // Postgres Changes listener ever fires (it won't anymore —
      // we removed the stroke INSERT listener — but defensive).
      final existingIds = state.strokes.map((s) => s.id).toSet();
      final merged = <GhostPainterStroke>[...state.strokes];
      for (final s in _broadcastStrokes) {
        if (!existingIds.contains(s.id)) {
          merged.add(s);
        }
      }
      merged.sort((a, b) => a.sequenceOrder.compareTo(b.sequenceOrder));
      state = state.copyWith(strokes: merged);
    } catch (e) {
      debugPrint('⚠️ GhostPainter stroke persist error: $e');
    }
  }

  /// Submit a guess
  Future<bool> submitGuess(String text) async {
    final client = _client;
    final myId = _myId;
    final roundId = state.activeRound?.id;
    if (client == null || myId == null || roundId == null) return false;
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final promptWord = state.activeRound!.promptWord.trim().toLowerCase();
      final guessLower = text.trim().toLowerCase();
      // Exact match only — substring matching was exploitable (guessing
      // "e" won "elephant").
      final isCorrect = guessLower == promptWord;
      final resp = await client.from('ghost_painter_guesses').insert({
        'roundId': roundId,
        'userId': myId,
        'userName': _myName,
        'guessText': text,
        'isCorrect': isCorrect,
      }).select().single();
      final guess = GhostPainterGuess.fromJson(resp);
      state = state.copyWith(myGuess: guess, isSubmitting: false);
      if (isCorrect) {
        // If I'm the drawer (shouldn't happen — drawer can't guess —
        // but defensively) flush strokes first.
        if (_broadcastStrokes.isNotEmpty) {
          await _persistAllStrokes(roundId);
        }
        // Complete the round
        await client.from('ghost_painter_rounds').update({
          'status': 'completed',
          'endsAt': DateTime.now().toIso8601String(),
        }).eq('id', roundId);
      }
      return isCorrect;
    } catch (e) {
      state = state.copyWith(isSubmitting: false, error: '$e');
      return false;
    }
  }

  /// Transition the round from 'drawing' to 'guessing' (drawer is done).
  /// Updates the Supabase row — other family members see this via Realtime.
  /// Guarded: never downgrades a round that already left 'drawing'
  /// (e.g. completed because someone guessed correctly).
  ///
  /// Step 2: now also flushes all accumulated strokes to Postgres as
  /// ONE batch INSERT (the only DB write in the hot path — one call
  /// per round, not one per stroke).
  Future<void> transitionToGuessing() async {
    final client = _client;
    final roundId = state.activeRound?.id;
    if (client == null || roundId == null) return;
    if (state.activeRound?.status != 'drawing') return; // already guessing/completed
    _countdownTimer?.cancel();
    try {
      // Step 2: persist all accumulated strokes BEFORE the status
      // flip so guessers who reload see the full drawing.
      await _persistAllStrokes(roundId);
      await client.from('ghost_painter_rounds').update({
        'status': 'guessing',
      }).eq('id', roundId).eq('status', 'drawing'); // server-side guard too
      // Update local state immediately for responsive UI
      final updatedRound = GhostPainterRound(
        id: state.activeRound!.id,
        familyId: state.activeRound!.familyId,
        drawerPersonId: state.activeRound!.drawerPersonId,
        drawerPersonName: state.activeRound!.drawerPersonName,
        promptWord: state.activeRound!.promptWord,
        status: 'guessing',
        startedAt: state.activeRound!.startedAt,
        endsAt: state.activeRound!.endsAt,
      );
      state = state.copyWith(activeRound: updatedRound);
    } catch (e) {
      debugPrint('⚠️ GhostPainter transitionToGuessing error: $e');
    }
  }

  /// Start a countdown timer that auto-transitions to guessing when time runs out
  void _startCountdownIfNeeded(GhostPainterRound round) {
    _countdownTimer?.cancel();
    if (round.status != 'drawing' || round.endsAt == null) return;
    final now = DateTime.now();
    final remaining = round.endsAt!.difference(now).inSeconds;
    if (remaining <= 0) {
      // Time already expired — transition immediately
      transitionToGuessing();
      return;
    }
    // Tick every second to check for time-expiry transition. The countdown
    // UI itself is now driven by _CountdownRing's own internal Timer (no
    // longer needs a state emission per second), so this timer's only job
    // is to detect when the round ends and trigger transitionToGuessing.
    // Previously this timer did `state = state.copyWith()` (empty copyWith)
    // every second — that re-allocated state and rebuilt the entire draw
    // screen Column 60+ times per match even though nothing meaningful
    // changed. Now state stays still unless the round actually ends.
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      // The round may have moved on (completed via a correct guess, or
      // transitioned by another device) — the timer must respect that.
      if (state.activeRound?.status != 'drawing') {
        timer.cancel();
        return;
      }
      final elapsed = DateTime.now().difference(round.startedAt).inSeconds;
      final totalDuration = round.endsAt!.difference(round.startedAt).inSeconds;
      final remainingNow = totalDuration - elapsed;
      if (remainingNow <= 0) {
        timer.cancel();
        transitionToGuessing();
        return;
      }
      // No state emission here — _CountdownRing ticks itself.
    });
  }

  /// Get remaining seconds for the current round's countdown
  int get remainingSeconds {
    final round = state.activeRound;
    if (round == null || round.endsAt == null) return 0;
    final remaining = round.endsAt!.difference(DateTime.now()).inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  /// End the round early (drawer gives up or time runs out)
  Future<void> endRound() async {
    final client = _client;
    final roundId = state.activeRound?.id;
    if (client == null || roundId == null) return;
    try {
      // Step 2: flush strokes before completing.
      if (_broadcastStrokes.isNotEmpty) {
        await _persistAllStrokes(roundId);
      }
      await client.from('ghost_painter_rounds').update({
        'status': 'completed',
        'endsAt': DateTime.now().toIso8601String(),
      }).eq('id', roundId);
    } catch (_) {}
  }

  /// Flush all buffered strokes as a single state emission. Called
  /// via `Timer.run` from the stroke listener — by the time this
  /// fires, any same-frame stroke broadcasts have already been
  /// accumulated into `_pendingStrokes`.
  void _flushStrokes() {
    _strokeFlush = null;
    if (_pendingStrokes.isEmpty || _disposed) return;
    final batch = List<GhostPainterStroke>.from(_pendingStrokes);
    _pendingStrokes.clear();
    state = state.copyWith(strokes: [...state.strokes, ...batch]);
  }

  @override
  void dispose() {
    _disposed = true;
    final roundId = state.activeRound?.id;
    if (roundId != null) {
      final registry = _ref.read(realtimeChannelRegistryProvider);
      registry.unregister('ghost_painter:$roundId');
    }
    _channel?.unsubscribe();
    _roundWatchChannel?.unsubscribe();
    _countdownTimer?.cancel();
    _strokeFlush?.cancel();
    super.dispose();
  }
}

final ghostPainterProvider =
    StateNotifierProvider.autoDispose.family<GhostPainterNotifier, GhostPainterState, String>(
  (ref, familyId) => GhostPainterNotifier(ref, familyId),
);
