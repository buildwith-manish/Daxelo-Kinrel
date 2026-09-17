// lib/features/games/shared/widgets/board_game_room_lobby.dart
//
// BoardGameRoomLobbyScreen — the shared "Create Room" lobby used by the
// 4 board games (Chess, Checkers, Carrom, Tic-Tac-Toe).
//
// It REPLACES the old ChallengeLobbyScreen ("Select Opponent" first,
// then create). Per the product decision, every multiplayer game now
// follows the SAME modern flow:
//
//   1. The user opens a game and sees a single "Create Room" button —
//      no opponent picking, no extra decisions up front.
//   2. Tapping it creates the room IMMEDIATELY (status 'waiting', the
//      creator attached as host / White / One / X) and lands the user
//      in the shared waiting room.
//   3. From the waiting room the host invites family members (one-tap
//      invites or the room code). The FIRST member to join takes the
//      opponent slot automatically — no manual team/side selection.
//   4. Both players ready up; the host taps Start Match; everyone is
//      navigated to the board.
//
// The waiting room renders the same TemporaryLobbyView every other
// multiplayer game uses (only the player roster scrolls; the Family
// Members invite card, lobby chat, Ready button and Close Room stay
// pinned below it), so the experience is consistent across the app.
//
// The roster comes from the shared `game_participants` table (via
// [boardRoomParticipantsProvider]) — board games keep their players in
// inline columns on the game row (playerWhite/playerBlack, …), so the
// room framework's participant rows are the single realtime roster
// source for the lobby.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../shared/widgets/dk_components.dart';
import '../../game_motion_tokens.dart';
import '../models/game_invite.dart' show GameType;
import '../multiplayer/room_state.dart' show RoomParticipant;
import '../services/temporary_room_service.dart';
import 'invite_family_sheet.dart';
import 'lobby_join_handler.dart';
import 'lobby_kit/lobby_kit.dart';
import 'room_lifecycle_listener.dart';
import 'temporary_lobby_view.dart';

// ═══════════════════════════════════════════════════════════════════
// Room roster — game_participants, shared by the 4 board games
// ═══════════════════════════════════════════════════════════════════

/// Roster state for one board-game room.
class BoardRoomParticipantsState {
  const BoardRoomParticipantsState({
    this.participants = const [],
    this.isLoading = false,
  });

  final List<RoomParticipant> participants;
  final bool isLoading;

  BoardRoomParticipantsState copyWith({
    List<RoomParticipant>? participants,
    bool? isLoading,
  }) =>
      BoardRoomParticipantsState(
        participants: participants ?? this.participants,
        isLoading: isLoading ?? this.isLoading,
      );
}

/// Provider key — one room roster per (gameTable, gameId).
typedef BoardRoomKey = ({String gameTable, String gameId});

