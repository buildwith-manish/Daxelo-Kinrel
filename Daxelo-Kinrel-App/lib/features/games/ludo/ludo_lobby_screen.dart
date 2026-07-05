// lib/features/games/ludo/ludo_lobby_screen.dart
//
// Ludo — Lobby screen to start a game and invite 1-3 family members.
// Route: /family/$familyId/ludo/lobby

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
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final joinId = GoRouterState.of(context).uri.queryParameters['join'];
      if (joinId != null && joinId.isNotEmpty) {
        ref.read(ludoProvider(widget.familyId).notifier).joinGame(joinId);
      }
    });
  }

  Future<void> _createGame() async {
    setState(() => _creating = true);
    final notifier = ref.read(ludoProvider(widget.familyId).notifier);
    final gameId = await notifier.createGame(playerCount: _playerCount);
    if (mounted) setState(() => _creating = false);
    // Stay on lobby to wait for players
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
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ludoProvider(widget.familyId));
    final notifier = ref.read(ludoProvider(widget.familyId).notifier);
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isHost = state.game?.hostUserId == myId || state.game == null;
    final canStart = state.game == null
        ? true
        : (isHost && state.players.length >= 2);

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

    final hasGame = state.game != null;

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (state.game != null) notifier.leaveGame();
            Navigator.of(context).pop();
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
          if (hasGame && isHost)
            IconButton(
              tooltip: 'Invite family member',
              icon: const Icon(Icons.person_add_outlined),
              onPressed: () {
                final code = state.game?.id != null ? state.game!.id.replaceAll('-', '').substring(0, 6).toUpperCase() : '------';
                final maxP = state.game?.playerCount ?? 4;
                GameMotionTokens.tap();
                InviteFamilySheet.show(
                  context,
                  familyId: widget.familyId,
                  gameType: GameType.ludo,
                  gameId: state.game?.id ?? '',
                  roomCode: code,
                  currentPlayerIds: state.players
                      .map((p) => p.userId)
                      .whereType<String>()
                      .toSet(),
                  maxPlayers: maxP,
                  currentPlayers: state.players.length,
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
              onRetry: () => notifier.createGame(playerCount: _playerCount),
            )
          : hasGame
              ? _lobbyView(state, notifier, isHost, canStart)
              : _setupView(state),
    );
  }

  Widget _setupView(LudoState state) {
    return ListView(
      padding: const EdgeInsets.all(KinrelSpacing.base),
      children: [
        _sectionLabel('Number of Players'),
        const SizedBox(height: KinrelSpacing.sm),
        _playerCountSelector(),
        const SizedBox(height: KinrelSpacing.lg),

        _sectionLabel('Color Order'),
        const SizedBox(height: KinrelSpacing.sm),
        _colorOrderCard(),
        const SizedBox(height: KinrelSpacing.lg),

        _sectionLabel('How to Play'),
        const SizedBox(height: KinrelSpacing.sm),
        _rulesCard(),
        const SizedBox(height: KinrelSpacing.xl),

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
    LudoState state,
    LudoNotifier notifier,
    bool isHost,
    bool canStart,
  ) {
    final code = state.game?.id != null
        ? state.game!.id.replaceAll('-', '').substring(0, 6).toUpperCase()
        : '------';
    final maxP = state.game?.playerCount ?? 4;

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
                  'Waiting for family to join (${state.players.length}/$maxP)',
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

        _sectionLabel('Players (${state.players.length}/$maxP)'),
        const SizedBox(height: KinrelSpacing.sm),
        ...state.players.map((p) => _playerTile(p, state.game?.hostUserId)),
        const SizedBox(height: KinrelSpacing.xl),

        if (hasGame)
          PendingInvitesSection(gameId: state.game!.id),
        const SizedBox(height: KinrelSpacing.md),
        DKButton(
          label: isHost
              ? (canStart
                    ? 'Start Game'
                    : 'Waiting for ${2 - state.players.length} more player…')
              : 'Waiting for host…',
          variant: DKButtonVariant.gradient,
          fullWidth: true,
          onPressed: isHost && canStart
              ? () => notifier.startGame()
              : null,
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

  Widget _playerCountSelector() {
    return Wrap(
      spacing: KinrelSpacing.sm,
      runSpacing: KinrelSpacing.sm,
      children: [2, 3, 4].map((n) {
        final selected = n == _playerCount;
        return GestureDetector(
          onTap: () {
            GameMotionTokens.tap();
            setState(() => _playerCount = n);
          },
          child: Container(
            width: 60,
            padding: const EdgeInsets.symmetric(vertical: KinrelSpacing.sm),
            decoration: BoxDecoration(
              color: KinrelColors.darkCard,
              borderRadius: BorderRadius.circular(KinrelRadius.md),
              border: Border.all(
                color: selected ? KinrelColors.orange : KinrelColors.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Center(
              child: Text(
                '$n',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? KinrelColors.orange
                      : KinrelColors.textDim,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _colorOrderCard() {
    final colors = [LudoColor.red, LudoColor.blue, LudoColor.green, LudoColor.yellow];
    return Container(
      padding: const EdgeInsets.all(KinrelSpacing.md),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: colors.take(_playerCount).map((c) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _colorValue(c),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                c.name.toUpperCase(),
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 9,
                  color: KinrelColors.textDim,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  /// Original Kinrel-branded color mapping (matches board screen).
  Color _colorValue(LudoColor c) {
    switch (c) {
      case LudoColor.red:
        return KinrelColors.orange;     // "Ember"
      case LudoColor.blue:
        return KinrelColors.blue;       // "Azure"
      case LudoColor.green:
        return KinrelColors.tealAccent; // "Jade"
      case LudoColor.yellow:
        return KinrelColors.gold;       // "Gold"
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
          _ruleLine('1.', 'Roll a 6 to move a token out of home base onto the board.'),
          const SizedBox(height: 6),
          _ruleLine('2.', 'Rolling a 6 grants an extra turn.'),
          const SizedBox(height: 6),
          _ruleLine('3.', 'Move tokens clockwise around the track by the number rolled.'),
          const SizedBox(height: 6),
          _ruleLine('4.', 'Land on an opponent (non-safe square) → send them home!'),
          const SizedBox(height: 6),
          _ruleLine('5.', 'Safe squares (starred) protect tokens from capture.'),
          const SizedBox(height: 6),
          _ruleLine('6.', 'After a full loop, enter your home column → reach the center.'),
          const SizedBox(height: 6),
          _ruleLine('7.', 'Must roll the exact number to reach the center.'),
          const SizedBox(height: 6),
          _ruleLine('★', 'Three 6s in a row = forfeit your turn!', highlight: true),
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

  Widget _playerTile(player, String? hostUserId) {
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isMe = player.userId == myId;
    return Container(
      margin: const EdgeInsets.only(bottom: KinrelSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.md,
        vertical: KinrelSpacing.md,
      ),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(
          color: isMe ? KinrelColors.orange : KinrelColors.border,
          width: isMe ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          DKAvatar(
            initials: player.userName.isNotEmpty
                ? player.userName[0].toUpperCase()
                : '?',
          ),
          const SizedBox(width: KinrelSpacing.md),
          Expanded(
            child: Text(
              isMe ? '${player.userName} (You)' : player.userName,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textWhite,
              ),
            ),
          ),
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _colorValue(player.color),
              border: Border.all(color: Colors.white, width: 1),
            ),
          ),
          if (player.userId == hostUserId) ...[
            const SizedBox(width: 4),
            Text('👑', style: TextStyle(fontSize: 14)),
          ],
        ],
      ),
    );
  }
}
