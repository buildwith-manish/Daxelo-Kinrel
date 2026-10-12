// lib/features/chat/presentation/widgets/chat_header_bar.dart
//
// DAXELO KINREL — Shared Chat Header Bar + overflow menu (Chat UI
// Reference D1 + D17).
//
// ONE header for both chat types:
//   • Group chat (D1): title (family/group name), subtitle
//     "N members · N online", orange letter avatar, phone + more_vert
//     actions.
//   • Direct chat (D1 direct variant): the other person's name, the
//     relationship to the viewer as the subtitle ("Father · online"),
//     chatReceived avatar with the initial in the relationship color.
//
// The header is exactly 56 logical pixels tall, chatBar background,
// avatar 34 dp circle, header icons 22 dp. Flat style: no shadows, no
// gradients, no blur.
//
// showChatOverflowMenu (D17) renders the 210 dp wide chatMenu card
// used by BOTH the header more_vert button and the selection-mode
// "more" button — one menu, one style.

import 'package:flutter/material.dart';

import '../../../../core/constants/brand_typography.dart';
import '../chat_ui_tokens.dart';

/// D1 — the shared chat header bar (group + direct).
class ChatHeaderBar extends StatelessWidget implements PreferredSizeWidget {
  const ChatHeaderBar({
    super.key,
    required this.title,
    required this.subtitle,
    required this.avatarInitial,
    this.isDirect = false,
    this.initialColor,
    this.onBack,
    this.onAvatarTap,
    this.onPhoneTap,
    this.onMoreTap,
  });

  /// Display name — family/group name or the other person's name.
  final String title;

  /// Line under the title — "N members · N online" (group) or
  /// "Father · online" (direct).
  final String subtitle;

  /// Text the avatar initial is taken from (first character).
  final String avatarInitial;

  /// Direct-chat variant — avatar fill becomes chatReceived and the
  /// initial uses [initialColor] (the relationship color).
  final bool isDirect;

  /// Relationship color for the direct-chat avatar initial.
  final Color? initialColor;

  final VoidCallback? onBack;
  final VoidCallback? onAvatarTap;
  final VoidCallback? onPhoneTap;
  final VoidCallback? onMoreTap;

  @override
  Size get preferredSize => const Size.fromHeight(ChatUi.headerHeight);

  String get _initial {
    final t = avatarInitial.trim();
    if (t.isEmpty) return 'F';
    return t.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Material(
        color: ChatUi.chatBar,
        child: SizedBox(
          height: ChatUi.headerHeight,
          child: Row(
            children: [
              // Back — 48 dp tap target, 22 dp icon.
              _HeaderIconButton(
                icon: Icons.arrow_back,
                tooltip: 'Back',
                onTap: onBack,
              ),
              // Avatar — 34 dp circle. Group: solid accent fill with a
              // textPrimary initial. Direct: chatReceived fill with the
              // initial in the relationship color.
              Semantics(
                label: 'Open profile',
                button: onAvatarTap != null,
                child: GestureDetector(
                  onTap: onAvatarTap,
                  child: Container(
                    width: ChatUi.avatarSize,
                    height: ChatUi.avatarSize,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDirect ? ChatUi.chatReceived : ChatUi.accent,
                    ),
                    child: Text(
                      _initial,
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: isDirect
                            ? (initialColor ?? ChatUi.textPrimary)
                            : ChatUi.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Title + subtitle.
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ChatUi.titleText.copyWith(fontSize: 16),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ChatUi.subtitleText,
                    ),
                  ],
                ),
              ),
              // Phone — both headers keep the voice-call action.
              _HeaderIconButton(
                icon: Icons.phone_outlined,
                tooltip: 'Voice call',
                onTap: onPhoneTap,
              ),
              // more_vert — opens the D17 overflow menu.
              _HeaderIconButton(
                icon: Icons.more_vert,
                tooltip: 'Chat options',
                onTap: onMoreTap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tooltip,
      button: true,
      child: SizedBox(
        width: ChatUi.tapTarget,
        height: ChatUi.headerHeight,
        child: IconButton(
          icon: Icon(icon, size: ChatUi.headerIconSize),
          color: ChatUi.textPrimary,
          tooltip: tooltip,
          onPressed: onTap,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// D17 — shared overflow menu card
// ═══════════════════════════════════════════════════════════════════════

/// One row of the D17 overflow menu.
class ChatOverflowMenuItem {
  const ChatOverflowMenuItem({
    required this.label,
    required this.icon,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
}

/// Opens the D17 overflow menu anchored to the top-right of the
/// screen: a 210 dp wide card, radius 12, chatMenu background, rows of
/// [ChatOverflowMenuItem] (20 dp icon + label). Dismissed by tapping
/// the scrim or selecting an item.
Future<void> showChatOverflowMenu(
  BuildContext context, {
  required List<ChatOverflowMenuItem> items,
}) {
  return Navigator.of(
    context,
    rootNavigator: true,
  ).push(_OverflowMenuRoute(items: items));
}

class _OverflowMenuRoute extends PopupRoute<void> {
  _OverflowMenuRoute({required this.items});

  final List<ChatOverflowMenuItem> items;

  @override
  Color? get barrierColor => Colors.black54;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss menu';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 140);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 100);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return Semantics(
      label: 'Chat options menu',
      child: GestureDetector(
        // Tap the scrim anywhere outside the card to dismiss.
        onTapDown: (_) => Navigator.of(context).maybePop(),
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            // Align the card to the header's more_vert button
            // (top-right, 8 dp inset).
            Positioned(
              top: ChatUi.headerHeight + 8,
              right: 8,
              child: ScaleTransition(
                scale: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                ),
                alignment: Alignment.topRight,
                child: Material(
                  color: ChatUi.chatMenu,
                  borderRadius: BorderRadius.circular(ChatUi.menuRadius),
                  clipBehavior: Clip.antiAlias,
                  child: SizedBox(
                    width: ChatUi.menuWidth,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < items.length; i++)
                          _OverflowMenuRow(
                            item: items[i],
                            showDivider: i != 0,
                            onDismiss: () => Navigator.of(context).maybePop(),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(opacity: animation, child: child);
  }

  @override
  bool get opaque => false;
}

class _OverflowMenuRow extends StatelessWidget {
  const _OverflowMenuRow({
    required this.item,
    required this.showDivider,
    required this.onDismiss,
  });

  final ChatOverflowMenuItem item;
  final bool showDivider;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showDivider)
          Container(
            height: 0.5,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            color: ChatUi.chatCardBorder,
          ),
        Semantics(
          label: item.label,
          button: true,
          child: InkWell(
            onTap: item.onTap == null
                ? null
                : () {
                    onDismiss();
                    // Run after the pop so sheets pushed by the action
                    // land above the menu route.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      item.onTap?.call();
                    });
                  },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  Icon(
                    item.icon,
                    size: ChatUi.menuIconSize,
                    color: ChatUi.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ChatUi.menuText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
