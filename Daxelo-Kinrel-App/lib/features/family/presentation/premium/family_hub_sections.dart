// lib/features/family/presentation/premium/family_hub_sections.dart
//
// DAXELO KINREL — Family Hub Sections (Premium Redesign)
//
// The 4 sections of the redesigned family hub, down from 7:
//   1. HeroSection            (hero_section.dart — replaces FeedHeader + GraphPreviewCard)
//   2. TruthStreakMoment      (this file — restyled "moment" card)
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
//   - TruthStreakMoment gets a terracotta gradient + single flame
//     line-icon + Display-type question — the one "moment" that pops.
//   - All section headers use a kolam-dot glyph bullet (no emoji).
//   - Stats + activity rows sit flat on Level 0 with hairline dividers,
//     never bordered boxes. Only Truth Streak + Games get Level 1 cards.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/family/family_provider.dart';
import '../../../games/shared/widgets/active_games_list.dart';
import '../../../games/shared/widgets/family_leaderboard_widget.dart';
import '../../../notifications/providers/notifications_provider.dart';
import '../../../occasions/providers/occasion_reminders_provider.dart';
import '../../../truth_streak/presentation/truth_streak_card.dart';
import '../family_detail_screen.dart' show FamilyDetail, premiumGamesRowBridge, AddPersonSheetBridge;
import 'design_system.dart';

// ═══════════════════════════════════════════════════════════════════════
// SECTION 2: TRUTH STREAK MOMENT
//
// The one place allowed a "moment" — terracotta gradient, single flame
// line-icon, Display-type question. Everything else stays restrained
// so this pops.
// ═══════════════════════════════════════════════════════════════════════

/// Wrapper that applies the premium "moment" treatment to the existing
/// TruthStreakCard. We don't rewrite TruthStreakCard — we wrap it so
/// the provider logic stays untouched and only the visual frame changes.
class TruthStreakMoment extends StatelessWidget {
  const TruthStreakMoment({super.key, required this.familyId});

