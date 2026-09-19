// lib/features/games/crystal_bridge/crystal_bridge_lobby_screen.dart
//
// Crystal Bridge — Create Room lobby.
// Route: /family/$familyId/crystal-bridge/lobby
//
// Setup screen: room name, bridge type (5 options), match length
// (10/20/30 rows), team mode (solo / 2v2 / 3v3 / 4v4), turn timer
// (15/20/30s), max players. Once the host creates the room we
// transition to the shared TemporaryLobbyView for the waiting room,
// then auto-navigate to the game screen when isInProgress becomes true.

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
import 'crystal_bridge_engine.dart';
import 'crystal_bridge_models.dart';
import 'crystal_bridge_provider.dart';

/// Cyan accent — evokes the crystal / ice / "live bridge" theme.
const Color kCrystalBridgeAccent = Color(0xFF06B6D4);

class CrystalBridgeLobbyScreen extends ConsumerStatefulWidget {
  const CrystalBridgeLobbyScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<CrystalBridgeLobbyScreen> createState() =>
      _CrystalBridgeLobbyScreenState();
}

class _CrystalBridgeLobbyScreenState
    extends ConsumerState<CrystalBridgeLobbyScreen> {
  final _roomNameController = TextEditingController();
  CrystalBridgeType _bridgeType = CrystalBridgeType.crystal;
  int _totalRows = 20;
  CrystalBridgeTeamMode _teamMode = CrystalBridgeTeamMode.solo;
  int _turnSeconds = 20;
  int _maxPlayers = 8;
  bool _spectatorsEnabled = true;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      joinRoomWhenReady(
        context: context,
        ref: ref,
        onJoin: (id) => ref
            .read(crystalBridgeProvider(widget.familyId).notifier)
            .joinGame(id),
      );
    });
  }

  @override
  void dispose() {
    _roomNameController.dispose();
    super.dispose();
  }

  Future<void> _createGame() async {
    setState(() => _creating = true);
    await ref.read(crystalBridgeProvider(widget.familyId).notifier).createGame(
          maxPlayers: _maxPlayers,
          bridgeType: _bridgeType,
          totalRows: _totalRows,
          teamMode: _teamMode,
          turnSeconds: _turnSeconds,
          roomName: _roomNameController.text,
          spectatorsEnabled: _spectatorsEnabled,
        );
    if (mounted) setState(() => _creating = false);
  }

  Future<void> _startMatch() async {
    final result = await ref
        .read(crystalBridgeProvider(widget.familyId).notifier)
        .startGame();
    if (!mounted || result == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result),
        backgroundColor: KinrelColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(crystalBridgeProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isHost = state.game?.hostUserId == myId || state.game == null;

    ref.listen(crystalBridgeProvider(widget.familyId), (previous, next) {
      if (next.isInProgress &&
          !(previous?.isInProgress ?? false) &&
          next.game?.id != null &&
          mounted) {
        context.pushReplacement(
          '/family/${widget.familyId}/crystal-bridge/game/${next.game!.id}',
        );
      }
    });

    final hasGame = state.game != null;
    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go('/family/${widget.familyId}'),
        ),
        title: hasGame
            ? Text(
                state.game?.roomName?.isNotEmpty == true
                    ? state.game!.roomName!
                    : 'Crystal Bridge',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textWhite,
                ),
              )
            : null,
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
        actions: [
          if (hasGame && isHost)
            IconButton(
              tooltip: 'Invite',
              icon: const Icon(Icons.person_add_outlined),
              onPressed: () => _openInviteSheet(state),
            ),
          if (hasGame)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              onPressed: () => _shareCode(state.game?.id),
            ),
        ],
      ),
      body: state.isLoading
          ? const Center(
              child:
                  CircularProgressIndicator(color: kCrystalBridgeAccent))
          : state.error != null && !hasGame
              ? DKErrorState(message: state.error!, onRetry: _createGame)
              : hasGame
                  ? _lobbyView(state, isHost)
                  : _setupView(),
    );
  }

  void _openInviteSheet(CrystalBridgeState_ state) {
    final game = state.game;
    if (game == null) return;
    GameMotionTokens.tap();
    InviteFamilySheet.show(
      context,
      familyId: widget.familyId,
      gameType: GameType.crystalBridge,
      gameId: game.id,
      roomCode: game.id.replaceAll('-', '').substring(0, 6).toUpperCase(),
      currentPlayerIds:
          state.players.map((p) => p.userId).whereType<String>().toSet(),
      maxPlayers: game.maxPlayers,
      currentPlayers: state.players.length,
    );
  }

  Future<void> _shareCode(String? gameId) async {
    if (gameId == null) return;
    final code = gameId.replaceAll('-', '').substring(0, 6).toUpperCase();
    GameMotionTokens.tap();
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
            Text('Share this code',
                style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.textWhite)),
            const SizedBox(height: KinrelSpacing.md),
            Text(code,
                style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 40,
                    fontWeight: FontWeight.w700,
                    color: kCrystalBridgeAccent,
                    letterSpacing: 6)),
            const SizedBox(height: KinrelSpacing.md),
            Text(
              'Up to ${_maxPlayers - 1} members. Cross the bridge — last survivor or first to finish wins!',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  color: KinrelColors.textDim),
            ),
            const SizedBox(height: KinrelSpacing.lg),
            DKButton(
              label: 'Done',
              variant: DKButtonVariant.primary,
              fullWidth: true,
              onPressed: () => context.canPop()
                  ? context.pop()
                  : context.go('/family/${widget.familyId}'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _setupView() {
    return LobbySetupScreen(
      gameId: 'crystal-bridge',
      title: 'Crystal Bridge',
      tagline: 'Cross the bridge — one crystal saves you, one shatters you',
      facts: [
        LobbyFact(icon: Icons.groups_2_outlined, label: '2–8 players'),
        LobbyFact(
            icon: Icons.layers_outlined, label: '$_totalRows rows'),
        LobbyFact(icon: Icons.timer_outlined, label: '$_turnSeconds s/turn'),
      ],
      settings: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LobbySection(
            label: 'Room Name',
            child: TextField(
              controller: _roomNameController,
              maxLength: 24,
              style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  color: KinrelColors.textWhite),
              decoration: InputDecoration(
                counterText: '',
                hintText: 'e.g. Family Crossing',
                hintStyle: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    color: KinrelColors.textDim.withValues(alpha: 0.6)),
                filled: true,
                fillColor: KinrelColors.darkCard,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(KinrelRadius.md),
                  borderSide: BorderSide(color: KinrelColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(KinrelRadius.md),
                  borderSide: const BorderSide(
                      color: kCrystalBridgeAccent, width: 1.4),
                ),
              ),
            ),
          ),
          const SizedBox(height: KinrelSpacing.md),
          LobbySection(
            label: 'Bridge Type',
            child: Column(
              children: [
                for (final type in CrystalBridgeEngine.allBridgeTypes)
                  _BridgeTypePill(
                    type: type,
                    selected: _bridgeType == type,
                    onSelect: (t) => setState(() => _bridgeType = t),
                  ),
              ],
            ),
          ),
          const SizedBox(height: KinrelSpacing.md),
          LobbySection(
            label: 'Match Length',
            child: LobbyChoiceGrid<int>(
              selected: _totalRows,
              onSelect: (v) => setState(() => _totalRows = v),
              options: const [
                LobbyOption(value: 10, label: '10', caption: 'Quick'),
                LobbyOption(value: 20, label: '20', caption: 'Standard'),
                LobbyOption(value: 30, label: '30', caption: 'Marathon'),
              ],
            ),
          ),
          const SizedBox(height: KinrelSpacing.md),
          LobbySection(
            label: 'Team Mode',
            child: LobbyChoiceGrid<CrystalBridgeTeamMode>(
              selected: _teamMode,
              onSelect: (v) => setState(() => _teamMode = v),
              options: [
                LobbyOption(
                    value: CrystalBridgeTeamMode.solo,
                    label: 'Solo',
                    caption: 'FFA'),
                LobbyOption(
                    value: CrystalBridgeTeamMode.twoVTwo,
                    label: '2v2',
                    caption: 'Teams'),
                LobbyOption(
                    value: CrystalBridgeTeamMode.threeVThree,
                    label: '3v3',
                    caption: 'Teams'),
                LobbyOption(
                    value: CrystalBridgeTeamMode.fourVFour,
                    label: '4v4',
                    caption: 'Teams'),
              ],
            ),
          ),
          const SizedBox(height: KinrelSpacing.md),
          LobbySection(
            label: 'Turn Timer',
            child: LobbyChoiceGrid<int>(
              selected: _turnSeconds,
              onSelect: (v) => setState(() => _turnSeconds = v),
              options: const [
                LobbyOption(value: 15, label: '15s', caption: 'Rapid'),
                LobbyOption(value: 20, label: '20s', caption: 'Standard'),
                LobbyOption(value: 30, label: '30s', caption: 'Relaxed'),
              ],
            ),
          ),
          const SizedBox(height: KinrelSpacing.md),
          LobbySection(
            label: 'Max Players',
            child: LobbyChoiceGrid<int>(
              selected: _maxPlayers,
              onSelect: (v) => setState(() => _maxPlayers = v),
              options: const [
                LobbyOption(value: 4, label: '4'),
                LobbyOption(value: 6, label: '6'),
                LobbyOption(value: 8, label: '8'),
              ],
            ),
          ),
        ],
      ),
      rules: [
        LobbyRule('Each row of the bridge has two crystals — left & right.'),
        LobbyRule('Players take turns choosing one. Only one is safe.'),
        LobbyRule('Wrong crystal shatters — you\'re eliminated.'),
        LobbyRule('Shield power saves you once; Leap skips a row entirely.'),
        LobbyRule('Reveal + Scanner expose safe sides; Swap shifts turn order.'),
        LobbyRule('Reach the final row OR be the last survivor to win.'),
        LobbyRule('Timer out = auto-eliminated. Choose fast, choose wise.'),
      ],
      rulesFootnote:
          'Quick = 10 rows · Standard = 20 · Marathon = 30. Powers are random — one use per match per player.',
      spectatorsEnabled: _spectatorsEnabled,
      onSpectatorsChanged: (v) => setState(() => _spectatorsEnabled = v),
      ctaLabel: 'Create Game',
      ctaHint: 'Invite family members, then cross the bridge!',
      ctaLoading: _creating,
      onCtaPressed: _createGame,
    );
  }

  Widget _lobbyView(CrystalBridgeState_ state, bool isHost) {
    final game = state.game!;
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
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
      gameTable: 'crystal_bridge_games',
      gameId: game.id,
      familyId: widget.familyId,
      hostUserId: game.hostUserId,
      players: lobbyPlayers,
      maxPlayers: game.maxPlayers,
      status: lobbyStatus,
      subtitle:
          '${game.bridgeType.label} · ${game.totalRows} rows · ${game.teamMode.label} · ${game.turnSeconds}s/turn',
    );
    return RoomLifecycleListener(
      gameTable: 'crystal_bridge_games',
      gameId: game.id,
      familyId: widget.familyId,
      isHost: game.hostUserId == myId,
      child: TemporaryLobbyView(
        config: config,
        myUserId: myId,
        onToggleReady: (isReady) => ref
            .read(crystalBridgeProvider(widget.familyId).notifier)
            .toggleReady(isReady),
        onStartMatch: _startMatch,
        onCancelRoom: () => ref
            .read(crystalBridgeProvider(widget.familyId).notifier)
            .leaveGame(),
        onInviteFamily: isHost ? () => _openInviteSheet(state) : null,
      ),
    );
  }
}

/// A selectable pill for a [CrystalBridgeType] — shows the type's
/// accent color, label, and a one-line description so the host can
/// quickly grok each bridge variant.
class _BridgeTypePill extends StatelessWidget {
  const _BridgeTypePill({
    required this.type,
    required this.selected,
    required this.onSelect,
  });

  final CrystalBridgeType type;
  final bool selected;
  final void Function(CrystalBridgeType) onSelect;

  @override
  Widget build(BuildContext context) {
    final accent = Color(type.accentArgb);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: () => onSelect(type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.18)
                : KinrelColors.darkCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: selected
                    ? accent.withValues(alpha: 0.6)
                    : KinrelColors.border,
                width: 1.4),
          ),
          child: Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(-0.4, -0.4),
                    colors: [
                      accent.withValues(alpha: 0.95),
                      accent.withValues(alpha: 0.55),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.label,
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? accent
                            : KinrelColors.textWhite,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      type.description,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 11,
                        color: KinrelColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                size: 18,
                color: selected
                    ? accent
                    : KinrelColors.textDim.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
