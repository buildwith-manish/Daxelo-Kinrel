// lib/features/games/redlight/redlight_lobby_screen.dart
//
// Freeze & Dash — Lobby / Setup screen.
// Route: /family/$familyId/freeze-dash/lobby
//
// Refactored to use the shared multiplayer framework:
//   • RoomSetupView for the setup view (caller character + map theme +
//     weather modifier + game modes + spectator toggle + auto-close
//     duration + Create button)
//   • LobbyView for the in-room view (auto-close timer, share code,
//     players list, pending invites, lobby chat, ready toggle / start
//     button, cancel room button)
//   • BackButtonGuard for the back button (host: Close Room? / player:
//     Leave Room?)
//
// NOTE: Freeze & Dash uses the `redlight_rounds` table (not `_games`)
// and exposes `createRound` / `joinRound` / `leaveRound` instead of
// the standard `createGame` / `joinGame` / `leaveGame` names. The
// RoomController doesn't care about the naming — it just needs the
// id, so we pass the roundId to `attachToExistingGame` /
// `attachOnJoin`.
//
// The existing RedlightNotifier handles game-specific logic (creating
// the redlight_rounds row + host's redlight_players row, emitting
// the start-countdown event when the host starts). The RoomController
// handles the shared room lifecycle.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../shared/widgets/dk_components.dart';
import '../game_motion_tokens.dart';
import '../shared/multiplayer/multiplayer.dart';
import '../shared/models/game_invite.dart';
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

  /// The room controller key for this Freeze & Dash lobby.
  RoomControllerKey get _roomKey =>
      RoomControllerKey(RoomConfig.redlight, widget.familyId);

  /// The `?join=<roundId>` query param from the deep-link.
  String? get _joinIdFromRoute =>
      GoRouterState.of(context).uri.queryParameters['join'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final joinId = _joinIdFromRoute;
      if (joinId != null && joinId.isNotEmpty) {
        // Non-host joining via deep-link: attach via the game provider
        // first (existing logic), then attach the room controller.
        final ok = await ref
            .read(redlightProvider(widget.familyId).notifier)
            .joinRound(joinId);
        if (ok) {
          await ref
              .read(roomControllerProvider(_roomKey).notifier)
              .attachOnJoin(joinId);
        }
      }
    });
  }

  Future<void> _createRound() async {
    // 1. Let the game provider create the round row with game-specific
    //    fields. Returns the roundId.
    final roundId = await ref
        .read(redlightProvider(widget.familyId).notifier)
        .createRound(
          callerCharacter: _caller,
          mapTheme: _mapTheme,
          weatherModifier: _weather,
          teamMode: _teamMode,
          eliminationMode: _eliminationMode,
        );
    if (roundId == null) return;
    // 2. Attach the room-lifecycle framework (auto-close, spectator,
    //    ready, lobby chat persistence, disconnect detection).
    //    The controller only needs the row id — roundId or gameId is
    //    interchangeable here.
    await ref
        .read(roomControllerProvider(_roomKey).notifier)
        .attachToExistingGame(
          roundId,
          spectatorsEnabled: true,
          autoCloseMinutes: 10,
        );
  }

  Future<void> _shareCode(String? roundId) async {
    if (roundId == null) return;
    final code = roundId.replaceAll('-', '').substring(0, 6).toUpperCase();
    unawaited(GameMotionTokens.tap());
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
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/family/${widget.familyId}');
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final redlightState = ref.watch(redlightProvider(widget.familyId));
    final roomState = ref.watch(roomControllerProvider(_roomKey));
    // The framework stores the roundId as `gameId`; the game provider
    // stores it as `round.id`. Either way, it's the same row id.
    final hasRound = redlightState.round != null || roomState.hasGame;

    // Auto-navigate to the game screen once the countdown or active
    // phase begins (host pressed Start, or we joined a running game).
    ref.listen<RedlightState>(
      redlightProvider(widget.familyId),
      (previous, next) {
        final shouldNavigate = next.isCountdown ||
            next.isActive ||
            next.phase != RedlightPhase.waiting ||
            next.countdownSeconds > 0;
        final wasNavigating = previous != null &&
            (previous.isCountdown ||
                previous.isActive ||
                previous.phase != RedlightPhase.waiting ||
                previous.countdownSeconds > 0);
        final roundId = next.round?.id;
        if (shouldNavigate && !wasNavigating && roundId != null && mounted) {
          context.pushReplacement(
            '/family/${widget.familyId}/freeze-dash/game/$roundId',
          );
        }
      },
    );

    // Auto-navigate back to setup if room was cancelled/closed
    ref.listen<RoomState>(
      roomControllerProvider(_roomKey),
      (previous, next) {
        if (next.isCancelled && previous != null && !previous.isCancelled) {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/family/${widget.familyId}');
          }
        }
      },
    );

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: BackButtonGuard(
          roomKey: _roomKey,
          onExit: () {
            ref.read(redlightProvider(widget.familyId).notifier).leaveRound();
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/family/${widget.familyId}');
            }
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
          if (hasRound && roomState.isHost)
            IconButton(
              tooltip: 'Share code',
              icon: const Icon(Icons.share_outlined),
              onPressed: () => _shareCode(
                roomState.gameId ?? redlightState.round?.id,
              ),
            ),
        ],
      ),
      body: redlightState.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: KinrelColors.orange),
            )
          : (redlightState.error != null && !hasRound)
              ? DKErrorState(
                  message: redlightState.error!,
                  onRetry: _createRound,
                )
              : hasRound
                  ? LobbyView(
                      roomKey: _roomKey,
                      gameType: GameType.redlight,
                      gameDisplayName: 'Freeze & Dash',
                      // RedlightNotifier.startGame() returns void (it
                      // just emits a socket event). Wrap in an async
                      // closure so it satisfies Future<void> Function().
                      startGame: () async => ref
                          .read(redlightProvider(widget.familyId).notifier)
                          .startGame(),
                    )
                  : _setupView(),
    );
  }

  /// The setup view (no round yet) — uses RoomSetupView wrapper.
  Widget _setupView() {
    return RoomSetupView(
      roomKey: _roomKey,
      createButtonLabel: 'Create Game',
      createGame: () async {
        await _createRound();
        return null;
      },
      defaultAutoCloseMinutes: 10,
      child: _gameSetupFields(),
    );
  }

  Widget _gameSetupFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
        const SizedBox(height: KinrelSpacing.lg),

        _sectionLabel('How to Play'),
        const SizedBox(height: KinrelSpacing.sm),
        _rulesCard(),
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

  Widget _callerSelector() {
    return Wrap(
      spacing: KinrelSpacing.sm,
      runSpacing: KinrelSpacing.sm,
      children: CallerCharacter.values.map((c) {
        final selected = c == _caller;
        return GestureDetector(
          onTap: () {
            unawaited(GameMotionTokens.tap());
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
                color: selected ? KinrelColors.orange : KinrelColors.border,
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
            unawaited(GameMotionTokens.tap());
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
                color: selected ? KinrelColors.orange : KinrelColors.border,
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
            unawaited(GameMotionTokens.tap());
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
                color: selected ? KinrelColors.orange : KinrelColors.border,
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
          description:
              'Two teams compete — first team with all members at 100% wins.',
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
          _ruleLine('1.', 'Host picks a Caller, Map, and (optional) Weather modifier.'),
          const SizedBox(height: 6),
          _ruleLine('2.', 'When the Caller turns GREEN, hold to Run.'),
          const SizedBox(height: 6),
          _ruleLine('3.', 'When the Caller turns RED, release immediately — or get caught.'),
          const SizedBox(height: 6),
          _ruleLine('4.', 'Caught = knockback (-10% progress) or elimination (in Elimination mode).'),
          const SizedBox(height: 6),
          _ruleLine('5.', 'First player (or team) to reach 100% progress wins!'),
          const SizedBox(height: 6),
          _ruleLine(
            '★',
            'Caller: ${_caller.emoji} ${_caller.label} · Map: ${_mapTheme.emoji} ${_mapTheme.label}'
            '${_weather != null ? ' · Weather: ${_weather!.emoji} ${_weather!.label}' : ''}',
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
}
