// lib/features/games/presentation/widgets/family_streak_hero_card.dart
//
// FamilyStreakHeroCard — Zone 1 of the 3-zone Family Arena home screen.
//
// Replaces the previous duplicate streak banners (the spec called out that
// the prior build rendered BOTH "Streak started — play tonight..." and
// "Your streak from last time is waiting for tonight..." simultaneously).
// This widget guarantees ONE streak card on the home surface, with copy
// logic that branches cleanly on streak value:
//
//   streak == 0 → "Start a family streak tonight — play any game together"
//   streak >= 1 → "🔥 {streak}-day family streak — play tonight to keep it alive"
//
// The Family Cup countdown is folded into the subtext (one line, small),
// e.g. "13d left in The Family Cup · you're #1". Tapping the card opens
// the FamilyStatsDetailSheet (bottom sheet) where the rank / win-streak /
// cup / badges / challenges content that used to live as separate stat
// chips on the home surface now lives one tap away.
//
// The card is Riverpod-consumed: it watches familyPlayStreakProvider +
// gamingDashboardProvider, and passes the merged data down to the detail
// sheet on tap.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../gaming_ecosystem/data/gaming_models.dart';
import '../../../gaming_ecosystem/data/gaming_providers.dart';
import '../../games/shared/icons/kinrel_icons.dart';
import 'family_stats_detail_sheet.dart';

/// Single source of truth for the streak hero card's headline copy.
///
/// Extracted as a static method so widget tests can verify the copy logic
/// (streak == 0 vs streak >= 1) without spinning up the Flutter test
/// runner's widget tree.
///
/// Contract:
///   • streak == 0 → "Start a family streak tonight — play any game together"
///   • streak >= 1 → "🔥 {streak}-day family streak — play tonight to keep it alive"
///   • Never mentions wins, losses, or win%.
String familyStreakHeroHeadline(int streakDays, {bool playedToday = false}) {
  if (streakDays <= 0) {
    return 'Start a family streak tonight — play any game together';
  }
  // The flame emoji is part of the copy per spec — it's a glyph, not a
  // win/loss indicator, so it doesn't violate the no-shame contract.
  return '🔥 $streakDays-day family streak — play tonight to keep it alive';
}

/// Builds the cup countdown subtext shown beneath the headline.
///
/// Returns null when there's no active season (the subtext row is hidden
/// entirely in that case — never rendered as an empty line).
String? familyStreakHeroSubtext({
  required GamingDashboard dashboard,
}) {
  final season = dashboard.season;
  if (season == null) return null;
  final me = dashboard.me;
  final meRank = me.rank > 0 ? '#${me.rank}' : null;
  final mePoints = me.points;
  final parts = <String>[];
  if (season.daysRemaining > 0) {
    parts.add('${season.daysRemaining}d left in ${season.name}');
  } else {
    parts.add('Last day of ${season.name}');
  }
  if (meRank != null && mePoints > 0) {
    parts.add("you're $meRank");
  } else if (mePoints == 0) {
    parts.add('play to earn Cup points');
  }
  return parts.join(' · ');
}

class FamilyStreakHeroCard extends ConsumerWidget {
  const FamilyStreakHeroCard({super.key, required this.familyId});
  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streakAsync = ref.watch(familyPlayStreakProvider(familyId));
    final dashAsync = ref.watch(gamingDashboardProvider(familyId));

    return streakAsync.maybeWhen(
      data: (s) {
        // Even when the streak is 0 / not visible, we still render the hero
        // card — it's the single Zone 1 surface. The cup countdown subtext
        // is shown only when the dashboard has loaded a season.
        final dashboard = dashAsync.asData?.value;
        final headline = familyStreakHeroHeadline(
          s.currentStreakDays,
          playedToday: s.playedToday,
        );
        final subtext = dashboard != null
            ? familyStreakHeroSubtext(dashboard: dashboard)
            : null;

        return GestureDetector(
          onTap: () => _openDetailSheet(context, ref),
          child: _HeroSurface(
            headline: headline,
            subtext: subtext,
            streakDays: s.currentStreakDays,
            playedToday: s.playedToday,
            matchesThisWeek: s.matchesThisWeek,
            bestStreakDays: s.bestStreakDays,
          ),
        )
            .animate()
            .fadeIn(duration: 350.ms)
            .slideY(begin: -0.03, end: 0, duration: 350.ms);
      },
      orElse: () => _HeroSurface(
        headline: familyStreakHeroHeadline(0),
        subtext: null,
        streakDays: 0,
        playedToday: false,
        matchesThisWeek: 0,
        bestStreakDays: 0,
        isLoading: true,
      ),
    );
  }

  void _openDetailSheet(BuildContext context, WidgetRef ref) {
    final dashboard = ref.read(gamingDashboardProvider(familyId)).asData?.value;
    final streak = ref.read(familyPlayStreakProvider(familyId)).asData?.value;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FamilyStatsDetailSheet(
        familyId: familyId,
        dashboard: dashboard,
        streak: streak,
      ),
    );
  }
}

