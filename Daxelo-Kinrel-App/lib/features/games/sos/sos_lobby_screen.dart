// lib/features/games/sos/sos_lobby_screen.dart
//
// SOS Game — Lobby / Setup screen.
// Route: /family/$familyId/sos/lobby
//
// This screen is the reference implementation of the SHARED multiplayer
// framework. It uses:
//   • RoomSetupView for the create-game setup view (mode selector + rules +
//     spectator toggle + auto-close duration + Create button)
//   • LobbyView for the in-room view (auto-close timer, share code,
//     players list, pending invites, lobby chat, ready toggle / start
//     button, cancel room button)
//   • BackButtonGuard for the back button (host: Close Room? / player:
//     Leave Room?)
//
// The existing SosNotifier handles game-specific logic (creating the
// sos_games row + host player row in sos_players, transitioning to
// 'active' when the host starts the match). The RoomController handles
// the shared room lifecycle (auto-close, spectator, ready, leave,
// cancel, lobby chat persistence, disconnect detection).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../shared/widgets/dk_components.dart';
import '../game_motion_tokens.dart';
import '../shared/multiplayer/multiplayer.dart';
import '../shared/models/game_invite.dart';
import 'sos_models.dart';
import 'sos_provider.dart';
import 'sos_reconnecting_banner.dart';

class SosLobbyScreen extends ConsumerStatefulWidget {
  const SosLobbyScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<SosLobbyScreen> createState() => _SosLobbyScreenState();
}

class _SosLobbyScreenState extends ConsumerState<SosLobbyScreen> {
  SosMode _mode = SosMode.twoPlayer;

  /// The room controller key for this SOS lobby.
  RoomControllerKey get _roomKey =>
      RoomControllerKey(RoomConfig.sos, widget.familyId);

