// lib/features/games/nameplace/nameplace_lobby_screen.dart
// Route: /family/$familyId/nameplace/lobby

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
import 'nameplace_provider.dart';

class NameplaceLobbyScreen extends ConsumerStatefulWidget {
  const NameplaceLobbyScreen({super.key, required this.familyId});
  final String familyId;
  @override
  ConsumerState<NameplaceLobbyScreen> createState() => _NameplaceLobbyScreenState();
}

class _NameplaceLobbyScreenState extends ConsumerState<NameplaceLobbyScreen> {
  int _totalRounds = 5;
  int _roundTimer = 60;
  bool _creating = false;
  bool _spectatorsEnabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final joinId = GoRouterState.of(context).uri.queryParameters['join'];
      if (joinId != null && joinId.isNotEmpty) {
        ref.read(nameplaceProvider(widget.familyId).notifier).joinGame(joinId);
      }
    });
  }

  Future<void> _createGame() async {
    setState(() => _creating = true);
    await ref.read(nameplaceProvider(widget.familyId).notifier).createGame(
      totalRounds: _totalRounds, roundTimerSeconds: _roundTimer);
    if (mounted) setState(() => _creating = false);
  }

  Future<void> _shareCode(String? gameId) async {
    if (gameId == null) return;
    final code = gameId.replaceAll('-', '').substring(0, 6).toUpperCase();
    GameMotionTokens.tap();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context, backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(KinrelRadius.lg))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(KinrelSpacing.xl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Share this code', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 18, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
          const SizedBox(height: KinrelSpacing.md),
          Text(code, style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 40, fontWeight: FontWeight.w700, color: KinrelColors.orange, letterSpacing: 6)),
          const SizedBox(height: KinrelSpacing.md),
          Text('Up to 19 family members can join. Categories: Name, Place, Animal, Thing, Movie.', textAlign: TextAlign.center,
            style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim)),
          const SizedBox(height: KinrelSpacing.lg),
          DKButton(label: 'Done', variant: DKButtonVariant.primary, fullWidth: true, onPressed: () { if (context.canPop()) { context.pop(); } else { context.go('/family/${widget.familyId}'); } }),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(nameplaceProvider(widget.familyId));
    final notifier = ref.read(nameplaceProvider(widget.familyId).notifier);
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isHost = state.game?.hostUserId == myId || state.game == null;
    final hasGame = state.game != null;

    ref.listen<NameplaceState>(nameplaceProvider(widget.familyId), (prev, next) {
      if (next.isInProgress && next.game?.currentLetter == null && !(prev?.isInProgress ?? false) && next.game?.id != null && mounted) {
        context.pushReplacement('/family/${widget.familyId}/nameplace/letter/${next.game!.id}');
      }
    });

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () { if (state.game != null) notifier.leaveGame(); if (context.canPop()) { context.pop(); } else { context.go('/family/${widget.familyId}'); } }),
        title: Text('Name, Place, Animal, Thing', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
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
                  gameType: GameType.nameplace,
                  gameId: state.game!.id,
                  roomCode: code,
                  currentPlayerIds: state.players.map((p) => p.userId).whereType<String>().toSet(),
                  maxPlayers: 20,
                  currentPlayers: state.players.length,
                );
              },
            ),
          if (hasGame) IconButton(icon: const Icon(Icons.share_outlined), onPressed: () => _shareCode(state.game?.id)),
        ],
      ),
      body: state.isLoading
        ? const Center(child: CircularProgressIndicator(color: KinrelColors.orange))
        : state.error != null && !hasGame
          ? DKErrorState(message: state.error!, onRetry: _createGame)
          : !hasGame
            ? _setupView()
            : _lobbyView(state, isHost),
    );
  }

  Widget _setupView() {
    return ListView(padding: const EdgeInsets.all(KinrelSpacing.base), children: [
      _sectionLabel('Total Rounds'),
      const SizedBox(height: KinrelSpacing.sm),
      Slider(value: _totalRounds.toDouble(), min: 1, max: 10, divisions: 9, activeColor: KinrelColors.orange, label: '$_totalRounds', onChanged: (v) => setState(() => _totalRounds = v.round())),
      const SizedBox(height: KinrelSpacing.lg),
      _sectionLabel('Round Timer: ${_roundTimer}s'),
      const SizedBox(height: KinrelSpacing.sm),
      Slider(value: _roundTimer.toDouble(), min: 30, max: 120, divisions: 9, activeColor: KinrelColors.orange, label: '${_roundTimer}s', onChanged: (v) => setState(() => _roundTimer = v.round())),
      const SizedBox(height: KinrelSpacing.lg),
      _sectionLabel('Categories'),
      const SizedBox(height: KinrelSpacing.sm),
      Wrap(spacing: 6, runSpacing: 4, children: ['Name', 'Place', 'Animal', 'Thing', 'Movie'].map((c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(8), border: Border.all(color: KinrelColors.border)),
        child: Text(c, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textWhite, fontWeight: FontWeight.w600)),
      )).toList()),
      const SizedBox(height: KinrelSpacing.lg),
      _sectionLabel('How to Play'),
      const SizedBox(height: KinrelSpacing.sm),
      Container(padding: const EdgeInsets.all(KinrelSpacing.md), decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(KinrelRadius.lg), border: Border.all(color: KinrelColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _ruleLine('1.', 'Each round, one player picks a letter.'),
          const SizedBox(height: 6), _ruleLine('2.', 'All players write one answer per category starting with that letter.'),
          const SizedBox(height: 6), _ruleLine('3.', 'Can\'t answer? Enter a dash (-).'),
          const SizedBox(height: 6), _ruleLine('4.', 'Unique answer = 10 pts. Duplicate = 5 pts. Dash = 0 pts.'),
          const SizedBox(height: 6), _ruleLine('★', 'Highest total after $_totalRounds rounds wins!', highlight: true),
        ])),
      const SizedBox(height: KinrelSpacing.xl),
            SpectatorToggle(
        value: _spectatorsEnabled,
        onChanged: (v) => setState(() => _spectatorsEnabled = v),
      ),
      const SizedBox(height: KinrelSpacing.md),
      DKButton(label: 'Create Game', variant: DKButtonVariant.gradient, fullWidth: true, isLoading: _creating, onPressed: _createGame),
    ]);
  }

  Widget _lobbyView(state, bool isHost) {
    final game = state.game!;
    final code = game.id.replaceAll('-', '').substring(0, 6).toUpperCase();
    final canStart = state.players.length >= 2;
    return ListView(padding: const EdgeInsets.all(KinrelSpacing.base), children: [
      GestureDetector(
        onTap: () => _shareCode(game.id),
        child: Container(padding: const EdgeInsets.all(KinrelSpacing.lg),
          decoration: BoxDecoration(gradient: KinrelGradients.igniteGradient, borderRadius: BorderRadius.circular(KinrelRadius.lg)),
          child: Column(children: [
            Text('Share Code', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.9))),
            const SizedBox(height: KinrelSpacing.sm),
            Text(code, style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 36, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 8)),
            const SizedBox(height: 4),
            Text('${state.players.length}/20 players', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 11, color: Colors.white.withValues(alpha: 0.8))),
          ]),
        ),
      ),
      const SizedBox(height: KinrelSpacing.lg),
      _sectionLabel('Players (${state.players.length})'),
      const SizedBox(height: KinrelSpacing.sm),
      ...state.players.map((p) => Container(margin: const EdgeInsets.only(bottom: KinrelSpacing.sm), padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.md, vertical: KinrelSpacing.md),
        decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(KinrelRadius.lg), border: Border.all(color: p.userId == ref.read(supabaseProvider)?.auth.currentUser?.id ? KinrelColors.orange : KinrelColors.border, width: p.userId == ref.read(supabaseProvider)?.auth.currentUser?.id ? 2 : 1)),
        child: Row(children: [
          DKAvatar(initials: p.userName.isNotEmpty ? p.userName[0].toUpperCase() : '?'),
          const SizedBox(width: KinrelSpacing.md),
          Expanded(child: Text(p.userId == ref.read(supabaseProvider)?.auth.currentUser?.id ? '${p.userName} (You)' : p.userName, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, fontWeight: FontWeight.w600, color: KinrelColors.textWhite))),
          if (p.userId == game.hostUserId) Text('👑', style: TextStyle(fontSize: 14)),
        ]),
      )),
      const SizedBox(height: KinrelSpacing.xl),
      if (isHost) ...[
        PendingInvitesSection(gameId: state.game!.id),
        const SizedBox(height: KinrelSpacing.md),
            LobbyChatPanel(
              gameTable: 'nameplace_games',
              gameId: state.game!.id,
              familyId: widget.familyId,
            ),
        DKButton(label: canStart ? 'Start Game' : 'Need 2+ players', variant: DKButtonVariant.gradient, fullWidth: true, onPressed: canStart ? () => ref.read(nameplaceProvider(widget.familyId).notifier).startGame() : null)
      ] else
        Container(padding: const EdgeInsets.all(KinrelSpacing.lg), decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(KinrelRadius.lg), border: Border.all(color: KinrelColors.border)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: KinrelColors.orange)),
            const SizedBox(width: KinrelSpacing.sm),
            Text('Waiting for host...', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, color: KinrelColors.textDim)),
          ]),
        ),
    ]);
  }

  Widget _sectionLabel(String text) => Text(text, style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 13, fontWeight: FontWeight.w600, color: KinrelColors.textDim, letterSpacing: 0.5));
  Widget _ruleLine(String num, String text, {bool highlight = false}) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    SizedBox(width: 24, child: Text(num, style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 12, fontWeight: FontWeight.w700, color: highlight ? KinrelColors.orange : KinrelColors.textDim))),
    Expanded(child: Text(text, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: highlight ? KinrelColors.textWhite : KinrelColors.textDim, height: 1.4))),
  ]);
}
