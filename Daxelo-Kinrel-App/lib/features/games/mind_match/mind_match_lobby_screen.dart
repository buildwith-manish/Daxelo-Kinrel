// lib/features/games/mind_match/mind_match_lobby_screen.dart
//
// Mind Match — Create Room lobby.
// Route: /family/$familyId/mind-match/lobby

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
import 'mind_match_engine.dart';
import 'mind_match_models.dart';
import 'mind_match_provider.dart';

class MindMatchLobbyScreen extends ConsumerStatefulWidget {
  const MindMatchLobbyScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<MindMatchLobbyScreen> createState() =>
      _MindMatchLobbyScreenState();
}

class _MindMatchLobbyScreenState
    extends ConsumerState<MindMatchLobbyScreen> {
  final _roomNameController = TextEditingController();
  int _maxPlayers = 8;
  int _totalRounds = 10;
  int _answerSeconds = 30;
  bool _everyday = true;
  bool _fun = true;
  bool _family = true;
  bool _global = true;
  bool _familyQuestionsEnabled = true;
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
            .read(mindMatchProvider(widget.familyId).notifier)
            .joinGame(id),
      );
    });
  }

  @override
  void dispose() {
    _roomNameController.dispose();
    super.dispose();
  }

  List<String> get _selectedCategories {
    final cats = <String>[];
    if (_everyday) cats.add('everyday');
    if (_fun) cats.add('fun');
    if (_family && _familyQuestionsEnabled) cats.add('family');
    if (_global) cats.add('global');
    return cats.isEmpty ? ['everyday'] : cats;
  }

  Future<void> _createGame() async {
    setState(() => _creating = true);
    await ref.read(mindMatchProvider(widget.familyId).notifier).createGame(
          maxPlayers: _maxPlayers,
          totalRounds: _totalRounds,
          answerSeconds: _answerSeconds,
          categories: _selectedCategories,
          familyQuestionsEnabled: _familyQuestionsEnabled,
          roomName: _roomNameController.text,
          spectatorsEnabled: _spectatorsEnabled,
        );
    if (mounted) setState(() => _creating = false);
  }

  Future<void> _startMatch() async {
    final result = await ref
        .read(mindMatchProvider(widget.familyId).notifier)
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
    final state = ref.watch(mindMatchProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isHost = state.game?.hostUserId == myId || state.game == null;

    ref.listen(mindMatchProvider(widget.familyId), (previous, next) {
      if (next.isInProgress &&
          !(previous?.isInProgress ?? false) &&
          next.game?.id != null &&
          mounted) {
        context.pushReplacement(
          '/family/${widget.familyId}/mind-match/game/${next.game!.id}',
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
                    : 'Mind Match',
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

  void _openInviteSheet(MindMatchState_ state) {
    final game = state.game;
    if (game == null) return;
    GameMotionTokens.tap();
    InviteFamilySheet.show(
      context,
      familyId: widget.familyId,
      gameType: GameType.mindMatch,
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
              'Up to ${_maxPlayers - 1} members. Think like the group!',
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
      gameId: 'mind-match',
      title: 'Mind Match',
      tagline: 'Think like everyone else — match answers, earn points',
      facts: [
        LobbyFact(icon: Icons.groups_2_outlined, label: '2–8 players'),
        LobbyFact(
            icon: Icons.quiz_outlined, label: '$_totalRounds rounds'),
        LobbyFact(icon: Icons.timer_outlined, label: '$_answerSeconds s/round'),
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
                hintText: 'e.g. Family Think-Alike',
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
                LobbyOption(value: 5, label: '5', caption: 'Quick'),
                LobbyOption(value: 10, label: '10', caption: 'Standard'),
                LobbyOption(value: 15, label: '15', caption: 'Party'),
              ],
            ),
          ),
          const SizedBox(height: KinrelSpacing.md),
          LobbySection(
            label: 'Round Timer',
            child: LobbyChoiceGrid<int>(
              selected: _answerSeconds,
              onSelect: (v) => setState(() => _answerSeconds = v),
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
          // Question categories
          LobbySection(
            label: 'Question Categories',
            child: Column(
              children: [
                _CategoryToggle(
                  category: MindMatchCategory.everyday,
                  selected: _everyday,
                  onChanged: (v) => setState(() => _everyday = v),
                ),
                _CategoryToggle(
                  category: MindMatchCategory.fun,
                  selected: _fun,
                  onChanged: (v) => setState(() => _fun = v),
                ),
                _CategoryToggle(
                  category: MindMatchCategory.global,
                  selected: _global,
                  onChanged: (v) => setState(() => _global = v),
                ),
                _CategoryToggle(
                  category: MindMatchCategory.family,
                  selected: _family,
                  enabled: _familyQuestionsEnabled,
                  onChanged: (v) => setState(() => _family = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: KinrelSpacing.md),
          // Family questions toggle
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: KinrelColors.darkCard,
              borderRadius: BorderRadius.circular(KinrelRadius.md),
              border: Border.all(
                  color: _familyQuestionsEnabled
                      ? KinrelColors.amber.withValues(alpha: 0.5)
                      : KinrelColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Family Questions Enabled',
                          style: TextStyle(
                              fontFamily: KinrelTypography.displayFont,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: KinrelColors.textWhite)),
                      const SizedBox(height: 2),
                      Text(
                        'Include family-themed questions (holidays, traditions).',
                        style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 11,
                            color: KinrelColors.textDim),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _familyQuestionsEnabled,
                  onChanged: (v) => setState(() {
                    _familyQuestionsEnabled = v;
                    if (!v) _family = false;
                  }),
                  activeThumbColor: KinrelColors.amber,
                ),
              ],
            ),
          ),
        ],
      ),
      rules: [
        LobbyRule('Each round, a question appears (e.g. "Name a fruit").'),
        LobbyRule('Submit your answer privately — others can\'t see it.'),
        LobbyRule('When all answers are locked, they\'re revealed + grouped.'),
        LobbyRule('Matching the most popular answer earns the most points.'),
        LobbyRule('Perfect Match (everyone same): +20 bonus to all.'),
        LobbyRule('Crowd Favorite bonus + streak bonuses for consecutive matches.'),
      ],
      rulesFootnote:
          'Quick = 5 rounds · Standard = 10 · Party = 15. Questions never repeat within 365 days per family.',
      spectatorsEnabled: _spectatorsEnabled,
      onSpectatorsChanged: (v) => setState(() => _spectatorsEnabled = v),
      ctaLabel: 'Create Game',
      ctaHint: 'Invite family members, then think like the group!',
      ctaLoading: _creating,
      onCtaPressed: _createGame,
    );
  }

  Widget _lobbyView(MindMatchState_ state, bool isHost) {
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
      gameTable: 'mind_match_games',
      gameId: game.id,
      familyId: widget.familyId,
      hostUserId: game.hostUserId,
      players: lobbyPlayers,
      maxPlayers: game.maxPlayers,
      status: lobbyStatus,
      subtitle:
          '${game.totalRounds} rounds · ${game.answerSeconds}s · ${game.categories.length} categories',
    );
    return RoomLifecycleListener(
      gameTable: 'mind_match_games',
      gameId: game.id,
      familyId: widget.familyId,
      isHost: game.hostUserId == myId,
      child: TemporaryLobbyView(
        config: config,
        myUserId: myId,
        onToggleReady: (isReady) => ref
            .read(mindMatchProvider(widget.familyId).notifier)
            .toggleReady(isReady),
        onStartMatch: _startMatch,
        onCancelRoom: () => ref
            .read(mindMatchProvider(widget.familyId).notifier)
            .leaveGame(),
        onInviteFamily: isHost ? () => _openInviteSheet(state) : null,
      ),
    );
  }
}

class _CategoryToggle extends StatelessWidget {
  const _CategoryToggle({
    required this.category,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });
  final MindMatchCategory category;
  final bool selected;
  final bool enabled;
  final void Function(bool) onChanged;

  @override
  Widget build(BuildContext context) {
    final accent = Color(category.accentArgb);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: enabled ? () => onChanged(!selected) : null,
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
              Text(category.glyph, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  category.label,
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? accent
                        : (enabled
                            ? KinrelColors.textWhite
                            : KinrelColors.textDim),
                  ),
                ),
              ),
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                size: 18,
                color: selected
                    ? accent
                    : (enabled
                        ? KinrelColors.textDim
                        : KinrelColors.textDim.withValues(alpha: 0.4)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
