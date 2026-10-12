// lib/features/chat/presentation/widgets/chat_header_bar.dart
//
// DAXELO KINREL — Chat Header Bar (Chat UI Reference D1)
//
// ONE shared header for group chat and direct chat:
//   • Height 56, background chatBar, horizontal padding 12, items in a
//     row with 10 gap.
//   • Back arrow 22 icon in a 48×48 target.
//   • Avatar circle 34: group avatar fills orange with the initial in
//     white (weight 500); direct avatar fills chatReceived with the
//     initial in the relationship color.
//   • Title display 16 / 500 textPrimary, one line, ellipsis.
//   • Subtitle 12 textSubtitle: group = "N members · M online";
//     direct = relationship · online status.
//   • Actions: phone and more_vert, 22 icons in 48×48 targets,
//     textPrimary.
//   • No Family chip. No bottom border or shadow.
//
// The screen keeps owning the data (member counts, relationship label,
// online status) and passes plain values in.

import 'package:flutter/material.dart';

import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/constants/brand_typography.dart';
import '../chat_ui_tokens.dart';

/// D1 shared chat header.
class ChatHeaderBar extends StatelessWidget implements PreferredSizeWidget {
  const ChatHeaderBar({
    super.key,
    required this.title,
    required this.subtitle,
    required this.avatarInitial,
    required this.onBack,
    this.onAvatarTap,
    this.isDirect = false,
    this.avatarFillColor,
    this.initialColor,
    this.onPhoneTap,
    this.onMoreTap,
  });

  /// Chat title (group name or the other person's name).
  final String title;

  /// Subtitle line (group: "5 members · 2 online"; direct:
  /// "Father · online").
  final String subtitle;

  /// The avatar's letter (group initial or person initial).
  final String avatarInitial;

  /// Back navigation callback.
  final VoidCallback onBack;

  /// Optional: avatar tap (group → family profile; direct → member
  /// profile sheet).
  final VoidCallback? onAvatarTap;

  /// True for direct chat (avatar fill chatReceived, initial colored
  /// with the relationship color); false for group (orange fill, white
  /// initial).
  final bool isDirect;

  /// Overrides the avatar fill color (defaults per [isDirect]).
  final Color? avatarFillColor;

  /// Overrides the initial color (defaults per [isDirect]).
  final Color? initialColor;

  /// Phone action (both headers).
  final VoidCallback? onPhoneTap;

  /// More (⋮) action — opens the D17 overflow menu.
  final VoidCallback? onMoreTap;

  @override
  Size get preferredSize => const Size.fromHeight(ChatUi.barHeight);

  @override
  Widget build(BuildContext context) {
    final fill = avatarFillColor ??
        (isDirect ? ChatUi.chatReceived : ChatUi.accent);
    final letterColor = initialColor ??
        (isDirect ? ChatUi.textSecondary : Colors.white);

    return Container(
      color: ChatUi.chatBar,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: ChatUi.barHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                // ── Back arrow — 22 icon in a 48×48 target ────────────
                _HeaderIconButton(
                  icon: Icons.arrow_back,
                  size: ChatUi.iconHeaderBack,
                  color: ChatUi.textPrimary,
                  semanticsLabel: 'Back',
                  onTap: onBack,
                ),
                const SizedBox(width: 10),
                // ── Avatar circle 34 ──────────────────────────────────
                GestureDetector(
                  onTap: onAvatarTap,
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: 34,
                    height: 34,
                    child: CircleAvatar(
                      backgroundColor: fill,
                      child: Text(
                        avatarInitial.isNotEmpty
                            ? avatarInitial.substring(0, 1).toUpperCase()
                            : '?',
                        style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: letterColor,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // ── Title + subtitle ───────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ChatUi.headerTitle,
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ChatUi.headerSubtitle,
                      ),
                    ],
                  ),
                ),
                // ── Actions: phone + more_vert ─────────────────────────
                _HeaderIconButton(
                  icon: Icons.phone_outlined,
                  size: ChatUi.iconHeaderPhone,
                  color: ChatUi.textPrimary,
                  semanticsLabel: 'Call',
                  onTap: onPhoneTap,
                ),
                _HeaderIconButton(
                  icon: Icons.more_vert,
                  size: ChatUi.iconHeaderMore,
                  color: ChatUi.textPrimary,
                  semanticsLabel: 'More options',
                  onTap: onMoreTap,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A 48×48 tap-target icon button with a smaller centered glyph.
class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.size,
    required this.color,
    required this.semanticsLabel,
    this.onTap,
  });

  final IconData icon;
  final double size;
  final Color color;
  final String semanticsLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      button: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: ChatUi.tapTarget,
          height: ChatUi.tapTarget,
          child: Center(
            child: Icon(icon, size: size, color: color),
          ),
        ),
      ),
    );
  }
}

/// D17 overflow menu — a 210 dp wide card, radius 12, background
/// chatMenu, border chatMenuBorder 0.5, vertical padding 4, anchored
/// 10 dp from the right edge and 54 dp below the header top. Items are
/// 44 dp tall (48 dp tap targets), horizontal padding 14, row with 12
/// gap: icon 20 in textSecondary, then the label 14 textPrimary.
/// No dividers, no shadow.
Future<void> showChatOverflowMenu(
  BuildContext context, {
  required List<ChatOverflowMenuItem> items,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) {
      final mq = MediaQuery.of(ctx);
      return GestureDetector(
        // Tap anywhere dismisses.
        behavior: HitTestBehavior.opaque,
        onTap: () => entry.remove(),
        child: Stack(
          children: [
            Positioned(
              // D17: anchored 10 dp from the right edge and 54 dp
              // below the top (of the header bar, which starts below
              // the status-bar padding).
              top: mq.padding.top + 54,
              right: 10,
              child: Material(
                color: Colors.transparent,
                child: ChatOverflowMenuCard(
                  items: items,
                  onItemTap: (item) {
                    entry.remove();
                    item.onTap();
                  },
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
  overlay.insert(entry);
  return Future<void>.value();
}

/// One D17 overflow-menu item definition.
class ChatOverflowMenuItem {
  const ChatOverflowMenuItem({
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

/// The D17 menu card itself — public so the UI gallery can embed it
/// with fixed sample items (the overlay wrapper above is what real
/// screens use).
class ChatOverflowMenuCard extends StatelessWidget {
  const ChatOverflowMenuCard({
    super.key,
    required this.items,
    required this.onItemTap,
  });

  final List<ChatOverflowMenuItem> items;
  final ValueChanged<ChatOverflowMenuItem> onItemTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: ChatUi.menuWidth,
      constraints: const BoxConstraints(maxHeight: 420),
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: ChatUi.chatMenu,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ChatUi.chatMenuBorder,
          width: ChatUi.menuBorderWidth,
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in items)
              _OverflowMenuTile(
                item: item,
                onTap: () => onItemTap(item),
              ),
          ],
        ),
      ),
    );
  }
}

class _OverflowMenuTile extends StatelessWidget {
  const _OverflowMenuTile({required this.item, required this.onTap});

  final ChatOverflowMenuItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: item.label,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          // 44 dp tall content inside a 48 dp tap target.
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: SizedBox(
            height: 44,
            child: Row(
              children: [
                Icon(
                  item.icon,
                  size: ChatUi.iconMenu,
                  color: item.isDestructive
                      ? const Color(0xFFF04E2A)
                      : ChatUi.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ChatUi.menuItem.copyWith(
                      color: item.isDestructive
                          ? const Color(0xFFF04E2A)
                          : ChatUi.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
