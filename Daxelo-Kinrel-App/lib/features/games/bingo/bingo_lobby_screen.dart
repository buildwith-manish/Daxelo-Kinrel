// lib/features/games/bingo/bingo_lobby_screen.dart
//
// Bingo — Lobby / Setup screen.
// Route: /family/$familyId/bingo/lobby

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
import '../shared/widgets/pending_invites_section.dart';
import '../shared/widgets/lobby_chat_panel.dart';
import '../shared/widgets/spectator_toggle.dart';
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
  bool _creating = false;
  bool _spectatorsEnabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final joinId = GoRouterState.of(context).uri.queryParameters['join'];
      if (joinId != null && joinId.isNotEmpty) {
        ref.read(bingoProvider(widget.familyId).notifier).joinGame(joinId);
      }
    });
  }

  Future<void> _createGame() async {
    setState(() => _creating = true);
    final notifier = ref.read(bingoProvider(widget.familyId).notifier);
    final gameId = await notifier.createGame(
      winPattern: _winPattern,
      callIntervalSeconds: _callInterval,
    );
      if (gameId != null) {
        await ref.read(supabaseProvider)?.from('bingo_games').update({'spectatorsEnabled': _spectatorsEnabled}).eq('id', gameId);
      }

    if (mounted) setState(() => _creating = false);
    // Stay on lobby to wait for players
    if (gameId == null && mounted) {
      // Error already set in state
    }
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
              'Up to 29 family members can join. Each player gets a random 5×5 card.',
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
              onPressed: () { if (context.canPop()) { context.pop(); } else { context.go('/family/${widget.familyId}'); } },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bingoProvider(widget.familyId));
    final notifier = ref.read(bingoProvider(widget.familyId).notifier);
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isHost = state.game?.hostUserId == myId || state.game == null;
    final canStart = state.game == null
        ? true
        : (isHost && state.allCards.length >= 2);

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

    final hasGame = state.game != null;

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (state.game != null) notifier.leaveGame();
            if (context.canPop()) { context.pop(); } else { context.go('/family/${widget.familyId}'); }
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
          if (hasGame && isHost)
            IconButton(
              tooltip: 'Invite family member',
              icon: const Icon(Icons.person_add_outlined),
              onPressed: () {
                final code = state.game?.id != null
                    ? state.game!.id
                        .replaceAll('-', '')
                        .substring(0, 6)
                        .toUpperCase()
                    : '------';
                final maxP = state.game?.maxPlayers ?? 30;
                GameMotionTokens.tap();
                InviteFamilySheet.show(
                  context,
                  familyId: widget.familyId,
                  gameType: GameType.bingo,
                  gameId: state.game?.id ?? '',
                  roomCode: code,
                  currentPlayerIds: state.allCards
                      .map((c) => c.playerId)
                      .whereType<String>()
                      .toSet(),
                  maxPlayers: maxP,
                  currentPlayers: state.allCards.length,
                );
              },
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
              child: CircularProgressIndicator(color: KinrelColors.orange),
            )
          : state.error != null && !hasGame
          ? DKErrorState(
              message: state.error!,
              onRetry: _createGame,
            )
          : hasGame
              ? _lobbyView(state, notifier, isHost, canStart)
              : _setupView(state),
    );
  }

  Widget _setupView(BingoState state) {
    return ListView(
      padding: const EdgeInsets.all(KinrelSpacing.base),
      children: [
        _sectionLabel('Win Pattern'),
        const SizedBox(height: KinrelSpacing.sm),
        _winPatternSelector(),
        const SizedBox(height: KinrelSpacing.lg),

        _sectionLabel('Call Speed: every ${_callInterval}s'),
        const SizedBox(height: KinrelSpacing.sm),
        _callIntervalSlider(),
        const SizedBox(height: KinrelSpacing.lg),

        _sectionLabel('How to Play'),
        const SizedBox(height: KinrelSpacing.sm),
        _rulesCard(),
        const SizedBox(height: KinrelSpacing.xl),

                SpectatorToggle(
          value: _spectatorsEnabled,
          onChanged: (v) => setState(() => _spectatorsEnabled = v),
        ),
        const SizedBox(height: KinrelSpacing.md),
        DKButton(
          label: 'Create Game',
          variant: DKButtonVariant.gradient,
          fullWidth: true,
          isLoading: _creating,
          onPressed: _createGame,
        ),
      ],
    );
  }

  Widget _lobbyView(
    BingoState state,
    BingoNotifier notifier,
    bool isHost,
    bool canStart,
  ) {
    final code = state.game?.id != null
        ? state.game!.id.replaceAll('-', '').substring(0, 6).toUpperCase()
        : '------';
    final maxP = state.game?.maxPlayers ?? 30;

    return ListView(
      padding: const EdgeInsets.all(KinrelSpacing.base),
      children: [
        GestureDetector(
          onTap: () => _shareCode(state.game?.id),
          child: Container(
            padding: const EdgeInsets.all(KinrelSpacing.lg),
            decoration: BoxDecoration(
              gradient: KinrelGradients.igniteGradient,
              borderRadius: BorderRadius.circular(KinrelRadius.lg),
            ),
            child: Column(
              children: [
                Text(
                  'Share Code',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.9),
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: KinrelSpacing.sm),
                Text(
                  code,
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Waiting for family to join (${state.allCards.length}/$maxP)',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: KinrelSpacing.lg),

        _settingsSummary(state),
        const SizedBox(height: KinrelSpacing.lg),

        _sectionLabel('Players (${state.allCards.length}/$maxP)'),
        const SizedBox(height: KinrelSpacing.sm),
        _playerList(state),
        const SizedBox(height: KinrelSpacing.xl),

                  PendingInvitesSection(gameId: state.game!.id),
        const SizedBox(height: KinrelSpacing.md),
            LobbyChatPanel(
              gameTable: 'bingo_games',
              gameId: state.game!.id,
              familyId: widget.familyId,
            ),
        DKButton(
          label: isHost
              ? (canStart
                    ? 'Start Game'
                    : 'Waiting for ${2 - state.allCards.length} more player…')
              : 'Waiting for host…',
          variant: DKButtonVariant.gradient,
          fullWidth: true,
          onPressed: isHost && canStart
              ? () => notifier.startGame()
              : null,
        ),
        if (isHost && !canStart)
          Padding(
            padding: const EdgeInsets.only(top: KinrelSpacing.sm),
            child: Text(
              'Need at least 2 players to start.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: KinrelColors.warning,
              ),
            ),
          ),
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
            GameMotionTokens.tap();
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.label,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    color: selected
                        ? KinrelColors.textWhite
                        : KinrelColors.textDim,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  p.description,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 10,
                    color: KinrelColors.textDim,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _callIntervalSlider() {
    return Slider(
      value: _callInterval.toDouble(),
      min: 3,
      max: 15,
      divisions: 12,
      activeColor: KinrelColors.orange,
      label: '${_callInterval}s',
      onChanged: (v) => setState(() => _callInterval = v.round()),
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
          _ruleLine('1.', 'Each player gets a random 5×5 card with numbers 1-75.'),
          const SizedBox(height: 6),
          _ruleLine('2.', 'The caller (automated) announces a random number every ${_callInterval}s.'),
          const SizedBox(height: 6),
          _ruleLine('3.', 'Tap matching numbers on your card to mark them.'),
          const SizedBox(height: 6),
          _ruleLine('4.', 'Center space is FREE — already marked.'),
          const SizedBox(height: 6),
          _ruleLine(
            '5.',
            _winPattern == BingoWinPattern.line
                ? 'Complete any row, column, or diagonal → tap BINGO!'
                : 'Mark every number on your card → tap BINGO!',
          ),
          const SizedBox(height: 6),
          _ruleLine('★', 'Wins are verified server-side — no cheating!', highlight: true),
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

  Widget _settingsSummary(BingoState state) {
    final game = state.game;
    if (game == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(KinrelSpacing.md),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Wrap(
        spacing: KinrelSpacing.sm,
        runSpacing: 4,
        children: [
          _chip(game.winPattern.label),
          _chip('${game.callIntervalSeconds}s/number'),
          _chip('Max ${game.maxPlayers} players'),
        ],
      ),
    );
  }

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: KinrelColors.darkElevated,
        borderRadius: BorderRadius.circular(KinrelRadius.xs),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 11,
          color: KinrelColors.textDim,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _playerList(BingoState state) {
    if (state.allCards.isEmpty) {
      return DKEmptyState(
        icon: Icons.group_outlined,
        title: 'No players yet',
        subtitle: 'Share the code to invite family members.',
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Column(
        children: [
          for (int i = 0; i < state.allCards.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: KinrelColors.border.withValues(alpha: 0.5)),
            _playerTile(state.allCards[i], state.game?.hostUserId),
          ],
        ],
      ),
    );
  }

  Widget _playerTile(BingoCard card, String? hostUserId) {
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isMe = card.playerId == myId;
    return ListTile(
      leading: DKAvatar(
        initials: card.playerName.isNotEmpty
            ? card.playerName[0].toUpperCase()
            : '?',
      ),
      title: Text(
        isMe ? '${card.playerName} (You)' : card.playerName,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 14,
          color: KinrelColors.textWhite,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: card.playerId == hostUserId
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: KinrelColors.orange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(KinrelRadius.xs),
              ),
              child: Text(
                'HOST',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 10,
                  color: KinrelColors.orange,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            )
          : null,
    );
  }
}
