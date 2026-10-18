// lib/features/chat/presentation/widgets/chat_inbox_filter_bar.dart
//
// DAXELO KINREL — Unified Inbox Filter Chip Bar
//
// A horizontally scrollable row of 4 chips: All, Unread (with count),
// Groups, Direct. The selected chip uses the orange theme token
// (filled background, white text); others use the neutral outlined
// style. Each chip is at least 48 dp tall (tap target).
//
// State: the selected filter is held in `unifiedInboxFilterProvider`
// (a StateProvider.autoDispose — survives across rebuilds, not
// persisted across app restarts per spec).
//
// Theme: KinrelColors / KinrelTypography / KinrelRadius — no
// hardcoded colors. The accent color is KinrelColors.ember (orange)
// matching the rest of the chat UI.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../l10n/app_localizations.dart';
import '../../providers/unified_inbox_provider.dart';

/// A single filter chip in the unified inbox.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.trailingCount,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? trailingCount;

  @override
  Widget build(BuildContext context) {
    // Selected: orange filled background + white text.
    // Unselected: transparent background + 0.5 silver border + white text.
    final bg = selected
        ? KinrelColors.ember
        : Colors.transparent;
    final border = Border.all(
      color: selected
          ? KinrelColors.ember
          : KinrelColors.textSilver.withValues(alpha: 0.3),
      width: selected ? 1.5 : 1,
    );
    final textColor = selected
        ? KinrelColors.textWhite
        : KinrelColors.textSilver;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(KinrelRadius.lg),
      child: Container(
        // Minimum 48dp tap target (Material accessibility guideline).
        constraints: const BoxConstraints(
          minHeight: 48,
          minWidth: 56,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.sm + 4,
          vertical: KinrelSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
          border: border,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: textColor,
              ),
            ),
            if (trailingCount != null && trailingCount! > 0) ...[
              const SizedBox(width: KinrelSpacing.xs),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 1,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? KinrelColors.textWhite.withValues(alpha: 0.25)
                      : KinrelColors.ember.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(KinrelRadius.xs),
                ),
                child: Text(
                  '${trailingCount!}',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? KinrelColors.textWhite
                        : KinrelColors.ember,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The full filter chip bar (horizontally scrollable).
class ChatInboxFilterBar extends ConsumerWidget {
  const ChatInboxFilterBar({
    super.key,
    required this.unreadCount,
  });

  /// The total unread count to show in the "Unread" chip's badge.
  /// Computed by the parent (chat_inbox_screen) from the filtered list
  /// so the badge reflects the user's actual unread total across all
  /// chats (groups + directs).
  final int unreadCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = S.of(context)!;
    final currentFilter = ref.watch(unifiedInboxFilterProvider);

    return SizedBox(
      height: 56, // chip + padding for the horizontal scrollbar
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.base,
          vertical: 4,
        ),
        children: [
          _FilterChip(
            label: l10n.chatInboxFilterAll,
            selected: currentFilter == UnifiedInboxFilter.all,
            onTap: () => ref
                .read(unifiedInboxFilterProvider.notifier)
                .state = UnifiedInboxFilter.all,
          ),
          const SizedBox(width: KinrelSpacing.sm),
          _FilterChip(
            label: l10n.chatInboxFilterUnread,
            selected: currentFilter == UnifiedInboxFilter.unread,
            trailingCount: unreadCount,
            onTap: () => ref
                .read(unifiedInboxFilterProvider.notifier)
                .state = UnifiedInboxFilter.unread,
          ),
          const SizedBox(width: KinrelSpacing.sm),
          _FilterChip(
            label: l10n.chatInboxFilterGroups,
            selected: currentFilter == UnifiedInboxFilter.groups,
            onTap: () => ref
                .read(unifiedInboxFilterProvider.notifier)
                .state = UnifiedInboxFilter.groups,
          ),
          const SizedBox(width: KinrelSpacing.sm),
          _FilterChip(
            label: l10n.chatInboxFilterDirect,
            selected: currentFilter == UnifiedInboxFilter.direct,
            onTap: () => ref
                .read(unifiedInboxFilterProvider.notifier)
                .state = UnifiedInboxFilter.direct,
          ),
        ],
      ),
    );
  }
}
