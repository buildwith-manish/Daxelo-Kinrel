// lib/features/games/shared/multiplayer/widgets/back_button_guard.dart
//
// Wraps the lobby screen's Back button to enforce the host-vs-player
// confirmation flow per the spec:
//
//   Host pressing Back:
//     "Close Room?"
//     "Closing the room will remove all players and end the lobby."
//     Buttons: Cancel, Close Room
//     → On "Close Room": calls RoomController.cancelRoom() (closes +
//       deletes + notifies all participants + returns to setup).
//
//   Player pressing Back:
//     "Leave Room?"
//     "You will leave this room."
//     Buttons: Stay, Leave
//     → On "Leave": calls RoomController.leaveRoom() (removes the
//       participant, frees their slot, posts a 'leave' system event).
//
//   Spectator pressing Back:
//     "Leave Spectator?"
//     "You will stop watching this room."
//     Buttons: Stay, Leave
//     → On "Leave": calls RoomController.leaveRoom() (calls
//       fn_leave_spectator which marks the spectator row as left +
//       posts a 'spectator_leave' system event).
//
// Usage:
//   AppBar(
//     leading: BackButtonGuard(
//       roomKey: roomKey,
//       onExit: () => context.go('/family/$familyId'),
//     ),
//     ...
//   )

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/constants/brand_colors.dart';
import '../../../../../core/constants/brand_spacing.dart';
import '../../../../../core/constants/brand_typography.dart';
import '../room_controller.dart';

class BackButtonGuard extends ConsumerWidget {
  const BackButtonGuard({
    super.key,
    required this.roomKey,
    required this.onExit,
  });

  final RoomControllerKey roomKey;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(roomControllerProvider(roomKey));
    final hasGame = state.hasGame;

    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () async {
        if (!hasGame) {
          // No active room — just exit.
          onExit();
          return;
        }
        final shouldExit = await _showConfirmDialog(context, state);
        if (shouldExit != true) return;

        // Perform the appropriate action based on the user's role
        final controller = ref.read(roomControllerProvider(roomKey).notifier);
        if (state.isHost) {
          await controller.cancelRoom();
        } else {
          await controller.leaveRoom();
        }
        onExit();
      },
    );
  }

  Future<bool?> _showConfirmDialog(
    BuildContext context,
    dynamic state,
  ) {
    final isHost = state.isHost;
    final isSpectator = state.isSpectator;

    final title = isHost
        ? 'Close Room?'
        : isSpectator
            ? 'Leave Spectator?'
            : 'Leave Room?';
    final body = isHost
        ? 'Closing the room will remove all players and end the lobby.'
        : isSpectator
            ? 'You will stop watching this room.'
            : 'You will leave this room.';
    final positiveLabel = isHost ? 'Close Room' : 'Leave';
    final negativeLabel = isHost ? 'Cancel' : 'Stay';

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KinrelColors.darkCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
        ),
        title: Row(
          children: [
            Icon(
              isHost ? Icons.warning_amber_rounded : Icons.logout,
              color: isHost ? KinrelColors.error : KinrelColors.orange,
              size: 24,
            ),
            const SizedBox(width: KinrelSpacing.sm),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          body,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            color: KinrelColors.textDim,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              negativeLabel,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                color: KinrelColors.textDim,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor:
                  isHost ? KinrelColors.error : KinrelColors.orange,
            ),
            child: Text(
              positiveLabel,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontWeight: FontWeight.w700,
                color: isHost ? KinrelColors.error : KinrelColors.orange,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
