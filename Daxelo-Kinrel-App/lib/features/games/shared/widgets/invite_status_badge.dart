// lib/features/games/shared/widgets/invite_status_badge.dart
//
// Tiny pill widget showing an invite's status (Pending / Accepted / Declined
// / Expired). Used inside InviteFamilySheet rows and the lobby's
// PendingInvitesSection so the host can see who has responded.
//
// Style: small pill, color-coded by status, fits next to a member's name
// without taking significant horizontal space.

import 'package:flutter/material.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../models/game_invite_status.dart';

class InviteStatusBadge extends StatelessWidget {
  const InviteStatusBadge({super.key, required this.status, this.compact = false});

  final InviteMemberStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _colors(status);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: compact ? 9 : 10,
          fontWeight: FontWeight.w700,
          color: fg,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  (Color, Color) _colors(InviteMemberStatus s) {
    switch (s) {
      case InviteMemberStatus.pending:
        return (KinrelColors.orange.withValues(alpha: 0.15), KinrelColors.orange);
      case InviteMemberStatus.accepted:
        return (const Color(0xFF22C55E).withValues(alpha: 0.15), const Color(0xFF22C55E));
      case InviteMemberStatus.declined:
        return (KinrelColors.error.withValues(alpha: 0.15), KinrelColors.error);
      case InviteMemberStatus.expired:
        return (KinrelColors.darkElevated, KinrelColors.textDim);
    }
  }
}
