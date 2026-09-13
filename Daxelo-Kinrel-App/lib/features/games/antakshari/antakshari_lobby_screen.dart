// lib/features/games/antakshari/antakshari_lobby_screen.dart
//
// Antakshari — Lobby / Setup screen.
// Route: /family/$familyId/antakshari/lobby
//
// Refactored to use the shared multiplayer framework:
//   • RoomSetupView for the setup view (game mode + max players + turn
//     timer + round limit + rules + spectator toggle + auto-close
//     duration + Create button)
//   • LobbyView for the in-room view (auto-close timer, share code,
//     players list, pending invites, lobby chat, ready toggle / start
//     button, cancel room button)
//   • BackButtonGuard for the back button (host: Close Room? / player:
//     Leave Room?)
//
// The existing AntakshariNotifier handles game-specific logic (creating
// the antakshari_games row + host's antakshari_players row,
// transitioning to 'in_progress' when the host starts the match). The
// RoomController handles the shared room lifecycle.

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
import 'antakshari_models.dart';
import 'antakshari_provider.dart';

class AntakshariLobbyScreen extends ConsumerStatefulWidget {
  const AntakshariLobbyScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<AntakshariLobbyScreen> createState() =>
      _AntakshariLobbyScreenState();
}

class _AntakshariLobbyScreenState
    extends ConsumerState<AntakshariLobbyScreen> {
  AntakshariGameMode _mode = AntakshariGameMode.standard;
  int _maxPlayers = 12;
  int _turnTimer = 30;
  int _roundLimit = 5;

  /// The room controller key for this Antakshari lobby.
  RoomControllerKey get _roomKey =>
      RoomControllerKey(RoomConfig.antakshari, widget.familyId);

  /// The `?join=<gameId>` query param from the deep-link.
  String? get _joinIdFromRoute =>
      GoRouterState.of(context).uri.queryParameters['join'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final joinId = _joinIdFromRoute;
      if (joinId != null && joinId.isNotEmpty) {
        // Non-host joining via deep-link: attach via the game provider
        // first (existing logic), then attach the room controller.
        final ok = await ref
            .read(antakshariProvider(widget.familyId).notifier)
            .joinGame(joinId);
        if (ok) {
          await ref
              .read(roomControllerProvider(_roomKey).notifier)
              .attachOnJoin(joinId);
        }
      }
    });
  }

  Future<void> _createGame() async {
    // 1. Let the game provider create the game row with game-specific fields
    final gameId = await ref
        .read(antakshariProvider(widget.familyId).notifier)
        .createGame(
          mode: _mode,
          maxPlayers: _maxPlayers,
          turnTimerSeconds: _turnTimer,
          roundLimit: _mode == AntakshariGameMode.roundLimited
              ? _roundLimit
              : null,
        );
    if (gameId == null) return;
    // 2. Attach the room-lifecycle framework (auto-close, spectator,
    //    ready, lobby chat persistence, disconnect detection)
    await ref
        .read(roomControllerProvider(_roomKey).notifier)
        .attachToExistingGame(
          gameId,
          spectatorsEnabled: true,
          autoCloseMinutes: 10,
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
              'Up to ${_maxPlayers - 1} family members can join. Turn order is randomized when the host starts the game.',
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
                  context.go('/family/${widget.familyId}');
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final antakshariState = ref.watch(antakshariProvider(widget.familyId));
    final roomState = ref.watch(roomControllerProvider(_roomKey));
    final hasGame = antakshariState.game != null || roomState.hasGame;

    // Auto-navigate to the board once the game becomes active
    ref.listen<AntakshariState>(
      antakshariProvider(widget.familyId),
      (previous, next) {
        final shouldNavigate = next.isInProgress;
        final wasInProgress = previous?.isInProgress ?? false;
        final gameId = next.game?.id;
        if (shouldNavigate && !wasInProgress && gameId != null && mounted) {
          context.pushReplacement(
            '/family/${widget.familyId}/antakshari/game/$gameId',
          );
        }
      },
    );

    // Auto-navigate back to setup if room was cancelled/closed
    ref.listen<RoomState>(
      roomControllerProvider(_roomKey),
      (previous, next) {
        if (next.isCancelled && previous != null && !previous.isCancelled) {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/family/${widget.familyId}');
          }
        }
      },
    );

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: BackButtonGuard(
          roomKey: _roomKey,
          onExit: () {
            ref.read(antakshariProvider(widget.familyId).notifier).leaveGame();
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/family/${widget.familyId}');
            }
          },
        ),
        title: Text(
          'Antakshari',
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
              onPressed: () => _shareCode(
                roomState.gameId ?? antakshariState.game?.id,
              ),
            ),
        ],
      ),
      body: antakshariState.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: KinrelColors.orange),
            )
          : (antakshariState.error != null && !hasGame)
              ? DKErrorState(
                  message: antakshariState.error!,
                  onRetry: _createGame,
                )
              : hasGame
                  ? LobbyView(
                      roomKey: _roomKey,
                      gameType: GameType.antakshari,
                      gameDisplayName: 'Antakshari',
                      startGame: () => ref
                          .read(antakshariProvider(widget.familyId).notifier)
                          .startGame(),
                    )
                  : _setupView(),
    );
  }

  /// The setup view (no game yet) — uses RoomSetupView wrapper.
  Widget _setupView() {
    return RoomSetupView(
      roomKey: _roomKey,
      createButtonLabel: 'Create Game',
      createGame: () async {
        await _createGame();
        return null;
      },
      defaultAutoCloseMinutes: 10,
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

        _sectionLabel('Max Players'),
        const SizedBox(height: KinrelSpacing.sm),
        _maxPlayersSelector(),
        const SizedBox(height: KinrelSpacing.lg),

        _sectionLabel('Turn Timer: ${_turnTimer}s'),
        const SizedBox(height: KinrelSpacing.sm),
        _turnTimerSlider(),
        const SizedBox(height: KinrelSpacing.lg),

        if (_mode == AntakshariGameMode.roundLimited) ...[
          _sectionLabel('Round Limit: $_roundLimit'),
          const SizedBox(height: KinrelSpacing.sm),
          _roundLimitSlider(),
          const SizedBox(height: KinrelSpacing.lg),
        ],

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
      children: AntakshariGameMode.values.map((m) {
        final selected = m == _mode;
        return GestureDetector(
          onTap: () {
            unawaited(GameMotionTokens.tap());
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      m == AntakshariGameMode.standard
                          ? Icons.person_outline
                          : Icons.groups_outlined,
                      size: 18,
                      color: selected
                          ? KinrelColors.orange
                          : KinrelColors.textDim,
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
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  m.description,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 10,
                    color: KinrelColors.textDim,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _maxPlayersSelector() {
    return Wrap(
      spacing: KinrelSpacing.sm,
      runSpacing: KinrelSpacing.sm,
      children: [6, 8, 12, 16, 20].map((n) {
        final selected = n == _maxPlayers;
        return GestureDetector(
          onTap: () {
            unawaited(GameMotionTokens.tap());
            setState(() => _maxPlayers = n);
          },
          child: Container(
            width: 50,
            padding: const EdgeInsets.symmetric(vertical: KinrelSpacing.sm),
            decoration: BoxDecoration(
              color: KinrelColors.darkCard,
              borderRadius: BorderRadius.circular(KinrelRadius.md),
              border: Border.all(
                color: selected ? KinrelColors.orange : KinrelColors.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Center(
              child: Text(
                '$n',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? KinrelColors.orange
                      : KinrelColors.textDim,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _turnTimerSlider() {
    return Slider(
      value: _turnTimer.toDouble(),
      min: 15,
      max: 60,
      divisions: 9,
      activeColor: KinrelColors.orange,
      label: '${_turnTimer}s',
      onChanged: (v) => setState(() => _turnTimer = v.round()),
    );
  }

  Widget _roundLimitSlider() {
    return Slider(
      value: _roundLimit.toDouble(),
      min: 3,
      max: 10,
      divisions: 7,
      activeColor: KinrelColors.orange,
      label: '$_roundLimit rounds',
      onChanged: (v) => setState(() => _roundLimit = v.round()),
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
          _ruleLine('1.', 'Players take turns singing a song line via voice/video call.'),
          const SizedBox(height: 6),
          _ruleLine('2.', 'Your song must start with the last letter of the previous player\'s song.'),
          const SizedBox(height: 6),
          _ruleLine('3.', 'After singing, type the letter your song ended on.'),
          const SizedBox(height: 6),
          _ruleLine('4.', 'Others can Challenge — 3+ challenges in 10s = you\'re out.'),
          const SizedBox(height: 6),
          _ruleLine('5.', 'Don\'t sing in ${_turnTimer}s = eliminated.'),
          const SizedBox(height: 6),
          _ruleLine(
            '★',
            _mode == AntakshariGameMode.standard
                ? 'Standard: last player standing wins.'
                : 'Round-limited: all survivors after $_roundLimit rounds win jointly.',
            highlight: true,
          ),
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
