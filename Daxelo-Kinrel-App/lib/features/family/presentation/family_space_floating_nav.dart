// lib/features/family/presentation/family_space_floating_nav.dart
//
// DAXELO KINREL — Family Space Floating Navigation Dock (Phase 31)
//
// A SEPARATE, self-contained floating bottom navigation bar for the
// Family Space screens ONLY. This does NOT use the global DKBottomNav
// component — it has its own premium styling so there's zero risk of
// affecting the Home page navigation.
//
// Design (restyled to match the Home screen's DKBottomNav proportions —
// see lib/shared/widgets/dk_components.dart → DKBottomNav / _DKNavItemWidget).
// The OUTER dock (side margins, bottom margin, corner radius, border,
// shadow, blur) is unchanged from Phase 30; only the INTERNAL tab
// sizing/spacing/active-state styling now mirrors DKBottomNav:
//   - Height: 80 px (matches DKBottomNav)
//   - Side margins: 28 px (unchanged — Family Space floats slightly
//     narrower than Home's 12 px to feel more card-like)
//   - Bottom margin: 24 px above bottom safe-area inset (unchanged)
//   - Corner radius: 32 px (unchanged)
//   - No internal top/bottom padding — content is centered vertically
//     via a Column with MainAxisAlignment.center inside a SizedBox of
//     height 80, exactly like _DKNavItemWidget.
//   - Icon size: 24 px (matches DKBottomNav)
//   - Icon → label spacing: 4 px (matches DKBottomNav)
//   - Label font: 11 px (matches DKBottomNav)
//   - Active indicator: 18 × 2.5 px orange pill, 3 px below the label
//     (matches DKBottomNav exactly)
//   - Active tab: orange icon + orange bold label + indicator pill ONLY.
//     NO rounded background box behind the active tab (removed in Phase 31
//     to match DKBottomNav, which has no active-tab background tint).
//   - Indicator pill renders ONLY when isSelected (not always-present-
//     transparent), matching _DKNavItemWidget's `if (isSelected) ...[...]`.
//   - Blur: 25 sigma (unchanged — Family Space keeps stronger frosted glass)
//   - Shadows: triple-layer (unchanged — deep float + tight edge + orange glow)
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
  //
  // Internal sizing values mirror DKBottomNav (Home screen nav) so the
  // two bars feel visually consistent. The outer dock values (side margin,
  // bottom margin, corner radius, blur, shadows) are NOT shared with
  // DKBottomNav — Family Space keeps its own slightly-more-premium float.
  static const _height = 80.0;
  static const _sideMargin = 28.0;
  static const _bottomMargin = 24.0;
  static const _cornerRadius = 32.0;
  static const _iconSize = 24.0;
  static const _iconLabelGap = 4.0;
  static const _labelFontSize = 11.0;
  static const _indicatorWidth = 18.0;
  static const _indicatorHeight = 2.5;
  static const _indicatorLabelGap = 3.0;

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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
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
    );
  }

  int _currentIndex(String location) {
    // Family Overview screen (route: /family/<id> with no suffix) is NOT
    // one of the 5 tabs — it's the landing screen that shows the hero,
    // Truth Streak, and Pulse sections. Return -1 so NO tab is
    // highlighted. This is safe: the widget already guards the active-
    // state rendering with `if (currentIndex >= 0)` for the orange glow
    // BoxShadow, and `_NavTabButton` computes `isSelected = index ==
    // currentIndex` (which is `index == -1` → false for all 5 tabs), so
    // no indicator pill renders either.
    if (location == '/family/$familyId') return -1;
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
        // v115: Chat tab now opens the Chat LIST screen (which shows
        // group chat + DMs) instead of the group chat directly.
        // The group chat conversation is opened by tapping the Family
        // Group Chat row inside the list.
        context.go('/family/$familyId/chats');
    }
  }
}

/// A single tappable tab button inside the floating dock.
///
/// Mirrors the structure of DKBottomNav's `_DKNavItemWidget` (see
/// lib/shared/widgets/dk_components.dart) so the Family Space tabs feel
/// visually identical to the Home tabs.
///
/// The active tab shows ONLY:
///   - Orange icon color
///   - Orange bold label
///   - A small 18 × 2.5 px orange indicator pill beneath the label
///
/// There is NO rounded background box behind the active tab (the Phase 30
/// orange-tinted `AnimatedContainer` background has been removed to match
/// DKBottomNav, which relies purely on color + indicator pill).
///
/// The indicator pill renders ONLY when `isSelected` — it is not a
/// always-present-transparent placeholder (matches `_DKNavItemWidget`'s
/// `if (isSelected) ...[...]` pattern).
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
    final color = isSelected ? activeColor : inactiveColor;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        // Match the parent container height so the tap target fills the bar,
        // exactly like _DKNavItemWidget does.
        height: FamilySpaceFloatingNav._height,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ── Icon ──
            Icon(
              isSelected ? tab.activeIcon : tab.icon,
              color: color,
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
                color: color,
                height: 1.2,
                letterSpacing: 0.1,
              ),
            ),
            // ── Active indicator pill (below the label) ──
            // Renders ONLY when selected — no transparent placeholder when
            // inactive. Mirrors _DKNavItemWidget's `if (isSelected) ...[...]`.
            if (isSelected) ...[
              SizedBox(height: FamilySpaceFloatingNav._indicatorLabelGap),
              Container(
                width: FamilySpaceFloatingNav._indicatorWidth,
                height: FamilySpaceFloatingNav._indicatorHeight,
                decoration: BoxDecoration(
                  color: KinrelColors.orange,
                  borderRadius: BorderRadius.circular(
                      FamilySpaceFloatingNav._indicatorHeight / 2),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
