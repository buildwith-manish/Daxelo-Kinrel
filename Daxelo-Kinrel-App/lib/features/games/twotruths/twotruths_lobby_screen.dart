// lib/features/games/twotruths/twotruths_lobby_screen.dart
//
// v2 (premium lobby system): setup phase renders the shared
// LobbySetupScreen — compact hero, visible mode/rounds/timer settings,
// spectator toggle, collapsible How to Play, pinned Create Game CTA.
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
import '../shared/widgets/lobby_kit/lobby_kit.dart';
import '../shared/widgets/temporary_lobby_view.dart';
import '../shared/widgets/room_lifecycle_listener.dart';
import 'twotruths_models.dart';
import 'twotruths_provider.dart';

class TtLobbyScreen extends ConsumerStatefulWidget {
  const TtLobbyScreen({super.key, required this.familyId}); final String familyId;
  @override
  ConsumerState<TtLobbyScreen> createState() => _TtLobbyScreenState();
}
class _TtLobbyScreenState extends ConsumerState<TtLobbyScreen> {
  TtMode _mode = TtMode.playerAuthored; int _totalRounds = 3; int _timer = 30; bool _creating = false;
  bool _spectatorsEnabled = true;

  @override
  void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) {
    final joinId = GoRouterState.of(context).uri.queryParameters['join'];
    if (joinId != null && joinId.isNotEmpty) ref.read(ttProvider(widget.familyId).notifier).joinGame(joinId);
  }); }

  Future<void> _createGame() async { setState(() => _creating = true); await ref.read(ttProvider(widget.familyId).notifier).createGame(mode: _mode, totalRounds: _totalRounds, roundTimerSeconds: _timer); if (mounted) setState(() => _creating = false); }

  Future<void> _shareCode(String? gameId) async {
    if (gameId == null) return; final code = gameId.replaceAll('-', '').substring(0, 6).toUpperCase(); GameMotionTokens.tap();
    if (!mounted) return;
    await showModalBottomSheet<void>(context: context, backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(KinrelRadius.lg))),
      builder: (_) => Padding(padding: const EdgeInsets.all(KinrelSpacing.xl), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Share this code', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 18, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
        const SizedBox(height: KinrelSpacing.md),
        Text(code, style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 40, fontWeight: FontWeight.w700, color: KinrelColors.orange, letterSpacing: 6)),
        const SizedBox(height: KinrelSpacing.lg),
        DKButton(label: 'Done', variant: DKButtonVariant.primary, fullWidth: true, onPressed: () { if (context.canPop()) { context.pop(); } else { context.go('/family/${widget.familyId}'); } }),
      ])));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ttProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isHost = state.game?.hostUserId == myId || state.game == null; final hasGame = state.game != null;
    ref.listen<TtState>(ttProvider(widget.familyId), (prev, next) {
      if (next.isInProgress && !(prev?.isInProgress ?? false) && next.game?.id != null && mounted)
        context.pushReplacement('/family/${widget.familyId}/twotruths/submit/${next.game!.id}');
    });
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
            ? Text('Two Truths and a Lie', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600, color: KinrelColors.textWhite))
            : null,
        backgroundColor: KinrelColors.darkCard, foregroundColor: KinrelColors.textWhite, elevation: 0,
        actions: [
          if (hasGame && isHost)
            IconButton(
              tooltip: 'Invite family member',
              icon: const Icon(Icons.person_add_outlined),
              onPressed: () {
                final code = state.game!.id.replaceAll('-', '').substring(0, 6).toUpperCase();
                GameMotionTokens.tap();
                InviteFamilySheet.show(
                  context,
                  familyId: widget.familyId,
                  gameType: GameType.twotruths,
                  gameId: state.game!.id,
                  roomCode: code,
                  currentPlayerIds: state.players.map((p) => p.userId).whereType<String>().toSet(),
                  maxPlayers: 12,
                  currentPlayers: state.players.length,
                );
              },
            ),
          if (hasGame) IconButton(icon: const Icon(Icons.share_outlined), onPressed: () => _shareCode(state.game?.id)),
        ],
      ),
      body: state.isLoading ? const Center(child: CircularProgressIndicator(color: KinrelColors.orange)) : !hasGame ? _setupView() : _lobbyView(state, isHost),
    );
  }

  Widget _setupView() {
    return LobbySetupScreen(
      gameId: 'twotruths',
      title: 'Two Truths and a Lie',
      tagline: 'Bluff your family, spot the fib, score the points',
      facts: [
        LobbyFact(icon: Icons.layers_outlined, label: '$_totalRounds rounds'),
        LobbyFact(icon: Icons.timer_outlined, label: '$_timer s guesses'),
      ],
      settings: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LobbySection(
            label: 'Game Mode',
            child: LobbyChoiceGrid<TtMode>(
              options: const [
                LobbyOption(
                  value: TtMode.playerAuthored,
                  label: 'Player-Authored',
                  icon: Icons.person,
                  caption: 'You write all 3 statements (2 true, 1 lie)',
                ),
                LobbyOption(
                  value: TtMode.aiLie,
                  label: 'AI Lie',
                  icon: Icons.smart_toy,
                  caption: 'You write 2 truths, AI generates the lie',
                ),
              ],
              selected: _mode,
              onSelect: (m) => setState(() => _mode = m),
            ),
          ),
          const SizedBox(height: KinrelSpacing.md),
          LobbySliderRow(
            label: 'Total Rounds',
            valueLabel: '$_totalRounds',
            value: _totalRounds,
            min: 1,
            max: 12,
            divisions: 11,
            onChanged: (v) => setState(() => _totalRounds = v),
          ),
          const SizedBox(height: KinrelSpacing.sm),
          LobbySliderRow(
            label: 'Guess Timer',
            valueLabel: '$_timer s',
            value: _timer,
            min: 15,
            max: 90,
            divisions: 15,
            onChanged: (v) => setState(() => _timer = v),
          ),
        ],
      ),
      rules: const [
        LobbyRule('Each round, one player submits 3 statements (2 true, 1 lie).'),
        LobbyRule('Others guess which is the lie.'),
        LobbyRule('Correct guess = 1pt. Each fooled player = 1pt for submitter.'),
      ],
      rulesFootnote: 'Highest total after $_totalRounds rounds wins!',
      spectatorsEnabled: _spectatorsEnabled,
      onSpectatorsChanged: (v) => setState(() => _spectatorsEnabled = v),
      ctaLabel: 'Create Game',
      ctaHint: 'Up to 11 family members can join',
      ctaLoading: _creating,
      onCtaPressed: _createGame,
    );
  }

  Widget _lobbyView(TtState state, bool isHost) {
    final game = state.game!;
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final notifier = ref.read(ttProvider(widget.familyId).notifier);

    // Map provider state → TemporaryLobbyConfig
    final lobbyStatus = game.isInProgress
        ? TemporaryLobbyStatus.starting
        : game.isCompleted
            ? TemporaryLobbyStatus.finished
            : TemporaryLobbyStatus.waiting;

    final lobbyPlayers = state.players
        .map((p) => TemporaryLobbyPlayer(
              userId: p.userId,
              userName: p.userName,
              isReady: p.isReady,
              isHost: p.userId == game.hostUserId,
              joinedAt: p.joinedAt,
            ))
        .toList();

    final config = TemporaryLobbyConfig(
      gameTable: 'twotruths_games',
      gameId: game.id,
      familyId: widget.familyId,
      hostUserId: game.hostUserId,
      players: lobbyPlayers,
      maxPlayers: 12,
      status: lobbyStatus,
      subtitle: '${game.mode == TtMode.aiLie ? 'AI Lie' : 'Player-Authored'} · ${game.totalRounds} rounds',
    );

    return RoomLifecycleListener(
          gameTable: 'twotruths_games',
          gameId: game.id,
          familyId: widget.familyId,
          isHost: (game.hostUserId == myId),
          child: TemporaryLobbyView(
        config: config,
        myUserId: myId,
        onToggleReady: (isReady) => notifier.toggleReady(isReady),
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
                  gameType: GameType.twotruths,
                  gameId: game.id,
                  roomCode: code,
                  currentPlayerIds: state.players
                      .map((p) => p.userId)
                      .whereType<String>()
                      .toSet(),
                  maxPlayers: 12,
                  currentPlayers: state.players.length,
                );
              }
            : null,
    ),
    );
  }
}