class _HeroSurface extends StatelessWidget {
  const _HeroSurface({
    required this.headline,
    required this.subtext,
    required this.streakDays,
    required this.playedToday,
    required this.matchesThisWeek,
    required this.bestStreakDays,
    this.isLoading = false,
  });

  final String headline;
  final String? subtext;
  final int streakDays;
  final bool playedToday;
  final int matchesThisWeek;
  final int bestStreakDays;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    // Color mood: warm amber when the streak is alive + played today,
    // orange when streak is alive but not yet played today (gentle invite),
    // muted amber when streak is 0 (new-family tone).
    final Color accentColor = streakDays >= 1
        ? (playedToday ? KinrelColors.amber : KinrelColors.orange)
        : KinrelColors.amber.withValues(alpha: 0.7);
    final List<Color> gradientColors = playedToday
        ? const [Color(0xFF2B1A0E), Color(0xFF1D1409)]
        : const [Color(0xFF3B1D0A), Color(0xFF241207)];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accentColor.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.20),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StreakFlame(
                streakDays: streakDays,
                playedToday: playedToday,
                accent: accentColor,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      headline,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: KinrelColors.textWhite,
                        height: 1.25,
                      ),
                    ),
                    if (subtext != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtext!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 11.5,
                          color: KinrelColors.textSilver,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: accentColor.withValues(alpha: 0.8), size: 22),
            ],
          ),
          if (streakDays >= 1 || matchesThisWeek > 0) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (streakDays >= 1)
                  _HeroFactChip(
                    label: 'Streak $streakDays ${streakDays == 1 ? 'day' : 'days'}',
                    accent: accentColor,
                  ),
                if (matchesThisWeek > 0)
                  _HeroFactChip(
                    label: '$matchesThisWeek ${matchesThisWeek == 1 ? 'game' : 'games'} this week',
                    accent: accentColor,
                  ),
                if (bestStreakDays > 0 && bestStreakDays > streakDays)
                  _HeroFactChip(
                    label: 'Best $bestStreakDays days',
                    accent: accentColor.withValues(alpha: 0.85),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StreakFlame extends StatefulWidget {
  const _StreakFlame({
    required this.streakDays,
    required this.playedToday,
    required this.accent,
  });
  final int streakDays;
  final bool playedToday;
  final Color accent;

  @override
  State<_StreakFlame> createState() => _StreakFlameState();
}

class _StreakFlameState extends State<_StreakFlame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breathe;

  @override
  void initState() {
    super.initState();
    _breathe = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    // Only animate when the streak is alive — keeps the card calm for
    // new families (streak == 0).
    if (widget.streakDays >= 1) _breathe.repeat(reverse: true);
  }

  @override
  void dispose() {
    _breathe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool active = widget.streakDays >= 1;
    return ScaleTransition(
      scale: Tween<double>(begin: 0.94, end: 1.06).animate(
        CurvedAnimation(parent: _breathe, curve: Curves.easeInOut),
      ),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(-0.2, -0.3),
            colors: [
              widget.accent.withValues(alpha: active ? 0.55 : 0.30),
              widget.accent.withValues(alpha: active ? 0.12 : 0.06),
            ],
          ),
          border: Border.all(color: widget.accent.withValues(alpha: 0.6)),
        ),
        child: Center(
          child: KinrelIcon(
            KinrelIconData.flame,
            size: 24,
            color: active ? KinrelColors.brightGold : KinrelColors.amber,
          ),
        ),
      ),
    );
  }
}

class _HeroFactChip extends StatelessWidget {
  const _HeroFactChip({required this.label, required this.accent});
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: KinrelTypography.monoFont,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: accent.withValues(alpha: 0.95),
        ),
      ),
    );
  }
}
