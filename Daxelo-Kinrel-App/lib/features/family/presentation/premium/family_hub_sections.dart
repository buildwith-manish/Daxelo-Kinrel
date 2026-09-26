// lib/features/family/presentation/premium/family_hub_sections.dart
//
// DAXELO KINREL — Family Hub Sections (Premium Redesign)
//
// The 4 sections of the redesigned family hub, down from 7:
//   1. HeroSection            (hero_section.dart — replaces FeedHeader + GraphPreviewCard)
//   2. PredictionBattleMoment (this file — wraps the v1 prediction card)
//   3. GamesSection           (this file — Games row + Play/Leaderboard toggle)
//   4. FamilyPulseSection     (this file — merges Activity + Calendar)
//
// IA cuts:
//   - "Family Graph" card killed entirely → folded into hero caption.
//   - "Family Leaderboard" killed as a separate section → nested as a
//     toggle inside Games ("Play" / "Leaderboard").
//   - "Recent Activity" + "Family Calendar" merged → "Family Pulse"
//     (nudges first, activity log below, one header).
//
// Visual identity:
//   - PredictionBattleMoment keeps a warm terracotta gradient frame, but
//     the inner card now comes from the v1 backend-scheduled prediction
//     system. The wrapper just supplies the horizontal padding so the
//     card's own margins remain consistent with the rest of the hub.
//   - All section headers use a kolam-dot glyph bullet (no emoji).
//   - Stats + activity rows sit flat on Level 0 with hairline dividers,
//     never bordered boxes. Only Prediction Battle + Games get Level 1
//     cards.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/family/family_provider.dart';
import '../../../shared_list/presentation/shared_list_screen.dart';
import '../../../games/shared/widgets/active_games_list.dart';
import '../../../games/shared/widgets/family_leaderboard_widget.dart';
import '../../../occasions/providers/occasion_reminders_provider.dart';
import '../family_detail_screen.dart' show premiumGamesRowBridge, AddPersonSheetBridge;
import 'design_system.dart';

// ═══════════════════════════════════════════════════════════════════════
// SECTION 2: PREDICTION BATTLE MOMENT (v1 — scheduled numeric estimation)
//
// The one place allowed a "moment" — purple/gold gradient, sparkle icon.
// Everything else stays restrained so this pops.
//
// Phase 3 cleanup: the `TruthStreakMoment` and `PredictionBattleMoment`
// wrapper classes that used to live here were removed when Truth Streak
// was fully deprecated. The family detail screen (`family_detail_screen.dart`)
// now renders `PredictionBattleV1Card` directly — no wrapper needed.
// ═══════════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════
// SECTION 3: GAMES (with Play / Leaderboard toggle)
//
// Nests the leaderboard inside Games as a toggle tab, not parallel
// real estate. An empty leaderboard no longer costs its own scroll-
// screen-worth of space — it shows collapsed/muted until the first
// completed game.
// ═══════════════════════════════════════════════════════════════════════

class GamesSection extends ConsumerStatefulWidget {
  const GamesSection({super.key, required this.familyId});

  final String familyId;

  @override
  ConsumerState<GamesSection> createState() => _GamesSectionState();
}

class _GamesSectionState extends ConsumerState<GamesSection> {
  _GamesTab _tab = _GamesTab.play;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header with kolam-dot glyph + Play/Leaderboard toggle.
        KolamSectionHeader(
          glyph: KolamGlyph.quadrant,
          title: 'Games',
          trailing: _GamesTabToggle(
            current: _tab,
            onChanged: (t) => setState(() => _tab = t),
          ),
        ),

        // Tab content
        if (_tab == _GamesTab.play) ...[
          // Active games list (flat rows, Level 0, hairline dividers).
          // Reuses the existing ActiveGamesList widget.
          ActiveGamesList(familyId: widget.familyId),

          // Games row (horizontal scroll of game tiles).
          // Reuses the existing _GamesRow via the FamilyDetailScreen's
          // private class. We access it through a public wrapper below.
          const SizedBox(height: FamilyHubSpace.sm),
          _PremiumGamesRow(familyId: widget.familyId),
        ] else ...[
          // Leaderboard tab — nested inside Games, not a separate section.
          // Shows collapsed/muted empty state until first game completed.
          _LeaderboardNested(familyId: widget.familyId),
        ],
      ],
    );
  }
}

enum _GamesTab { play, leaderboard }

class _GamesTabToggle extends StatelessWidget {
  const _GamesTabToggle({
    required this.current,
    required this.onChanged,
  });

