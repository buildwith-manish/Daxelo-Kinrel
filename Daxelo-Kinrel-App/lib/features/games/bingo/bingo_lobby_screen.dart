// lib/features/games/bingo/bingo_lobby_screen.dart
//
// Bingo — Lobby / Setup screen.
// Route: /family/$familyId/bingo/lobby
//
// v2 (premium lobby system): setup phase renders the shared
// LobbySetupScreen — compact hero, visible win-pattern + call-speed
// settings, spectator toggle, collapsible How to Play, pinned
// Create Game CTA. Waiting-room phase still renders TemporaryLobbyView.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../game_motion_tokens.dart';
import '../shared/models/game_invite.dart';
import '../shared/widgets/invite_family_sheet.dart';
import '../shared/widgets/lobby_join_handler.dart';
import '../shared/widgets/lobby_kit/lobby_kit.dart';
import '../shared/widgets/temporary_lobby_view.dart';
import '../shared/services/temporary_room_service.dart';
import '../shared/widgets/room_lifecycle_listener.dart';
import 'bingo_models.dart';
import 'bingo_provider.dart';

class BingoLobbyScreen extends ConsumerStatefulWidget {
  const BingoLobbyScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<BingoLobbyScreen> createState() => _BingoLobbyScreenState();
}

class _BingoLobbyScreenState extends ConsumerState<BingoLobbyScreen> {
  BingoWinPattern _winPattern = BingoWinPattern.line;
  int _callInterval = 5;
  bool _creating = false;
  bool _spectatorsEnabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      joinRoomWhenReady(
        context: context,
        ref: ref,
        onJoin: (id) =>
            ref.read(bingoProvider(widget.familyId).notifier).joinGame(id),
      );
    });
  }

  Future<void> _createGame() async {
    setState(() => _creating = true);
    final notifier = ref.read(bingoProvider(widget.familyId).notifier);
    final gameId = await notifier.createGame(
      winPattern: _winPattern,
      callIntervalSeconds: _callInterval,
    );
      if (gameId != null) {
        await ref.read(supabaseProvider)?.from('bingo_games').update({'spectatorsEnabled': _spectatorsEnabled}).eq('id', gameId);
      }

    if (mounted) setState(() => _creating = false);
    // Stay on lobby to wait for players
    if (gameId == null && mounted) {
      // Error already set in state
    }
  }

  Future<void> _shareCode(String? gameId) async {
    if (gameId == null) return;
    final code = gameId.replaceAll('-', '').substring(0, 6).toUpperCase();
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
              'Up to 29 family members can join. Each player gets a random 5×5 card.',
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
              onPressed: () { if (context.canPop()) { context.pop(); } else { context.go('/family/${widget.familyId}'); } },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bingoProvider(widget.familyId));
    final notifier = ref.read(bingoProvider(widget.familyId).notifier);
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isHost = state.game?.hostUserId == myId || state.game == null;
    final canStart = state.game == null
        ? true
        : (isHost && state.allCards.length >= 2);

    // Auto-navigate to board when game starts
    ref.listen<BingoState>(bingoProvider(widget.familyId), (previous, next) {
      if (next.isInProgress &&
          !(previous?.isInProgress ?? false) &&
          next.game?.id != null &&
          mounted) {
        context.pushReplacement(
          '/family/${widget.familyId}/bingo/board/${next.game!.id}',
        );
      }
    });

    final hasGame = state.game != null;

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          // Plain pop — the route-level onExit guard (app_router.dart)
          // intercepts this while a room is active and shows the
          // confirmation dialog first.
          onPressed: () { if (context.canPop()) { context.pop(); } else { context.go('/family/${widget.familyId}'); } },
        ),
        title: hasGame
            ? Text(
                'Bingo',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textWhite,
                ),
              )
            : null,
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
        actions: [
          if (hasGame && isHost)
            IconButton(
              tooltip: 'Invite family member',
              icon: const Icon(Icons.person_add_outlined),
              onPressed: () {
                final code = state.game?.id != null
                    ? state.game!.id
                        .replaceAll('-', '')
                        .substring(0, 6)
                        .toUpperCase()
                    : '------';
                final maxP = state.game?.maxPlayers ?? 30;
                GameMotionTokens.tap();
                InviteFamilySheet.show(
                  context,
                  familyId: widget.familyId,
                  gameType: GameType.bingo,
                  gameId: state.game?.id ?? '',
                  roomCode: code,
                  currentPlayerIds: state.allCards
                      .map((c) => c.playerId)
                      .whereType<String>()
                      .toSet(),
                  maxPlayers: maxP,
                  currentPlayers: state.allCards.length,
                );
              },
            ),
          if (hasGame)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              onPressed: () => _shareCode(state.game?.id),
            ),
        ],
      ),
      body: state.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: KinrelColors.orange),
            )
          : state.error != null && !hasGame
          ? DKErrorState(
              message: state.error!,
              // Closed room → the button creates a NEW room (per spec the
              // closed one is deleted and must never reappear).
              actionLabel:
                  state.error == kRoomClosedMessage ? 'Create New Room' : null,
              icon: state.error == kRoomClosedMessage
                  ? Icons.meeting_room_rounded
                  : null,
              onRetry: _createGame,
            )
          : hasGame
              ? _lobbyView(state, notifier, isHost, canStart)
              : _setupView(state),
    );
  }

  Widget _setupView(BingoState state) {
    return LobbySetupScreen(
      gameId: 'bingo',
      title: 'Bingo',
      tagline: 'Mark your card, race to shout BINGO first',
      facts: const [
        LobbyFact(icon: Icons.groups_outlined, label: 'Up to 30 players'),
        LobbyFact(icon: Icons.grid_on_outlined, label: '5×5 cards'),
      ],
      settings: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LobbySection(
            label: 'Win Pattern',
            child: LobbyChoiceGrid<BingoWinPattern>(
              options: [
                for (final p in BingoWinPattern.values)
                  LobbyOption(
                    value: p,
                    label: p.label,
                    caption: p.description,
                  ),
              ],
              selected: _winPattern,
              onSelect: (p) => setState(() => _winPattern = p),
            ),
          ),
          const SizedBox(height: KinrelSpacing.md),
          LobbySliderRow(
            label: 'Call Speed',
            valueLabel: 'every $_callInterval s',
            value: _callInterval,
            min: 3,
            max: 15,
            divisions: 12,
            onChanged: (v) => setState(() => _callInterval = v),
          ),
        ],
      ),
      rules: [
        const LobbyRule('Each player gets a random 5×5 card with numbers 1-75.'),
        LobbyRule('The caller (automated) announces a random number every $_callInterval s.'),
        const LobbyRule('Tap matching numbers on your card to mark them.'),
        const LobbyRule('Center space is FREE — already marked.'),
        LobbyRule(
          _winPattern == BingoWinPattern.line
              ? 'Complete any row, column, or diagonal → tap BINGO!'
              : 'Mark every number on your card → tap BINGO!',
        ),
      ],
      rulesFootnote: 'Wins are verified server-side — no cheating!',
      spectatorsEnabled: _spectatorsEnabled,
      onSpectatorsChanged: (v) => setState(() => _spectatorsEnabled = v),
      ctaLabel: 'Create Game',
      ctaHint: 'Everyone gets a random card — up to 29 family members can join',
      ctaLoading: _creating,
      onCtaPressed: _createGame,
    );
  }

  Widget _lobbyView(
    BingoState state,
    BingoNotifier notifier,
    bool isHost,
    bool canStart,
  ) {
    final game = state.game!;
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;

    // Map provider state → TemporaryLobbyConfig. Bingo has no
    // `bingo_players` table — the player list is derived from
    // `bingo_cards`. There's no `isReady` concept per player, so we
    // hide the ready toggle and pre-set every player to "ready".
    final lobbyStatus = game.isInProgress
        ? TemporaryLobbyStatus.starting
        : game.isCompleted
            ? TemporaryLobbyStatus.finished
            : TemporaryLobbyStatus.waiting;

    final lobbyPlayers = state.allCards
        .map((c) => TemporaryLobbyPlayer(
              userId: c.playerId,
              userName: c.playerName,
              isReady: true, // No ready concept in bingo — always ready.
              isHost: c.playerId == game.hostUserId,
              joinedAt: c.createdAt,
            ))
        .toList();

    final config = TemporaryLobbyConfig(
      gameTable: 'bingo_games',
      gameId: game.id,
      familyId: widget.familyId,
      hostUserId: game.hostUserId,
      players: lobbyPlayers,
      maxPlayers: game.maxPlayers,
      status: lobbyStatus,
      subtitle: '${game.winPattern.label} · ${game.callIntervalSeconds}s/number',
      showReadyToggle: false, // Bingo has no player table → no ready flag.
    );

    return RoomLifecycleListener(
          gameTable: 'bingo_games',
          gameId: game.id,
          familyId: widget.familyId,
          isHost: (game.hostUserId == myId),
          child: TemporaryLobbyView(
        config: config,
        myUserId: myId,
        onToggleReady: (_) async {}, // No-op for bingo (no isReady column).
        onStartMatch: () => notifier.startGame(),
        onCancelRoom: () => notifier.leaveGame(),
        onInviteFamily: isHost
            ? () {
                final code = game.id
                    .replaceAll('-', '')
                    .substring(0, 6)
                    .toUpperCase();
                GameMotionTokens.tap();
                InviteFamilySheet.show(
                  context,
                  familyId: widget.familyId,
                  gameType: GameType.bingo,
                  gameId: game.id,
                  roomCode: code,
                  currentPlayerIds: state.allCards
                      .map((c) => c.playerId)
                      .whereType<String>()
                      .toSet(),
                  maxPlayers: game.maxPlayers,
                  currentPlayers: state.allCards.length,
                );
              }
            : null,
    ),
    );
  }
}