  final String familyId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FamilyHubSpace.md),
      child: TruthStreakCard(familyId: familyId),
    );
  }
}

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

        // ── Nudges (upcoming occasions + missing info) ────────────
        if (hasNudges) ...[
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: FamilyHubSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Upcoming occasions — flat rows, Level 0, hairline dividers.
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
            ),
          ),
        ],

        // ── Divider between nudges and activity ───────────────────
        if (hasNudges && hasActivity) ...[
          const SizedBox(height: FamilyHubSpace.sm),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: FamilyHubSpace.md),
            child: Divider(
                height: 1,
                thickness: 1,
                color: FamilyHubSurface.hairline(context)),
          ),
          const SizedBox(height: FamilyHubSpace.sm),
        ],

        // ── Activity log ──────────────────────────────────────────
        if (hasActivity) ...[
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: FamilyHubSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recent',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: FamilyHubSurface.iconMuted,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: FamilyHubSpace.xs),
                ...recentActivities.map((activity) => _PulseActivityRow(
                      icon: activity.icon,
                      text: activity.text,
                      timestamp: activity.timestamp,
                    )),
                if (activities.length > 4)
                  Padding(
                    padding: const EdgeInsets.only(top: FamilyHubSpace.xs),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: () => context.push('/family/$familyId/activity'),
                        child: Text(
                          'View all activity',
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: FamilyHubSurface.accent,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
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

// ═══════════════════════════════════════════════════════════════════════
// SECTION 3 (REDESIGN): QUICK-JUMP NAVIGATION ROW
//
// A single horizontal row of 5 icon-and-label chips, scrollable if
// needed. Each chip is a full destination — tapping it navigates to
// that feature's own dedicated screen.
//
// Five chips: Members, Games, Calendar, Memories, Chat.
//
// Visually: chips are muted/neutral by default. Only apply the accent
// color to a chip if it currently has something the user should notice
// (e.g. an unread badge, a pending invite, an active game).
//
// This row replaces having Members, Games, Calendar, Documents, and
// Memory Vault each be their own stacked section on the main screen.
// None of that content is duplicated inline further down the page.
// ═══════════════════════════════════════════════════════════════════════

class QuickJumpNavRow extends ConsumerWidget {
  const QuickJumpNavRow({super.key, required this.familyId});

  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch unread chat count for the badge.
    final unreadCount = ref.watch(unreadCountProvider);

    // ── Compact floating pill dock ──────────────────────────────────
    // Inspired by Instagram's bottom nav: a compact, fully-rounded
    // pill that floats above the content with visible margin on all
    // sides. NOT a full-width bar that touches the screen edges.
    //
    // Key dimensions:
    //   - Horizontal margin: 24px each side (visible gutter)
    //   - Border radius: 28px (pill/capsule, not rounded-rectangle)
    //   - Internal padding: 4px (tight, so icons fill the compact space)
    //   - Icon size: 20px (down from 24 — proportional shrink)
    //   - Label size: 10px (down from 11 — proportional shrink)
    //   - Shadow: stronger, multi-layer for floating elevation
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: FamilyHubSpace.lg),
      child: Container(
        // Pill/capsule shape — significantly more rounded than the
        // 20px used on the Truth Streak card. At 28px the corners
        // read as a soft pill, not a rounded rectangle.
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: KinrelColors.textWhite.withValues(alpha: 0.06),
            width: 1,
          ),
          // Multi-layer shadow for a clear floating elevation effect.
          // Layer 1: tight ambient shadow (close to the element)
          // Layer 2: wider diffuse shadow (spreads the float feel)
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 8,
              spreadRadius: 0,
              offset: const Offset(0, 2),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 20,
              spreadRadius: 0,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        // Tight internal padding so the dock stays compact.
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FamilyHubSpace.xs,
            vertical: FamilyHubSpace.xs + 2,
          ),
          // Evenly distribute the 5 items across the full width
          // using a Row with Expanded children — no dividers.
          child: Row(
            children: [
              Expanded(
                child: _QuickJumpChip(
                  icon: Icons.people_outline,
                  label: 'Members',
                  onTap: () => context.push('/family/$familyId/members'),
                ),
              ),
              Expanded(
                child: _QuickJumpChip(
                  icon: Icons.sports_esports_outlined,
                  label: 'Games',
                  onTap: () => context.push('/games?familyId=$familyId'),
                ),
              ),
              Expanded(
                child: _QuickJumpChip(
                  icon: Icons.calendar_today_outlined,
                  label: 'Calendar',
                  onTap: () => context.push('/family/$familyId/calendar'),
                ),
              ),
              Expanded(
                child: _QuickJumpChip(
                  icon: Icons.photo_library_outlined,
                  label: 'Memories',
                  onTap: () =>
                      context.push('/memories?familyId=$familyId'),
                ),
              ),
              Expanded(
                child: _QuickJumpChip(
                  icon: Icons.chat_bubble_outline,
                  label: 'Chat',
                  badgeCount: unreadCount,
                  isAccent: unreadCount > 0,
                  onTap: () => context.push('/family/$familyId/chat'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickJumpChip extends StatelessWidget {
  const _QuickJumpChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badgeCount = 0,
    this.isAccent = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int badgeCount;
  final bool isAccent;

  @override
  Widget build(BuildContext context) {
    final color = isAccent
        ? FamilyHubSurface.accent
        : FamilyHubSurface.iconMuted;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            vertical: FamilyHubSpace.xs + 1),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon with optional badge — shrunk from 24 to 20px to
            // fit the compact dock proportionally.
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 20, color: color),
                if (badgeCount > 0)
                  Positioned(
                    right: -5,
                    top: -3,
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 12,
                        minHeight: 12,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: FamilyHubSurface.accent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          width: 1.2,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          badgeCount > 9 ? '9+' : '$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 7,
                            fontWeight: FontWeight.w700,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SECTION 5: UTILITY ROW
//
// Small, muted, sits at the very bottom of the scroll. Contains:
// Invite members, Family settings, Leave family.
//
// This should feel clearly secondary — smaller text, no icons competing
// visually with the sections above, essentially the "housekeeping" row
// a user only looks at occasionally. Sits flat on Level 0 with
// hairline dividers between items.
// ═══════════════════════════════════════════════════════════════════════

class UtilityRow extends StatelessWidget {
  const UtilityRow({
    super.key,
    required this.familyId,
    required this.onInvite,
    required this.onSettings,
    required this.onLeave,
  });

  final String familyId;
  final VoidCallback onInvite;
  final VoidCallback onSettings;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: FamilyHubSpace.md),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: FamilyHubSurface.hairline(context),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: _UtilityItem(
                label: 'Invite',
                onTap: onInvite,
              ),
            ),
            Container(
              width: 0.5,
              height: 32,
              color: FamilyHubSurface.hairline(context),
            ),
            Expanded(
              child: _UtilityItem(
                label: 'Settings',
                onTap: onSettings,
              ),
            ),
            Container(
              width: 0.5,
              height: 32,
              color: FamilyHubSurface.hairline(context),
            ),
            Expanded(
              child: _UtilityItem(
                label: 'Leave',
                onTap: onLeave,
                isDestructive: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UtilityItem extends StatelessWidget {
  const _UtilityItem({
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            vertical: FamilyHubSpace.md),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDestructive
                  ? Colors.red.withValues(alpha: 0.7)
                  : FamilyHubSurface.iconMuted,
            ),
          ),
        ),
      ),
    );
  }
}
