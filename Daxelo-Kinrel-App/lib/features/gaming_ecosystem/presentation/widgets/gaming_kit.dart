// lib/features/gaming_ecosystem/presentation/widgets/gaming_kit.dart
//
// Gaming Kit — the shared visual language for every Family Gaming Ecosystem
// surface. Built on the Kinrel brand tokens (orange #E8612A, amber, gold,
// dark #13141E surfaces, Outfit display + DM Sans body) so the gaming
// experience feels native to Kinrel — never like a bolt-on gaming platform.
//
// Components:
//   • GamingSectionHeader  — title + optional "View all" action
//   • GamingProgressRing   — animated circular progress (challenges)
//   • GamingProgressBar    — slim linear progress with orange gradient
//   • GamingStatChip       — compact stat display (icon + value + label)
//   • GamingBadgeChip      — badge w/ tier ring + earned glow
//   • GamingPodiumBar      — top-3 podium bars for leaderboards
//   • GamingRankRow        — single leaderboard row (non-toxic framing)
//   • GamingActivityTile   — one activity feed entry
//   • GamingEmptyCard      — friendly empty state
//   • GamingTierColors     — tier → color mapping helper

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../games/shared/icons/kinrel_icons.dart';

/// Tier accent colors — bronze → platinum.
class GamingTierColors {
  GamingTierColors._();

  static Color of(String tier) {
    switch (tier) {
      case 'platinum':
        return const Color(0xFF7DD3FC);
      case 'gold':
        return KinrelColors.brightGold;
      case 'silver':
        return const Color(0xFFCBD5E1);
      default:
        return const Color(0xFFD97706); // bronze
    }
  }
}

/// Section header used across every gaming screen.
class GamingSectionHeader extends StatelessWidget {
  const GamingSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: KinrelColors.orange),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                    letterSpacing: 0.2,
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        color: KinrelColors.textDim,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(44, 36),
                foregroundColor: KinrelColors.amber,
                textStyle: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

/// Animated circular progress ring (used by challenge cards).
class GamingProgressRing extends StatelessWidget {
  const GamingProgressRing({
    super.key,
    required this.progress,
    required this.size,
    this.strokeWidth = 5,
    this.color,
    this.child,
  });

  final double progress; // 0..1
  final double size;
  final double strokeWidth;
  final Color? color;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = color ?? KinrelColors.orange;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              strokeWidth: strokeWidth,
              color: c,
              backgroundColor: c.withValues(alpha: 0.15),
              strokeCap: StrokeCap.round,
            ),
          )
              .animate()
              .fadeIn(duration: 400.ms)
              .scale(delay: 100.ms, duration: 350.ms, curve: Curves.easeOutBack),
          if (child != null) child!,
        ],
      ),
    );
  }
}

/// Slim linear progress bar with the Kinrel orange gradient.
class GamingProgressBar extends StatelessWidget {
  const GamingProgressBar({
    super.key,
    required this.progress,
    this.height = 8,
    this.color,
  });

  final double progress;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? KinrelColors.orange;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: LinearProgressIndicator(
        value: progress.clamp(0.0, 1.0),
        minHeight: height,
        backgroundColor: c.withValues(alpha: 0.15),
        valueColor: AlwaysStoppedAnimation<Color>(c),
      ),
    );
  }
}

/// Compact stat chip — icon + value + label.
///
/// Icon priority: [kinrelIcon] (Kinrel custom icon) → [icon] (Material)
/// → [emoji] (mapped through [kinrelIconFromEmoji] — server data still
/// arrives as emoji strings; it is NEVER rendered as a raw glyph).
class GamingStatChip extends StatelessWidget {
  const GamingStatChip({
    super.key,
    this.icon,
    required this.value,
    required this.label,
    this.color,
    this.emoji,
    this.kinrelIcon,
  });

