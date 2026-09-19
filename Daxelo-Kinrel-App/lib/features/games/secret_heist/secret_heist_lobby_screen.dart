// lib/features/games/secret_heist/secret_heist_lobby_screen.dart
//
// Secret Heist — Create Room lobby.
// Route: /family/$familyId/secret-heist/lobby
//
// Mirrors the Freeze Auction + Impostor lobby pattern: a setup screen
// lets the host configure match parameters (rounds, vault size, chaos
// mode, starting coins), then a waiting room shows the live player
// roster and lets the host start the match once ≥3 players have joined.

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
import 'secret_heist_provider.dart';

class SecretHeistLobbyScreen extends ConsumerStatefulWidget {
  const SecretHeistLobbyScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<SecretHeistLobbyScreen> createState() =>
      _SecretHeistLobbyScreenState();
}

class _SecretHeistLobbyScreenState
    extends ConsumerState<SecretHeistLobbyScreen> {
  final _roomNameController = TextEditingController();
  int _maxPlayers = 8;
  int _totalRounds = 5;
  int _startingCoins = 100;
  int _vaultSize = 500;
  int _actionSeconds = 30;
  bool _chaosMode = false;
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
            .read(secretHeistProvider(widget.familyId).notifier)
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
    await ref.read(secretHeistProvider(widget.familyId).notifier).createGame(
          maxPlayers: _maxPlayers,
          totalRounds: _totalRounds,
          startingCoins: _startingCoins,
          vaultSize: _vaultSize,
          chaosMode: _chaosMode,
          actionSeconds: _actionSeconds,
          roomName: _roomNameController.text,
          spectatorsEnabled: _spectatorsEnabled,
        );
    if (mounted) setState(() => _creating = false);
  }

  Future<void> _startMatch() async {
    final result = await ref
        .read(secretHeistProvider(widget.familyId).notifier)
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
    final state = ref.watch(secretHeistProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isHost = state.game?.hostUserId == myId || state.game == null;

    ref.listen(secretHeistProvider(widget.familyId), (previous, next) {
      if (next.isInProgress &&
          !(previous?.isInProgress ?? false) &&
          next.game?.id != null &&
          mounted) {
        context.pushReplacement(
          '/family/${widget.familyId}/secret-heist/game/${next.game!.id}',
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
                    : 'Secret Heist',
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
              child: CircularProgressIndicator(color: KinrelColors.orange))
          : state.error != null && !hasGame
              ? DKErrorState(message: state.error!, onRetry: _createGame)
              : hasGame
                  ? _lobbyView(state, isHost)
                  : _setupView(),
    );
  }

  void _openInviteSheet(SecretHeistState_ state) {
    final game = state.game;
    if (game == null) return;
    GameMotionTokens.tap();
    InviteFamilySheet.show(
      context,
      familyId: widget.familyId,
      gameType: GameType.secretHeist,
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
                    color: KinrelColors.orange,
                    letterSpacing: 6)),
            const SizedBox(height: KinrelSpacing.md),
            Text(
              'Up to ${_maxPlayers - 1} members. Bluff, steal, outsmart!',
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
      gameId: 'secret-heist',
      title: 'Secret Heist',
      tagline: 'Bluff, steal, outsmart — hidden-role heist',
      facts: [
        LobbyFact(icon: Icons.groups_2_outlined, label: '3–8 players'),
        LobbyFact(
            icon: Icons.account_balance_outlined,
            label: '$_vaultSize vault'),
        LobbyFact(icon: Icons.timer_outlined, label: '$_actionSeconds s/round'),
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
                hintText: 'e.g. Family Vault Heist',
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
                      color: KinrelColors.orange, width: 1.4),
                ),
              ),
            ),
          ),
          const SizedBox(height: KinrelSpacing.md),
          LobbySection(
            label: 'Rounds',
            child: LobbyChoiceGrid<int>(
              selected: _totalRounds,
              onSelect: (v) => setState(() => _totalRounds = v),
              options: const [
                LobbyOption(value: 5, label: '5', caption: 'Standard'),
                LobbyOption(value: 10, label: '10', caption: 'Extended'),
              ],
            ),
          ),
          const SizedBox(height: KinrelSpacing.md),
          LobbySection(
            label: 'Vault Size',
            child: LobbyChoiceGrid<int>(
              selected: _vaultSize,
              onSelect: (v) => setState(() => _vaultSize = v),
              options: const [
                LobbyOption(value: 300, label: '300', caption: 'Quick'),
                LobbyOption(value: 500, label: '500', caption: 'Standard'),
                LobbyOption(value: 1000, label: '1000', caption: 'Marathon'),
              ],
            ),
          ),
          const SizedBox(height: KinrelSpacing.md),
          LobbySection(
            label: 'Starting Coins',
            child: LobbyChoiceGrid<int>(
              selected: _startingCoins,
              onSelect: (v) => setState(() => _startingCoins = v),
              options: const [
                LobbyOption(value: 50, label: '50'),
                LobbyOption(value: 100, label: '100'),
                LobbyOption(value: 200, label: '200'),
              ],
            ),
          ),
          const SizedBox(height: KinrelSpacing.md),
          LobbySection(
            label: 'Round Timer',
            child: LobbyChoiceGrid<int>(
              selected: _actionSeconds,
              onSelect: (v) => setState(() => _actionSeconds = v),
              options: const [
                LobbyOption(value: 20, label: '20s', caption: 'Fast'),
                LobbyOption(value: 30, label: '30s', caption: 'Standard'),
                LobbyOption(value: 45, label: '45s', caption: 'Relaxed'),
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
          const SizedBox(height: KinrelSpacing.md),
          // Chaos mode toggle
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: KinrelColors.darkCard,
              borderRadius: BorderRadius.circular(KinrelRadius.md),
              border: Border.all(
                  color: _chaosMode
                      ? KinrelColors.amber.withValues(alpha: 0.5)
                      : KinrelColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Chaos Mode',
                          style: TextStyle(
                              fontFamily: KinrelTypography.displayFont,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: KinrelColors.textWhite)),
                      const SizedBox(height: 2),
                      Text(
                        'Unlocks Double Steal + Alarm Bait actions.',
                        style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 11,
                            color: KinrelColors.textDim),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _chaosMode,
                  onChanged: (v) => setState(() => _chaosMode = v),
                  activeThumbColor: KinrelColors.amber,
                ),
              ],
            ),
          ),
        ],
      ),
      rules: [
        LobbyRule('Every round, secretly choose: Steal, Protect, Spy, Trap, or Hack.'),
        LobbyRule('Choices are revealed only after everyone locks in.'),
        LobbyRule('Steal takes coins from the vault. Protect blocks steals.'),
        LobbyRule('Trap catches thieves — they lose 10 coins. Hack can double, backfire, or trigger an alarm.'),
        LobbyRule('Suspicion meter rises with aggressive play — others will notice.'),
        LobbyRule('After all rounds, the player with the most coins wins!'),
      ],
      rulesFootnote:
          'Standard = 5 rounds. Extended = 10 rounds. Chaos Mode adds extra high-variance actions.',
      spectatorsEnabled: _spectatorsEnabled,
      onSpectatorsChanged: (v) => setState(() => _spectatorsEnabled = v),
      ctaLabel: 'Create Game',
      ctaHint: 'Invite family members, then plan your heist!',
      ctaLoading: _creating,
      onCtaPressed: _createGame,
    );
  }

  Widget _lobbyView(SecretHeistState_ state, bool isHost) {
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
      gameTable: 'secret_heist_games',
      gameId: game.id,
      familyId: widget.familyId,
      hostUserId: game.hostUserId,
      players: lobbyPlayers,
      maxPlayers: game.maxPlayers,
      status: lobbyStatus,
      subtitle:
          '${game.totalRounds} rounds · ${game.vaultSize} vault · ${game.chaosMode ? 'Chaos' : 'Standard'}',
    );
    return RoomLifecycleListener(
      gameTable: 'secret_heist_games',
      gameId: game.id,
      familyId: widget.familyId,
      isHost: game.hostUserId == myId,
      child: TemporaryLobbyView(
        config: config,
        myUserId: myId,
        onToggleReady: (isReady) =>
            ref.read(secretHeistProvider(widget.familyId).notifier).toggleReady(isReady),
        onStartMatch: _startMatch,
        onCancelRoom: () => ref
            .read(secretHeistProvider(widget.familyId).notifier)
            .leaveGame(),
        onInviteFamily: isHost ? () => _openInviteSheet(state) : null,
      ),
    );
  }
}
