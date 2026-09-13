// lib/features/games/bingo/bingo_lobby_screen.dart
//
// Bingo — Lobby / Setup screen.
// Route: /family/$familyId/bingo/lobby
//
// Refactored to use the shared multiplayer framework:
//   • RoomSetupView for the setup view (win pattern + call interval +
//     spectator toggle + auto-close duration + Create button)
//   • LobbyView for the in-room view (auto-close timer, share code,
//     players list, pending invites, lobby chat, ready toggle / start
//     button, cancel room button)
//   • BackButtonGuard for the back button (host: Close Room? / player:
//     Leave Room?)
//
// The existing BingoNotifier handles game-specific logic (creating the
// bingo_games row + host's bingo_card, transitioning to 'in_progress'
// when the host starts the match, calling the bingo-caller Edge
// Function). The RoomController handles the shared room lifecycle.

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

  RoomControllerKey get _roomKey =>
      RoomControllerKey(RoomConfig.bingo, widget.familyId);

  String? get _joinIdFromRoute =>
      GoRouterState.of(context).uri.queryParameters['join'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final joinId = _joinIdFromRoute;
      if (joinId != null && joinId.isNotEmpty) {
        final ok = await ref
            .read(bingoProvider(widget.familyId).notifier)
            .joinGame(joinId);
        if (ok) {
          await ref.read(roomControllerProvider(_roomKey).notifier).attachOnJoin(joinId);
        }
      }
    });
  }

  Future<void> _createGame() async {
    final gameId = await ref.read(bingoProvider(widget.familyId).notifier).createGame(
          winPattern: _winPattern,
          callIntervalSeconds: _callInterval,
        );
    if (gameId == null) return;
    await ref.read(roomControllerProvider(_roomKey).notifier).attachToExistingGame(
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
              'Up to 30 family members can join. Each player gets a random 5×5 card.',
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
    final bingoState = ref.watch(bingoProvider(widget.familyId));
    final roomState = ref.watch(roomControllerProvider(_roomKey));
    final hasGame = bingoState.game != null || roomState.hasGame;

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

    // Auto-navigate back to setup if room was cancelled
    ref.listen<RoomState>(roomControllerProvider(_roomKey), (previous, next) {
      if (next.isCancelled && previous != null && !previous.isCancelled) {
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
            ref.read(bingoProvider(widget.familyId).notifier).leaveGame();
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/family/${widget.familyId}');
            }
          },
        ),
        title: Text(
          'Bingo',
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
                  _shareCode(roomState.gameId ?? bingoState.game?.id),
            ),
        ],
      ),
      body: bingoState.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: KinrelColors.orange),
            )
          : hasGame
              ? LobbyView(
                  roomKey: _roomKey,
                  gameType: GameType.bingo,
                  gameDisplayName: 'Bingo',
                  startGame: () => ref
                      .read(bingoProvider(widget.familyId).notifier)
                      .startGame(),
                )
              : _setupView(),
    );
  }

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
        _sectionLabel('Win Pattern'),
        const SizedBox(height: KinrelSpacing.sm),
        _winPatternSelector(),
        const SizedBox(height: KinrelSpacing.lg),
        _sectionLabel('Call Speed'),
        const SizedBox(height: KinrelSpacing.sm),
        _callIntervalSelector(),
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

  Widget _winPatternSelector() {
    return Wrap(
      spacing: KinrelSpacing.sm,
      runSpacing: KinrelSpacing.sm,
      children: BingoWinPattern.values.map((p) {
        final selected = p == _winPattern;
        return GestureDetector(
          onTap: () {
            unawaited(GameMotionTokens.tap());
            setState(() => _winPattern = p);
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
            child: Text(
              p.label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color:
                    selected ? KinrelColors.textWhite : KinrelColors.textDim,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _callIntervalSelector() {
    return Wrap(
      spacing: KinrelSpacing.sm,
      runSpacing: KinrelSpacing.sm,
      children: [3, 5, 7, 10].map((s) {
        final selected = s == _callInterval;
        return GestureDetector(
          onTap: () {
            unawaited(GameMotionTokens.tap());
            setState(() => _callInterval = s);
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
            child: Text(
              '${s}s',
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 13,
                color:
                    selected ? KinrelColors.textWhite : KinrelColors.textDim,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
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
          _ruleLine('1.', 'Each player gets a random 5×5 Bingo card with numbers 1–75.'),
          const SizedBox(height: 6),
          _ruleLine('2.', 'Numbers are called automatically at the chosen interval.'),
          const SizedBox(height: 6),
          _ruleLine('3.', 'Mark called numbers on your card by tapping them.'),
          const SizedBox(height: 6),
          _ruleLine('4.', 'Complete the win pattern to call BINGO!'),
          const SizedBox(height: 6),
          _ruleLine('5.', 'First valid BINGO wins. Server verifies all claims.'),
          const SizedBox(height: 6),
          _ruleLine(
            '★',
            'Win pattern: ${_winPattern.label}',
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
