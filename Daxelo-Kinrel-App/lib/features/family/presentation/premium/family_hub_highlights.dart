// lib/features/family/presentation/premium/family_hub_highlights.dart
//
// DAXELO KINREL — Family Hub Highlights + Quick Actions
//
// Two premium widgets introduced in the top-class UX redesign:
//
//   • HighlightsRow      — Instagram-style horizontal strip of circular
//                          quick-access tiles (Memories, Oral History,
//                          Achievements, Activity). Replaces the
//                          off-palette `_QuickLinksRow` chip strip.
//                          Single-accent (orange) discipline.
//
//   • QuickActionsRow    — WhatsApp/Telegram-style horizontal strip of
//                          3 prominent glassy pill actions: Invite,
//                          Family Chat, Settings. Replaces the flat
//                          muted `UtilityRow`. The destructive "Leave"
//                          action moves into Settings (it never belonged
//                          at top level — destructive actions should
//                          sit behind a confirmation, never one tap from
//                          the home scroll).
//
// Design discipline enforced by these widgets (the audit found all
// three broken in the prior Family Space):
//   1. Single accent color — KinrelColors.orange at varying opacities,
//      not five different hex colors per chip.
//   2. Single icon language — Material outline icons only. No emoji,
//      no Kolam dots, no per-tile colored borders.
//   3. Animation rhythm — both wrap cleanly in the existing
//      `staggerFade(child, index)` helper from family_hub_sections.dart
//      so they enter with the same fade-slide cadence as the rest of
//      the page.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_tokens.dart';
import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/constants/brand_spacing.dart';
import 'design_system.dart';

// ═══════════════════════════════════════════════════════════════════════
// HIGHLIGHTS ROW — Instagram-style circular quick-access tiles
// ═══════════════════════════════════════════════════════════════════════

/// A horizontally-scrolling row of circular quick-access tiles, modeled
/// on Instagram's "Highlights" bar. Each tile is 64×64 with a single-
/// accent orange ring and a 13px label below. This replaces the prior
/// `_QuickLinksRow` chip strip that used 5 different off-palette colors
/// (`0xFFF4511E`, `0xFF00897B`, `0xFFD81B60`, `0xFFC8853A`, `0xFF8E24AA`)
/// none of which were in the Kinrel palette.
///
/// The "Lists & Errands" tile (formerly `_SharedListTile`) is folded in
/// here as a 5th highlight, removing the redundant separate section it
/// used to occupy. "Pulse" is omitted because the Family Pulse section
/// already lives directly on the page (and "Activity" links to it).
class HighlightsRow extends StatelessWidget {
  const HighlightsRow({super.key, required this.familyId});

  final String familyId;

  static const _tiles = [
    // Phase 1 (ux/family-space-refinement): Graph + Map merged into
    // the shortcut row. They were previously flanking the identity
    // circle in the HeroSection at 12% opacity (nearly invisible).
    // Now they're first-class labeled tiles with the same icon +
    // label treatment as the other 5. Order: Graph, Map first
    // (core family-relationship features), then the content
    // shortcuts. Row is horizontally scrollable if 7 items don't
    // fit — see ListView.separated below.
    _HighlightTile(icon: Icons.account_tree_outlined, label: 'Graph'),
    _HighlightTile(icon: Icons.map_outlined,          label: 'Map'),
    _HighlightTile(icon: Icons.photo_library_outlined, label: 'Memories'),
    _HighlightTile(icon: Icons.mic_none_outlined,      label: 'Oral History'),
    _HighlightTile(icon: Icons.emoji_events_outlined,  label: 'Achievements'),
    _HighlightTile(icon: Icons.checklist_rounded,      label: 'Lists'),
    _HighlightTile(icon: Icons.history_rounded,        label: 'Activity'),
  ];

  String _routeFor(String label) {
    switch (label) {
      case 'Graph':        return '/family/$familyId/graph';
      case 'Map':         return '/family/$familyId/map';
      case 'Memories':    return '/memory-vault?familyId=$familyId';
      case 'Oral History': return '/oral-history?familyId=$familyId';
      case 'Achievements': return '/achievements';
      case 'Lists':       return '/family/$familyId/lists';
      case 'Activity':    return '/memories?familyId=$familyId';
      default:            return '/home';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96, // 64 circle + 8 gap + 16 label + 8 breathing room
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
        itemCount: _tiles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 18),
        itemBuilder: (context, i) {
          final tile = _tiles[i];
          return _HighlightCircle(
            icon: tile.icon,
            label: tile.label,
            onTap: () => context.push(_routeFor(tile.label)),
          )
              .animate()
              .fadeIn(delay: (60 * i).ms, duration: 280.ms)
              .slideY(begin: 0.05, end: 0, delay: (60 * i).ms, duration: 280.ms);
        },
      ),
    );
  }
}

