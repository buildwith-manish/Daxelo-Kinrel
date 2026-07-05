// lib/features/games/antakshari/antakshari_lobby_screen.dart
//
// Antakshari — Lobby / Setup screen.
// Route: /family/$familyId/antakshari/lobby

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
import 'antakshari_models.dart';
import 'antakshari_provider.dart';

class AntakshariLobbyScreen extends ConsumerStatefulWidget {
  const AntakshariLobbyScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<AntakshariLobbyScreen> createState() =>
      _AntakshariLobbyScreenState();
}

class _AntakshariLobbyScreenState
    extends ConsumerState<AntakshariLobbyScreen> {
  AntakshariGameMode _mode = AntakshariGameMode.standard;
  int _maxPlayers = 12;
  int _turnTimer = 30;
  int _roundLimit = 5;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final joinId = GoRouterState.of(context).uri.queryParameters['join'];
      if (joinId != null && joinId.isNotEmpty) {
        ref.read(antakshariProvider(widget.familyId).notifier).joinGame(joinId);
      }
    });
  }

  Future<void> _createGame() async {
    setState(() => _creating = true);
    final notifier = ref.read(antakshariProvider(widget.familyId).notifier);
    await notifier.createGame(
      mode: _mode,
      maxPlayers: _maxPlayers,
      turnTimerSeconds: _turnTimer,
      roundLimit: _mode == AntakshariGameMode.roundLimited
          ? _roundLimit
          : null,
    );
    if (mounted) setState(() => _creating = false);
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
              'Up to ${_maxPlayers - 1} family members can join. Turn order is randomized when the host starts the game.',
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
    final state = ref.watch(antakshariProvider(widget.familyId));
    final notifier = ref.read(antakshariProvider(widget.familyId).notifier);
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isHost = state.game?.hostUserId == myId || state.game == null;
    final canStart = state.game == null
        ? true
        : (isHost && state.players.length >= 2);

    // Auto-navigate to game screen when game starts
    ref.listen<AntakshariState>(antakshariProvider(widget.familyId),
        (previous, next) {
      if (next.isInProgress &&
          !(previous?.isInProgress ?? false) &&
          next.game?.id != null &&
          mounted) {
        context.pushReplacement(
          '/family/${widget.familyId}/antakshari/game/${next.game!.id}',
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
          'Antakshari',
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
                final maxP = state.game?.maxPlayers ?? 12;
                GameMotionTokens.tap();
                InviteFamilySheet.show(
                  context,
                  familyId: widget.familyId,
                  gameType: GameType.antakshari,
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
              onRetry: _createGame,
            )
          : hasGame
              ? _lobbyView(state, notifier, isHost, canStart)
              : _setupView(state),
    );
  }

  Widget _setupView(AntakshariState state) {
    return ListView(
      padding: const EdgeInsets.all(KinrelSpacing.base),
      children: [
        _sectionLabel('Game Mode'),
        const SizedBox(height: KinrelSpacing.sm),
        _modeSelector(),
        const SizedBox(height: KinrelSpacing.lg),

        _sectionLabel('Max Players'),
        const SizedBox(height: KinrelSpacing.sm),
        _maxPlayersSelector(),
        const SizedBox(height: KinrelSpacing.lg),

        _sectionLabel('Turn Timer: ${_turnTimer}s'),
        const SizedBox(height: KinrelSpacing.sm),
        _turnTimerSlider(),
        const SizedBox(height: KinrelSpacing.lg),

        if (_mode == AntakshariGameMode.roundLimited) ...[
          _sectionLabel('Round Limit: $_roundLimit'),
          const SizedBox(height: KinrelSpacing.sm),
          _roundLimitSlider(),
          const SizedBox(height: KinrelSpacing.lg),
        ],

        // Rules card
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
    AntakshariState state,
    AntakshariNotifier notifier,
    bool isHost,
    bool canStart,
  ) {
    final code = state.game?.id != null
        ? state.game!.id.replaceAll('-', '').substring(0, 6).toUpperCase()
        : '------';
    final maxP = state.game?.maxPlayers ?? 12;

    return ListView(
      padding: const EdgeInsets.all(KinrelSpacing.base),
      children: [
        // Share code card
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

        // Settings summary
        _settingsSummary(state),
        const SizedBox(height: KinrelSpacing.lg),

        // Players
        _sectionLabel('Players (${state.players.length}/$maxP)'),
        const SizedBox(height: KinrelSpacing.sm),
        _playerList(state),
        const SizedBox(height: KinrelSpacing.xl),

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

  Widget _modeSelector() {
    return Wrap(
      spacing: KinrelSpacing.sm,
      runSpacing: KinrelSpacing.sm,
      children: AntakshariGameMode.values.map((m) {
        final selected = m == _mode;
        return GestureDetector(
          onTap: () {
            GameMotionTokens.tap();
            setState(() => _mode = m);
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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      m == AntakshariGameMode.standard
                          ? Icons.person_outline
                          : Icons.groups_outlined,
                      size: 18,
                      color: selected
                          ? KinrelColors.orange
                          : KinrelColors.textDim,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      m.label,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        color: selected
                            ? KinrelColors.textWhite
                            : KinrelColors.textDim,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  m.description,
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

  Widget _maxPlayersSelector() {
    return Wrap(
      spacing: KinrelSpacing.sm,
      runSpacing: KinrelSpacing.sm,
      children: [6, 8, 12, 16, 20].map((n) {
        final selected = n == _maxPlayers;
        return GestureDetector(
          onTap: () {
            GameMotionTokens.tap();
            setState(() => _maxPlayers = n);
          },
          child: Container(
            width: 50,
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
                  fontSize: 16,
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

  Widget _turnTimerSlider() {
    return Slider(
      value: _turnTimer.toDouble(),
      min: 15,
      max: 60,
      divisions: 9,
      activeColor: KinrelColors.orange,
      label: '${_turnTimer}s',
      onChanged: (v) => setState(() => _turnTimer = v.round()),
    );
  }

  Widget _roundLimitSlider() {
    return Slider(
      value: _roundLimit.toDouble(),
      min: 3,
      max: 10,
      divisions: 7,
      activeColor: KinrelColors.orange,
      label: '$_roundLimit rounds',
      onChanged: (v) => setState(() => _roundLimit = v.round()),
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
          _ruleLine('1.', 'Players take turns singing a song line via voice/video call.'),
          const SizedBox(height: 6),
          _ruleLine('2.', 'Your song must start with the last letter of the previous player\'s song.'),
          const SizedBox(height: 6),
          _ruleLine('3.', 'After singing, type the letter your song ended on.'),
          const SizedBox(height: 6),
          _ruleLine('4.', 'Others can Challenge — 3+ challenges in 10s = you\'re out.'),
          const SizedBox(height: 6),
          _ruleLine('5.', 'Don\'t sing in ${_turnTimer}s = eliminated.'),
          const SizedBox(height: 6),
          _ruleLine('★', _mode == AntakshariGameMode.standard
              ? 'Standard: last player standing wins.'
              : 'Round-limited: all survivors after $_roundLimit rounds win jointly.',
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

  Widget _settingsSummary(AntakshariState state) {
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
          _chip(game.gameMode.label),
          _chip('Max ${game.maxPlayers} players'),
          _chip('${game.turnTimerSeconds}s/turn'),
          if (game.roundLimit != null) _chip('${game.roundLimit} rounds'),
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

  Widget _playerList(AntakshariState state) {
    if (state.players.isEmpty) {
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
          for (int i = 0; i < state.players.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: KinrelColors.border.withValues(alpha: 0.5)),
            _playerTile(state.players[i], state.game?.hostUserId),
          ],
        ],
      ),
    );
  }

  Widget _playerTile(AntakshariPlayer player, String? hostUserId) {
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isMe = player.userId == myId;
    return ListTile(
      leading: DKAvatar(
        initials: player.userName.isNotEmpty
            ? player.userName[0].toUpperCase()
            : '?',
      ),
      title: Text(
        isMe ? '${player.userName} (You)' : player.userName,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 14,
          color: KinrelColors.textWhite,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: player.userId == hostUserId
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
