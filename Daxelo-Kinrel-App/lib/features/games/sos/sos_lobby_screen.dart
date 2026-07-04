// lib/features/games/sos/sos_lobby_screen.dart
//
// SOS Game — Lobby / Setup screen.
// Route: /family/$familyId/sos/lobby

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../game_motion_tokens.dart';
import 'sos_models.dart';
import 'sos_provider.dart';

class SosLobbyScreen extends ConsumerStatefulWidget {
  const SosLobbyScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<SosLobbyScreen> createState() => _SosLobbyScreenState();
}

class _SosLobbyScreenState extends ConsumerState<SosLobbyScreen> {
  SosMode _mode = SosMode.twoPlayer;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final joinId = GoRouterState.of(context).uri.queryParameters['join'];
      if (joinId != null && joinId.isNotEmpty) {
        ref.read(sosProvider(widget.familyId).notifier).joinGame(joinId);
      }
    });
  }

  Future<void> _createGame() async {
    setState(() => _creating = true);
    final notifier = ref.read(sosProvider(widget.familyId).notifier);
    await notifier.createGame(mode: _mode);
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
              _mode == SosMode.fourPlayerTeams
                  ? '3 family members can join. Teams are assigned automatically: 1st & 3rd joiner → Team S, 2nd & 4th → Team O.'
                  : '1 family member can join to start a 2-player game.',
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
    final state = ref.watch(sosProvider(widget.familyId));
    final notifier = ref.read(sosProvider(widget.familyId).notifier);
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isHost = state.game?.hostUserId == myId || state.game == null;
    final canStart = state.game == null
        ? true
        : (isHost && state.players.length >= (state.game?.mode.minPlayers ?? 2));

    // Auto-navigate to the board once the game becomes active
    ref.listen<SosState>(sosProvider(widget.familyId), (previous, next) {
      final shouldNavigate = next.isActive;
      final wasActive = previous?.isActive ?? false;
      final gameId = next.game?.id;
      if (shouldNavigate && !wasActive && gameId != null && mounted) {
        context.pushReplacement(
          '/family/${widget.familyId}/sos/game/$gameId',
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
            if (state.game != null) {
              notifier.leaveGame();
            }
            Navigator.of(context).pop();
          },
        ),
        title: Text(
          'SOS',
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
              onRetry: () => notifier.createGame(mode: _mode),
            )
          : hasGame
              ? _lobbyView(state, notifier, isHost, canStart)
              : _setupView(state),
    );
  }

  Widget _setupView(SosState state) {
    return ListView(
      padding: const EdgeInsets.all(KinrelSpacing.base),
      children: [
        _sectionLabel('Game Mode'),
        const SizedBox(height: KinrelSpacing.sm),
        _modeSelector(),
        const SizedBox(height: KinrelSpacing.lg),

        // Mode description
        Container(
          padding: const EdgeInsets.all(KinrelSpacing.md),
          decoration: BoxDecoration(
            color: KinrelColors.darkCard,
            borderRadius: BorderRadius.circular(KinrelRadius.lg),
            border: Border.all(color: KinrelColors.border),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: KinrelColors.info, size: 20),
              const SizedBox(width: KinrelSpacing.sm),
              Expanded(
                child: Text(
                  _mode.description,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    color: KinrelColors.textDim,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: KinrelSpacing.xl),

        // Rules summary
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
    SosState state,
    SosNotifier notifier,
    bool isHost,
    bool canStart,
  ) {
    final code = state.game?.id != null
        ? state.game!.id.replaceAll('-', '').substring(0, 6).toUpperCase()
        : '------';
    final mode = state.game?.mode ?? SosMode.twoPlayer;
    final minPlayers = mode.minPlayers;

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
                  mode == SosMode.fourPlayerTeams
                      ? 'Waiting for ${minPlayers - state.players.length} more players'
                      : 'Waiting for ${minPlayers - state.players.length} more player',
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

        // Mode + teams summary
        _modeSummary(state),
        const SizedBox(height: KinrelSpacing.lg),

        // Players list
        _sectionLabel('Players (${state.players.length}/${mode.maxPlayers})'),
        const SizedBox(height: KinrelSpacing.sm),
        _playerList(state),
        const SizedBox(height: KinrelSpacing.xl),

        DKButton(
          label: isHost
              ? (canStart
                    ? 'Start Game'
                    : 'Waiting for ${minPlayers - state.players.length} more…')
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

  Widget _modeSelector() {
    return Wrap(
      spacing: KinrelSpacing.sm,
      runSpacing: KinrelSpacing.sm,
      children: SosMode.values.map((m) {
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  m == SosMode.twoPlayer
                      ? Icons.person_outline
                      : Icons.groups_outlined,
                  size: 18,
                  color: selected ? KinrelColors.orange : KinrelColors.textDim,
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
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
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
          _ruleLine('1.', 'Players take turns placing S or O letters on a 7×7 grid.'),
          const SizedBox(height: 6),
          _ruleLine('2.', 'Complete an S-O-S sequence (3 cells in a line) to score a point.'),
          const SizedBox(height: 6),
          _ruleLine('3.', 'Sequences can be horizontal, vertical, or diagonal.'),
          const SizedBox(height: 6),
          _ruleLine('4.', 'Score a sequence → go again. Otherwise, turn passes.'),
          const SizedBox(height: 6),
          _ruleLine('5.', 'Grid full → game over. Most sequences wins.'),
          if (_mode == SosMode.fourPlayerTeams) ...[
            const SizedBox(height: 6),
            _ruleLine(
              '★',
              'Team mode: Team S places only S, Team O places only O. Turns rotate S1→O1→S2→O2.',
              highlight: true,
            ),
          ],
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

  Widget _modeSummary(SosState state) {
    final mode = state.game?.mode ?? SosMode.twoPlayer;
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
          Row(
            children: [
              Icon(
                mode == SosMode.twoPlayer
                    ? Icons.person_outline
                    : Icons.groups_outlined,
                size: 20,
                color: KinrelColors.orange,
              ),
              const SizedBox(width: KinrelSpacing.sm),
              Text(
                mode.label,
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textWhite,
                ),
              ),
            ],
          ),
          if (mode == SosMode.fourPlayerTeams) ...[
            const SizedBox(height: KinrelSpacing.sm),
            Row(
              children: [
                _teamChip(SosTeam.s),
                const SizedBox(width: KinrelSpacing.sm),
                _teamChip(SosTeam.o),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _teamChip(SosTeam team) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: Color(team.colorValue).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(KinrelRadius.xs),
        border: Border.all(color: Color(team.colorValue), width: 1),
      ),
      child: Text(
        team.label,
        style: TextStyle(
          fontFamily: KinrelTypography.monoFont,
          fontSize: 11,
          color: Color(team.colorValue),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _playerList(SosState state) {
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

  Widget _playerTile(SosPlayer player, String? hostUserId) {
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isMe = player.userId == myId;
    return ListTile(
      leading: DKAvatar(
        initials: player.userName.isNotEmpty
            ? player.userName[0].toUpperCase()
            : '?',
        borderColor: player.team != null
            ? Color(player.team!.colorValue)
            : null,
      ),
      title: Row(
        children: [
          Text(
            isMe ? '${player.userName} (You)' : player.userName,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              color: KinrelColors.textWhite,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (player.team != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Color(player.team!.colorValue).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                player.team!.name,
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 10,
                  color: Color(player.team!.colorValue),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
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
