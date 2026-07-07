// lib/features/games/shared/widgets/rematch_button.dart
//
// Shown on a game's results / game-over screen when the game has reached
// status='completed' (or 'finished' for SOS/redlight). Visible only to the
// host. Tapping it:
//   1. Creates a new row in the same game's table (same familyId, host).
//   2. Inserts game_invites for every player who was in the just-completed
//      game (with sourceGameId set so analytics can distinguish rematches).
//   3. Navigates the host into the new game's lobby.
//
// The game-row creation goes through the game's existing provider's
// createGame() method to ensure all the per-game required fields are set
// correctly (each game has different required columns).
//
// Usage:
//   RematchButton(
//     familyId: widget.familyId,
//     gameType: GameType.bingo,
//     previousGameId: state.game!.id,
//     participantUserIds: state.allCards.map((c) => c.playerId).toList(),
//     onCreateNewGame: () => ref.read(bingoProvider(widget.familyId).notifier).createGame(),
//   )

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/network/socket_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../models/game_invite.dart';

class RematchButton extends ConsumerWidget {
  const RematchButton({
    super.key,
    required this.familyId,
    required this.gameType,
    required this.previousGameId,
    required this.participantUserIds,
    required this.onCreateNewGame,
    this.hostUserId,
  });

  final String familyId;
  final GameType gameType;
  final String previousGameId;
  final List<String> participantUserIds;
  final Future<String?> Function() onCreateNewGame;
  final String? hostUserId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DKButton(
      label: 'Rematch',
      icon: Icons.refresh,
      variant: DKButtonVariant.gradient,
      fullWidth: true,
      onPressed: () => _rematch(context, ref),
    );
  }

  Future<void> _rematch(BuildContext context, WidgetRef ref) async {
    final client = ref.read(supabaseProvider);
    final myId = client?.auth.currentUser?.id ?? '';
    final myName =
        (client?.auth.currentUser?.userMetadata?['name'] as String?) ??
            'A family member';

    // 1. Create the new game row via the game's provider
    final newGameId = await onCreateNewGame();
    if (newGameId == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Couldn\'t start rematch — try again'),
            backgroundColor: KinrelColors.error,
          ),
        );
      }
      return;
    }

    // 2. Insert game_invites for every participant (except the host themselves)
    final roomCode =
        newGameId.replaceAll('-', '').substring(0, 6).toUpperCase();
    final invites = participantUserIds
        .where((id) => id.isNotEmpty && id != myId)
        .map((userId) => ({
              'gameTable': _gameTableName(gameType),
              'gameId': newGameId,
              'gameType': gameType.routeSegment,
              'familyId': familyId,
              'roomCode': roomCode,
              'invitedUserId': userId,
              'invitedByUserId': myId,
              'invitedByName': myName,
              'maxPlayers': 2,
              'currentPlayers': 1,
              'message': '$myName wants a rematch in ${gameType.displayName}',
              'status': 'pending',
              'sourceGameId': previousGameId,
            }))
        .toList();

    if (invites.isNotEmpty && client != null) {
      try {
        await client.from('game_invites').insert(invites);
      } catch (_) {
        // best-effort — host is already in the new room
      }
    }

    // 3. Navigate the host into the new game's lobby
    if (!context.mounted) return;
    GoRouter.of(context).go(
      '/family/$familyId/${gameType.routeSegment}/lobby?join=$newGameId',
    );
  }

  String _gameTableName(GameType t) {
    switch (t) {
      case GameType.bingo: return 'bingo_games';
      case GameType.ludo: return 'ludo_games';
      case GameType.checkers: return 'checkers_games';
      case GameType.carrom: return 'carrom_games';
      case GameType.chess: return 'chess_games';
      case GameType.chitmatch: return 'chitmatch_games';
      case GameType.nameplace: return 'nameplace_games';
      case GameType.tictactoe: return 'tictactoe_games';
      case GameType.truthordare: return 'truthordare_games';
      case GameType.twotruths: return 'twotruths_games';
      case GameType.dotsboxes: return 'dotsboxes_games';
      case GameType.sos: return 'sos_games';
      case GameType.antakshari: return 'antakshari_games';
      case GameType.redlight: return 'redlight_rounds';
    }
  }
}

// Local DKButton re-export to avoid pulling in the full dk_components file
// (which may have other dependencies). If the project already has DKButton
// in dk_components.dart, this can be removed in favor of importing it.
class DKButton extends StatelessWidget {
  const DKButton({
    super.key,
    required this.label,
    this.icon,
    this.variant = DKButtonVariant.primary,
    this.fullWidth = false,
    this.onPressed,
  });
  final String label;
  final IconData? icon;
  final DKButtonVariant variant;
  final bool fullWidth;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final isGradient = variant == DKButtonVariant.gradient;
    return SizedBox(
      width: fullWidth ? double.infinity : null,
      child: Material(
        color: isGradient ? null : KinrelColors.orange,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: isGradient
                ? BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF6B35), Color(0xFFFF8C42)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  )
                : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: Colors.white, size: 16),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum DKButtonVariant { primary, gradient }
