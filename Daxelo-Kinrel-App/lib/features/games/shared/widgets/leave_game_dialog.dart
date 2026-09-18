// lib/features/games/shared/widgets/leave_game_dialog.dart
//
// LeaveGameDialog — shared confirmation dialog for leaving any multiplayer
// game session (board, table, or active game screen).
//
// UX:
//   ┌────────────────────────────────────────┐
//   │           Leave Game                    │
//   │                                         │
//   │  Are you sure you want to leave this    │
//   │  game? Leaving will end your            │
//   │  participation and may close the room  │
//   │  if you are the host.                   │
//   │                                         │
//   │      [ Stay ]      [ Leave Game ]       │
//   └────────────────────────────────────────┘
//
// Usage from any game screen:
//   final shouldLeave = await LeaveGameDialog.show(
//     context,
//     isHost: state.game?.hostUserId == myId,
//   );
//   if (shouldLeave == true) {
//     ref.read(chessProvider(familyId).notifier).leaveGame();
//     if (context.canPop()) context.pop(); else context.go('/family/$familyId');
//   }
//
// Why a dialog instead of letting the X button exit immediately:
//   • Prevents accidental exits during a live game (a single stray tap
//     used to forfeit the player)
//   • Tells the user up-front whether their leave will close the room
//     for everyone (when they're the host)
//   • Provides a clear "Stay" escape hatch
//
// Behavior:
//   • If isHost=true, the message warns "this will close the room for
//     all players".
//   • If isHost=false, the message just says leaving will end their
//     participation.
//   • Returns true if the user confirmed, false (or null) if they tapped
//     Stay or dismissed the dialog.

import 'package:flutter/material.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../shared/widgets/dk_components.dart';

class LeaveGameDialog {
  LeaveGameDialog._(); // prevent instantiation

  /// Show the leave-game confirmation dialog.
  ///
  /// Returns true if the user tapped "Leave Game", false if they tapped
  /// "Stay", and null if they dismissed the dialog (tapped outside).
  static Future<bool?> show(
    BuildContext context, {
    bool isHost = false,
    String? gameName,
  }) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true, // tapping outside = cancel
      builder: (ctx) => _LeaveGameDialogContent(
        isHost: isHost,
        gameName: gameName,
      ),
    );
  }
}

class _LeaveGameDialogContent extends StatelessWidget {
  const _LeaveGameDialogContent({required this.isHost, this.gameName});

  final bool isHost;
  final String? gameName;

  @override
  Widget build(BuildContext context) {
    final title = gameName != null ? 'Leave $gameName?' : 'Leave Game?';
    final message = isHost
        ? 'Are you sure you want to leave this game? Leaving will end your '
            'participation and will close the room for everyone, since you '
            'are the host.'
        : 'Are you sure you want to leave this game? Leaving will end your '
            'participation, but the room will stay open for other players.';

    return Dialog(
      backgroundColor: KinrelColors.darkCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(KinrelSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Icon + title row
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: (isHost ? KinrelColors.red : KinrelColors.warning)
                        .withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isHost ? Icons.warning_amber_rounded : Icons.exit_to_app,
                    color: isHost ? KinrelColors.red : KinrelColors.warning,
                    size: 22,
                  ),
                ),
                const SizedBox(width: KinrelSpacing.md),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: KinrelSpacing.md),
            // Message
            Text(
              message,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: KinrelColors.textDim,
                height: 1.45,
              ),
            ),
            const SizedBox(height: KinrelSpacing.xl),
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: DKButton(
                    label: 'Stay',
                    variant: DKButtonVariant.secondary,
                    fullWidth: true,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(width: KinrelSpacing.sm),
                Expanded(
                  child: DKButton(
                    label: 'Leave Game',
                    variant: DKButtonVariant.primary,
                    fullWidth: true,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
