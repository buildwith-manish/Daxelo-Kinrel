// lib/features/games/twotruths/twotruths_lobby_screen.dart
//
// Two Truths & a Lie — Lobby / Setup screen.
// Route: /family/$familyId/twotruths/lobby
//
// Refactored to use the shared multiplayer framework:
//   • RoomSetupView for the setup view (game mode + total rounds +
//     guess timer + rules + spectator toggle + auto-close duration +
//     Create button)
//   • LobbyView for the in-room view (auto-close timer, share code,
//     players list, pending invites, lobby chat, ready toggle / start
//     button, cancel room button)
//   • BackButtonGuard for the back button (host: Close Room? / player:
//     Leave Room?)
//
// The existing TtNotifier handles game-specific logic (creating the
// twotruths_games row + host's twotruths_players row, transitioning
// to 'in_progress' when the host starts the match). The RoomController
// handles the shared room lifecycle.

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
import 'twotruths_models.dart';
import 'twotruths_provider.dart';

class TtLobbyScreen extends ConsumerStatefulWidget {
  const TtLobbyScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<TtLobbyScreen> createState() => _TtLobbyScreenState();
}

class _TtLobbyScreenState extends ConsumerState<TtLobbyScreen> {
  TtMode _mode = TtMode.playerAuthored;
  int _totalRounds = 3;
  int _timer = 30;

  /// The room controller key for this Two Truths & a Lie lobby.
  RoomControllerKey get _roomKey =>
      RoomControllerKey(RoomConfig.twotruths, widget.familyId);

  /// The `?join=<gameId>` query param from the deep-link.
  String? get _joinIdFromRoute =>
      GoRouterState.of(context).uri.queryParameters['join'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final joinId = _joinIdFromRoute;
      if (joinId != null && joinId.isNotEmpty) {
        final ok = await ref
            .read(ttProvider(widget.familyId).notifier)
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
    final gameId = await ref
        .read(ttProvider(widget.familyId).notifier)
        .createGame(
          mode: _mode,
          totalRounds: _totalRounds,
          roundTimerSeconds: _timer,
        );
    if (gameId == null) return;
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
    final ttState = ref.watch(ttProvider(widget.familyId));
    final roomState = ref.watch(roomControllerProvider(_roomKey));
    final hasGame = ttState.game != null || roomState.hasGame;

    // Auto-navigate to the submit screen once the game becomes active
    ref.listen<TtState>(ttProvider(widget.familyId), (previous, next) {
      final shouldNavigate = next.isInProgress;
      final wasInProgress = previous?.isInProgress ?? false;
      final gameId = next.game?.id;
      if (shouldNavigate && !wasInProgress && gameId != null && mounted) {
        context.pushReplacement(
          '/family/${widget.familyId}/twotruths/submit/$gameId',
        );
      }
    });

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
            ref.read(ttProvider(widget.familyId).notifier).leaveGame();
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/family/${widget.familyId}');
            }
          },
        ),
        title: Text(
          'Two Truths and a Lie',
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
              onPressed: () =>
                  _shareCode(roomState.gameId ?? ttState.game?.id),
            ),
        ],
      ),
      body: ttState.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: KinrelColors.orange),
            )
          : hasGame
              ? LobbyView(
                  roomKey: _roomKey,
                  gameType: GameType.twotruths,
                  gameDisplayName: 'Two Truths & a Lie',
                  startGame: () => ref
                      .read(ttProvider(widget.familyId).notifier)
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
        _sectionLabel('Total Rounds: $_totalRounds'),
        const SizedBox(height: KinrelSpacing.sm),
        Slider(
          value: _totalRounds.toDouble(),
          min: 1,
          max: 12,
          divisions: 11,
          activeColor: KinrelColors.orange,
          label: '$_totalRounds',
          onChanged: (v) => setState(() => _totalRounds = v.round()),
        ),
        const SizedBox(height: KinrelSpacing.sm),
        _sectionLabel('Guess Timer: ${_timer}s'),
        const SizedBox(height: KinrelSpacing.sm),
        Slider(
          value: _timer.toDouble(),
          min: 15,
          max: 90,
          divisions: 15,
          activeColor: KinrelColors.orange,
          label: '${_timer}s',
          onChanged: (v) => setState(() => _timer = v.round()),
        ),
        const SizedBox(height: KinrelSpacing.lg),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _modeCard(
          icon: Icons.person,
          selected: _mode == TtMode.playerAuthored,
          title: 'Player-Authored',
          description: 'You write all 3 statements (2 true, 1 lie)',
          onTap: () {
            unawaited(GameMotionTokens.tap());
            setState(() => _mode = TtMode.playerAuthored);
          },
        ),
        const SizedBox(height: KinrelSpacing.sm),
        _modeCard(
          icon: Icons.smart_toy,
          selected: _mode == TtMode.aiLie,
          title: 'AI Lie Mode',
          description: 'You write 2 truths, AI generates the lie',
          onTap: () {
            unawaited(GameMotionTokens.tap());
            setState(() => _mode = TtMode.aiLie);
          },
        ),
      ],
    );
  }

  Widget _modeCard({
    required IconData icon,
    required bool selected,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(KinrelSpacing.md),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
          border: Border.all(
            color: selected ? KinrelColors.orange : KinrelColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: selected ? KinrelColors.orange : KinrelColors.textDim,
              size: 20,
            ),
            const SizedBox(width: KinrelSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? KinrelColors.textWhite
                          : KinrelColors.textDim,
                    ),
                  ),
                  Text(
                    description,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 11,
                      color: KinrelColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
          Text(
            'How to Play',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textWhite,
            ),
          ),
          const SizedBox(height: KinrelSpacing.sm),
          Text(
            '• Each round, one player submits 3 statements (2 true, 1 lie)\n'
            '• Others guess which is the lie\n'
            '• Correct guess = 1pt. Each fooled player = 1pt for submitter\n'
            '• Highest total after $_totalRounds rounds wins!',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              color: KinrelColors.textDim,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