  final IconData? icon;
  final String? emoji;
  final KinrelIconData? kinrelIcon;
  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? KinrelColors.orange;
    final mappedEmojiIcon = kinrelIconFromEmoji(emoji);
    Widget? leading;
    if (kinrelIcon != null) {
      leading = KinrelIcon(kinrelIcon!, size: 18, color: c);
    } else if (mappedEmojiIcon != null) {
      leading = KinrelIcon(mappedEmojiIcon, size: 18, color: c);
    } else if (icon != null) {
      leading = Icon(icon, size: 18, color: c);
    } else if (emoji != null) {
      // Unrecognized server emoji → neutral sparkle (never a raw glyph).
      leading = KinrelIcon(KinrelIconData.sparkle, size: 18, color: c);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            leading,
            const SizedBox(width: 8),
          ],
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: KinrelColors.textWhite,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 10,
                  color: KinrelColors.textDim,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Badge chip with tier-colored ring + earned glow.
class GamingBadgeChip extends StatelessWidget {
  const GamingBadgeChip({
    super.key,
    required this.icon,
    required this.name,
    required this.tier,
    this.earned = false,
    this.size = 64,
    this.showName = true,
  });

  final String icon;
  final String name;
  final String tier;
  final bool earned;
  final double size;
  final bool showName;

  /// Badge glyph — server data still sends emoji strings; they are
  /// mapped to the Kinrel icon system, never rendered raw.
  KinrelIconData get _badgeIcon =>
      kinrelIconFromEmoji(icon) ?? KinrelIconData.medal;

