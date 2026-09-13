// lib/features/games/ludo/ludo_lobby_screen.dart
//
// Ludo — Lobby screen to start a game and invite 1-3 family members.
// Route: /family/$familyId/ludo/lobby
//
// Refactored to use the shared multiplayer framework:
//   • RoomSetupView for the setup view (player count + spectator toggle +
//     auto-close duration + Create button)
//   • LobbyView for the in-room view (auto-close timer, share code,
//     players list, pending invites, lobby chat, ready toggle / start
//     button, cancel room button)
//   • BackButtonGuard for the back button (host: Close Room? / player:
//     Leave Room?)
//
// The existing LudoNotifier handles game-specific logic (creating the
// ludo_games row + host's ludo_players + token rows, transitioning to
// 'in_progress' when the host starts the match, calling the
// ludo-roll-dice Edge Function). The RoomController handles the shared
// room lifecycle.

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
import 'ludo_game_logic.dart';
import 'ludo_provider.dart';

class LudoLobbyScreen extends ConsumerStatefulWidget {
  const LudoLobbyScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<LudoLobbyScreen> createState() => _LudoLobbyScreenState();
}

class _LudoLobbyScreenState extends ConsumerState<LudoLobbyScreen> {
  int _playerCount = 4;

  RoomControllerKey get _roomKey =>
      RoomControllerKey(RoomConfig.ludo, widget.familyId);

  String? get _joinIdFromRoute =>
      GoRouterState.of(context).uri.queryParameters['join'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final joinId = _joinIdFromRoute;
      if (joinId != null && joinId.isNotEmpty) {
        final ok = await ref
            .read(ludoProvider(widget.familyId).notifier)
            .joinGame(joinId);
        if (ok) {
          await ref.read(roomControllerProvider(_roomKey).notifier).attachOnJoin(joinId);
        }
      }
    });
  }

  Future<void> _createGame() async {
    final gameId = await ref
        .read(ludoProvider(widget.familyId).notifier)
        .createGame(playerCount: _playerCount);
    if (gameId == null) return;
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
              'Up to ${_playerCount - 1} family members can join. Colors are assigned in order: Red, Blue, Green, Yellow.',
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
    final ludoState = ref.watch(ludoProvider(widget.familyId));
    final roomState = ref.watch(roomControllerProvider(_roomKey));
    final hasGame = ludoState.game != null || roomState.hasGame;

    // Auto-navigate to board when game starts
    ref.listen<LudoState>(ludoProvider(widget.familyId), (previous, next) {
      if (next.isInProgress &&
          !(previous?.isInProgress ?? false) &&
          next.game?.id != null &&
          mounted) {
        context.pushReplacement(
          '/family/${widget.familyId}/ludo/board/${next.game!.id}',
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
            ref.read(ludoProvider(widget.familyId).notifier).leaveGame();
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/family/${widget.familyId}');
            }
          },
        ),
        title: Text(
          'Ludo',
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
                  _shareCode(roomState.gameId ?? ludoState.game?.id),
            ),
        ],
      ),
      body: ludoState.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: KinrelColors.orange),
            )
          : hasGame
              ? LobbyView(
                  roomKey: _roomKey,
                  gameType: GameType.ludo,
                  gameDisplayName: 'Ludo',
                  startGame: () => ref
                      .read(ludoProvider(widget.familyId).notifier)
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
      defaultAutoCloseMinutes: 5,
      child: _gameSetupFields(),
    );
  }

  Widget _gameSetupFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Players'),
        const SizedBox(height: KinrelSpacing.sm),
        _playerCountSelector(),
        const SizedBox(height: KinrelSpacing.lg),
        // Color legend
        _colorLegend(),
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

  Widget _playerCountSelector() {
    return Wrap(
      spacing: KinrelSpacing.sm,
      runSpacing: KinrelSpacing.sm,
      children: [2, 3, 4].map((c) {
        final selected = c == _playerCount;
        return GestureDetector(
          onTap: () {
            unawaited(GameMotionTokens.tap());
            setState(() => _playerCount = c);
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
                  c == 2
                      ? Icons.person_outline
                      : c == 3
                          ? Icons.group_outlined
                          : Icons.groups_outlined,
                  size: 18,
                  color: selected ? KinrelColors.orange : KinrelColors.textDim,
                ),
                const SizedBox(width: 6),
                Text(
                  '$c players',
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

  Widget _colorLegend() {
    final colors = LudoColor.values.take(_playerCount).toList();
    return Container(
      padding: const EdgeInsets.all(KinrelSpacing.md),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Row(
        children: colors.map(_colorChip).toList(),
      ),
    );
  }

  Widget _colorChip(LudoColor color) {
    final c = _colorValue(color);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              color.name,
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 10,
                color: KinrelColors.textDim,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Map LudoColor → Material Color. Matches the board screen's mapping.
  Color _colorValue(LudoColor c) {
    switch (c) {
      case LudoColor.red:
        return KinrelColors.orange;
      case LudoColor.blue:
        return KinrelColors.blue;
      case LudoColor.green:
        return KinrelColors.tealAccent;
      case LudoColor.yellow:
        return KinrelColors.gold;
    }
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
          _ruleLine('1.', 'Roll the dice on your turn. Roll a 6 to move a token out of base.'),
          const SizedBox(height: 6),
          _ruleLine('2.', 'Move tokens around the board toward the home column.'),
          const SizedBox(height: 6),
          _ruleLine('3.', 'Roll a 6 → roll again. Land on an opponent → send them back to base.'),
          const SizedBox(height: 6),
          _ruleLine('4.', 'Get all 4 tokens home to win.'),
          const SizedBox(height: 6),
          _ruleLine('★', 'Dice rolls are server-authoritative — clients never roll.', highlight: true),
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