/// Realtime roster for a board-game waiting room.
///
/// • Initial fetch: game_participants rows for the room (leftAt NULL,
///   ordered by joinedAt — the actual join order).
/// • Live sync: Supabase Realtime INSERT/UPDATE/DELETE on
///   game_participants filtered to this gameId (the callback re-checks
///   gameTable because the filter column alone is not unique).
/// • setReady: the shared 4-arg fn_set_player_ready RPC (updates
///   readyAt on the participant row + posts a ready/not_ready lobby
///   event). The HOST never calls this — hosts are always ready.
class BoardRoomParticipantsNotifier
    extends StateNotifier<BoardRoomParticipantsState> {
  BoardRoomParticipantsNotifier(this._ref, this._key)
      : super(const BoardRoomParticipantsState(isLoading: true)) {
    _init();
  }

  final Ref _ref;
  final BoardRoomKey _key;

  RealtimeChannel? _channel;

  SupabaseClient? get _client => _ref.read(supabaseProvider);
  String? get _myId => _client?.auth.currentUser?.id;

  Future<void> _init() async {
    await _fetch();
    _subscribe();
  }

  Future<void> _fetch() async {
    final client = _client;
    if (client == null) return;
    try {
      final rows = await client
          .from('game_participants')
          .select()
          .eq('gameTable', _key.gameTable)
          .eq('gameId', _key.gameId)
          .isFilter('leftAt', null)
          .order('joinedAt', ascending: true);
      final participants = rows
          .map((r) => RoomParticipant.fromJson(
              Map<String, dynamic>.from(r as Map)))
          .toList()
        ..sort(_byJoinedAt);
      state = state.copyWith(participants: participants, isLoading: false);
    } catch (e) {
      debugPrint('[BoardRoom] participants fetch error: $e');
      state = state.copyWith(isLoading: false);
    }
  }

  void _subscribe() {
    final client = _client;
    if (client == null) return;
    _channel?.unsubscribe();
    _channel = client
        .channel('board_room:${_key.gameTable}:${_key.gameId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'game_participants',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: _key.gameId,
          ),
          callback: (payload) => _upsert(
              Map<String, dynamic>.from(payload.newRecord)),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'game_participants',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: _key.gameId,
          ),
          callback: (payload) {
            final row = Map<String, dynamic>.from(payload.newRecord);
            if (row['gameTable'] != _key.gameTable) return;
            if (row['leftAt'] != null) {
              _remove(row['userId'] as String? ?? '');
            } else {
              _upsert(row);
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'game_participants',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: _key.gameId,
          ),
          callback: (payload) {
            final old =
                Map<String, dynamic>.from(payload.oldRecord);
            if (old['gameTable'] != _key.gameTable) return;
            _remove(old['userId'] as String? ?? '');
          },
        )
        .subscribe();
  }

  void _upsert(Map<String, dynamic> row) {
    if (row['gameTable'] != _key.gameTable) return;
    if (row['leftAt'] != null) return;
    final participant = RoomParticipant.fromJson(row);
    final next = [...state.participants];
    final i = next.indexWhere((p) => p.userId == participant.userId);
    if (i >= 0) {
      next[i] = participant;
    } else {
      next.add(participant);
    }
    next.sort(_byJoinedAt);
    state = state.copyWith(participants: next);
  }

  void _remove(String userId) {
    state = state.copyWith(
      participants:
          state.participants.where((p) => p.userId != userId).toList(),
    );
  }

  int _byJoinedAt(RoomParticipant a, RoomParticipant b) {
    final ja = a.joinedAt;
    final jb = b.joinedAt;
    if (ja == null && jb == null) return 0;
    if (ja == null) return 1;
    if (jb == null) return -1;
    return ja.compareTo(jb);
  }

  /// Toggle the local user's ready flag (non-hosts only — the host is
  /// always ready by definition of the room framework).
  Future<void> setReady(bool ready) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) return;
    try {
      await client.rpc('fn_set_player_ready', params: {
        'p_game_table': _key.gameTable,
        'p_game_id': _key.gameId,
        'p_user_id': myId,
        'p_ready': ready,
      });
      // Optimistic patch — realtime will confirm.
      final next = state.participants
          .map((p) => p.userId == myId
              ? p.copyWith(
                  readyAt: ready ? DateTime.now() : null,
                  clearReadyAt: !ready,
                )
              : p)
          .toList();
      state = state.copyWith(participants: next);
    } catch (e) {
      debugPrint('[BoardRoom] setReady error: $e');
    }
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _channel = null;
    super.dispose();
  }
}

/// Roster provider — auto-disposes (and unsubscribes) when the lobby
/// screen is replaced by the board route.
final boardRoomParticipantsProvider = StateNotifierProvider.autoDispose
    .family<BoardRoomParticipantsNotifier, BoardRoomParticipantsState,
        BoardRoomKey>(
  (ref, key) => BoardRoomParticipantsNotifier(ref, key),
);

// ═══════════════════════════════════════════════════════════════════
// Screen + spec
// ═══════════════════════════════════════════════════════════════════

