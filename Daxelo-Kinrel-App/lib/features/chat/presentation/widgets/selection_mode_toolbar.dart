// lib/features/chat/presentation/widgets/selection_mode_toolbar.dart
//
// DAXELO KINREL — Selection Mode Toolbar + Context Menu
// (Chat UI Reference D14 + D17)
//
// Selection Mode (D14):
//   - Top bar replaces the chat AppBar when active — same 56 dp
//     height and chatBar surface as the D1 header, flat (no border,
//     no shadow)
//   - Left: X (close) + selected count
//   - Right: Reply, Forward, Star, Delete, More actions
//   - Selected rows get a full-bleed chatSelectedRow tint (D16 —
//     handled by ChatMessageList, no ring/checkbox per spec)
//
// Context Menu (D17 card style):
//   - iOS-style popover anchored to the message bubble
//   - Items: Copy, Star, Pin, Message info, Share outside Kinrel
//   - Uses OverlayEntry for precise positioning
//   - chatMenu card, radius 12, 20 dp icons, flat (no shadow)

import 'package:flutter/material.dart';

import '../chat_ui_tokens.dart';

/// Callback signature for bulk actions on a set of selected message ids.
typedef SelectionActionCallback = void Function(Set<String> messageIds);

/// The top toolbar shown when selection mode is active.
///
/// Layout (matching reference image 3):
///   [X]  N selected        [↩] [↪] [★] [🗑] [⋮]
///   close  count           reply fwd star del more
///
/// The toolbar is rendered as a normal AppBar (preferredSize 56) so it
/// can be dropped into the Scaffold's `appBar` slot when selection mode
/// is active. The parent screen toggles selection mode and passes the
/// current selection set + callbacks.
class SelectionModeToolbar extends StatelessWidget
    implements PreferredSizeWidget {
  const SelectionModeToolbar({
    super.key,
    required this.selectedCount,
    required this.onClose,
    required this.onReply,
    required this.onForward,
    required this.onStar,
    required this.onDelete,
    required this.onMore,
  });

  /// Number of currently selected messages.
  final int selectedCount;

  /// Close selection mode (X button).
  final VoidCallback onClose;

  /// Bulk reply — uses the LAST selected message as the reply target
  /// (multi-reply isn't a standard pattern; the toolbar reply opens
  /// reply mode on the most-recently-selected message).
  final VoidCallback onReply;

  /// Bulk forward all selected messages.
  final VoidCallback onForward;

  /// Bulk star all selected messages.
  final VoidCallback onStar;

  /// Bulk delete all selected messages (for-me).
  final VoidCallback onDelete;

  /// Show more actions (bottom sheet with Pin, Copy, Share, etc.).
  final VoidCallback onMore;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final hasSelection = selectedCount > 0;
    // D14: chatBar surface, flat — no bottom border, no shadow.
    return Container(
      color: ChatUi.chatBar,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: ChatUi.headerHeight,
          child: NavigationToolbar(
            leading: IconButton(
              icon: const Icon(
                Icons.close_rounded,
                color: ChatUi.textPrimary,
                size: ChatUi.headerIconSize,
              ),
              onPressed: onClose,
              tooltip: 'Close selection mode',
            ),
            middle: Text(
              selectedCount == 0
                  ? 'Select messages'
                  : '$selectedCount selected',
              style: ChatUi.titleText,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ToolbarIconButton(
                  icon: Icons.reply_rounded,
                  onPressed: hasSelection ? onReply : null,
                  tooltip: 'Reply',
                ),
                _ToolbarIconButton(
                  icon: Icons.shortcut_rounded,
                  onPressed: hasSelection ? onForward : null,
                  tooltip: 'Forward',
                ),
                _ToolbarIconButton(
                  icon: Icons.star_outline_rounded,
                  onPressed: hasSelection ? onStar : null,
                  tooltip: 'Star',
                ),
                _ToolbarIconButton(
                  icon: Icons.delete_outline_rounded,
                  onPressed: hasSelection ? onDelete : null,
                  tooltip: 'Delete',
                ),
                _ToolbarIconButton(
                  icon: Icons.more_vert_rounded,
                  onPressed: hasSelection ? onMore : null,
                  tooltip: 'More',
                ),
                const SizedBox(width: 4),
              ],
            ),
            centerMiddle: true,
          ),
        ),
      ),
    );
  }
}

class _ToolbarIconButton extends StatelessWidget {
  const _ToolbarIconButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return IconButton(
      icon: Icon(
        icon,
        color: enabled ? ChatUi.textPrimary : ChatUi.textMeta,
        size: ChatUi.headerIconSize,
      ),
      onPressed: onPressed,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
    );
  }
}