  final _GamesTab current;
  final ValueChanged<_GamesTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: KinrelColors.textWhite.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggleChip('Play', _GamesTab.play),
          _toggleChip('Leaders', _GamesTab.leaderboard),
        ],
      ),
    );
  }

  Widget _toggleChip(String label, _GamesTab tab) {
    final isActive = current == tab;
    return GestureDetector(
      onTap: () => onChanged(tab),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isActive ? FamilyHubSurface.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isActive ? Colors.white : FamilyHubSurface.iconMuted,
          ),
        ),
      ),
    );
  }
}

/// Leaderboard nested inside the Games section. Shows a collapsed/muted
/// placeholder until the first game is completed — "Leaderboard unlocks
/// after your first completed game" rather than an empty podium.
class _LeaderboardNested extends StatelessWidget {
  const _LeaderboardNested({required this.familyId});

  final String familyId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FamilyHubSpace.md),
      child: FamilyLeaderboardWidget(
        familyId: familyId,
        maxRows: 5,
        // The widget already handles the empty state with a muted icon +
        // "No games completed yet" message — that's our collapsed/muted
        // placeholder. No empty podium.
      ),
    );
  }
}

/// Public wrapper for the private _GamesRow from family_detail_screen.
/// Delegates to the existing horizontal games row so we don't duplicate
/// the 16-game list.
class _PremiumGamesRow extends StatelessWidget {
  const _PremiumGamesRow({required this.familyId});

  final String familyId;

