// lib/features/games/shared/multiplayer/widgets/match_countdown.dart
//
// MatchCountdown — full-screen 5-4-3-2-1-GO overlay shown when the host
// taps "Start Match". Every connected client renders this overlay in
// sync using the server-authoritative `countdownEndsAt` deadline.
//
// Behaviour:
//   • Reads state.countdownEndsAt from the RoomController.
//   • Renders a semi-transparent dark backdrop + a big animated number
//     (5 → 4 → 3 → 2 → 1 → GO!).
//   • Each number pops in with an elastic scale + fades out 600ms later.
//   • "GO!" is shown for 400ms before the overlay disappears.
//   • Auto-hides when state.isCountdown becomes false (e.g. when the
//     game row transitions to 'active').
//   • Host sees a small "Cancel" pill at the bottom in case they want
//     to abort the countdown.
//
// Used by LobbyView — wraps the entire lobby body in this overlay
// whenever state.isCountdown is true.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/constants/brand_colors.dart';
import '../../../../../core/constants/brand_typography.dart';
import '../../../../../shared/widgets/dk_components.dart';
import '../room_controller.dart';
import '../room_state.dart';

class MatchCountdown extends ConsumerStatefulWidget {
  const MatchCountdown({
    super.key,
    required this.roomKey,
    this.onCancel,
  });

  final RoomControllerKey roomKey;

  /// Host-only: called when the user taps "Cancel" during the countdown.
  /// The host's RoomController.cancelCountdown() clears the countdown
  /// state, which causes this widget to disappear.
  final VoidCallback? onCancel;

  @override
  ConsumerState<MatchCountdown> createState() => _MatchCountdownState();
}

class _MatchCountdownState extends ConsumerState<MatchCountdown> {
  int _lastDisplayed = -1;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(roomControllerProvider(widget.roomKey));
    if (!state.isCountdown) return const SizedBox.shrink();

    final secondsLeft = state.secondsUntilCountdownEnds ?? 0;
    // We display "GO!" for the final tick (when secondsLeft == 0 but the
    // state is still countdown — i.e. waiting for the game-row update to
    // 'active' to arrive via realtime).
    final displayNumber = secondsLeft > 0 ? secondsLeft : 0;
    final isGo = secondsLeft == 0;

    // Track when the displayed number changes so we can re-trigger the
    // pop animation.
    if (displayNumber != _lastDisplayed) {
      _lastDisplayed = displayNumber;
    }

    return Positioned.fill(
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          color: Colors.black.withValues(alpha: 0.78),
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Label
                Text(
                  'Match starts in',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.75),
                    letterSpacing: 1.5,
                  ),
                )
                    .animate()
                    .fadeIn(duration: 250.ms),
                const SizedBox(height: 16),

                // Big number
                _BigNumber(
                  key: ValueKey(isGo ? 'GO' : displayNumber),
                  text: isGo ? 'GO!' : '$displayNumber',
                  isGo: isGo,
                ),
                const SizedBox(height: 32),

                // Sublabel
                Text(
                  _sublabel(state),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),

                // Host cancel pill (only if host + cancel callback provided)
                if (state.isHost && widget.onCancel != null) ...[
                  const SizedBox(height: 48),
                  SizedBox(
                    width: 200,
                    child: DKButton(
                      label: 'Cancel',
                      variant: DKButtonVariant.secondary,
                      icon: Icons.close,
                      fullWidth: true,
                      onPressed: widget.onCancel!,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _sublabel(RoomState state) {
    if (state.isHost) {
      return 'Starting the match for ${state.playerCount} player${state.playerCount == 1 ? '' : 's'}\u2026';
    }
    return 'Host is starting the match\u2026';
  }
}

/// The big animated number / "GO!" text.
class _BigNumber extends StatelessWidget {
  const _BigNumber({super.key, required this.text, required this.isGo});

  final String text;
  final bool isGo;

  @override
  Widget build(BuildContext context) {
    final color = isGo ? KinrelColors.tealAccent : KinrelColors.orange;
    final size = isGo ? 88.0 : 120.0;
    return SizedBox(
      height: 140,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Glow background
          Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  color.withValues(alpha: 0.35),
                  color.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
          // Number
          Text(
            text,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: size,
              fontWeight: FontWeight.w900,
              color: color,
              letterSpacing: -2,
              height: 1,
              shadows: [
                Shadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 24,
                ),
              ],
            ),
          )
              .animate()
              .scale(
                duration: 350.ms,
                curve: Curves.elasticOut,
                begin: const Offset(0.4, 0.4),
                end: const Offset(1.0, 1.0),
              )
              .then()
              .fade(duration: 500.ms, delay: 400.ms, begin: 1, end: 0.55),
        ],
      ),
    );
  }
}