/// A context menu item definition.
class ContextMenuItem {
  const ContextMenuItem({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isDestructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isDestructive;
}

/// Shows an iOS-style context menu popover anchored to a message bubble.
///
/// The menu appears as a dark rounded rectangle (bg #232336, radius 12)
/// with a drop shadow, positioned above or below the tapped bubble
/// depending on available space. Matches the reference image 3 styling.
///
/// Items shown (per reference image 3):
///   - Copy
///   - Star
///   - Pin
///   - Message info
///   - Share outside Kinrel
///
/// Additional items (Reply, Forward, Delete, React) are still available
/// via the long-press bottom sheet — this popover is the QUICK menu for
/// the most common actions.
class MessageContextMenu {
  MessageContextMenu._();

  static OverlayEntry? _entry;

  /// Shows the context menu anchored to [anchorLink] (a LayerLink
  /// captured from the message bubble's CompositedTransformTarget).
  ///
  /// [items] is the list of actions to show. The menu auto-dismisses
  /// when an item is tapped or the user taps outside.
  static void show({
    required BuildContext context,
    required LayerLink anchorLink,
    required List<ContextMenuItem> items,
    bool showAboveByDefault = true,
  }) {
    // Dismiss any existing menu first.
    dismiss();

    final overlay = Overlay.of(context, rootOverlay: true);
    _entry = OverlayEntry(
      builder: (ctx) => _ContextMenuOverlay(
        anchorLink: anchorLink,
        items: items,
        onDismiss: dismiss,
        preferAbove: showAboveByDefault,
      ),
    );
    overlay.insert(_entry!);
  }

  /// Dismisses the currently shown context menu (if any).
  static void dismiss() {
    _entry?.remove();
    _entry = null;
  }
}

class _ContextMenuOverlay extends StatefulWidget {
  const _ContextMenuOverlay({
    required this.anchorLink,
    required this.items,
    required this.onDismiss,
    required this.preferAbove,
  });

  final LayerLink anchorLink;
  final List<ContextMenuItem> items;
  final VoidCallback onDismiss;
  final bool preferAbove;

  @override
  State<_ContextMenuOverlay> createState() => _ContextMenuOverlayState();
}

class _ContextMenuOverlayState extends State<_ContextMenuOverlay> {
  bool _showAbove = true;

  @override
  void initState() {
    super.initState();
    _showAbove = widget.preferAbove;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => widget.onDismiss(),
      child: Stack(
        children: [
          // The menu itself — anchored to the bubble via CompositedTransformFollower.
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: CompositedTransformFollower(
                link: widget.anchorLink,
                targetAnchor: _showAbove
                    ? Alignment.topLeft
                    : Alignment.bottomLeft,
                followerAnchor: _showAbove
                    ? Alignment.bottomLeft
                    : Alignment.topLeft,
                offset: Offset(0, _showAbove ? -8.0 : 8.0),
                child: IgnorePointer(
                  ignoring: false,
                  child: Material(
                    color: Colors.transparent,
                    child: _MenuCard(
                      items: widget.items,
                      onDismiss: widget.onDismiss,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.items, required this.onDismiss});

  final List<ContextMenuItem> items;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    // D17 card: chatMenu fill, radius 12, 210 dp wide, flat (no
    // shadow), hairline border.
    return Container(
      constraints: const BoxConstraints(minWidth: ChatUi.menuWidth),
      decoration: BoxDecoration(
        color: ChatUi.chatMenu,
        borderRadius: BorderRadius.circular(ChatUi.menuRadius),
        border: Border.all(
          color: ChatUi.chatCardBorder,
          width: ChatUi.cardBorderWidth,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < items.length; i++) ...[
            _MenuItemTile(item: items[i], onDismiss: onDismiss),
            if (i < items.length - 1)
              Divider(height: 1, thickness: 0.5, color: ChatUi.chatCardBorder),
          ],
        ],
      ),
    );
  }
}

class _MenuItemTile extends StatelessWidget {
  const _MenuItemTile({required this.item, required this.onDismiss});

  final ContextMenuItem item;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final color = item.isDestructive ? Colors.red.shade300 : ChatUi.textPrimary;
    return InkWell(
      onTap: () {
        onDismiss();
        item.onTap();
      },
      borderRadius: BorderRadius.circular(ChatUi.menuRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            Icon(item.icon, size: ChatUi.menuIconSize, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.label,
                style: ChatUi.menuText.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A wrapper widget that captures a LayerLink for a message bubble,
/// enabling the context menu to anchor to it.
///
/// Usage in MessageBubble:
///   CompositedTransformTarget(
///     link: contextMenuLink,
///     child: ...bubble content...,
///   )
///
/// Then on long-press, call:
///   MessageContextMenu.show(context: context, anchorLink: link, items: [...])
class BubbleAnchor extends StatefulWidget {
  const BubbleAnchor({super.key, required this.child});

  final Widget child;

  @override
  State<BubbleAnchor> createState() => BubbleAnchorState();
}

class BubbleAnchorState extends State<BubbleAnchor> {
  final LayerLink link = LayerLink();

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(link: link, child: widget.child);
  }
}

/// Selection highlight ring painted around a selected message bubble.
///
/// LEGACY (pre-D16): kept for API compatibility. The unified chat UI
/// marks selection with a full-bleed chatSelectedRow row tint in
/// ChatMessageList (D16) — no ring, no checkbox. This widget renders
/// nothing extra unless explicitly used.
class SelectionRing extends StatelessWidget {
  const SelectionRing({
    super.key,
    required this.isSelected,
    required this.child,
  });

  final bool isSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isSelected) return child;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: ChatUi.accent.withValues(alpha: 0.6),
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(ChatUi.bubbleRadius + 10),
      ),
      child: child,
    );
  }
}

/// A circular checkbox shown overlapping the bubble's leading edge
/// when selection mode is active. Tapping toggles selection.
///
/// LEGACY (pre-D16): the unified chat UI toggles selection by tapping
/// the row itself (no checkbox icon per D16).
class SelectionCheckbox extends StatelessWidget {
  const SelectionCheckbox({
    super.key,
    required this.isSelected,
    required this.onTap,
    required this.isMe,
  });

  final bool isSelected;
  final VoidCallback onTap;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected
              ? ChatUi.accent
              : Colors.black.withValues(alpha: 0.4),
          border: Border.all(
            color: isSelected
                ? ChatUi.accent
                : Colors.white.withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
        child: isSelected
            ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
            : null,
      ),
    );
  }
}
