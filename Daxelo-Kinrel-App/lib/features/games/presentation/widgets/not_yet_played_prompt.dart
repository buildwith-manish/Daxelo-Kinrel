// lib/features/games/presentation/widgets/not_yet_played_prompt.dart
//
// NotYetPlayedPrompt — a small prompt rendered BELOW the ranked list on
// the participation-based leaderboard, for family members who haven't
// played any games yet (games_played == 0).
//
// Per the spec: "Members with games_played == 0 (never played at all)
// are EXCLUDED from the ranked list entirely. Show them instead in a
// separate small prompt below the ranked list: 'Account X hasn't played
// yet — invite them' with a quick invite action, rather than a rank row
// showing 0."
//
// Each prompt is a compact row: avatar, name, "hasn't played yet" label,
// and a tappable "Invite" action that navigates to the Play With flow
// (which will pre-fill a Tic-Tac-Toe invite for that member — the
// lightest game for a first interaction).

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../gaming_ecosystem/data/game_registry.dart';
import '../../shared/icons/kinrel_icons.dart';

class NotYetPlayedPrompt extends StatelessWidget {
  const NotYetPlayedPrompt({
    super.key,
    required this.member,
    required this.familyId,
  });

  final NotYetPlayedMemberData member;
  final String familyId;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: KinrelColors.amber.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          _Avatar(name: member.userName, avatarUrl: member.avatarUrl),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  member.userName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Hasn\'t played yet — invite them',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 11,
                    color: KinrelColors.amber,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              // Navigate to Tic-Tac-Toe lobby (the lightest game for a
              // first interaction). The lobby's invite flow lets the
              // viewer pick this member.
              final game = gameById('tictactoe');
              if (game != null) {
                context.push(gameRoute(game, familyId));
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: KinrelColors.orange,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const KinrelIcon(KinrelIconData.controller,
                      size: 12, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    'Invite',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 250.ms)
        .slideY(begin: 0.03, end: 0, duration: 250.ms);
  }
}

/// Simple data class for the prompt. The provider returns
/// `NotYetPlayedMember` from gaming_providers.dart — this is the plain
/// data the widget needs, decoupled from the provider layer so the
/// widget is testable without Riverpod.
class NotYetPlayedMemberData {
  const NotYetPlayedMemberData({
    required this.userId,
    required this.userName,
    this.avatarUrl,
  });
  final String userId;
  final String userName;
  final String? avatarUrl;
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.avatarUrl});
  final String name;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            KinrelColors.amber.withValues(alpha: 0.35),
            KinrelColors.orange.withValues(alpha: 0.20),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: CircleAvatar(
        radius: 16,
        backgroundColor: Colors.transparent,
        foregroundImage: (avatarUrl != null && avatarUrl!.isNotEmpty)
            ? NetworkImage(avatarUrl!)
            : null,
        child: Text(
          name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: KinrelColors.textWhite,
          ),
        ),
      ),
    );
  }
}