  @override
  Widget build(BuildContext context) {
    final tierColor = GamingTierColors.of(tier);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: earned
                ? KinrelGradients.achievementGradient
                : null,
            color: earned ? null : KinrelColors.darkElevated,
            border: Border.all(
              color: earned ? tierColor : tierColor.withValues(alpha: 0.3),
              width: earned ? 2.5 : 1.5,
            ),
            boxShadow: earned
                ? [
                    BoxShadow(
                      color: tierColor.withValues(alpha: 0.35),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: KinrelIcon(
              _badgeIcon,
              size: size * 0.46,
              color: earned ? Colors.white : Colors.white.withValues(alpha: 0.28),
            ),
          ),
        ),
        if (showName) ...[
          const SizedBox(height: 6),
          SizedBox(
            width: size + 18,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 10,
                fontWeight: earned ? FontWeight.w600 : FontWeight.w400,
                color: earned ? KinrelColors.textWhite : KinrelColors.textDim,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Top-3 podium (2nd · 1st · 3rd) for the leaderboard hero.
class GamingPodium extends StatelessWidget {
  const GamingPodium({
    super.key,
    required this.entries,
    required this.myUserId,
    this.onTap,
  });

  final List<dynamic> entries; // LeaderboardEntry (kept dynamic to avoid import cycles)
  final String myUserId;
  final void Function(dynamic entry)? onTap;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final top = entries.take(3).toList();
    final first = top[0];
    final second = top.length > 1 ? top[1] : null;
    final third = top.length > 2 ? top[2] : null;

    Widget slot(dynamic e, double height, Color color, int rank) {
      final name = (e.userName as String?) ?? 'Family';
      final points = (e.points as num?)?.toInt() ?? 0;
      final isMe = (e.userId as String?) == myUserId;
      return GestureDetector(
        onTap: onTap != null ? () => onTap!(e) : null,
        child: Container(
          width: 92,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: KinrelColors.darkCard,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            border: Border.all(
              color: isMe ? KinrelColors.orange : color.withValues(alpha: 0.4),
              width: isMe ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Rank medal — Kinrel custom icon in a tier-colored disc.
              Container(
                width: height > 70 ? 30 : 24,
                height: height > 70 ? 30 : 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.16),
                  border: Border.all(color: color, width: 1.6),
                ),
                child: Center(
                  child: Text(
                    '$rank',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: height > 70 ? 14 : 11,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textWhite,
                ),
              ),
              Text(
                '$points pts',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 10,
                  color: color,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                height: height,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [color.withValues(alpha: 0.45), color.withValues(alpha: 0.12)],
                  ),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 150,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (second != null) slot(second, 52, const Color(0xFFCBD5E1), 2),
          const SizedBox(width: 8),
          slot(first, 78, KinrelColors.brightGold, 1)
              .animate()
              .scale(delay: 150.ms, duration: 400.ms, curve: Curves.easeOutBack),
          const SizedBox(width: 8),
          if (third != null) slot(third, 40, const Color(0xFFD97706), 3),
        ],
      ),
    );
  }
}

/// A single leaderboard row — motivating, non-toxic.
///
/// Privacy contract (matches the backend `fn_get_family_leaderboard_v2`):
///   • Rank, points, matches (games played) — visible to all family members.
///   • Streak — only shown for the viewing user's OWN row. The backend
///     returns 0 for every other row; we additionally gate the chip on
///     [isMe] so a stale local cache cannot leak it.
///   • Wins / losses / win percentage — NEVER rendered. The account owner
///     sees their own full stats on their profile screen; on the leaderboard
///     nobody sees them, including themselves (this surface is shared).
class GamingRankRow extends StatelessWidget {
  const GamingRankRow({
    super.key,
    required this.rank,
    required this.userName,
    required this.points,
    required this.matches,
    @Deprecated('Wins are no longer surfaced on the shared leaderboard. '
        'The field is retained for backward-compatible call sites but is '
        'never rendered. Use [isMe] + the player profile screen for the '
        'owner\'s own win count.')
    this.wins = 0,
    this.streak = 0,
    @Deprecated('winRateLabel is no longer rendered on the shared leaderboard.')
    this.winRateLabel,
    this.isMe = false,
    this.onTap,
    this.pointsLabelOverride,
    this.hideScoreChip = false,
  });

  final int rank;
  final String userName;
  final int points;
  final int matches;
  final int wins; // ignored — kept for backward-compatible call sites
  final int streak;
  final String? winRateLabel; // ignored — kept for backward-compatible call sites
  final bool isMe;
  final VoidCallback? onTap;

  /// Optional override for the right-side points chip label. When non-null,
  /// replaces the numeric `'$points'` rendering — used for the zero-state
  /// "Just joined" string so a member with 0 games never sees a bare `0`
  /// on a shared leaderboard surface. When null, the numeric points value
  /// is rendered as before.
  final String? pointsLabelOverride;

  /// When true, the right-side points chip is NOT rendered at all. Used by
  /// the participation-based leaderboard (v3) where the spec removes the
  /// numeric score chip entirely — the row shows just rank + name +
  /// "Played N games together" text inline.
  final bool hideScoreChip;

  /// Top-3 rank rendering — a Kinrel medal disc with the rank number.
  Widget _rankBadge(int rank) {
    final color = rank == 1
        ? KinrelColors.brightGold
        : rank == 2
            ? const Color(0xFFCBD5E1)
            : const Color(0xFFD97706);
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.16),
        border: Border.all(color: color, width: 1.6),
      ),
      child: Center(
        child: Text(
          '$rank',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ),
    );
  }

  /// Participation-focused subtitle. Never mentions wins/losses/win%.
  /// For the viewer's own row with 0 games, becomes a soft nudge CTA.
  String _participationLine() => participationLineFor(matches: matches, isMe: isMe);

  /// Pure (non-Widget) helper that builds the participation subtitle.
  /// Extracted so unit tests can verify the privacy + reframe contract
  /// without having to spin up the Flutter test runner (which would
  /// require building native assets).
  ///
  /// Contract:
  ///   • Never contains the substrings "win", "loss", "%".
  ///   • For 0-match non-self rows, returns a soft nudge CTA instead of
  ///     any count that could be framed as a loss record.
  ///   • For 0-match self rows, returns an inviting CTA to play tonight.
  static String participationLineFor({required int matches, required bool isMe}) {
    if (matches == 0) {
      return isMe
          ? 'Play your first match tonight'
          : 'New to the Arena — invite them to play';
    }
    if (matches == 1) return 'Played 1 game together';
    return 'Played $matches games together';
  }

  @override
  Widget build(BuildContext context) {
    final highlight = isMe;
    // Streak is only rendered for the viewer's OWN row. The backend already
    // returns 0 for everyone else, but we double-gate on [isMe] so that a
    // stale local cache or future API change can never leak another
    // member's streak on a shared surface.
    final showStreak = isMe && streak >= 2;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: highlight ? KinrelColors.orange.withValues(alpha: 0.1) : KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlight
              ? KinrelColors.orange.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.05),
          width: highlight ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  child: rank <= 3
                      ? _rankBadge(rank)
                      : Text(
                          '#$rank',
                          style: TextStyle(
                            fontFamily: KinrelTypography.monoFont,
                            fontSize: 13,
                            color: KinrelColors.textDim,
                          ),
                        ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              isMe ? '$userName (you)' : userName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: KinrelColors.textWhite,
                              ),
                            ),
                          ),
                          if (showStreak) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: KinrelColors.error.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const KinrelIcon(KinrelIconData.flame,
                                      size: 11, color: KinrelColors.warning),
                                  const SizedBox(width: 3),
                                  Text(
                                    '$streak',
                                    style: TextStyle(
                                      fontFamily: KinrelTypography.monoFont,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: KinrelColors.warning,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _participationLine(),
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 11,
                          color: KinrelColors.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
                // Right-side score chip. Hidden entirely when
                // [hideScoreChip] is true (participation-based leaderboard
                // v3 — the spec removes the numeric score chip and shows
                // "Played N games together" inline instead).
                if (!hideScoreChip)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: rank <= 3
                          ? KinrelGradients.achievementGradient
                          : null,
                      color: rank <= 3 ? null : KinrelColors.darkElevated,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      pointsLabelOverride ?? '$points',
                      style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: pointsLabelOverride != null ? 10 : 13,
                        fontWeight: FontWeight.w700,
                        color: rank <= 3 ? KinrelColors.textDark : KinrelColors.textWhite,
                      ),
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

/// One activity feed tile with its event icon.
class GamingActivityTile extends StatelessWidget {
  const GamingActivityTile({
    super.key,
    required this.icon,
    required this.description,
    required this.timeLabel,
    this.accent,
  });

  final String icon;
  final String description;
  final String timeLabel;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final c = accent ?? KinrelColors.orange;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.withValues(alpha: 0.3)),
            ),            child: Center(
              child: KinrelIcon(
                kinrelIconFromEmoji(icon) ?? KinrelIconData.sparkle,
                size: 19,
                color: c,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    height: 1.35,
                    color: KinrelColors.textSilver,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  timeLabel,
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 10,
                    color: KinrelColors.textDim,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Friendly empty state for gaming sections.
///
/// Icon priority: [kinrelIcon] → [kinrelIconFromEmoji]([emoji]) →
/// sparkle fallback. Emoji strings from server data are never rendered
/// as raw glyphs.
class GamingEmptyCard extends StatelessWidget {
  const GamingEmptyCard({
    super.key,
    required this.emoji,
    required this.title,
    required this.message,
    this.kinrelIcon,
    this.color,
  });

  final String emoji;
  final KinrelIconData? kinrelIcon;
  final String title;
  final String message;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? KinrelColors.textDim;
    final icon =
        kinrelIcon ?? kinrelIconFromEmoji(emoji) ?? KinrelIconData.sparkle;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          KinrelIcon(icon, size: 34, color: c),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              height: 1.4,
              color: KinrelColors.textDim,
            ),
          ),
        ],
      ),
    );
  }
}

/// Formats a relative time label like "2h ago" / "just now".
String gamingTimeAgo(DateTime? time) {
  if (time == null) return '';
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${diff.inDays ~/ 7}w ago';
}
