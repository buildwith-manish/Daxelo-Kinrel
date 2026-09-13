// lib/features/games/truthordare/truthordare_lobby_screen.dart
//
// Truth or Dare — Lobby / Setup screen.
// Route: /family/$familyId/truthordare/lobby
//
// Refactored to use the shared multiplayer framework:
//   • RoomSetupView for the setup view (description + rules + approved
//     prompt count + spectator toggle + auto-close duration +
//     Create button)
//   • LobbyView for the in-room view (auto-close timer, share code,
//     players list, pending invites, lobby chat, ready toggle / start
//     button, cancel room button)
//   • BackButtonGuard for the back button (host: Close Room? / player:
//     Leave Room?)
//
// The existing TodNotifier handles game-specific logic (creating the
// truthordare_games row + host's truthordare_players row,
// transitioning to 'in_progress' when the host starts the match).
// The RoomController handles the shared room lifecycle.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../game_motion_tokens.dart';
import '../shared/multiplayer/multiplayer.dart';
import '../shared/models/game_invite.dart';
import 'truthordare_provider.dart';

class TodLobbyScreen extends ConsumerStatefulWidget {
  const TodLobbyScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<TodLobbyScreen> createState() => _TodLobbyScreenState();
}

class _TodLobbyScreenState extends ConsumerState<TodLobbyScreen> {
  /// The room controller key for this Truth or Dare lobby.
  RoomControllerKey get _roomKey =>
      RoomControllerKey(RoomConfig.truthordare, widget.familyId);

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
            .read(todProvider(widget.familyId).notifier)
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
        .read(todProvider(widget.familyId).notifier)
        .createGame();
    if (gameId == null) return;
    await ref
        .read(roomControllerProvider(_roomKey).notifier)
        .attachToExistingGame(
          gameId,
          spectatorsEnabled: true,
          autoCloseMinutes: 10,
        );
  }

  Future<int> _loadPromptCount() async {
    final client = ref.read(supabaseProvider);
    if (client == null) return 0;
    try {
      final resp = await client
          .from('truthordare_prompts')
          .select()
          .eq('familyId', widget.familyId)
          .eq('status', 'approved');
      return resp.length;
    } catch (_) {
      return 0;
    }
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
              '4-12 players. Spin the bottle, pick Truth or Dare!',
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
    final todState = ref.watch(todProvider(widget.familyId));
    final roomState = ref.watch(roomControllerProvider(_roomKey));
    final hasGame = todState.game != null || roomState.hasGame;

    // Auto-navigate to the table once the game becomes active
    ref.listen<TodState>(todProvider(widget.familyId), (previous, next) {
      final shouldNavigate = next.isInProgress;
      final wasInProgress = previous?.isInProgress ?? false;
      final gameId = next.game?.id;
      if (shouldNavigate && !wasInProgress && gameId != null && mounted) {
        context.pushReplacement(
          '/family/${widget.familyId}/truthordare/table/$gameId',
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
            ref.read(todProvider(widget.familyId).notifier).leaveGame();
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/family/${widget.familyId}');
            }
          },
        ),
        title: Text(
          'Truth or Dare',
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
          // Game-specific admin actions (always available, even before
          // a game is created): submit a new prompt, or review pending
          // prompt submissions.
          IconButton(
            tooltip: 'Submit a prompt',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () =>
                context.push('/family/${widget.familyId}/truthordare/submit'),
          ),
          IconButton(
            tooltip: 'Review pending prompts',
            icon: const Icon(Icons.rate_review),
            onPressed: () =>
                context.push('/family/${widget.familyId}/truthordare/review'),
          ),
          if (hasGame && roomState.isHost)
            IconButton(
              tooltip: 'Share code',
              icon: const Icon(Icons.share_outlined),
              onPressed: () =>
                  _shareCode(roomState.gameId ?? todState.game?.id),
            ),
        ],
      ),
      body: todState.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: KinrelColors.orange),
            )
          : hasGame
              ? LobbyView(
                  roomKey: _roomKey,
                  gameType: GameType.truthordare,
                  gameDisplayName: 'Truth or Dare',
                  startGame: () => ref
                      .read(todProvider(widget.familyId).notifier)
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
        Text(
          'Truth or Dare',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textWhite,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Spin the bottle, pick Truth or Dare, answer family-submitted prompts!',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 12,
            color: KinrelColors.textDim,
          ),
        ),
        const SizedBox(height: KinrelSpacing.lg),
        _rulesCard(),
        const SizedBox(height: KinrelSpacing.lg),
        FutureBuilder<int>(
          future: _loadPromptCount(),
          builder: (context, snapshot) => Text(
            '${snapshot.data ?? 0} approved prompts ready',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              color: KinrelColors.textDim,
            ),
          ),
        ),
      ],
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
          _rule('1. Each round, the spinner taps to spin the bottle.'),
          const SizedBox(height: 4),
          _rule('2. The bottle lands on a random player (never the spinner).'),
          const SizedBox(height: 4),
          _rule('3. That player picks Truth or Dare.'),
          const SizedBox(height: 4),
          _rule('4. A random approved prompt is revealed.'),
          const SizedBox(height: 4),
          _rule('5. Complete the prompt and tap Done!'),
          const SizedBox(height: 4),
          _rule(
            '★ Submit your own prompts via the + icon!',
            highlight: true,
          ),
        ],
      ),
    );
  }

  Widget _rule(String text, {bool highlight = false}) => Text(
        text,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 12,
          color: highlight ? KinrelColors.orange : KinrelColors.textDim,
          height: 1.4,
        ),
      );
}