/// A generic snapshot of the game's own provider state — everything
/// the shared screen needs to drive its phases.
class BoardRoomSnapshot {
  const BoardRoomSnapshot({
    this.gameId,
    this.hostUserId,
    this.isWaiting = false,
    this.isInProgress = false,
    this.isCompleted = false,
    this.isLoading = false,
    this.error,
    this.autoCloseDeadline,
  });

  final String? gameId;
  final String? hostUserId;
  final bool isWaiting;
  final bool isInProgress;
  final bool isCompleted;
  final bool isLoading;
  final String? error;
  final DateTime? autoCloseDeadline;
}

/// Everything the shared screen needs to know about one board game.
class BoardGameRoomSpec {
  const BoardGameRoomSpec({
    required this.gameId,
    required this.title,
    required this.tagline,
    required this.gameTable,
    required this.routeSegment,
    required this.gameType,
    required this.maxPlayers,
    required this.rules,
    this.facts,
    this.rulesFootnote,
    this.settings,
    this.waitingRoomNote,
    required this.watchRoom,
    required this.onCreateRoom,
    required this.onJoinRoom,
    required this.onStartMatch,
    required this.onLeaveRoom,
  });

  /// 'chess' — icon + accent color.
  final String gameId;

  /// 'Chess' — hero + app bar title.
  final String title;

  /// Hero tagline.
  final String tagline;

  /// 'chess_games' — Supabase table.
  final String gameTable;

  /// 'chess' — board route segment.
  final String routeSegment;

  final GameType gameType;

  /// Room capacity (2 for every board game).
  final int maxPlayers;

  final List<LobbyFact>? facts;
  final List<LobbyRule> rules;
  final String? rulesFootnote;

  /// Game-specific setup widget (e.g. Tic-Tac-Toe's BEST OF selector).
  final Widget? settings;

  /// Read-only explainer shown in the waiting room (e.g. "You play
  /// White and move first.").
  final String? waitingRoomNote;

  /// Watch the game's own provider → generic room snapshot.
  final BoardRoomSnapshot Function(WidgetRef ref, String familyId)
      watchRoom;

  /// Host: create the room (game row in 'waiting' + host attached).
  /// Returns the new game id, or null on failure.
  final Future<String?> Function(
    WidgetRef ref,
    String familyId, {
    required bool spectatorsEnabled,
  }) onCreateRoom;

  /// Non-host: join the room (take the opponent slot, or spectate once
  /// the match is already running).
  final Future<bool> Function(
          WidgetRef ref, String familyId, String gameId)
      onJoinRoom;

  /// Host: start the match (waiting → in_progress). Returns a user-
  /// readable error message, or null on success.
  final Future<String?> Function(WidgetRef ref, String familyId)
      onStartMatch;

  /// Leave / close the room from the waiting lobby.
  final Future<void> Function(WidgetRef ref, String familyId)
      onLeaveRoom;
}

/// The shared Create Room lobby screen for the board games.
class BoardGameRoomLobbyScreen extends ConsumerStatefulWidget {
  const BoardGameRoomLobbyScreen({
    super.key,
    required this.familyId,
    required this.spec,
  });

  final String familyId;
  final BoardGameRoomSpec spec;

  @override
  ConsumerState<BoardGameRoomLobbyScreen> createState() =>
      _BoardGameRoomLobbyScreenState();
}

