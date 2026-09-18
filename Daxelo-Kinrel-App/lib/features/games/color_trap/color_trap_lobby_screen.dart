// lib/features/games/color_trap/color_trap_lobby_screen.dart
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
import '../shared/services/temporary_room_service.dart' show kRoomClosedMessage;
import '../shared/widgets/temporary_lobby_view.dart';
import 'color_trap_engine.dart';
import 'color_trap_provider.dart';

class ColorTrapLobbyScreen extends ConsumerStatefulWidget {
  const ColorTrapLobbyScreen({super.key, required this.familyId});
  final String familyId;
  @override ConsumerState<ColorTrapLobbyScreen> createState() => _ColorTrapLobbyScreenState();
}

class _ColorTrapLobbyScreenState extends ConsumerState<ColorTrapLobbyScreen> {
  final _roomNameController = TextEditingController();
  int _maxPlayers = 8; ColorTrapDifficulty _difficulty = ColorTrapDifficulty.medium;
  bool _spectatorsEnabled = true; bool _creating = false;

  @override void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) { joinRoomWhenReady(context: context, ref: ref, onJoin: (id) => ref.read(colorTrapProvider(widget.familyId).notifier).joinGame(id)); }); }
  @override void dispose() { _roomNameController.dispose(); super.dispose(); }

  Future<void> _createGame() async {
    setState(() => _creating = true);
    await ref.read(colorTrapProvider(widget.familyId).notifier).createGame(maxPlayers: _maxPlayers, difficulty: _difficulty, roomName: _roomNameController.text, spectatorsEnabled: _spectatorsEnabled);
    if (mounted) setState(() => _creating = false);
  }

  Future<void> _startMatch() async {
    final result = await ref.read(colorTrapProvider(widget.familyId).notifier).startGame();
    if (!mounted || result == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result), backgroundColor: KinrelColors.error, behavior: SnackBarBehavior.floating));
  }

  @override Widget build(BuildContext context) {
    final state = ref.watch(colorTrapProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isHost = state.game?.hostUserId == myId || state.game == null;
    ref.listen<ColorTrapState>(colorTrapProvider(widget.familyId), (previous, next) {
      if (next.isInProgress && !(previous?.isInProgress ?? false) && next.game?.id != null && mounted) { context.pushReplacement('/family/${widget.familyId}/color-trap/game/${next.game!.id}'); }
    });
    final hasGame = state.game != null;
    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.canPop() ? context.pop() : context.go('/family/${widget.familyId}')),
        title: hasGame ? Text(state.game?.roomName?.isNotEmpty == true ? state.game!.roomName! : 'Color Trap', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)) : null,
        backgroundColor: KinrelColors.darkCard, foregroundColor: KinrelColors.textWhite, elevation: 0,
        actions: [if (hasGame && isHost) IconButton(tooltip: 'Invite', icon: const Icon(Icons.person_add_outlined), onPressed: () => _openInviteSheet(state)), if (hasGame) IconButton(icon: const Icon(Icons.share_outlined), onPressed: () => _shareCode(state.game?.id))],
      ),
      body: state.isLoading ? const Center(child: CircularProgressIndicator(color: KinrelColors.orange)) : state.error != null && !hasGame ? DKErrorState(message: state.error!, onRetry: _createGame) : hasGame ? _lobbyView(state, isHost) : _setupView(),
    );
  }

  void _openInviteSheet(ColorTrapState state) {
    final game = state.game; if (game == null) return; GameMotionTokens.tap();
    InviteFamilySheet.show(context, familyId: widget.familyId, gameType: GameType.colorTrap, gameId: game.id, roomCode: game.id.replaceAll('-', '').substring(0, 6).toUpperCase(), currentPlayerIds: state.players.map((p) => p.userId).whereType<String>().toSet(), maxPlayers: game.maxPlayers, currentPlayers: state.players.length);
  }

  Future<void> _shareCode(String? gameId) async {
    if (gameId == null) return; final code = gameId.replaceAll('-', '').substring(0, 6).toUpperCase(); GameMotionTokens.tap(); if (!mounted) return;
    await showModalBottomSheet<void>(context: context, backgroundColor: KinrelColors.darkCard, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(KinrelRadius.lg))), builder: (_) => Padding(padding: const EdgeInsets.all(KinrelSpacing.xl), child: Column(mainAxisSize: MainAxisSize.min, children: [Text('Share this code', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 18, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)), const SizedBox(height: KinrelSpacing.md), Text(code, style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 40, fontWeight: FontWeight.w700, color: KinrelColors.orange, letterSpacing: 6)), const SizedBox(height: KinrelSpacing.md), Text('Up to ${_maxPlayers - 1} members. Last one standing wins!', textAlign: TextAlign.center, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim)), const SizedBox(height: KinrelSpacing.lg), DKButton(label: 'Done', variant: DKButtonVariant.primary, fullWidth: true, onPressed: () => context.canPop() ? context.pop() : context.go('/family/${widget.familyId}'))])));
  }

  Widget _setupView() {
    return LobbySetupScreen(
      gameId: 'color-trap', title: 'Color Trap', tagline: 'Last player standing — move to the safe color or fall!',
      facts: const [LobbyFact(icon: Icons.groups_2_outlined, label: '2–8 players'), LobbyFact(icon: Icons.grid_view_outlined, label: 'Colored tile grid'), LobbyFact(icon: Icons.emoji_events_outlined, label: 'Last one alive wins')],
      settings: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LobbySection(label: 'Room Name', child: TextField(controller: _roomNameController, maxLength: 24, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, color: KinrelColors.textWhite), decoration: InputDecoration(counterText: '', hintText: 'e.g. Color Survival', hintStyle: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, color: KinrelColors.textDim.withValues(alpha: 0.6)), filled: true, fillColor: KinrelColors.darkCard, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(KinrelRadius.md), borderSide: BorderSide(color: KinrelColors.border)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(KinrelRadius.md), borderSide: const BorderSide(color: KinrelColors.orange, width: 1.4))))),
        const SizedBox(height: KinrelSpacing.md),
        LobbySection(label: 'Difficulty', caption: 'Controls colors, tile size, and countdown speed', child: LobbyChoiceGrid<ColorTrapDifficulty>(selected: _difficulty, onSelect: (v) => setState(() => _difficulty = v), options: const [LobbyOption(value: ColorTrapDifficulty.easy, label: 'Easy', caption: '4 colors · 5s'), LobbyOption(value: ColorTrapDifficulty.medium, label: 'Medium', caption: '5 colors · 4s'), LobbyOption(value: ColorTrapDifficulty.hard, label: 'Hard', caption: '6 colors · 3s'), LobbyOption(value: ColorTrapDifficulty.expert, label: 'Expert', caption: '8 colors · 2s')])),
        const SizedBox(height: KinrelSpacing.md),
        LobbySection(label: 'Max Players', child: LobbyChoiceGrid<int>(selected: _maxPlayers, onSelect: (v) => setState(() => _maxPlayers = v), options: const [LobbyOption(value: 2, label: '2'), LobbyOption(value: 4, label: '4'), LobbyOption(value: 6, label: '6'), LobbyOption(value: 8, label: '8')])),
      ]),
      rules: const [
        LobbyRule('Players stand on a grid of colored tiles. A target color is announced.'),
        LobbyRule('Move to a tile of the target color before the countdown ends!'),
        LobbyRule('When time\'s up, all non-target tiles disappear. Players on wrong colors fall and are eliminated.'),
        LobbyRule('The arena regenerates and a new round begins. Last player alive wins!'),
        LobbyRule('Tap adjacent tiles to move. Eliminated players become spectators.'),
        LobbyRule('Each round has a countdown timer. Final rounds are faster with more colors!'),
      ],
      rulesFootnote: '4 difficulty levels: Easy (4 colors, 5s) → Expert (8 colors, 2s).',
      spectatorsEnabled: _spectatorsEnabled, onSpectatorsChanged: (v) => setState(() => _spectatorsEnabled = v),
      ctaLabel: 'Create Game', ctaHint: 'Invite family members, then survive the colors!',
      ctaLoading: _creating, onCtaPressed: _createGame);
  }

  Widget _lobbyView(ColorTrapState state, bool isHost) {
    final game = state.game!; final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final lobbyStatus = game.isInProgress ? TemporaryLobbyStatus.starting : game.isCompleted ? TemporaryLobbyStatus.finished : TemporaryLobbyStatus.waiting;
    final lobbyPlayers = state.players.map((p) => TemporaryLobbyPlayer(userId: p.userId, userName: p.userName, isReady: p.isReady, isHost: p.userId == game.hostUserId, joinedAt: p.joinedAt)).toList();
    final config = TemporaryLobbyConfig(gameTable: 'color_trap_games', gameId: game.id, familyId: widget.familyId, hostUserId: game.hostUserId, players: lobbyPlayers, maxPlayers: game.maxPlayers, status: lobbyStatus, subtitle: '${game.difficulty.label} · ${game.maxPlayers} max · ${game.difficulty.colorCount} colors');
    return RoomLifecycleListener(gameTable: 'color_trap_games', gameId: game.id, familyId: widget.familyId, isHost: game.hostUserId == myId, child: TemporaryLobbyView(config: config, myUserId: myId, onToggleReady: (isReady) => ref.read(colorTrapProvider(widget.familyId).notifier).toggleReady(isReady), onStartMatch: _startMatch, onCancelRoom: () => ref.read(colorTrapProvider(widget.familyId).notifier).leaveGame(), onInviteFamily: isHost ? () => _openInviteSheet(state) : null));
  }
}
