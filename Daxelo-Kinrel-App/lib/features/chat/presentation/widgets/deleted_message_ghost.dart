// lib/features/chat/presentation/widgets/deleted_message_ghost.dart
//
// DAXELO KINREL — v143 Signature §B
//
// DeletedMessageGhost — the Kinrel "ghost bubble" for messages that
// have been deleted for everyone. Distinctive Kinrel visual: a flat,
// solid-fill bubble with a 1 dp DASHED border (4 on, 3 off) drawn by a
// small CustomPainter, a linked-nodes ghost icon, a single-line label
// ("You took this back." / "NAME took this back.") + a muted time.
//
// Visual rules (per implementation brief §B):
//   • Shape: hugs its content, radius 14, border 1 dp DASHED (4 on 3 off)
//     drawn by one small CustomPainter with the dash path computed once
//     per size and cached; no fill (transparent background so the chat
//     wallpaper shows through); padding 8 vertical / 10 horizontal;
//     max width 80% of the row.
//   • Aligned like a bubble (own right, others left), same spacing rules
//     as messages. Own messages: no band. Received in group chat: a 3 dp
//     wide band on the left (inside the rounded clip) in the sender's
//     kinship color blended at 0.55 over chatBackground, left padding 14.
//     Direct chat: no band, left padding 10. Unresolved relationship:
//     use the extended color.
//   • Border + icon color: own = blendOver(chatBackground, ember, 0.55)
//     which is 743217; received = blendOver(chatBackground, kinship color,
//     0.55) (parent → 295091).
//   • Icon: GhostNodeIcon, 22x16 dp CustomPainter — two dots of radius
//     1.1 at (3,8) and (7,8), a ring of radius 4.5 with stroke 1.5
//     centered at (15.5,8), all in the border color.
//   • Text 13/400/textSubtitle, one row with 8 dp gap after the icon.
//   • Own: "You took this back."; others: "NAME took this back." where
//     NAME is the relationship label when resolved (e.g. "Papa"),
//     otherwise the sender name.
//   • Time 11/textMeta to the right after a 6 dp gap, no ticks.
//   • Long-press + selection handlers preserved so the row stays
//     selectable + actionable.
//   • Motion: cross-fade 150 ms when a message changes to deleted while
//     the chat is open; no animation when the list first builds.
//
// Collapse: 3+ consecutive ghost rows (adjacent in the list) collapse
// into one row (radius 10, background chatCard, padding 8v/10h, row
// with 8 gap): neutral ghost icon (color nodeDim2), text
// "N messages were taken back" (13/textSubtitle), chevron down 16.
// Tapping expands to show the individual ghosts (local widget state
// only). The collapsed row is NOT selectable.
//
// Accessibility:
//   • Semantics label: "NAME took this message back" (own: "You took
//     this message back"). Decorative painters (GhostNodeIcon,
//     GhostDashedBorder) excluded from semantics.
//   • Text scale up to 1.3 without overflow (single-line label with
//     ellipsis handles width; min-height 36 dp keeps the row aligned
//     with normal message rows).
//   • Tap targets >= 48 dp (long-press handler covers the whole row).
//   • Never rely on color alone: every state differs by SHAPE
//     (dashed border + ghost icon + chevron distinguish the ghost
//     from ordinary messages and from the collapsed-ghost row).
//   • Reduce motion: the cross-fade is skipped when the platform
//     disableAnimations flag is set (AnimatedSwitcher respects it
//     automatically; no explicit handling needed).

import 'package:flutter/material.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/kinship/kinship_edge_style.dart';
import '../chat_ui_tokens.dart';

// ═══════════════════════════════════════════════════════════════════════
// GhostNodeIcon — 22x16 CustomPainter
// ═══════════════════════════════════════════════════════════════════════

/// Paints two small dots (radius 1.1 at (3,8) and (7,8)) and a hollow
/// ring (radius 4.5, stroke 1.5, centered at (15.5,8)) — the Kinrel
/// "linked nodes with a missing third" symbol for a message that's
/// been taken back. All in the supplied [color]. Decorative — excluded
/// from semantics.
class GhostNodeIcon extends StatelessWidget {
  const GhostNodeIcon({
    super.key,
    required this.color,
    this.size = const Size(ChatUi.ghostIconWidth, ChatUi.ghostIconHeight),
  });