class _BoardGameRoomLobbyScreenState
    extends ConsumerState<BoardGameRoomLobbyScreen> {
  bool _spectatorsEnabled = true;
  bool _creating = false;
  bool _didAutoJoin = false;

  /// Snapshot seen by the previous build — drives the one-time
  /// "match started" navigation without needing a provider bridge.
  BoardRoomSnapshot? _lastSnapshot;

  String get _familyId => widget.familyId;
  BoardGameRoomSpec get _spec => widget.spec;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleJoinParam());
  }

  /// Deep-link (`?join=<gameId>`) — invite accept, chat invite card, room
  /// code link and the active-games list all land here. Retries until the
  /// Supabase session is wired (cold-boot deep links can mount this screen
  /// before auth is restored — without the retry the join was silently
  /// dropped and the member landed on the setup screen).
  Future<void> _handleJoinParam() async {
    if (_didAutoJoin || !mounted) return;
    final joinId = GoRouterState.of(context).uri.queryParameters['join'];
    if (joinId == null || joinId.isEmpty) return;
    _didAutoJoin = true;
    joinRoomWhenReady(
      context: context,
      ref: ref,
      onJoin: (id) => _spec.onJoinRoom(ref, _familyId, id),
    );
  }

  Future<void> _createRoom() async {
    setState(() => _creating = true);
    await _spec.onCreateRoom(
      ref,
      _familyId,
      spectatorsEnabled: _spectatorsEnabled,
    );
    if (mounted) setState(() => _creating = false);
    // Stay on this screen — the waiting room takes over.
  }

  Future<void> _startMatch() async {
    final error = await _spec.onStartMatch(ref, _familyId);
    if (!mounted || error == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error),
        backgroundColor: KinrelColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _spec.watchRoom(ref, _familyId);
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isHost = snapshot.hostUserId == myId;

    // ── Navigate to the board the moment the match starts ──────────
    // The game row flips waiting → in_progress via the host's start
    // RPC; every client's realtime subscription re-renders the lobby
    // and lands on the board together.
    final wasInProgress = _lastSnapshot?.isInProgress ?? false;
    final startTarget =
        snapshot.isInProgress && !wasInProgress ? snapshot.gameId : null;
    _lastSnapshot = snapshot;
    if (startTarget != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.pushReplacement(
          '/family/$_familyId/${_spec.routeSegment}/board/$startTarget',
        );
      });
    }

    final hasRoom = snapshot.gameId != null;

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          // Route-level onExit guard (app_router.dart) intercepts while
          // a room is active and shows the confirmation dialog first.
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/family/$_familyId');
            }
          },
        ),
        title: Text(
          _spec.title,
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontWeight: FontWeight.w600,
            color: KinrelColors.textWhite,
          ),
        ),
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
        actions: [
          if (hasRoom && isHost)
            IconButton(
              tooltip: 'Invite family member',
              icon: const Icon(Icons.person_add_outlined),
              onPressed: () => _openInviteSheet(snapshot),
            ),
          if (hasRoom)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              onPressed: () => _shareCode(snapshot.gameId),
            ),
        ],
      ),
      body: snapshot.isLoading && !hasRoom
          ? const Center(
              child: CircularProgressIndicator(color: KinrelColors.orange),
            )
          : snapshot.error != null && !hasRoom
              ? DKErrorState(
                  message: snapshot.error!,
                  actionLabel: snapshot.error == kRoomClosedMessage
                      ? 'Create New Room'
                      : null,
                  icon: snapshot.error == kRoomClosedMessage
                      ? Icons.meeting_room_rounded
                      : null,
                  onRetry: _createRoom,
                )
              : hasRoom
                  ? _waitingRoom(snapshot, isHost)
                  : _setupView(),
    );
  }

  // ── Setup phase — one decision: create the room ───────────────────

  Widget _setupView() {
    return LobbySetupScreen(
      gameId: _spec.gameId,
      title: _spec.title,
      tagline: _spec.tagline,
      facts: _spec.facts,
      settings: _spec.settings,
      rules: _spec.rules,
      rulesFootnote: _spec.rulesFootnote,
      spectatorsEnabled: _spectatorsEnabled,
      onSpectatorsChanged: (v) => setState(() => _spectatorsEnabled = v),
      ctaLabel: 'Create Room',
      ctaHint:
          'Invite family members — the first to join becomes your opponent',
      ctaLoading: _creating,
      onCtaPressed: _createRoom,
    );
  }

  // ── Waiting room phase — shared TemporaryLobbyView ────────────────

  Widget _waitingRoom(BoardRoomSnapshot snapshot, bool isHost) {
    final gameId = snapshot.gameId!;
    final roster = ref.watch(boardRoomParticipantsProvider(
      (gameTable: _spec.gameTable, gameId: gameId),
    ));

    final lobbyStatus = snapshot.isInProgress
        ? TemporaryLobbyStatus.starting
        : snapshot.isCompleted
            ? TemporaryLobbyStatus.finished
            : TemporaryLobbyStatus.waiting;

    final players = roster.participants
        .map((p) => TemporaryLobbyPlayer(
              userId: p.userId,
              userName: p.userName ?? 'Player',
              // Host is always ready (room framework semantics).
              isReady: p.isReady || p.isHost,
              isHost: p.isHost,
              joinedAt: p.joinedAt,
            ))
        .toList();

    // Auto-close countdown mirrors the server deadline (5-minute
    // default, refreshed on activity).
    final secsLeft = snapshot.autoCloseDeadline
            ?.difference(DateTime.now())
            .inSeconds ??
        300;
    final remaining = secsLeft < 0
        ? 0
        : secsLeft > 300
            ? 300
            : secsLeft;

    final config = TemporaryLobbyConfig(
      gameTable: _spec.gameTable,
      gameId: gameId,
      familyId: _familyId,
      hostUserId: snapshot.hostUserId,
      players: players,
      maxPlayers: _spec.maxPlayers,
      status: lobbyStatus,
      subtitle: _spec.tagline,
      // The host is always ready — only guests get the Ready toggle.
      showReadyToggle: !isHost,
      autoCloseSeconds: remaining,
    );

    return RoomLifecycleListener(
      gameTable: _spec.gameTable,
      gameId: gameId,
      familyId: _familyId,
      isHost: isHost,
      child: TemporaryLobbyView(
        config: config,
        myUserId: ref.read(supabaseProvider)?.auth.currentUser?.id,
        onToggleReady: (isReady) => ref
            .read(boardRoomParticipantsProvider(
              (gameTable: _spec.gameTable, gameId: gameId),
            ).notifier)
            .setReady(isReady),
        onStartMatch: _startMatch,
        onCancelRoom: () => _spec.onLeaveRoom(ref, _familyId),
        onInviteFamily: isHost ? () => _openInviteSheet(snapshot) : null,
        footer: _spec.waitingRoomNote == null
            ? null
            : LobbyInfoNote(
                icon: Icons.swap_horiz_rounded,
                text: _spec.waitingRoomNote!,
              ),
      ),
    );
  }

  // ── Invite + room code ────────────────────────────────────────────

  void _openInviteSheet(BoardRoomSnapshot snapshot) {
    final gameId = snapshot.gameId;
    if (gameId == null) return;
    GameMotionTokens.tap();
    final roster = ref.read(boardRoomParticipantsProvider(
      (gameTable: _spec.gameTable, gameId: gameId),
    ));
    InviteFamilySheet.show(
      context,
      familyId: _familyId,
      gameType: _spec.gameType,
      gameId: gameId,
      roomCode: _roomCode(gameId),
      currentPlayerIds:
          roster.participants.map((p) => p.userId).toSet(),
      maxPlayers: _spec.maxPlayers,
      currentPlayers: roster.participants.length,
    );
  }

  Future<void> _shareCode(String? gameId) async {
    if (gameId == null) return;
    final code = _roomCode(gameId);
    GameMotionTokens.tap();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(KinrelRadius.lg)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(KinrelSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Share this code',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: KinrelSpacing.md),
            Text(
              code,
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 40,
                fontWeight: FontWeight.w700,
                color: KinrelColors.orange,
                letterSpacing: 6,
              ),
            ),
            const SizedBox(height: KinrelSpacing.md),
            Text(
              'Share the code with family — the first member to join '
              'becomes your opponent.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: KinrelColors.textDim,
              ),
            ),
            const SizedBox(height: KinrelSpacing.lg),
            DKButton(
              label: 'Done',
              variant: DKButtonVariant.primary,
              fullWidth: true,
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/family/$_familyId');
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  String _roomCode(String gameId) =>
      gameId.replaceAll('-', '').substring(0, 6).toUpperCase();
}
