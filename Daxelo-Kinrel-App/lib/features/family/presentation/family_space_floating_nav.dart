// lib/features/family/presentation/family_space_floating_nav.dart
//
// DAXELO KINREL — Family Space Floating Navigation Dock (Phase 30)
//
// A SEPARATE, self-contained floating bottom navigation bar for the
// Family Space screens ONLY. This does NOT use the global DKBottomNav
// component — it has its own premium styling so there's zero risk of
// affecting the Home page navigation.
//
// Design (matching reference image — tall, premium floating card):
//   - Height: 96 px (tall — no longer a "thin strip")
//   - Side margins: 28 px (narrower than full-width — floats as a card)
//   - Bottom margin: 24 px above bottom safe-area inset (clearly floating)
//   - Corner radius: 32 px (premium rounded card)
//   - Internal vertical padding: 12 px top / 10 px bottom (generous
//     breathing room WITHOUT crushing the content — content area ~74 px)
//   - Icon size: 28 px (prominent — ~29% of bar height)
//   - Icon → label spacing: 6 px (clear separation)
//   - Label font: 13 px (readable, prominent, semibold when active)
//   - Active indicator: 32 × 4 px orange pill, 6 px below the label
//   - Active tab: orange icon + label + pill indicator + subtle
//     orange-tinted rounded background (stronger highlight than color alone)
//   - Blur: 25 sigma (strong frosted glass — pops off the dark bg)
//   - Shadows: triple-layer (deep float + tight edge + orange glow on active)
//
// CRITICAL FIX (vs. previous attempts):
//   The previous version forced a redundant `SizedBox(height: 96)` INSIDE
//   each tab button and THEN added 16 px vertical padding — leaving only
//   ~64 px for the actual icon+label+indicator content. That made the bar
//   VISUALLY feel thin even though the outer container was 96 px. This
//   version lets each tab fill the parent height via the Row/Column layout
//   (no inner SizedBox), so the full 96 px is used and the content has
//   real visual mass.
//
// Tabs (all family-scoped):
//   0. Members   → /family/<id>/members
//   1. Games     → /games?familyId=<id>
//   2. Calendar  → /family/<id>/calendar
//   3. Lists     → /family/<id>/lists
//   4. Chat      → /family/<id>/chat
//

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/utils/accessibility_utils.dart';

