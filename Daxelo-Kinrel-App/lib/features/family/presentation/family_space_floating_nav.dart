// lib/features/family/presentation/family_space_floating_nav.dart
//
// DAXELO KINREL — Family Space Floating Navigation Dock (Phase 28)
//
// A SEPARATE, self-contained floating bottom navigation bar for the
// Family Space screens ONLY. This does NOT use the global DKBottomNav
// component — it has its own premium styling so there's zero risk of
// affecting the Home page navigation.
//
// Design (matching reference proportions):
//   - Height: 88 px (taller, more substantial)
//   - Side margins: 20 px (doesn't stretch edge-to-edge but stays wide
//     enough for 5 tabs with comfortable spacing)
//   - Bottom margin: 18 px above bottom safe-area inset (raised from
//     bottom edge — floating card effect)
//   - Corner radius: 28 px (premium rounded card)
//   - Internal vertical padding: 14 px (generous breathing room)
//   - Icon size: 27 px (prominent, easy to tap)
//   - Icon → label spacing: 8 px (clear separation)
//   - Label font: 13 px (readable)
//   - Active tab: rounded highlight pill behind icon + label (orange
//     tint background, not just an underline — matches reference)
//   - Blur: 20 sigma (frosted glass)
//   - Shadows: dual-layer for depth
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
/// All styling (height, margins, corners, shadows, blur, icon size,
/// spacing) is defined here and only here. Changing the Home page's
/// nav will NOT affect this widget, and vice versa.
class FamilySpaceFloatingNav extends StatelessWidget {
  const FamilySpaceFloatingNav({
    super.key,
    required this.familyId,
  });

  final String familyId;

  // ── Design constants ──
  // Centralised so they're easy to tune. All values match the reference
  // image proportions analysed via VLM.
  static const _height = 88.0;        // ~12-14% of screen height
  static const _sideMargin = 20.0;     // ~5% of screen width
  static const _bottomMargin = 18.0;  // ~2.5-3% of screen height
  static const _cornerRadius = 24.0;   // ~27% of bar height (premium squircle)
  static const _verticalPadding = 12.0; // generous internal padding
  static const _iconSize = 32.0;       // ~36% of bar height — prominent
  static const _iconLabelGap = 6.0;     // ~7% of bar height — tight, grouped
  static const _labelFontSize = 14.0;  // readable, prominent

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
          // Semi-transparent dark card with frosted glass blur
          color: KinrelColors.darkCard.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(_cornerRadius),
          border: Border.all(
            color: const Color(0xFF3A3A4A),
            width: 0.5,
          ),
          boxShadow: [
            // Primary drop shadow — gives the float effect
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
            // Secondary tight shadow — defines the card edge
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_cornerRadius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
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
/// The active tab gets a rounded highlight pill behind the icon + label
/// (orange-tinted background), not just an underline — matching the
/// reference image's style.
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
      child: SizedBox(
        height: FamilySpaceFloatingNav._height,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: FamilySpaceFloatingNav._verticalPadding,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
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
                ),
              ),
              // ── Active indicator pill (below the label) ──
              // A small rounded capsule in the active color, matching the
              // reference image's underline-style indicator.
              SizedBox(height: isSelected ? 4 : 8),
              Container(
                width: isSelected ? 26 : 0,
                height: isSelected ? 3 : 0,
                decoration: BoxDecoration(
                  color: isSelected
                      ? KinrelColors.orange
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