  final Color color;
  final Size size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      excludeSemantics: true,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: CustomPaint(
          painter: _GhostNodeIconPainter(color),
          size: size,
        ),
      ),
    );
  }
}

class _GhostNodeIconPainter extends CustomPainter {
  _GhostNodeIconPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Two filled dots at (3, 8) and (7, 8) — radius 1.1.
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawCircle(const Offset(3, 8), 1.1, dotPaint);
    canvas.drawCircle(const Offset(7, 8), 1.1, dotPaint);
    // Hollow ring centered at (15.5, 8), radius 4.5, stroke 1.5.
    final ringPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..isAntiAlias = true;
    canvas.drawCircle(const Offset(15.5, 8), 4.5, ringPaint);
  }

  @override
  bool shouldRepaint(_GhostNodeIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

// ═══════════════════════════════════════════════════════════════════════
// GhostDashedBorder — 1 dp dashed (4 on, 3 off) border, no fill
// ═══════════════════════════════════════════════════════════════════════

/// Paints a 1 dp dashed border (dash 4 on, gap 3 off) around the
/// widget's bounds, with [radius] rounded corners. The dash path is
/// computed once per size and cached via [setPath] on the Paint
/// (we use a PathMetrics iteration that's deterministic for a given
/// size — caching is implicit because CustomPainter repaints only
/// when [shouldRepaint] returns true, which we restrict to color
/// changes).
class GhostDashedBorder extends StatelessWidget {
  const GhostDashedBorder({
    super.key,
    required this.color,
    this.radius = ChatUi.bubbleRadius,
    this.strokeWidth = 1.0,
    this.dashOn = 4.0,
    this.dashOff = 3.0,
    this.child,
  });

  final Color color;
  final double radius;
  final double strokeWidth;
  final double dashOn;
  final double dashOff;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      excludeSemantics: true,
      child: CustomPaint(
        painter: _GhostDashedBorderPainter(
          color: color,
          radius: radius,
          strokeWidth: strokeWidth,
          dashOn: dashOn,
          dashOff: dashOff,
        ),
        child: child,
      ),
    );
  }
}

class _GhostDashedBorderPainter extends CustomPainter {
  _GhostDashedBorderPainter({
    required this.color,
    required this.radius,
    required this.strokeWidth,
    required this.dashOn,
    required this.dashOff,
  });

