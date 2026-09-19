// lib/features/games/impostor/impostor_lobby_screen.dart
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
import '../shared/widgets/room_lifecycle_listener.dart';
import '../shared/widgets/temporary_lobby_view.dart';
import 'impostor_engine.dart';
import 'impostor_provider.dart';

class ImpostorLobbyScreen extends ConsumerStatefulWidget {
  const ImpostorLobbyScreen({super.key, required this.familyId});
  final String familyId;
  @override ConsumerState<ImpostorLobbyScreen> createState() => _ImpostorLobbyScreenState();
}

class _ImpostorLobbyScreenState extends ConsumerState<ImpostorLobbyScreen> {
  final _roomNameController = TextEditingController();
  int _maxPlayers = 10; int _totalRounds = 3; String _wordPackId = 'food';
  int _clueSeconds = 30; int _voteSeconds = 30;
  bool _spectatorsEnabled = true; bool _creating = false;

  @override void initState() { super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      joinRoomWhenReady(context: context, ref: ref, onJoin: (id) => ref.read(impostorProvider(widget.familyId).notifier).joinGame(id));
    });
  }
  @override void dispose() { _roomNameController.dispose(); super.dispose(); }

  Future<void> _createGame() async {
    setState(() => _creating = true);
    await ref.read(impostorProvider(widget.familyId).notifier).createGame(
      maxPlayers: _maxPlayers, totalRounds: _totalRounds, wordPackId: _wordPackId,
      clueSeconds: _clueSeconds, voteSeconds: _voteSeconds,
      roomName: _roomNameController.text, spectatorsEnabled: _spectatorsEnabled);
    if (mounted) setState(() => _creating = false);
  }

  Future<void> _startMatch() async {
    final result = await ref.read(impostorProvider(widget.familyId).notifier).startGame();
    if (!mounted || result == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result), backgroundColor: KinrelColors.error, behavior: SnackBarBehavior.floating));
  }

  @override Widget build(BuildContext context) {
    final state = ref.watch(impostorProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isHost = state.game?.hostUserId == myId || state.game == null;
    ref.listen<ImpostorState>(impostorProvider(widget.familyId), (previous, next) {
      if (next.isInProgress && !(previous?.isInProgress ?? false) && next.game?.id != null && mounted) {
        context.pushReplacement('/family/${widget.familyId}/impostor/game/${next.game!.id}');
      }
    });
    final hasGame = state.game != null;
    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.canPop() ? context.pop() : context.go('/family/${widget.familyId}')),
        title: hasGame ? Text(state.game?.roomName?.isNotEmpty == true ? state.game!.roomName! : 'Who\'s the Impostor?', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)) : null,
        backgroundColor: KinrelColors.darkCard, foregroundColor: KinrelColors.textWhite, elevation: 0,
        actions: [
          if (hasGame && isHost) IconButton(tooltip: 'Invite family member', icon: const Icon(Icons.person_add_outlined), onPressed: () => _openInviteSheet(state)),
          if (hasGame) IconButton(icon: const Icon(Icons.share_outlined), onPressed: () => _shareCode(state.game?.id)),
        ],
      ),
      body: state.isLoading ? const Center(child: CircularProgressIndicator(color: KinrelColors.orange))
        : state.error != null && !hasGame ? DKErrorState(message: state.error!, onRetry: _createGame)
        : hasGame ? _lobbyView(state, isHost) : _setupView(),
    );
  }

  void _openInviteSheet(ImpostorState state) {
    final game = state.game; if (game == null) return; GameMotionTokens.tap();
    InviteFamilySheet.show(context, familyId: widget.familyId, gameType: GameType.impostor, gameId: game.id, roomCode: game.id.replaceAll('-', '').substring(0, 6).toUpperCase(), currentPlayerIds: state.players.map((p) => p.userId).whereType<String>().toSet(), maxPlayers: game.maxPlayers, currentPlayers: state.players.length);
  }

  Future<void> _shareCode(String? gameId) async {
    if (gameId == null) return;
    final code = gameId.replaceAll('-', '').substring(0, 6).toUpperCase(); GameMotionTokens.tap();
    if (!mounted) return;
    await showModalBottomSheet<void>(context: context, backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(KinrelRadius.lg))),
      builder: (_) => Padding(padding: const EdgeInsets.all(KinrelSpacing.xl), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Share this code', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 18, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
        const SizedBox(height: KinrelSpacing.md),
        Text(code, style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 40, fontWeight: FontWeight.w700, color: KinrelColors.orange, letterSpacing: 6)),
        const SizedBox(height: KinrelSpacing.md),
        Text('Up to ${_maxPlayers - 1} family members can join. Find the impostor!', textAlign: TextAlign.center, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim)),
        const SizedBox(height: KinrelSpacing.lg),
        DKButton(label: 'Done', variant: DKButtonVariant.primary, fullWidth: true, onPressed: () => context.canPop() ? context.pop() : context.go('/family/${widget.familyId}')),
      ])));
  }

  Widget _setupView() {
    return LobbySetupScreen(
      gameId: 'impostor', title: 'Who\'s the Impostor?',
      tagline: 'Social deduction — blend in or get caught!',
      facts: const [LobbyFact(icon: Icons.groups_2_outlined, label: '3–10 players'), LobbyFact(icon: Icons.casino_outlined, label: '3/5/10 rounds'), LobbyFact(icon: Icons.psychology_outlined, label: 'Find the impostor')],
      settings: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LobbySection(label: 'Room Name', child: TextField(controller: _roomNameController, maxLength: 24, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, color: KinrelColors.textWhite),
          decoration: InputDecoration(counterText: '', hintText: 'e.g. Family Mystery Night', hintStyle: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, color: KinrelColors.textDim.withValues(alpha: 0.6)),
            filled: true, fillColor: KinrelColors.darkCard, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(KinrelRadius.md), borderSide: BorderSide(color: KinrelColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(KinrelRadius.md), borderSide: const BorderSide(color: KinrelColors.orange, width: 1.4))))),
        const SizedBox(height: KinrelSpacing.md),
        LobbySection(label: 'Rounds', child: LobbyChoiceGrid<int>(selected: _totalRounds, onSelect: (v) => setState(() => _totalRounds = v), options: const [LobbyOption(value: 3, label: '3 Rounds', caption: 'Quick'), LobbyOption(value: 5, label: '5 Rounds', caption: 'Standard'), LobbyOption(value: 10, label: '10 Rounds', caption: 'Marathon')])),
        const SizedBox(height: KinrelSpacing.md),
        LobbySection(label: 'Word Pack', child: LobbyChoiceGrid<String>(selected: _wordPackId, onSelect: (v) => setState(() => _wordPackId = v), options: [for (final p in ImpostorWordPack.all) LobbyOption(value: p.id, label: p.name, caption: '${p.words.length} words', emoji: p.emoji)])),
        const SizedBox(height: KinrelSpacing.md),
        LobbySection(label: 'Max Players', child: LobbyChoiceGrid<int>(selected: _maxPlayers, onSelect: (v) => setState(() => _maxPlayers = v), options: const [LobbyOption(value: 3, label: '3'), LobbyOption(value: 5, label: '5'), LobbyOption(value: 8, label: '8'), LobbyOption(value: 10, label: '10')])),
      ]),
      rules: const [
        LobbyRule('One player is secretly the Impostor — they don\'t know the secret word. Everyone else does.'),
        LobbyRule('Each player gives a one-word clue. The Impostor must bluff a convincing clue without knowing the word!'),
        LobbyRule('After all clues, everyone votes for who they think is the Impostor. Can\'t vote for yourself.'),
        LobbyRule('Crew wins if the Impostor gets the most votes. Impostor wins if they escape detection (or it\'s a tie).'),
        LobbyRule('Multiple rounds with new words + new impostors each time. Highest cumulative score wins the match!'),
        LobbyRule('Each clue + vote has a 30-second timer. Spectators can cheer with emoji reactions!'),
      ],
      rulesFootnote: '5 word packs available: Food, Animals, Places, Activities, Family Life.',
      spectatorsEnabled: _spectatorsEnabled, onSpectatorsChanged: (v) => setState(() => _spectatorsEnabled = v),
      ctaLabel: 'Create Game', ctaHint: 'Invite family members, then find the impostor!',
      ctaLoading: _creating, onCtaPressed: _createGame,
    );
  }

  Widget _lobbyView(ImpostorState state, bool isHost) {
    final game = state.game!; final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final lobbyStatus = game.isInProgress ? TemporaryLobbyStatus.starting : game.isCompleted ? TemporaryLobbyStatus.finished : TemporaryLobbyStatus.waiting;
    final lobbyPlayers = state.players.map((p) => TemporaryLobbyPlayer(userId: p.userId, userName: p.userName, isReady: p.isReady, isHost: p.userId == game.hostUserId, joinedAt: p.joinedAt)).toList();
    final pack = ImpostorWordPack.byId(game.wordPackId);
    final config = TemporaryLobbyConfig(gameTable: 'impostor_games', gameId: game.id, familyId: widget.familyId, hostUserId: game.hostUserId, players: lobbyPlayers, maxPlayers: game.maxPlayers, status: lobbyStatus, subtitle: '${game.totalRounds} rounds · ${pack.name} · ${game.maxPlayers} max');
    return RoomLifecycleListener(gameTable: 'impostor_games', gameId: game.id, familyId: widget.familyId, isHost: game.hostUserId == myId,
      child: TemporaryLobbyView(config: config, myUserId: myId,
        onToggleReady: (isReady) => ref.read(impostorProvider(widget.familyId).notifier).toggleReady(isReady),
        onStartMatch: _startMatch,
        onCancelRoom: () => ref.read(impostorProvider(widget.familyId).notifier).leaveGame(),
        onInviteFamily: isHost ? () => _openInviteSheet(state) : null));
  }
}
