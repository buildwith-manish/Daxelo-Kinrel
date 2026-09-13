// lib/features/games/nameplace/nameplace_lobby_screen.dart
//
// Name, Place, Animal, Thing — Lobby / Setup screen.
// Route: /family/$familyId/nameplace/lobby
//
// Refactored to use the shared multiplayer framework:
//   • RoomSetupView for the setup view (total rounds + round timer +
//     categories + rules + spectator toggle + auto-close duration +
//     Create button)
//   • LobbyView for the in-room view (auto-close timer, share code,
//     players list, pending invites, lobby chat, ready toggle / start
//     button, cancel room button)
//   • BackButtonGuard for the back button (host: Close Room? / player:
//     Leave Room?)
//
// The existing NameplaceNotifier handles game-specific logic (creating
// the nameplace_games row + host's nameplace_players row,
// transitioning to 'active' when the host starts the match). The
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
import 'nameplace_provider.dart';

class NameplaceLobbyScreen extends ConsumerStatefulWidget {
  const NameplaceLobbyScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<NameplaceLobbyScreen> createState() =>
      _NameplaceLobbyScreenState();
}

class _NameplaceLobbyScreenState extends ConsumerState<NameplaceLobbyScreen> {
  int _totalRounds = 5;
  int _roundTimer = 60;

  /// The room controller key for this Name Place lobby.
  RoomControllerKey get _roomKey =>
      RoomControllerKey(RoomConfig.nameplace, widget.familyId);

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
            .read(nameplaceProvider(widget.familyId).notifier)
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
        .read(nameplaceProvider(widget.familyId).notifier)
        .createGame(
          totalRounds: _totalRounds,
          roundTimerSeconds: _roundTimer,
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
            const SizedBox(height: KinrelSpacing.md),
            Text(
              'Up to 19 family members can join. Categories: Name, Place, Animal, Thing, Movie.',
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
    final npState = ref.watch(nameplaceProvider(widget.familyId));
    final roomState = ref.watch(roomControllerProvider(_roomKey));
    final hasGame = npState.game != null || roomState.hasGame;

    // Auto-navigate to the letter-pick screen when the host starts the
    // match (transitions to in_progress, no letter chosen yet).
    ref.listen<NameplaceState>(
      nameplaceProvider(widget.familyId),
      (previous, next) {
        final wasInProgress = previous?.isInProgress ?? false;
        final shouldNavigate = next.isInProgress &&
            next.game?.currentLetter == null &&
            next.game?.id != null;
        if (shouldNavigate && !wasInProgress && mounted) {
          context.pushReplacement(
            '/family/${widget.familyId}/nameplace/letter/${next.game!.id}',
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
            ref.read(nameplaceProvider(widget.familyId).notifier).leaveGame();
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/family/${widget.familyId}');
            }
          },
        ),
        title: Text(
          'Name, Place, Animal, Thing',
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
                  _shareCode(roomState.gameId ?? npState.game?.id),
            ),
        ],
      ),
      body: npState.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: KinrelColors.orange),
            )
          : (npState.error != null && !hasGame)
              ? DKErrorState(
                  message: npState.error!,
                  onRetry: _createGame,
                )
              : hasGame
                  ? LobbyView(
                      roomKey: _roomKey,
                      gameType: GameType.nameplace,
                      gameDisplayName: 'Name Place Animal Thing',
                      startGame: () => ref
                          .read(nameplaceProvider(widget.familyId).notifier)
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
        _sectionLabel('Total Rounds'),
        const SizedBox(height: KinrelSpacing.sm),
        Slider(
          value: _totalRounds.toDouble(),
          min: 1,
          max: 10,
          divisions: 9,
          activeColor: KinrelColors.orange,
          label: '$_totalRounds',
          onChanged: (v) => setState(() => _totalRounds = v.round()),
        ),
        const SizedBox(height: KinrelSpacing.lg),
        _sectionLabel('Round Timer: ${_roundTimer}s'),
        const SizedBox(height: KinrelSpacing.sm),
        Slider(
          value: _roundTimer.toDouble(),
          min: 30,
          max: 120,
          divisions: 9,
          activeColor: KinrelColors.orange,
          label: '${_roundTimer}s',
          onChanged: (v) => setState(() => _roundTimer = v.round()),
        ),
        const SizedBox(height: KinrelSpacing.lg),
        _sectionLabel('Categories'),
        const SizedBox(height: KinrelSpacing.sm),
        _categoriesChips(),
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

  Widget _categoriesChips() {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: ['Name', 'Place', 'Animal', 'Thing', 'Movie'].map((c) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: KinrelColors.darkCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: KinrelColors.border),
          ),
          child: Text(
            c,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              color: KinrelColors.textWhite,
              fontWeight: FontWeight.w600,
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
          _ruleLine('1.', 'Each round, one player picks a letter.'),
          const SizedBox(height: 6),
          _ruleLine('2.',
              'All players write one answer per category starting with that letter.'),
          const SizedBox(height: 6),
          _ruleLine('3.', 'Can\'t answer? Enter a dash (-).'),
          const SizedBox(height: 6),
          _ruleLine('4.', 'Unique answer = 10 pts. Duplicate = 5 pts. Dash = 0 pts.'),
          const SizedBox(height: 6),
          _ruleLine(
            '★',
            'Highest total after $_totalRounds rounds wins!',
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