  /// The `?join=<gameId>` query param from the deep-link.
  String? get _joinIdFromRoute =>
      GoRouterState.of(context).uri.queryParameters['join'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final joinId = _joinIdFromRoute;
      if (joinId != null && joinId.isNotEmpty) {
        // Non-host joining via deep-link: attach via SOS provider first
        // (existing logic), then attach the room controller.
        final ok = await ref.read(sosProvider(widget.familyId).notifier).joinGame(joinId);
        if (ok) {
          await ref.read(roomControllerProvider(_roomKey).notifier).attachOnJoin(joinId);
        }
      }
    });
  }

  Future<void> _createGame() async {
    // 1. Let SOS provider create the game row with game-specific fields
    final gameId = await ref.read(sosProvider(widget.familyId).notifier).createGame(mode: _mode);
    if (gameId == null) return;
    // 2. Attach the room-lifecycle framework (auto-close, spectator,
    //    ready, lobby chat persistence, disconnect detection)
    await ref.read(roomControllerProvider(_roomKey).notifier).attachToExistingGame(
          gameId,
          spectatorsEnabled: true,
          autoCloseMinutes: 5,
        );
  }

  Future<void> _shareCode(String? gameId) async {
    if (gameId == null) return;
    final code = gameId.replaceAll('-', '').substring(0, 6).toUpperCase();
    unawaited(GameMotionTokens.tap());
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
              _mode == SosMode.fourPlayerTeams
                  ? '3 family members can join. Teams are assigned automatically: 1st & 3rd joiner → Team S, 2nd & 4th → Team O.'
                  : '1 family member can join to start a 2-player game.',
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

  Future<void> _retry() async {
    final notifier = ref.read(sosProvider(widget.familyId).notifier);
    final state = ref.read(sosProvider(widget.familyId));
    final joinId = _joinIdFromRoute;
    if (state.game == null && joinId != null && joinId.isNotEmpty) {
      await notifier.joinGame(joinId);
    } else {
      await notifier.retryConnection();
    }
    await ref.read(roomControllerProvider(_roomKey).notifier).retryConnection();
  }

  @override
  Widget build(BuildContext context) {
    final sosState = ref.watch(sosProvider(widget.familyId));
    final roomState = ref.watch(roomControllerProvider(_roomKey));
    final hasGame = sosState.game != null || roomState.hasGame;

    // Auto-navigate to the board once the game becomes active
    ref.listen<SosState>(sosProvider(widget.familyId), (previous, next) {
      final shouldNavigate = next.isActive;
      final wasActive = previous?.isActive ?? false;
      final gameId = next.game?.id;
      if (shouldNavigate && !wasActive && gameId != null && mounted) {
        context.pushReplacement(
          '/family/${widget.familyId}/sos/game/$gameId',
        );
      }
    });

    // Auto-navigate back to setup if room was cancelled/closed
    ref.listen<RoomState>(roomControllerProvider(_roomKey), (previous, next) {
      if (next.isCancelled && previous != null && !previous.isCancelled) {
        // Room was cancelled / auto-closed — bail to the family hub.
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/family/${widget.familyId}');
        }
      }
    });

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: BackButtonGuard(
          roomKey: _roomKey,
          onExit: () {
            // Also leave the SOS provider's room
            ref.read(sosProvider(widget.familyId).notifier).leaveGame();
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/family/${widget.familyId}');
            }
          },
        ),
        title: Text(
          'SOS',
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
          if (hasGame && roomState.isHost)
            IconButton(
              tooltip: 'Share code',
              icon: const Icon(Icons.share_outlined),
              onPressed: () => _shareCode(roomState.gameId ?? sosState.game?.id),
            ),
        ],
      ),
      body: Column(
        children: [
          SosReconnectingBanner(
            status: sosState.connectionStatus,
            friendlyError: sosState.friendlyError ?? roomState.friendlyError,
            onRetry: _retry,
          ),
          Expanded(
            child: sosState.isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: KinrelColors.orange),
                  )
                : (sosState.friendlyError != null && !hasGame)
                ? DKErrorState(
                    message: sosState.friendlyError!,
                    onRetry: _retry,
                  )
                : hasGame
                    ? LobbyView(
                        roomKey: _roomKey,
                        gameType: GameType.sos,
                        gameDisplayName: 'SOS',
                        startGame: () => ref.read(sosProvider(widget.familyId).notifier).startGame(),
                      )
                    : _setupView(),
          ),
        ],
      ),
    );
  }

  /// The setup view (no game yet) — uses RoomSetupView wrapper.
  Widget _setupView() {
    return RoomSetupView(
      roomKey: _roomKey,
      createButtonLabel: 'Create Game',
      createGame: () async {
        // The actual create happens in _createGame, but RoomSetupView
        // calls this callback to get the game-specific fields. We
        // delegate to _createGame which writes everything.
        await _createGame();
        // Returning null signals "no game-specific fields to write via
        // the room controller's createRoom path" — we already attached
        // via attachToExistingGame.
        return null;
      },
      defaultAutoCloseMinutes: 5,
      child: _gameSetupFields(),
    );
  }

  Widget _gameSetupFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Game Mode'),
        const SizedBox(height: KinrelSpacing.sm),
        _modeSelector(),
        const SizedBox(height: KinrelSpacing.lg),
        Container(
          padding: const EdgeInsets.all(KinrelSpacing.md),
          decoration: BoxDecoration(
            color: KinrelColors.darkCard,
            borderRadius: BorderRadius.circular(KinrelRadius.lg),
            border: Border.all(color: KinrelColors.border),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: KinrelColors.info, size: 20),
              const SizedBox(width: KinrelSpacing.sm),
              Expanded(
                child: Text(
                  _mode.description,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    color: KinrelColors.textDim,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: KinrelSpacing.xl),
        _sectionLabel('How to Play'),
        const SizedBox(height: KinrelSpacing.sm),
        _rulesCard(),
      ],
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: TextStyle(
          fontFamily: KinrelTypography.displayFont,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: KinrelColors.textDim,
          letterSpacing: 0.5,
        ),
      );

  Widget _modeSelector() {
    return Wrap(
      spacing: KinrelSpacing.sm,
      runSpacing: KinrelSpacing.sm,
      children: SosMode.values.map((m) {
        final selected = m == _mode;
        return GestureDetector(
          onTap: () {
            GameMotionTokens.tap();
            setState(() => _mode = m);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(
              vertical: KinrelSpacing.sm,
              horizontal: KinrelSpacing.md,
            ),
            decoration: BoxDecoration(
              color: KinrelColors.darkCard,
              borderRadius: BorderRadius.circular(KinrelRadius.lg),
              border: Border.all(
                color: selected ? KinrelColors.orange : KinrelColors.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  m == SosMode.twoPlayer
                      ? Icons.person_outline
                      : Icons.groups_outlined,
                  size: 18,
                  color: selected ? KinrelColors.orange : KinrelColors.textDim,
                ),
                const SizedBox(width: 6),
                Text(
                  m.label,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    color: selected
                        ? KinrelColors.textWhite
                        : KinrelColors.textDim,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _rulesCard() {
    return Container(
      padding: const EdgeInsets.all(KinrelSpacing.md),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ruleLine('1.', 'Players take turns placing S or O letters on a 7×7 grid.'),
          const SizedBox(height: 6),
          _ruleLine('2.', 'Complete an S-O-S sequence (3 cells in a line) to score a point.'),
          const SizedBox(height: 6),
          _ruleLine('3.', 'Sequences can be horizontal, vertical, or diagonal.'),
          const SizedBox(height: 6),
          _ruleLine('4.', 'Score a sequence → go again. Otherwise, turn passes.'),
          const SizedBox(height: 6),
          _ruleLine('5.', 'Grid full → game over. Most sequences wins.'),
          if (_mode == SosMode.fourPlayerTeams) ...[
            const SizedBox(height: 6),
            _ruleLine(
              '★',
              'Team mode: Team S places only S, Team O places only O. Turns rotate S1→O1→S2→O2.',
              highlight: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _ruleLine(String num, String text, {bool highlight = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          child: Text(
            num,
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: highlight ? KinrelColors.orange : KinrelColors.textDim,
            ),
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              color: highlight ? KinrelColors.textWhite : KinrelColors.textDim,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
