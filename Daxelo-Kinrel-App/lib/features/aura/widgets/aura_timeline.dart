// lib/features/aura/widgets/aura_timeline.dart
//
// AURA — Timeline Widget (Phase 13).
//
// Scrubable horizontal timeline of historical AURA snapshots. Each
// snapshot is rendered as a small dot; tapping a dot loads that
// snapshot's archetype + symbol parameters into the parent screen so
// the user can see how their family's AURA evolved over time.
//
// Data comes from `GET /aura/:familyId/history` → AuraHistorySnapshot[].
// When the list is empty, the widget renders a friendly empty state.

import 'package:flutter/material.dart';

import '../data/archetype_strings.dart';
import '../data/aura_model.dart';

class AuraTimeline extends StatelessWidget {
  const AuraTimeline({
    super.key,
    required this.snapshots,
    required this.selectedIndex,
    required this.onSelect,
  });

  /// Historical AURA snapshots, ordered oldest → newest.
  final List<AuraHistorySnapshot> snapshots;

  /// Index of the currently-selected snapshot. -1 = none selected
  /// (the parent screen typically selects the last one on load).
  final int selectedIndex;

  /// Called when the user taps a snapshot dot.
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (snapshots.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(Icons.history, size: 32, color: theme.colorScheme.outline),
            const SizedBox(height: 8),
            Text(
              'No AURA history yet',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'As your family grows, snapshots of how the AURA evolved '
              'will appear here.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'AURA Timeline',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        SizedBox(
          height: 110,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            itemCount: snapshots.length,
            itemBuilder: (context, index) {
              final snap = snapshots[index];
              final isSelected = index == selectedIndex;
              return _TimelineDot(
                snapshot: snap,
                isSelected: isSelected,
                onTap: () => onSelect(index),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TimelineDot extends StatelessWidget {
  const _TimelineDot({
    required this.snapshot,
    required this.isSelected,
    required this.onTap,
  });

  final AuraHistorySnapshot snapshot;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Bug 8 fix: history snapshots don't carry the localized definition
    // (it's only on the current-AURA endpoint), so we fall back to the
    // hardcoded English bundle for timeline dots. The name shown is
    // short (e.g. "Banyan" without "The ") so the locale difference is
    // minimal in this compact view.
    final strings = archetypeStrings(snapshot.archetypeKey);
    final color = _parseColor(snapshot.primaryColorHex);

    final date = snapshot.capturedAt.toLocal();
    final dateLabel =
        '${date.day}/${date.month}/${date.year.toString().substring(2)}';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 96,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.18)
              : theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Mini AURA preview — just the rings colour.
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.15),
                border: Border.all(color: color, width: 1.5),
              ),
              child: Center(
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              strings.name.replaceFirst('The ', ''),
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: isSelected ? color : null,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              dateLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 10,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            if (snapshot.archetypeChanged)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.auto_awesome,
                  size: 10,
                  color: color,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Color _parseColor(String hex) {
  var h = hex.trim();
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length == 6) {
    final value = int.tryParse('FF$h', radix: 16);
    if (value != null) return Color(value);
  }
  return const Color(0xFFC8853A);
}
