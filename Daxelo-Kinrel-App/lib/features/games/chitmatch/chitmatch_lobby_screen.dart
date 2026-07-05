// lib/features/games/chitmatch/chitmatch_lobby_screen.dart
//
// TripleMatch — Lobby screen.
// Route: /family/$familyId/chitmatch/lobby

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
import 'chitmatch_models.dart';
import 'chitmatch_provider.dart';

class ChitmatchLobbyScreen extends ConsumerStatefulWidget {
  const ChitmatchLobbyScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<ChitmatchLobbyScreen> createState() => _ChitmatchLobbyScreenState();
}

class _ChitmatchLobbyScreenState extends ConsumerState<ChitmatchLobbyScreen> {
  int _playerCount = 6;
  int _roundTimer = 20;
  bool _creating = false;
  final _wordController = TextEditingController();
  bool _wordSubmitted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final joinId = GoRouterState.of(context).uri.queryParameters['join'];
      if (joinId != null && joinId.isNotEmpty) {
        ref.read(chitmatchProvider(widget.familyId).notifier).joinGame(joinId);
      }
    });
  }

  @override
  void dispose() {
    _wordController.dispose();
    super.dispose();
  }

  Future<void> _createGame() async {
    setState(() => _creating = true);
    final notifier = ref.read(chitmatchProvider(widget.familyId).notifier);
    await notifier.createGame(playerCount: _playerCount, roundTimerSeconds: _roundTimer);
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(KinrelRadius.lg))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(KinrelSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Share this code', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 18, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
            const SizedBox(height: KinrelSpacing.md),
            Text(code, style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 40, fontWeight: FontWeight.w700, color: KinrelColors.orange, letterSpacing: 6)),
            const SizedBox(height: KinrelSpacing.md),
            Text('${_playerCount - 1} family members can join (4-${_playerCount} total).', textAlign: TextAlign.center, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim)),
            const SizedBox(height: KinrelSpacing.lg),
            DKButton(label: 'Done', variant: DKButtonVariant.primary, fullWidth: true, onPressed: () => Navigator.of(context).pop()),
          ],
        ),
      ),
    );
  }

  Future<void> _submitWord() async {
    final word = _wordController.text.trim();
    if (word.isEmpty) return;
    await ref.read(chitmatchProvider(widget.familyId).notifier).submitWord(word);
    setState(() => _wordSubmitted = true);
  }

  Future<void> _startSetup() async {
    await ref.read(chitmatchProvider(widget.familyId).notifier).startSetup();
  }

  Future<void> _dealAndStart() async {
    await ref.read(chitmatchProvider(widget.familyId).notifier).dealAndStartGame();
    final gameId = ref.read(chitmatchProvider(widget.familyId)).game?.id;
    if (gameId != null && mounted) {
      context.pushReplacement('/family/${widget.familyId}/chitmatch/game/$gameId');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chitmatchProvider(widget.familyId));
    final notifier = ref.read(chitmatchProvider(widget.familyId).notifier);
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isHost = state.game?.hostUserId == myId || state.game == null;
    final hasGame = state.game != null;
    final allWordsSubmitted = hasGame && state.players.isNotEmpty && state.players.every((p) => p.submittedWord != null && p.submittedWord!.isNotEmpty);

    // Auto-navigate to game screen when game goes in_progress
    ref.listen<ChitmatchState>(chitmatchProvider(widget.familyId), (prev, next) {
      if (next.isInProgress && !(prev?.isInProgress ?? false) && next.game?.id != null && mounted) {
        context.pushReplacement('/family/${widget.familyId}/chitmatch/game/${next.game!.id}');
      }
    });

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () {
          if (state.game != null) notifier.leaveGame();
          Navigator.of(context).pop();
        }),
        title: Text('TripleMatch', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
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
                  gameType: GameType.chitmatch,
                  gameId: state.game!.id,
                  roomCode: code,
                  currentPlayerIds: state.players.map((p) => p.userId).whereType<String>().toSet(),
                  maxPlayers: state.game!.playerCount,
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
          ? DKErrorState(message: state.error!, onRetry: () => notifier.createGame(playerCount: _playerCount, roundTimerSeconds: _roundTimer))
          : !hasGame
            ? _setupView(state)
            : state.game!.isWaiting
              ? _lobbyView(state, isHost)
              : state.game!.isSetup
                ? _wordSubmissionView(state, isHost, allWordsSubmitted)
                : _lobbyView(state, isHost),
    );
  }

  Widget _setupView(ChitmatchState state) {
    return ListView(
      padding: const EdgeInsets.all(KinrelSpacing.base),
      children: [
        _sectionLabel('Number of Players'),
        const SizedBox(height: KinrelSpacing.sm),
        _playerCountSelector(),
        const SizedBox(height: KinrelSpacing.lg),
        _sectionLabel('Round Timer: ${_roundTimer}s'),
        const SizedBox(height: KinrelSpacing.sm),
        Slider(value: _roundTimer.toDouble(), min: 10, max: 60, divisions: 10, activeColor: KinrelColors.orange, label: '${_roundTimer}s', onChanged: (v) => setState(() => _roundTimer = v.round())),
        const SizedBox(height: KinrelSpacing.lg),
        _sectionLabel('How to Play'),
        const SizedBox(height: KinrelSpacing.sm),
        _rulesCard(),
        const SizedBox(height: KinrelSpacing.xl),
        DKButton(label: 'Create Game', variant: DKButtonVariant.gradient, fullWidth: true, isLoading: _creating, onPressed: _createGame),
      ],
    );
  }

  Widget _lobbyView(ChitmatchState state, bool isHost) {
    final game = state.game!;
    final code = game.id.replaceAll('-', '').substring(0, 6).toUpperCase();
    final canStart = state.players.length >= 4;

    return ListView(
      padding: const EdgeInsets.all(KinrelSpacing.base),
      children: [
        GestureDetector(
          onTap: () => _shareCode(game.id),
          child: Container(
            padding: const EdgeInsets.all(KinrelSpacing.lg),
            decoration: BoxDecoration(gradient: KinrelGradients.igniteGradient, borderRadius: BorderRadius.circular(KinrelRadius.lg)),
            child: Column(children: [
              Text('Share Code', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.9), letterSpacing: 1)),
              const SizedBox(height: KinrelSpacing.sm),
              Text(code, style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 36, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 8)),
              const SizedBox(height: 4),
              Text('Waiting (${state.players.length}/${game.playerCount})', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 11, color: Colors.white.withValues(alpha: 0.8))),
            ]),
          ),
        ),
        const SizedBox(height: KinrelSpacing.lg),
        _sectionLabel('Players (${state.players.length}/${game.playerCount})'),
        const SizedBox(height: KinrelSpacing.sm),
        ...state.players.map((p) => _playerTile(p, game.hostUserId)),
        const SizedBox(height: KinrelSpacing.xl),
        if (isHost)
          if (hasGame)
          PendingInvitesSection(gameId: state.game!.id),
        const SizedBox(height: KinrelSpacing.md),
        DKButton(
            label: canStart ? 'Start Setup (Submit Words)' : 'Need 4+ players',
            variant: DKButtonVariant.gradient, fullWidth: true,
            onPressed: canStart ? _startSetup : null,
          )
        else
          _waitingIndicator(),
      ],
    );
  }

  Widget _wordSubmissionView(ChitmatchState state, bool isHost, bool allWordsSubmitted) {
    return ListView(
      padding: const EdgeInsets.all(KinrelSpacing.base),
      children: [
        Text('Submit Your Word', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 18, fontWeight: FontWeight.w700, color: KinrelColors.textWhite)),
        const SizedBox(height: 4),
        Text('Choose an animal or object name. 3 chits with this word will be created and shuffled into the game.', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim)),
        const SizedBox(height: KinrelSpacing.lg),
        if (_wordSubmitted || state.myWord != null)
          Container(
            padding: const EdgeInsets.all(KinrelSpacing.lg),
            decoration: BoxDecoration(color: KinrelColors.success.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(KinrelRadius.lg), border: Border.all(color: KinrelColors.success, width: 1)),
            child: Row(children: [
              Icon(Icons.check_circle, color: KinrelColors.success, size: 24),
              const SizedBox(width: KinrelSpacing.sm),
              Expanded(child: Text('Your word: "${state.myWord ?? _wordController.text}"', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, color: KinrelColors.textWhite, fontWeight: FontWeight.w600))),
            ]),
          )
        else ...[
          TextField(
            controller: _wordController,
            style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 16, color: KinrelColors.textWhite),
            decoration: InputDecoration(
              hintText: 'e.g. Elephant, Tiger, Rocket...',
              hintStyle: TextStyle(color: KinrelColors.textDim),
              filled: true, fillColor: KinrelColors.darkCard,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(KinrelRadius.lg), borderSide: BorderSide(color: KinrelColors.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(KinrelRadius.lg), borderSide: BorderSide(color: KinrelColors.orange, width: 2)),
            ),
            onSubmitted: (_) => _submitWord(),
          ),
          const SizedBox(height: KinrelSpacing.md),
          DKButton(label: 'Submit Word', variant: DKButtonVariant.gradient, fullWidth: true, isLoading: state.isSubmitting, onPressed: _submitWord),
        ],
        const SizedBox(height: KinrelSpacing.xl),
        // Show how many players have submitted
        _sectionLabel('Word Submissions'),
        const SizedBox(height: KinrelSpacing.sm),
        ...state.players.map((p) {
          final submitted = p.submittedWord != null && p.submittedWord!.isNotEmpty;
          return Container(
            margin: const EdgeInsets.only(bottom: KinrelSpacing.sm),
            padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.md, vertical: KinrelSpacing.sm),
            decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(KinrelRadius.md), border: Border.all(color: KinrelColors.border)),
            child: Row(children: [
              DKAvatar(initials: p.userName.isNotEmpty ? p.userName[0].toUpperCase() : '?'),
              const SizedBox(width: KinrelSpacing.md),
              Expanded(child: Text(p.userId == _myId(state) ? '${p.userName} (You)' : p.userName, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, color: KinrelColors.textWhite))),
              Icon(submitted ? Icons.check_circle : Icons.hourglass_empty, size: 16, color: submitted ? KinrelColors.success : KinrelColors.textDim),
            ]),
          );
        }),
        const SizedBox(height: KinrelSpacing.xl),
        if (isHost && allWordsSubmitted)
          DKButton(label: 'Deal Chits & Start!', variant: DKButtonVariant.gradient, fullWidth: true, isLoading: state.isResolving, onPressed: _dealAndStart)
        else if (isHost)
          Text('Waiting for all players to submit words...', textAlign: TextAlign.center, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim))
        else
          _waitingIndicator(),
      ],
    );
  }

  String? _myId(ChitmatchState state) => ref.read(supabaseProvider)?.auth.currentUser?.id;

  Widget _playerCountSelector() {
    return Wrap(spacing: KinrelSpacing.sm, runSpacing: KinrelSpacing.sm,
      children: [4, 6, 8, 10, 12].map((n) {
        final selected = n == _playerCount;
        return GestureDetector(onTap: () { GameMotionTokens.tap(); setState(() => _playerCount = n); },
          child: Container(width: 50, padding: const EdgeInsets.symmetric(vertical: KinrelSpacing.sm),
            decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(KinrelRadius.md), border: Border.all(color: selected ? KinrelColors.orange : KinrelColors.border, width: selected ? 2 : 1)),
            child: Center(child: Text('$n', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 16, fontWeight: FontWeight.w700, color: selected ? KinrelColors.orange : KinrelColors.textDim))),
          ),
        );
      }).toList(),
    );
  }

  Widget _rulesCard() {
    return Container(padding: const EdgeInsets.all(KinrelSpacing.md), decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(KinrelRadius.lg), border: Border.all(color: KinrelColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _ruleLine('1.', 'Each player submits a word. 3 chits per word are created.'),
        const SizedBox(height: 6),
        _ruleLine('2.', 'All chits are shuffled. Each player gets 3 random chits.'),
        const SizedBox(height: 6),
        _ruleLine('3.', 'Each round, everyone selects 1 chit to pass clockwise.'),
        const SizedBox(height: 6),
        _ruleLine('4.', 'Passes resolve simultaneously — all at once!'),
        const SizedBox(height: 6),
        _ruleLine('5.', 'First to 3 matching chits wins. Joint winners possible!'),
        const SizedBox(height: 6),
        _ruleLine('★', 'Don\'t respond in ${_roundTimer}s? Auto-selected for you.', highlight: true),
      ]),
    );
  }

  Widget _sectionLabel(String text) => Text(text, style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 13, fontWeight: FontWeight.w600, color: KinrelColors.textDim, letterSpacing: 0.5));
  Widget _ruleLine(String num, String text, {bool highlight = false}) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    SizedBox(width: 24, child: Text(num, style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 12, fontWeight: FontWeight.w700, color: highlight ? KinrelColors.orange : KinrelColors.textDim))),
    Expanded(child: Text(text, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: highlight ? KinrelColors.textWhite : KinrelColors.textDim, height: 1.4))),
  ]);

  Widget _playerTile(ChitmatchPlayerModel p, String? hostUserId) {
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isMe = p.userId == myId;
    return Container(margin: const EdgeInsets.only(bottom: KinrelSpacing.sm), padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.md, vertical: KinrelSpacing.md),
      decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(KinrelRadius.lg), border: Border.all(color: isMe ? KinrelColors.orange : KinrelColors.border, width: isMe ? 2 : 1)),
      child: Row(children: [
        DKAvatar(initials: p.userName.isNotEmpty ? p.userName[0].toUpperCase() : '?'),
        const SizedBox(width: KinrelSpacing.md),
        Expanded(child: Text(isMe ? '${p.userName} (You)' : p.userName, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, fontWeight: FontWeight.w600, color: KinrelColors.textWhite))),
        if (p.userId == hostUserId) Text('👑', style: TextStyle(fontSize: 14)),
      ]),
    );
  }

  Widget _waitingIndicator() => Container(padding: const EdgeInsets.all(KinrelSpacing.lg), decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(KinrelRadius.lg), border: Border.all(color: KinrelColors.border)),
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: KinrelColors.orange)),
      const SizedBox(width: KinrelSpacing.sm),
      Text('Waiting for host...', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, color: KinrelColors.textDim)),
    ]),
  );
}