  @override
  Widget build(BuildContext context) {
    // Access the private _GamesRow via a public bridge exported from
    // family_detail_screen.dart. The bridge is defined at the bottom
    // of family_detail_screen.dart as `premiumGamesRowBridge`.
    return premiumGamesRowBridge(familyId);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SECTION 4: FAMILY PULSE
//
// Merges Recent Activity + Family Calendar into one section. Both are
// "here's what needs attention" — one "Family Pulse" section handles
// both: nudges (missing info, upcoming occasions) first, activity log
// below, one header.
// ═══════════════════════════════════════════════════════════════════════

class FamilyPulseSection extends ConsumerWidget {
  const FamilyPulseSection({
    super.key,
    required this.detail,
    required this.familyId,
  });

  final FamilyDetail detail;
  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final occasions = ref.watch(familyOccasionsProvider(familyId));
    final upcoming = occasions.take(3).toList();
    final missingDob = detail.members
        .where((p) =>
            p.deletedAt == null &&
            (p.dateOfBirth == null || p.dateOfBirth!.isEmpty))
        .toList();

    // Build activity items from relationships + members.
    final activities = <_PulseActivity>[];
    for (final rel in detail.relationships) {
      final fromPerson =
          detail.members.where((p) => p.id == rel.fromPersonId).firstOrNull;
      final toPerson =
          detail.members.where((p) => p.id == rel.toPersonId).firstOrNull;
      activities.add(_PulseActivity(
        icon: Icons.link_outlined,
        text:
            '${fromPerson?.name ?? "Someone"} added ${toPerson?.name ?? "a family member"} as ${rel.relationshipKey.replaceAll("_", " ")}',
        timestamp: rel.createdAt,
      ));
    }
    for (final member in detail.members) {
      activities.add(_PulseActivity(
        icon: Icons.person_add_outlined,
        text: '${member.name} joined the family',
        timestamp: member.createdAt,
      ));
    }
    activities.sort((a, b) {
      if (a.timestamp == null && b.timestamp == null) return 0;
      if (a.timestamp == null) return 1;
      if (b.timestamp == null) return -1;
      return b.timestamp!.compareTo(a.timestamp!);
    });
    final recentActivities = activities.take(4).toList();

    final hasNudges = upcoming.isNotEmpty || missingDob.isNotEmpty;
    final hasActivity = recentActivities.isNotEmpty;

    if (!hasNudges && !hasActivity) {
      // Nothing to show — collapse the whole section.
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KolamSectionHeader(
          glyph: KolamGlyph.spiral,
          title: 'Family Pulse',
        ),

        // Phase 3.30: Polished card container for nudges + activity.
        // Wraps both sections in a single card with consistent
        // spacing instead of loose rows.
        Container(
          margin: const EdgeInsets.symmetric(horizontal: FamilyHubSpace.md),
          decoration: BoxDecoration(
            color: FamilyHubSurface.level1,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: FamilyHubSurface.hairline(context),
              width: 0.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Nudges (upcoming occasions + missing info) ────────────
              if (hasNudges) ...[
                ...upcoming.map((occasion) => _PulseNudgeRow(
                      icon: occasion.type.toString().contains('birthday')
                          ? Icons.cake_outlined
                          : Icons.favorite_outline,
                      title: occasion.name,
                      subtitle: occasion.type.toString().contains('birthday')
                          ? 'Birthday'
                          : 'Anniversary',
                      trailing: occasion.daysUntil == 0
                          ? 'Today'
                          : occasion.daysUntil == 1
                              ? 'Tomorrow'
                              : '${occasion.daysUntil}d',
                      isUrgent: occasion.daysUntil <= 7,
                      onTap: () =>
                          context.push('/family/$familyId/calendar'),
                    )),

                // Missing info nudges — muted, collapsed.
                ...missingDob.take(3).map((person) => _PulseNudgeRow(
                      icon: Icons.info_outline,
                      title: 'Add ${person.name}\'s birthday',
                      subtitle: 'Missing info',
                      trailing: null,
                      isUrgent: false,
                      isMuted: true,
                      onTap: () => AddPersonSheetBridge.show(
                        context,
                        familyId: familyId,
                        person: person,
                      ),
                    )),
              ],

              // ── Divider between nudges and activity ───────────────────
              if (hasNudges && hasActivity) ...[
                Divider(
                    height: 1,
                    thickness: 0.5,
                    color: FamilyHubSurface.hairline(context)),
              ],

              // ── Activity log ──────────────────────────────────────────
              if (hasActivity) ...[
                Padding(
                  padding: const EdgeInsets.only(
                      left: FamilyHubSpace.sm, top: FamilyHubSpace.sm),
                  child: Text(
                    'Recent',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: FamilyHubSurface.iconMuted,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                ...recentActivities.map((activity) => _PulseActivityRow(
                      icon: activity.icon,
                      text: activity.text,
                      timestamp: activity.timestamp,
                    )),
                if (activities.length > 4)
                  Padding(
                    padding: const EdgeInsets.only(
                        left: FamilyHubSpace.sm,
                        right: FamilyHubSpace.sm,
                        bottom: FamilyHubSpace.sm,
                        top: 4),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: () => context.push('/family/$familyId/activity'),
                        child: Text(
                          'View all',
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: FamilyHubSurface.accent,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Pulse row primitives (flat, Level 0, hairline dividers) ──────────

class _PulseNudgeRow extends StatelessWidget {
  const _PulseNudgeRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.isUrgent,
    this.isMuted = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? trailing;
  final bool isUrgent;
  final bool isMuted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: FamilyHubSpace.sm, vertical: FamilyHubSpace.sm + 2),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: FamilyHubSurface.hairline(context),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: isUrgent
                  ? FamilyHubSurface.accent
                  : (isMuted
                      ? FamilyHubSurface.iconMuted
                      : FamilyHubSurface.iconMuted),
            ),
            const SizedBox(width: FamilyHubSpace.sm + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isMuted
                          ? FamilyHubSurface.iconMuted
                          : KinrelColors.textWhite,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 11,
                      color: FamilyHubSurface.iconMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isUrgent
                      ? FamilyHubSurface.accent.withValues(alpha: 0.15)
                      : KinrelColors.textWhite.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  trailing!,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isUrgent
                        ? FamilyHubSurface.accent
                        : FamilyHubSurface.iconMuted,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PulseActivityRow extends StatelessWidget {
  const _PulseActivityRow({
    required this.icon,
    required this.text,
    required this.timestamp,
  });

  final IconData icon;
  final String text;
  final DateTime? timestamp;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: FamilyHubSpace.sm, vertical: FamilyHubSpace.sm + 2),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: FamilyHubSurface.hairline(context),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: FamilyHubSurface.iconMuted),
          const SizedBox(width: FamilyHubSpace.sm + 2),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: KinrelColors.textSilver,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseActivity {
  const _PulseActivity({
    required this.icon,
    required this.text,
    required this.timestamp,
  });

  final IconData icon;
  final String text;
  final DateTime? timestamp;
}

// ═══════════════════════════════════════════════════════════════════════
// STAGGER-FADE ENTRY ANIMATION HELPER
//
// Wrap each section in this to get a 100–150ms stagger-fade as it
// scrolls into view. flutter_animate is already in pubspec — cheap
// to add and reads as intentional craft.
// ═══════════════════════════════════════════════════════════════════════

Widget staggerFade(Widget child, int index) {
  return child
      .animate()
      .fadeIn(
        duration: 400.ms,
        delay: (index * 100).ms,
        curve: Curves.easeOut,
      )
      .slideY(
        begin: 0.05,
        end: 0,
        duration: 400.ms,
        delay: (index * 100).ms,
        curve: Curves.easeOut,
      );
}

