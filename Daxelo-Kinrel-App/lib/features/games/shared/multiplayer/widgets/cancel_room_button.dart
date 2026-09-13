// lib/features/games/shared/multiplayer/widgets/cancel_room_button.dart
//
// Large, prominent "Close Room" button for the host. Sits at the bottom
// of every lobby's lobby view. NEVER immediately closes the room —
// always shows the shared confirmation dialog first.
//
// Per the spec:
//   • Make the Close Room button clearly visible at all times for the
//     host.
//   • Increase button size and prominence.
//   • Place it in an easily accessible location.
//   • Do not hide it behind menus or secondary actions.
//   • Clicking Close Room must first show a confirmation dialog.
//
// Visual design (upgraded from secondary variant to a prominent red
// error-styled button):
//   • Full-width
//   • Larger vertical padding (18px vs 12px default)
//   • Red background (KinrelColors.error) with subtle glow shadow
//   • Warning icon (Icons.warning_amber_rounded)
//   • Bold white text "Close Room"
//   • Subtitle line below: "Removes all players and spectators"
//   • Loading spinner while the RPC is in-flight
//
// On confirm: calls RoomController.cancelRoom() which:
//   1. Calls fn_cancel_game_room RPC (host-only check server-side)
//   2. Server marks game row cancelledAt + closedAt = now()
//   3. Server DELETEs from game_participants WHERE gameId = ...
//   4. Server DELETEs from game_spectators WHERE gameId = ...
//   5. Server DELETEs from the game's *_players table WHERE gameId = ...
//   6. Server posts a 'cancel' room event (fanned out via realtime)
//   7. Local _cleanup() stops heartbeat + auto-close timer + lobby
//      poll + countdown timer + unsubscribes the realtime channel
//   8. Local state is cleared to const RoomState()
//   9. onCancelled callback fires (typically navigates to setup screen)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/constants/brand_colors.dart';
import '../../../../../core/constants/brand_spacing.dart';
import '../../../../../core/constants/brand_typography.dart';
import '../room_controller.dart';
import 'room_close_dialog.dart';

class CancelRoomButton extends ConsumerWidget {
  const CancelRoomButton({
    super.key,
    required this.roomKey,
    this.onCancelled,
  });

  final RoomControllerKey roomKey;
  final VoidCallback? onCancelled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(roomControllerProvider(roomKey));
    final isSubmitting = state.isSubmitting;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: KinrelSpacing.md),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isSubmitting ? null : () => _confirmCancel(context, ref),
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: KinrelSpacing.lg, vertical: 18),
            decoration: BoxDecoration(
              color: isSubmitting
                  ? KinrelColors.error.withValues(alpha: 0.5)
                  : KinrelColors.error.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(KinrelRadius.md),
              border: Border.all(
                color: KinrelColors.error.withValues(alpha: 0.6),
                width: 1.5,
              ),
              boxShadow: isSubmitting
                  ? null
                  : [
                      BoxShadow(
                        color: KinrelColors.error.withValues(alpha: 0.2),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isSubmitting)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(KinrelColors.error),
                    ),
                  )
                else
                  Icon(Icons.warning_amber_rounded,
                      color: KinrelColors.error, size: 22),
                const SizedBox(width: KinrelSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Close Room',
                        style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: KinrelColors.error,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Removes all players and spectators',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 10,
                          color: KinrelColors.error.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    color: KinrelColors.error.withValues(alpha: 0.7),
                    size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref) async {
    // Show the shared confirmation dialog (exact spec text).
    final confirmed = await showRoomCloseConfirmDialog(context);
    if (confirmed != true) return;
    if (!context.mounted) return;

    // Perform the cancellation — RoomController.cancelRoom() handles:
    //   • fn_cancel_game_room RPC (deletes participants + spectators +
    //     game row + posts 'cancel' event)
    //   • _cleanup() (stops heartbeat + auto-close timer + lobby poll +
    //     countdown timer + unsubscribes realtime channel)
    //   • state = const RoomState() (clears all local cache)
    await ref.read(roomControllerProvider(roomKey).notifier).cancelRoom();

    // Fire the onCancelled callback (typically navigates to setup).
    onCancelled?.call();
  }
}
