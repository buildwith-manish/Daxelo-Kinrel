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
//
// The roster is passed in as a constructor parameter — it is therefore
// captured at RESULTS-SCREEN BUILD time, BEFORE the button is tapped and
// BEFORE onCreateNewGame() swaps the provider onto the new game (the QA bug
// where "rematch invited nobody" was exactly a roster read after create).
//
// Two rollout knobs:
//   • maxPlayers — recorded on the invite rows (was hardcoded 2, which
//     mislabelled 3–4 player games).
//   • insertInvites — set to false for games whose provider rematch()
//     already inserts game_invites (and carries the roster over), so the
//     two paths don't double-invite.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../shared/widgets/dk_components.dart';
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
    this.maxPlayers = 2,
    this.insertInvites = true,
    this.label = 'Rematch',
    this.beforeNavigate,
  });

  final String familyId;
  final GameType gameType;
  final String previousGameId;
  final List<String> participantUserIds;
  final Future<String?> Function() onCreateNewGame;
  final String? hostUserId;

  /// Recorded on the invite rows. Pass the completed game's real capacity
  /// (e.g. ludo/dotsboxes support 4) — defaults to 2 for duels.
  final int maxPlayers;

  /// Whether THIS widget inserts the game_invites rows. Games whose provider
  /// rematch() already inserts invites (and pre-fills the roster) pass false.
  final bool insertInvites;

  /// Button label — 'Rematch' everywhere except round-based games where the
  /// action really starts a new round (e.g. Ghost Painter's 'Next Round').
  final String label;

  /// Runs after the new game exists but before navigation — e.g. closing a
  /// wrapping modal bottom sheet (Truth or Dare's Family Moments sheet).
  final VoidCallback? beforeNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DKButton(
      label: label,
      icon: Icons.refresh,
      variant: DKButtonVariant.gradient,
      fullWidth: true,
      onPressed: () => _rematch(context, ref),
    );
  }

  Future<void> _rematch(BuildContext context, WidgetRef ref) async {
    // Capture the router + messenger BEFORE any await — the results view can
    // unmount mid-flight (provider swaps onto the new waiting game, or a
    // wrapping bottom sheet pops), which would otherwise strand the host on
    // a dead screen after the room was already created.
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final client = ref.read(supabaseProvider);
    final myId = client?.auth.currentUser?.id ?? '';
    final myName =
        (client?.auth.currentUser?.userMetadata?['name'] as String?) ??
            'A family member';

    // 1. Create the new game row via the game's provider
    final newGameId = await onCreateNewGame();
    if (newGameId == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Couldn\'t start rematch — try again'),
          backgroundColor: KinrelColors.error,
        ),
      );
      return;
    }

    // 2. Insert game_invites for every participant (except the host themselves)
    final roomCode =
        newGameId.replaceAll('-', '').substring(0, 6).toUpperCase();
    final invites = participantUserIds
        .where((id) => id.isNotEmpty && id != myId)
        .map((userId) => ({
              'gameTable': gameTableForType(gameType),
              'gameId': newGameId,
              'gameType': gameType.routeSegment,
              'familyId': familyId,
              'roomCode': roomCode,
              'invitedUserId': userId,
              'invitedByUserId': myId,
              'invitedByName': myName,
              'maxPlayers': maxPlayers,
              'currentPlayers': 1,
              'message': '$myName wants a rematch in ${gameType.displayName}',
              'status': 'pending',
              'sourceGameId': previousGameId,
            }))
        .toList();

    if (insertInvites && invites.isNotEmpty && client != null) {
      try {
        await client.from('game_invites').insert(invites);
      } catch (_) {
        // best-effort — host is already in the new room
      }
    }

    // 3. Navigate the host into the new game's lobby
    beforeNavigate?.call();
    router.go(
      '/family/$familyId/${gameType.routeSegment}/lobby?join=$newGameId',
    );
  }
}