/// A single navigation item for [FamilySpaceFloatingNav].
class _NavTab {
  const _NavTab({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// Floating bottom navigation dock for Family Space screens.
///
/// This is a SELF-CONTAINED widget — it does NOT use [DKBottomNav].
/// All styling is defined here and only here.
class FamilySpaceFloatingNav extends StatelessWidget {
  const FamilySpaceFloatingNav({
    super.key,
    required this.familyId,
  });

  final String familyId;

  // ── Design constants ──
  // Centralised so they're easy to tune.
  static const _height = 96.0;
  static const _sideMargin = 28.0;
  static const _bottomMargin = 24.0;
  static const _cornerRadius = 32.0;
  static const _topPadding = 12.0;
  static const _bottomPadding = 10.0;
  static const _iconSize = 28.0;
  static const _iconLabelGap = 6.0;
  static const _labelFontSize = 13.0;
  static const _indicatorWidth = 32.0;
  static const _indicatorHeight = 4.0;
  static const _indicatorLabelGap = 6.0;
  static const _tabHorizontalPadding = 6.0;
  static const _activeTabRadius = 18.0;

  static const _tabs = [
    _NavTab(
      icon: Icons.people_outline_rounded,
      activeIcon: Icons.people_rounded,
      label: 'Members',
    ),
    _NavTab(
      icon: Icons.sports_esports_outlined,
      activeIcon: Icons.sports_esports_rounded,
      label: 'Games',
    ),
    _NavTab(
      icon: Icons.calendar_today_outlined,
      activeIcon: Icons.calendar_month_rounded,
      label: 'Calendar',
    ),
    _NavTab(
      icon: Icons.checklist_rounded,
      activeIcon: Icons.checklist_rounded,
      label: 'Lists',
    ),
    _NavTab(
      icon: Icons.chat_bubble_outline_rounded,
      activeIcon: Icons.chat_rounded,
      label: 'Chat',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex = _currentIndex(location);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: _sideMargin,
        right: _sideMargin,
        bottom: bottomInset > 0 ? bottomInset + _bottomMargin : _bottomMargin,
      ),
      child: Container(
        height: _height,
        decoration: BoxDecoration(
          color: KinrelColors.darkCard.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(_cornerRadius),
          border: Border.all(
            color: const Color(0xFF3A3A4A),
            width: 0.5,
          ),
          boxShadow: [
            // Primary drop shadow — deep float effect
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.50),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
            // Secondary tight shadow — defines the card edge
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
            // Subtle orange glow — gives the bar a premium warmth and
            // makes the active state feel intentional.
            if (currentIndex >= 0)
              BoxShadow(
                color: KinrelColors.orange.withValues(alpha: 0.18),
                blurRadius: 24,
                offset: const Offset(0, 6),
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_cornerRadius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
            child: Padding(
              padding: const EdgeInsets.only(
                top: _topPadding,
                bottom: _bottomPadding,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: List.generate(_tabs.length, (index) {
                  final tab = _tabs[index];
                  final isSelected = index == currentIndex;
                  return Expanded(
                    child: semanticTab(
                      label: tab.label,
                      index: index,
                      isSelected: isSelected,
                      totalTabs: _tabs.length,
                      child: _NavTabButton(
                        tab: tab,
                        isSelected: isSelected,
                        onTap: () => _onTap(context, index),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }

  int _currentIndex(String location) {
    if (location.contains('/members')) return 0;
    if (location.contains('/games') ||
        location.contains('/ghost-painter') ||
        location.contains('/sos/') ||
        location.contains('/antakshari/') ||
        location.contains('/bingo/') ||
        location.contains('/checkers/') ||
        location.contains('/ludo/') ||
        location.contains('/carrom/') ||
        location.contains('/chess/') ||
        location.contains('/freeze-dash/')) {
      return 1;
    }
    if (location.contains('/calendar')) return 2;
    if (location.contains('/lists') || location.contains('/shared-list')) return 3;
    if (location.contains('/chat')) return 4;
    return 0;
  }

  void _onTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/family/$familyId/members');
      case 1:
        context.go('/games?familyId=$familyId');
      case 2:
        context.go('/family/$familyId/calendar');
      case 3:
        context.go('/family/$familyId/lists');
      case 4:
        context.go('/family/$familyId/chat');
    }
  }
}

/// A single tappable tab button inside the floating dock.
///
/// The active tab gets:
///   - Orange icon + label color
///   - A 32 × 4 px pill indicator beneath the label
///   - A subtle orange-tinted rounded background behind the entire tab
///     (this is the "stronger highlight" the user asked for — it makes
///     the active tab clearly stand out from the inactive ones, matching
///     the reference image's visual hierarchy)
///
/// NOTE: This button does NOT set its own height — it fills the height
/// of its parent (the dock's Row, which is constrained to [_height] by
/// the outer Container). The previous version forced a redundant
/// `SizedBox(height: _height)` here AND added 16 px vertical padding,
/// which crushed the content into ~64 px and made the bar look thin.
class _NavTabButton extends StatelessWidget {
  const _NavTabButton({
    required this.tab,
    required this.isSelected,
    required this.onTap,
  });

  final _NavTab tab;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final activeColor = KinrelColors.orange;
    final inactiveColor = KinrelColors.textSilver;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: FamilySpaceFloatingNav._tabHorizontalPadding,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: isSelected
                ? KinrelColors.orange.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius:
                BorderRadius.circular(FamilySpaceFloatingNav._activeTabRadius),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Icon ──
              Icon(
                isSelected ? tab.activeIcon : tab.icon,
                color: isSelected ? activeColor : inactiveColor,
                size: FamilySpaceFloatingNav._iconSize,
              ),
              SizedBox(height: FamilySpaceFloatingNav._iconLabelGap),
              // ── Label ──
              Text(
                tab.label,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: FamilySpaceFloatingNav._labelFontSize,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? activeColor : inactiveColor,
                  height: 1.2,
                  letterSpacing: 0.1,
                ),
              ),
              // ── Active indicator pill (below the label) ──
              SizedBox(height: FamilySpaceFloatingNav._indicatorLabelGap),
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                width: isSelected
                    ? FamilySpaceFloatingNav._indicatorWidth
                    : FamilySpaceFloatingNav._indicatorWidth,
                height: FamilySpaceFloatingNav._indicatorHeight,
                decoration: BoxDecoration(
                  color: isSelected
                      ? KinrelColors.orange
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(
                      FamilySpaceFloatingNav._indicatorHeight / 2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
