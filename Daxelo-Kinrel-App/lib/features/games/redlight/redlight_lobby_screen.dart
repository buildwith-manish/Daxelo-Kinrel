// lib/features/games/redlight/redlight_lobby_screen.dart
//
// Freeze & Dash — Lobby / Setup screen.
// Route: /family/$familyId/freeze-dash/lobby

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../game_motion_tokens.dart';
import 'redlight_models.dart';
import 'redlight_provider.dart';

class RedlightLobbyScreen extends ConsumerStatefulWidget {
  const RedlightLobbyScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<RedlightLobbyScreen> createState() =>
      _RedlightLobbyScreenState();
}

class _RedlightLobbyScreenState extends ConsumerState<RedlightLobbyScreen> {
  CallerCharacter _caller = CallerCharacter.grandma;
  MapTheme _mapTheme = MapTheme.forest;
  WeatherModifier? _weather;
  bool _teamMode = false;
  bool _eliminationMode = false;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    // If a roundId was passed via query (join flow), auto-join.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final joinId = GoRouterState.of(context).uri.queryParameters['join'];
      if (joinId != null && joinId.isNotEmpty) {
        ref.read(redlightProvider(widget.familyId).notifier).joinRound(joinId);
      }
    });
  }

  Future<void> _createAndStart() async {
    setState(() => _creating = true);
    final notifier = ref.read(redlightProvider(widget.familyId).notifier);
    final roundId = await notifier.createRound(
      callerCharacter: _caller,
      mapTheme: _mapTheme,
      weatherModifier: _weather,
      teamMode: _teamMode,
      eliminationMode: _eliminationMode,
    );
    if (!mounted) {
      setState(() => _creating = false);
      return;
    }
    if (roundId == null) {
      setState(() => _creating = false);
      return;
    }
    // Jump straight into the game screen — host can press "Start" from there.
    if (mounted) {
      context.pushReplacement(
        '/family/${widget.familyId}/freeze-dash/game/$roundId',
      );
    }
  }

  Future<void> _shareCode(String? roundId) async {
    if (roundId == null) return;
    // Show a 6-char code (first 6 chars of the roundId)
    final code = roundId.replaceAll('-', '').substring(0, 6).toUpperCase();
    GameMotionTokens.tap();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(KinrelRadius.lg)),
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
              'Family members can join from the Games Hub.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
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
    final state = ref.watch(redlightProvider(widget.familyId));
    final notifier = ref.read(redlightProvider(widget.familyId).notifier);
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isHost =
        state.round?.hostUserId == myId || state.round == null;
    final canStart = state.round == null
        ? true
        : (isHost && state.players.length >= 3);

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (state.round != null) {
              notifier.leaveRound();
            }
            Navigator.of(context).pop();
          },
        ),
        title: Text(
          'Freeze & Dash',
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
          if (state.round != null)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              onPressed: () => _shareCode(state.round?.id),
            ),
        ],
      ),
      body: state.isLoading && state.round == null
          ? const Center(
              child: CircularProgressIndicator(color: KinrelColors.orange),
            )
          : state.error != null && state.round == null
          ? DKErrorState(
              message: state.error!,
              onRetry: () {
                notifier.createRound(
                  callerCharacter: _caller,
                  mapTheme: _mapTheme,
                  weatherModifier: _weather,
                  teamMode: _teamMode,
                  eliminationMode: _eliminationMode,
                );
              },
            )
          : ListView(
              padding: const EdgeInsets.all(KinrelSpacing.base),
              children: [
                _sectionLabel('Caller Character'),
                const SizedBox(height: KinrelSpacing.sm),
                _callerSelector(),
                const SizedBox(height: KinrelSpacing.lg),

                _sectionLabel('Map Theme'),
                const SizedBox(height: KinrelSpacing.sm),
                _mapSelector(),
                const SizedBox(height: KinrelSpacing.lg),

                _sectionLabel('Weather Modifier'),
                const SizedBox(height: KinrelSpacing.sm),
                _weatherSelector(),
                const SizedBox(height: KinrelSpacing.lg),

                _sectionLabel('Game Modes'),
                const SizedBox(height: KinrelSpacing.sm),
                _modeToggles(),
                const SizedBox(height: KinrelSpacing.xl),

                _sectionLabel(
                  'Players (${state.players.length}/20)',
                ),
                const SizedBox(height: KinrelSpacing.sm),
                _playerList(state),
                const SizedBox(height: KinrelSpacing.xl),

                if (state.round != null && state.round!.isCountdown)
                  _countdownBanner(state.countdownSeconds),

                DKButton(
                  label: state.round == null
                      ? 'Create Game'
                      : (isHost ? 'Start Game' : 'Waiting for host…'),
                  variant: DKButtonVariant.gradient,
                  fullWidth: true,
                  isLoading: _creating,
                  onPressed: state.round == null
                      ? _createAndStart
                      : (isHost && canStart
                            ? () => notifier.startGame()
                            : null),
                ),
                if (state.round != null && !canStart && isHost)
                  Padding(
                    padding: const EdgeInsets.only(top: KinrelSpacing.sm),
                    child: Text(
                      'Need at least 3 players to start (currently ${state.players.length}).',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        color: KinrelColors.warning,
                      ),
                    ),
                  ),
              ],
            ),
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

  Widget _callerSelector() {
    return Wrap(
      spacing: KinrelSpacing.sm,
      runSpacing: KinrelSpacing.sm,
      children: CallerCharacter.values.map((c) {
        final selected = c == _caller;
        return GestureDetector(
          onTap: () {
            GameMotionTokens.tap();
            setState(() => _caller = c);
          },
          child: Container(
            width: 72,
            padding: const EdgeInsets.symmetric(
              vertical: KinrelSpacing.sm,
              horizontal: KinrelSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: KinrelColors.darkCard,
              borderRadius: BorderRadius.circular(KinrelRadius.lg),
              border: Border.all(
                color: selected
                    ? KinrelColors.orange
                    : KinrelColors.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(c.emoji, style: const TextStyle(fontSize: 28)),
                const SizedBox(height: 4),
                Text(
                  c.label,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 11,
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

  Widget _mapSelector() {
    return Wrap(
      spacing: KinrelSpacing.sm,
      runSpacing: KinrelSpacing.sm,
      children: MapTheme.values.map((m) {
        final selected = m == _mapTheme;
        return GestureDetector(
          onTap: () {
            GameMotionTokens.tap();
            setState(() => _mapTheme = m);
          },
          child: Container(
            width: 80,
            padding: const EdgeInsets.symmetric(
              vertical: KinrelSpacing.sm,
              horizontal: KinrelSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: KinrelColors.darkCard,
              borderRadius: BorderRadius.circular(KinrelRadius.lg),
              border: Border.all(
                color: selected
                    ? KinrelColors.orange
                    : KinrelColors.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(m.emoji, style: const TextStyle(fontSize: 26)),
                const SizedBox(height: 4),
                Text(
                  m.label,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 11,
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

  Widget _weatherSelector() {
    final options = [null, ...WeatherModifier.values];
    return Wrap(
      spacing: KinrelSpacing.sm,
      runSpacing: KinrelSpacing.sm,
      children: options.map((w) {
        final selected = w == _weather;
        final label = w == null ? 'None' : w.label;
        final emoji = w == null ? '☀️' : w.emoji;
        return GestureDetector(
          onTap: () {
            GameMotionTokens.tap();
            setState(() => _weather = w);
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
                color: selected
                    ? KinrelColors.orange
                    : KinrelColors.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
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

  Widget _modeToggles() {
    return Column(
      children: [
        _modeRow(
          label: 'Team Mode',
          description: 'Two teams compete — first team with all members at 100% wins.',
          value: _teamMode,
          onChanged: (v) => setState(() => _teamMode = v),
        ),
        const SizedBox(height: KinrelSpacing.sm),
        _modeRow(
          label: 'Elimination Mode',
          description:
              'Caught = eliminated. Default is knockback (-10% progress).',
          value: _eliminationMode,
          onChanged: (v) => setState(() => _eliminationMode = v),
        ),
      ],
    );
  }

  Widget _modeRow({
    required String label,
    required String description,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(KinrelSpacing.md),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.textWhite,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 11,
                    color: KinrelColors.textDim,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeColor: KinrelColors.orange,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _playerList(RedlightState state) {
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
              Divider(
                height: 1,
                color: KinrelColors.border.withValues(alpha: 0.5),
              ),
            ListTile(
              leading: DKAvatar(initials: state.players[i].userName.isNotEmpty ? state.players[i].userName[0].toUpperCase() : '?'),
              title: Text(
                state.players[i].userName,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  color: KinrelColors.textWhite,
                  fontWeight: FontWeight.w500,
                ),
              ),
              trailing: state.players[i].userId == state.round?.hostUserId
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: KinrelSpacing.sm,
                        vertical: 2,
                      ),
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
            ),
          ],
        ],
      ),
    );
  }

  Widget _countdownBanner(int seconds) {
    return Container(
      margin: const EdgeInsets.only(bottom: KinrelSpacing.lg),
      padding: const EdgeInsets.all(KinrelSpacing.lg),
      decoration: BoxDecoration(
        color: KinrelColors.orange.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(color: KinrelColors.orange),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Starting in $seconds…',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: KinrelColors.orange,
            ),
          ),
        ],
      ),
    );
  }
}
