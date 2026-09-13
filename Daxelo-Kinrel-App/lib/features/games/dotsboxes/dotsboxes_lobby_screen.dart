// lib/features/games/dotsboxes/dotsboxes_lobby_screen.dart
//
// Dots & Boxes — Lobby / Setup screen.
// Route: /family/$familyId/dotsboxes/lobby
//
// Refactored to use the shared multiplayer framework:
//   • RoomSetupView for the setup view (grid size + rules + spectator
//     toggle + auto-close duration + Create button)
//   • LobbyView for the in-room view (auto-close timer, share code,
//     players list, pending invites, lobby chat, ready toggle / start
//     button, cancel room button)
//   • BackButtonGuard for the back button (host: Close Room? / player:
//     Leave Room?)
//
// The existing DbNotifier handles game-specific logic (creating the
// dotsboxes_games row + host's dotsboxes_players row, transitioning
// to 'active' when the host starts the match). The RoomController
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
import 'dotsboxes_provider.dart';

class DotsboxesLobbyScreen extends ConsumerStatefulWidget {
  const DotsboxesLobbyScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<DotsboxesLobbyScreen> createState() =>
      _DotsboxesLobbyScreenState();
}

class _DotsboxesLobbyScreenState extends ConsumerState<DotsboxesLobbyScreen> {
  int _gridSize = 5;

  /// The room controller key for this Dots & Boxes lobby.
  RoomControllerKey get _roomKey =>
      RoomControllerKey(RoomConfig.dotsboxes, widget.familyId);

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
            .read(dbProvider(widget.familyId).notifier)
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
        .read(dbProvider(widget.familyId).notifier)
        .createGame(gridSize: _gridSize);
    if (gameId == null) return;
    await ref
        .read(roomControllerProvider(_roomKey).notifier)
        .attachToExistingGame(
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
              '1-3 family members can join (2-4 total).',
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
    final dbState = ref.watch(dbProvider(widget.familyId));
    final roomState = ref.watch(roomControllerProvider(_roomKey));
    final hasGame = dbState.game != null || roomState.hasGame;

    // Auto-navigate to the board once the game becomes active
    ref.listen<DbState>(dbProvider(widget.familyId), (previous, next) {
      final shouldNavigate = next.isInProgress;
      final wasInProgress = previous?.isInProgress ?? false;
      final gameId = next.game?.id;
      if (shouldNavigate && !wasInProgress && gameId != null && mounted) {
        context.pushReplacement(
          '/family/${widget.familyId}/dotsboxes/board/$gameId',
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
            ref.read(dbProvider(widget.familyId).notifier).leaveGame();
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/family/${widget.familyId}');
            }
          },
        ),
        title: Text(
          'Dots and Boxes',
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
                  _shareCode(roomState.gameId ?? dbState.game?.id),
            ),
        ],
      ),
      body: dbState.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: KinrelColors.orange),
            )
          : (dbState.error != null && !hasGame)
              ? DKErrorState(
                  message: dbState.error!,
                  onRetry: _createGame,
                )
              : hasGame
                  ? LobbyView(
                      roomKey: _roomKey,
                      gameType: GameType.dotsboxes,
                      gameDisplayName: 'Dots & Boxes',
                      startGame: () => ref
                          .read(dbProvider(widget.familyId).notifier)
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
      defaultAutoCloseMinutes: 5,
      child: _gameSetupFields(),
    );
  }

  Widget _gameSetupFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Grid Size'),
        const SizedBox(height: KinrelSpacing.sm),
        _gridSizeSelector(),
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

  Widget _gridSizeSelector() {
    return Wrap(
      spacing: KinrelSpacing.sm,
      runSpacing: KinrelSpacing.sm,
      children: [5, 9].map((n) {
        final selected = n == _gridSize;
        return GestureDetector(
          onTap: () {
            unawaited(GameMotionTokens.tap());
            setState(() => _gridSize = n);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: KinrelSpacing.md,
              vertical: KinrelSpacing.sm,
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
              '${n}×$n boxes',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? KinrelColors.orange : KinrelColors.textDim,
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
            '• Take turns drawing lines between adjacent dots\n'
            '• Complete the 4th side of a box to capture it\n'
            '• Capturing a box = bonus turn (keep drawing!)\n'
            '• Chain captures: multiple boxes in one move\n'
            '• Most boxes when grid is full wins!',
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
