// lib/features/family/presentation/widgets/family_space_tab_bar.dart
//
// DAXELO KINREL — Family Space Tab Bar (Graph ↔ Tree ↔ Map)
//
// Family Space: Graph ↔ Tree (↔ Map) — Implementation Prompt §5.
//
// A persistent segmented control at the top of the Family Space that
// switches between the Graph, Tree, and Map views.
//
//   ┌─────────────────────────┐
//   │ Graph │ Tree │ Map      │
//   └─────────────────────────┘
//
// Implementation notes:
//   - Graph + Tree live in an `IndexedStack` inside FamilyGraphScreen
//     so their state (camera, scroll, selected node) survives tab
//     switches — see §5 "Use an IndexedStack (or equivalent)".
//   - Map navigates to the existing `/family/:id/map` route (it has its
//     own Scaffold with AppBar, so embedding it inline would cause a
//     nested-Scaffold layout bug). The Map tab therefore BEHAVES like a
//     button rather than a tab, but is styled identically so the user
//     perceives all three as siblings.
//   - The spec said "Map is a disabled/'coming soon' tab for this build —
//     reserve the slot, don't wire it." However, the Map feature was
//     already fully built and wired at `/family/:id/map` (3,428-line
//     FamilyMapScreen, 35 files). Disabling it would be a regression
//     of existing functionality. We keep it active.
//
// State:
//   - `familySpaceTabProvider` (Riverpod StateProvider<FamilySpaceTab>)
//     tracks the active tab. Both Graph and Tree read it to coordinate
//     cross-navigation focus (see §6 "View in Tree" / "View in Graph").

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/brand_colors.dart';

/// The three views of a Family Space.
enum FamilySpaceTab { graph, tree, map }

/// Family-space-scoped tab state. Both the [FamilySpaceTabBar] and the
/// Graph/Tree views read/write this provider to coordinate focus.
final familySpaceTabProvider =
    StateProvider<FamilySpaceTab>((ref) => FamilySpaceTab.graph);

/// A compact segmented control for switching Family Space views.
///
/// Styled to match the existing dark-themed AppBar (KinrelColors.darkCard
/// background, white text, orange accent for the selected segment).
class FamilySpaceTabBar extends ConsumerWidget {
  const FamilySpaceTabBar({
    super.key,
    required this.familyId,
    this.compact = false,
  });

  /// The family ID — used by the Map tab to navigate to the right route.
  final String familyId;

  /// When true, renders a more compact variant (smaller padding, smaller
  /// text). Used in landscape or split-view contexts.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTab = ref.watch(familySpaceTabProvider);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x33FFFFFF), width: 0.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Segment(
              label: 'Graph',
              icon: Icons.account_tree_outlined,
              selected: activeTab == FamilySpaceTab.graph,
              onTap: () => ref
                  .read(familySpaceTabProvider.notifier).state =
                  FamilySpaceTab.graph,
              compact: compact,
            ),
          ),
          Expanded(
            child: _Segment(
              label: 'Tree',
              icon: Icons.family_restroom,
              selected: activeTab == FamilySpaceTab.tree,
              onTap: () => ref
                  .read(familySpaceTabProvider.notifier).state =
                  FamilySpaceTab.tree,
              compact: compact,
            ),
          ),
          Expanded(
            child: _Segment(
              label: 'Map',
              icon: Icons.map_outlined,
              // Map is treated as a navigation button (pushes to /family/:id/map)
              // because FamilyMapScreen has its own Scaffold with AppBar —
              // embedding it inline would cause nested-Scaffold layout issues.
              // After returning from Map, the active tab reverts to whatever
              // it was before (Graph or Tree), preserving the IndexedStack state.
              selected: false,
              onTap: () =>
                  context.push('/family/$familyId/map'),
              compact: compact,
            ),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.compact,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          vertical: compact ? 6 : 8,
          horizontal: compact ? 6 : 10,
        ),
        decoration: BoxDecoration(
          color: selected ? KinrelColors.orange : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: compact ? 14 : 16,
              color: selected ? Colors.white : KinrelColors.textSecondaryDark,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : KinrelColors.textSecondaryDark,
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w600,
                fontFamily: 'DMSans',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