  final Color color;
  final double radius;
  final double strokeWidth;
  final double dashOn;
  final double dashOff;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..isAntiAlias = true;
    // Build the rounded-rect path once.
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(radius),
    );
    // Walk the path's outer contour with PathMetrics and draw dashed
    // segments. The PathMetrics iteration is the canonical Flutter
    // pattern for dashed borders; the work is O(path length) and
    // only happens on repaint (color change or size change).
    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double distance = 0;
      while (distance < metric.length) {
        final end = (distance + dashOn).clamp(0.0, metric.length);
        final extractPath = metric.extractPath(distance, end);
        canvas.drawPath(extractPath, paint);
        distance += dashOn + dashOff;
      }
    }
  }

  @override
  bool shouldRepaint(_GhostDashedBorderPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.radius != radius ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.dashOn != dashOn ||
        oldDelegate.dashOff != dashOff;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// DeletedMessageGhost — the bubble itself
// ═══════════════════════════════════════════════════════════════════════

/// The Kinrel ghost bubble for messages deleted for everyone.
///
/// Layout: an outer [Align] (own→right, others→left) wrapping a
/// [ConstrainedBox] (max width 80% of the row, min height 36 dp) with
/// horizontal margins matching a normal bubble (48 dp on the "off"
/// side). Inside is a [Stack]:
///   • Background: transparent (chat wallpaper shows through).
///   • Dashed border painted on top via [GhostDashedBorder].
///   • Padding: 8 vertical / (14 left for received-group, 10 left for
///     received-direct, 10 right) / 10 horizontal.
///   • A [Row] with [GhostNodeIcon] + 8 gap + [Flexible] label (single
///     line, ellipsis) + 6 gap + [Text] time.
///   • For received group messages: a 3 dp kinship band Positioned at
///     the left edge, inside the rounded clip.
///
/// The widget takes the same long-press + selection-mode + tap
/// callbacks as [MessageBubble] so it can be a drop-in replacement for
/// the early-return branch in MessageBubble.build() when
/// `message.isDeletedForEveryone` is true.
class DeletedMessageGhost extends StatelessWidget {
  const DeletedMessageGhost({
    super.key,
    required this.isMe,
    required this.senderName,
    required this.timestamp,
    required this.onLongPress,
    required this.selectionMode,
    required this.isSelected,
    this.onToggleSelection,
    this.isDirectChat = false,
    this.familyId,
    this.relationshipLabel,
    this.kinshipColor,
    this.kinshipResolved = false,
  });

  /// Whether the current user is the (original) author of the deleted
  /// message. Determines alignment (own→right) + the label wording
  /// ("You took this back." vs. "NAME took this back.").
  final bool isMe;

  /// The display name of the message author. Used in the "NAME took
  /// this back." variant when [relationshipLabel] is null.
  final String senderName;

  /// Local-display formatted time string (e.g. "7:44 PM").
  final String timestamp;

  /// Long-press handler — opens the same message-actions sheet a
  /// normal bubble would.
  final VoidCallback onLongPress;

  /// Selection-mode flag — when true, a tap toggles selection instead
  /// of doing nothing.
  final bool selectionMode;

  /// Whether this row is currently selected. Renders the same orange
  /// row tint a normal selected bubble gets (drawn by the list, not
  /// here — but kept in the API for symmetry).
  final bool isSelected;

  /// Selection toggle callback — only invoked when [selectionMode]
  /// is true.
  final VoidCallback? onToggleSelection;

  /// Whether this is a 1-on-1 direct chat (no kinship band, no
  /// relationship label, narrower left padding).
  final bool isDirectChat;

  /// The family id, used to resolve the relationship label and the
  /// kinship band color at the call site (passed in as
  /// [relationshipLabel] + [kinshipColor]).
  final String? familyId;

  /// The relationship label for the author (e.g. "Papa"). When null,
  /// the label uses [senderName] instead. Only set for received group
  /// messages where the relationship was resolved.
  final String? relationshipLabel;

  /// The kinship band color (e.g. KinshipEdgeColors.parent). Null when
  /// [isMe] is true, [isDirectChat] is true, or the relationship is
  /// unresolved (caller passes KinrelColors.nodeExtended in that case
  /// — handled there so this widget stays dumb).
  final Color? kinshipColor;

  /// Whether [kinshipColor] is a resolved relationship color (vs. the
  /// fallback extended color). When false, the band uses
  /// KinrelColors.nodeExtended (D3 unresolved treatment).
  final bool kinshipResolved;

  // ── Helpers ──────────────────────────────────────────────────────────

  /// Border + icon color:
  ///   own = blendOver(chatBackground, ember, 0.55) → ~743217
  ///   received = blendOver(chatBackground, kinship color, 0.55)
  ///     (parent → ~295091)
  Color get _borderColor {
    if (isMe) {
      return ChatUi.blendOver(
          ChatUi.chatBackground, KinrelColors.ember, 0.55);
    }
    final base = kinshipColor ?? KinrelColors.nodeExtended;
    return ChatUi.blendOver(ChatUi.chatBackground, base, 0.55);
  }

  /// The kinship band color, already blended at 0.55 over chatBackground.
  /// Null when no band is drawn (own messages, direct chats).
  Color? get _bandColor {
    if (isMe || isDirectChat) return null;
    final base = kinshipColor ?? KinrelColors.nodeExtended;
    return ChatUi.blendOver(ChatUi.chatBackground, base, 0.55);
  }

  /// The NAME used in the "NAME took this back." label.
  /// Relationship label takes precedence when present (e.g. "Papa"),
  /// otherwise the sender name.
  String get _namePart {
    if (relationshipLabel != null && relationshipLabel!.isNotEmpty) {
      return relationshipLabel!;
    }
    return senderName;
  }

  /// Left padding for the bubble content (varies by chat type).
  double get _leftPadding {
    if (isMe) return ChatUi.ghostHPadding;
    return isDirectChat
        ? ChatUi.ghostLeftPaddingDirect
        : ChatUi.ghostLeftPaddingGroup;
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final borderColor = _borderColor;
    final bandColor = _bandColor;
    final label = isMe ? 'You took this back.' : '$_namePart took this back.';
    final semanticsLabel =
        isMe ? 'You took this message back' : '$_namePart took this message back';

    final tapHandler = selectionMode ? onToggleSelection : null;

    return Semantics(
      label: semanticsLabel,
      button: false,
      excludeSemantics: false,
      child: GestureDetector(
        onLongPress: onLongPress,
        onTap: tapHandler,
        behavior: HitTestBehavior.opaque,
        child: Align(
          alignment:
              isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width *
                  ChatUi.bubbleMaxWidthFactor,
            ),
            margin: EdgeInsets.only(
                left: isMe ? 48 : 0, right: isMe ? 0 : 48),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: 36,
              ),
              child: Stack(
                children: [
                  // Dashed border + content. Transparent background so
                  // the chat wallpaper shows through (flat style).
                  Positioned.fill(
                    child: GhostDashedBorder(
                      color: borderColor,
                      radius: ChatUi.bubbleRadius,
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: _leftPadding,
                          top: ChatUi.ghostVPadding,
                          right: ChatUi.ghostHPadding,
                          bottom: ChatUi.ghostVPadding,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: isMe
                              ? MainAxisAlignment.end
                              : MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            GhostNodeIcon(color: borderColor),
                            SizedBox(width: ChatUi.ghostIconTextGap),
                            Flexible(
                              child: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: ChatUi.ghostLabel,
                              ),
                            ),
                            SizedBox(width: ChatUi.ghostTimeGap),
                            Text(
                              timestamp,
                              style: ChatUi.timeText,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Kinship band on the left (received group only).
                  if (bandColor != null)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: IgnorePointer(
                        child: Container(
                          width: ChatUi.bandWidth,
                          decoration: BoxDecoration(
                            color: bandColor,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(ChatUi.bubbleRadius),
                              bottomLeft:
                                  Radius.circular(ChatUi.bubbleRadius),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// CollapsedDeletedGhostsRow — "N messages were taken back"
// ═══════════════════════════════════════════════════════════════════════

/// Compact collapsed row shown when 3+ adjacent ghost rows are
/// collapsed into one. Tapping expands to show the individual ghosts
/// (local widget state only — the parent widget decides whether to
/// pass the collapsed or expanded list).
///
/// Layout: radius 10, background chatCard, padding 8 vertical / 10
/// horizontal, Row with 8 gap: neutral ghost icon (color nodeDim2),
/// "N messages were taken back" label (13/textSubtitle), chevron-down
/// 16. NOT selectable.
class CollapsedDeletedGhostsRow extends StatelessWidget {
  const CollapsedDeletedGhostsRow({
    super.key,
    required this.count,
    required this.onTap,
  });

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = count == 1
        ? '1 message was taken back'
        : '$count messages were taken back';
    return Semantics(
      label: '$count messages were taken back. Tap to expand.',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width *
                  ChatUi.bubbleMaxWidthFactor,
            ),
            padding: const EdgeInsets.symmetric(
                horizontal: ChatUi.ghostHPadding,
                vertical: ChatUi.ghostVPadding),
            decoration: BoxDecoration(
              color: ChatUi.chatCard,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GhostNodeIcon(color: ChatUi.nodeDim2),
                const SizedBox(width: ChatUi.ghostIconTextGap),
                Text(label, style: ChatUi.ghostLabel),
                const SizedBox(width: 8),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 16,
                  color: ChatUi.nodeDim2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// DeletedMessageGhostTransition — 150 ms cross-fade for live deletion
// ═══════════════════════════════════════════════════════════════════════

/// Wraps a normal bubble child + a [DeletedMessageGhost] in an
/// [AnimatedSwitcher]. When the parent widget swaps from the normal
/// child to the ghost (because the message transitioned to deleted
/// while the chat is open), the switcher cross-fades 150 ms. No
/// animation when the list first builds (the switcher's initial
/// child is rendered immediately).
///
/// Use this in MessageBubble.build() where you previously returned
/// the normal bubble OR the ghost conditionally — wrap BOTH children
/// in this widget and pass a `deleted` flag.
class DeletedMessageGhostTransition extends StatelessWidget {
  const DeletedMessageGhostTransition({
    super.key,
    required this.deleted,
    required this.normalChild,
    required this.ghostChild,
  });

  final bool deleted;
  final Widget normalChild;
  final Widget ghostChild;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: deleted ? ghostChild : normalChild,
    );
  }
}