class _HighlightTile {
  const _HighlightTile({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

class _HighlightCircle extends StatelessWidget {
  const _HighlightCircle({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 64×64 circular tile. Single-accent orange ring (not a
            // per-tile colored border) — consistent with the rest of
            // the Family Space palette discipline.
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KinrelColors.darkCard,
                border: Border.all(
                  color: KinrelColors.orange.withValues(alpha: 0.30),
                  width: 1.2,
                ),
              ),
              child: Icon(
                icon,
                size: 26,
                color: KinrelColors.orange,
              ),
            ),
            const SizedBox(height: 8),
            // 13px label, single line, center-aligned.
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: KinrelColors.textSilver,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// QUICK ACTIONS ROW — WhatsApp/Telegram-style prominent pill actions
// ═══════════════════════════════════════════════════════════════════════
//
// DEPRECATED in the duplicate-Family-Chat-removal pass. This 3-pill
// row (Invite / Family Chat / Settings) was the prior middle action
// row. Per the new IA brief:
//   • Family Chat is removed entirely from this row — its only entry
//     point on the space-detail screen is now the persistent bottom
//     nav item.
//   • Settings is moved to the AppBar as a low-emphasis icon-only
//     button (consistent with the other AppBar action icons).
//   • Invite is promoted to a standalone full-width prominent button
//     (see InviteButton below) — the one visually-bold element in
//     this section, per the "spend your boldness in one place"
//     principle from the design-system pass.
//
// The class is kept here (not deleted) so any external references
// continue to compile, but it is no longer instantiated by the
// space-detail screen. Safe to delete once all references are
// confirmed gone.

/// A horizontally-distributed row of 3 prominent glassy pill actions,
/// modeled on WhatsApp's chat header action row (call / video / menu)
/// and Telegram's chat action row (search / mute / more). Each pill is
/// a 44px-tall glassy surface with an icon + label, distributed evenly
/// across the row.
///
/// **Deprecated** — see the file-level comment above. The
/// space-detail screen now uses [InviteButton] (standalone) +
/// AppBar-resident Settings icon instead.
@Deprecated('Use InviteButton (standalone) + AppBar Settings icon instead. '
    'Family Chat is no longer in the middle action row — it lives only in '
    'the persistent bottom nav.')
class QuickActionsRow extends StatelessWidget {
  const QuickActionsRow({
    super.key,
    required this.familyId,
    required this.onInvite,
    required this.onSettings,
    required this.onFamilyChat,
  });

  final String familyId;
  final VoidCallback onInvite;
  final VoidCallback onSettings;
  final VoidCallback onFamilyChat;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: Row(
        children: [
          Expanded(
            child: _QuickActionPill(
              icon: Icons.person_add_outlined,
              label: 'Invite',
              onTap: onInvite,
              // Invite is the only one that uses the solid accent
              // fill — it's the action we most want to surface (the
              // app's value scales with family size).
              emphasized: true,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _QuickActionPill(
              icon: Icons.chat_bubble_outline_rounded,
              label: 'Family Chat',
              onTap: onFamilyChat,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _QuickActionPill(
              icon: Icons.settings_outlined,
              label: 'Settings',
              onTap: onSettings,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// INVITE BUTTON — standalone prominent full-width action
// ═══════════════════════════════════════════════════════════════════════
//
// Replaces QuickActionsRow on the space-detail screen. Invite is the
// one visually-bold element in the middle section — full-width, warm
// orange→amber gradient, white text + icon, soft accent glow shadow.
// Per the design-system pass "spend your boldness in one place"
// principle, this is the ONLY prominent CTA on the screen above the
// primary content feed.
//
// Family Chat was removed from this row — its only entry point on
// this screen is the persistent bottom nav item. Settings was moved
// to the AppBar as a low-emphasis icon-only button.

/// A standalone full-width prominent "Invite" button for the
/// space-detail screen.
///
/// Visual: 48px tall, full width (minus screen horizontal padding),
/// warm orange→amber gradient background, white text + icon, soft
/// accent glow shadow. The icon is `Icons.person_add_outlined` (the
/// AppIcon.invite semantic from the design-tokens pass), the label
/// is "Invite family member" (specific action language per the
/// Phase 4 copy audit — not generic "Invite").
///
/// This is the ONLY prominent CTA on the space-detail screen above
/// the primary content feed. Per the design-system pass "spend your
/// boldness in one place" principle, no other element in this
/// section competes for visual weight.
class InviteButton extends StatelessWidget {
  const InviteButton({
    super.key,
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: double.infinity,
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
          decoration: BoxDecoration(
            // Warm orange→amber gradient — the brandGradient from
            // AppColor. Inline here so the widget stays self-contained
            // without importing KinrelGradients just for one usage.
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFE8612A), Color(0xFFF59240)],
            ),
            borderRadius: BorderRadius.circular(AppRadius.cardStandard),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColor.orange.withValues(alpha: 0.28),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.person_add_outlined,
                size: 20,
                color: Colors.white,
              ),
              const SizedBox(width: AppSpacing.xs),
              // Specific action language per the Phase 4 copy audit:
              // "Invite family member" — not generic "Invite". The
              // vocabulary matches the action the user is about to
              // take (opening the add-member options sheet).
              Text(
                'Invite family member',
                style: AppType.title.copyWith(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionPill extends StatelessWidget {
  const _QuickActionPill({
    required this.icon,
    required this.label,
    required this.onTap,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  /// When true, the pill uses the accent gradient fill (orange →
  /// amber) with white text — the "primary" CTA of the row. When
  /// false, the pill uses a glassy dark-card surface with silver
  /// text. Only one pill per row should be `emphasized: true`.
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final isEmph = emphasized;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          // Emphasized = warm orange→amber gradient (KinrelGradients.
          // igniteGradient is 0xFFE8612A → 0xFFF59240 at 135°). The
          // inline gradient keeps this widget self-contained without
          // importing KinrelGradients just for one usage.
          gradient: isEmph
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFE8612A), Color(0xFFF59240)],
                )
              : null,
          color: isEmph ? null : KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isEmph
                ? Colors.white.withValues(alpha: 0.18)
                : KinrelColors.orange.withValues(alpha: 0.18),
            width: 1,
          ),
          boxShadow: isEmph
              ? [
                  BoxShadow(
                    color: KinrelColors.orange.withValues(alpha: 0.28),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 17,
              color: isEmph ? Colors.white : KinrelColors.textSilver,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isEmph ? Colors.white : KinrelColors.textSilver,
                  height: 1.0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// RECENT MOMENTS SECTION — unified recent activity (replaces the two
// back-to-back "Recent" sections that were previously stacked on the
// Family Space: FamilyPulseSection's internal "Recent" label + the
// standalone `_CrossFeatureMomentsCard` with its own "Recent Moments"
// header). This widget is the canonical "Recent Moments" entry on
// the Family Space; FamilyPulseSection still owns nudges + relationship
// activity, but cross-feature moments (oral history / memory vault /
// quiz) render here so the two sections aren't visually competing.
// ═══════════════════════════════════════════════════════════════════════

/// A flat list of cross-feature moments (oral history clips, memory
/// vault items, quiz results) rendered as first-class pulse items.
/// Uses the Family Hub palette (`FamilyHubSurface.level1` /
/// `KinrelColors.darkCard`), not Material 3's
/// `theme.colorScheme.surfaceContainerHighest` — fixing the palette
/// discipline violation in the prior `_CrossFeatureMomentsCard`.
///
/// Collapses to `SizedBox.shrink()` when there are no moments, so the
/// section gracefully disappears for fresh families.
///
/// The header uses a single Material icon (`Icons.history_rounded`)
/// instead of the prior `✨` emoji — enforcing single-icon-language
/// discipline across the page.
class RecentMomentsSection extends StatelessWidget {
  const RecentMomentsSection({
    super.key,
    required this.moments,
    this.onViewAll,
  });

  /// Already-fetched moments. The widget does not own fetching — the
  /// parent (FamilyDetailScreen) reads `crossFeatureMomentsProvider`
  /// and passes the result in, keeping this widget a pure render
  /// function (and testable in isolation).
  final List<CrossFeatureMomentLike> moments;

  /// Optional "View all" tap. When non-null, a "View all" affordance
  /// appears at the bottom-right of the header row.
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    if (moments.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.base, vertical: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        // Family Hub palette — NOT theme.colorScheme.surfaceContainerHighest.
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: FamilyHubSurface.hairline(context),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row — single Material icon + label + (optional)
          // "View all". No emoji.
          Row(
            children: [
              const Icon(
                Icons.history_rounded,
                size: 16,
                color: KinrelColors.orange,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: const Text(
                  'Recent Moments',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
              if (onViewAll != null)
                GestureDetector(
                  onTap: onViewAll,
                  behavior: HitTestBehavior.opaque,
                  child: const Text(
                    'View all',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.orange,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Moments list — flat, hairline-divided rows. Each row is
          // a single Material icon (replacing the prior per-moment
          // emoji) + title + optional subtitle + time-ago.
          ...moments.map((m) => _MomentRow(moment: m)),
        ],
      ),
    );
  }
}

class _MomentRow extends StatelessWidget {
  const _MomentRow({required this.moment});
  final CrossFeatureMomentLike moment;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Single Material icon for every moment type, with a soft
          // orange-tinted circle behind it for visual consistency
          // with the Highlights row above.
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KinrelColors.orange.withValues(alpha: 0.10),
            ),
            child: Icon(
              moment.icon,
              size: 14,
              color: KinrelColors.orange,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  moment.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: KinrelColors.textWhite,
                    height: 1.3,
                  ),
                ),
                if (moment.subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    moment.subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 11,
                      color: KinrelColors.textDim,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _timeAgo(moment.createdAt),
            style: const TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 10,
              color: KinrelColors.textDim,
            ),
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dt.day}/${dt.month}';
  }
}

/// Lightweight shape used by `RecentMomentsSection`. The Family
/// Space's actual moments come from `crossFeatureMomentsProvider`
/// which returns `List<CrossFeatureMoment>` — we map each one to
/// this shape at the call site so this widget doesn't import the
/// provider (and stays a pure render function).
class CrossFeatureMomentLike {
  const CrossFeatureMomentLike({
    required this.title,
    required this.icon,
    this.subtitle,
    required this.createdAt,
  });

  final String title;
  final IconData icon;
  final String? subtitle;
  final DateTime createdAt;
}
