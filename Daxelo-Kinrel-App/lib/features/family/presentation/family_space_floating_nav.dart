// lib/features/family/presentation/family_space_floating_nav.dart
//
// DAXELO KINREL — Family Space Floating Navigation Dock (Phase 27)
//
// A SEPARATE, self-contained floating bottom navigation bar for the
// Family Space screens ONLY. This does NOT use the global DKBottomNav
// component — it has its own premium styling so there's zero risk of
// affecting the Home page navigation.
//
// Design (Instagram-style floating dock):
//   - Height: 92 px (taller for better touch interaction)
//   - Side margins: 48 px (narrower — doesn't stretch edge-to-edge)
//   - Float gap: 22 px above bottom safe-area inset (raised from bottom)
//   - Corner radius: 28 px (premium, pill-like capsule shape)
//   - Internal horizontal padding: 10 px (icons have breathing room)
//   - Internal vertical padding: 16 px (generous spacing)
//   - Icon size: 26 px (larger, easier to tap)
//   - Icon → label spacing: 7 px
//   - Label font: 12 px
//   - Active indicator: 22×3 px pill (orange/gold)
//   - Blur: 18 sigma (frosted glass)
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
        left: 48,   // narrower — doesn't stretch edge-to-edge
        right: 48,
        // Raised higher from the bottom edge
        bottom: bottomInset > 0 ? bottomInset + 22 : 22,
      ),
      child: Container(
        height: 92, // taller for better usability
        decoration: BoxDecoration(
          // Semi-transparent dark card with frosted glass blur
          color: KinrelColors.darkCard.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(28), // premium pill-like shape
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
            // Secondary tight shadow — defines the capsule edge
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
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
    final color = isSelected ? KinrelColors.orange : KinrelColors.textSilver;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 92, // match the dock height — full-area tap target
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isSelected ? tab.activeIcon : tab.icon,
                color: color,
                size: 26, // larger, easier to tap
              ),
              const SizedBox(height: 7), // generous spacing
              Text(
                tab.label,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: color,
                  height: 1.2,
                ),
              ),
              if (isSelected) ...[
                const SizedBox(height: 5),
                Container(
                  width: 22, // wider indicator pill
                  height: 3, // chunkier indicator
                  decoration: BoxDecoration(
                    color: KinrelColors.orange,
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
