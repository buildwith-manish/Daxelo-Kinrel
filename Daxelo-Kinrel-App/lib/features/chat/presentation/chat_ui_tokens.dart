// lib/features/chat/presentation/chat_ui_tokens.dart
//
// DAXELO KINREL — Chat UI tokens (Kin Thread / Chat UI Reference)
//
// The single source of truth for the unified chat UI. Every visual
// component in features/chat reads its colors, radii, sizes and type
// styles from this file — no chat widget hard-codes a color or a
// dimension. Values follow the Chat UI Reference (see
// docs/CHAT_UI_SPEC.md):
//
//   A. Color tokens — flat solid fills only (no gradients, no
//      shadows, no blur, no Opacity/ColorFiltered layers).
//   B. Typography — body 14/400/1.4 for message text, display(Outfit)
//      16/500 for titles, 11 for times. Weights stay <= 500; the
//      mono font is never used in pills/timestamps.
//   C. Icon/sizing metrics — header icons 22, composer icons 20,
//      menu icons 20, ticks 13, tap targets >= 48.
//
// Kinship band colors come from KinrelColors.node* (see
// brand_colors.dart) — ChatUi only re-exports what the chat needs.

import 'package:flutter/material.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';

/// Chat UI Reference tokens — section A (colors), B (typography),
/// C (sizes). Referenced by every chat widget.
abstract final class ChatUi {
  ChatUi._();

  // ── A. Colors ────────────────────────────────────────────────────────

  /// Screen background behind the wallpaper (D2).
  static const Color chatBackground = Color(0xFF131416);

  /// Header / composer bar surface (D1, D12, D14).
  static const Color chatBar = Color(0xFF13141E);

  /// Card surface — date chips, invite cards, recording capsule (D8,
  /// D11, D12, D18).
  static const Color chatCard = Color(0xFF191B2C);

  /// Hairline border for chat cards (D11, D18).
  static final Color chatCardBorder = Colors.white.withValues(alpha: 0.08);

  /// Received-message bubble fill (D3, D4, D8 floating chip, D10).
  static const Color chatReceived = Color(0xFF2A2D48);

  /// Sent-message bubble fill (D5).
  static const Color chatSent = Color(0xFF34201A);

  /// Sent-bubble border — ember at 28 percent alpha, 0.75 dp (D5).
  static final Color chatSentBorder = KinrelColors.ember.withValues(
    alpha: 0.28,
  );

  /// Overflow / context menu card (D17).
  static const Color chatMenu = Color(0xFF1F2236);

  /// Full-bleed selected-row tint — orange at 18 percent alpha (D16).
  static final Color chatSelectedRow = KinrelColors.orange.withValues(
    alpha: 0.18,
  );

  /// Primary chat text (message bodies, names, unread pill).
  static const Color textPrimary = Color(0xFFECEAF2);

  /// Secondary chat text (subtitles, pill labels, hints).
  static const Color textSecondary = Color(0xFFB9BDD0);

  /// Meta text — timestamps, counts (D7).
  static const Color textMeta = Color(0xFF8E92A8);

  /// v143 / Signature §A — Subtitle text. Sits between textSecondary
  /// (B9BDD0) and textMeta (8E92A8) — used for ghost-bubble labels,
  /// typing indicator text, and other "supporting copy" that's one
  /// notch dimmer than body secondary text.
  static const Color textSubtitle = Color(0xFF9AA0B8);

  /// v143 / Signature §A — Hairline rule color for date markers, unread
  /// markers, and similar thread-separator rows. Distinct from
  /// chatCardBorder (white @ 8%) so separators stay solid + crisp.
  static const Color lineColor = Color(0xFF2E3150);

  /// v143 / Signature §A — Linked-node palette. Three steps from bright
  /// to dim used by the typing indicator, delivery marks, and ghost
  /// icon's two-dot+ring shape. nodeDim1 == textSecondary,
  /// nodeDim2 == textMeta (kept as separate aliases so a future palette
  /// tweak doesn't have to touch multiple call sites).
  static const Color nodeDim1 = Color(0xFFB9BDD0);
  static const Color nodeDim2 = Color(0xFF8E92A8);
  static const Color nodeDim3 = Color(0xFF5A5E78);

  /// v143 / Signature §A — Edge color between linked nodes in the
  /// typing indicator painter (1 dp strokes).
  static const Color edgeDim = Color(0xFF6B6F86);

  /// Brand accent (send circle, hearts, links, active dots).
  static const Color accent = KinrelColors.orange;

  /// Plus button in the reaction bar (D15).
  static const Color reactionPlus = textSecondary;

  /// Constellation wallpaper dots (D13).
  static const Color wallDot = Color(0xFF1F2230);

  /// Constellation wallpaper lines, 1 dp (D13).
  static const Color wallLine = Color(0xFF1A1C27);

  // ── B. Typography ────────────────────────────────────────────────────

  /// Message body — 14 / 400 / 1.4 line height (spec B).
  static const TextStyle messageText = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: textPrimary,
    height: 1.4,
  );

  /// Screen / card titles — display font 16 / 500.
  static const TextStyle titleText = TextStyle(
    fontFamily: KinrelTypography.displayFont,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: textPrimary,
  );

  /// Header subtitle — "N members · N online" (D1).
  static const TextStyle subtitleText = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textSecondary,
  );

  /// Time row inside bubbles — 11 / 400 / textMeta (D7).
  static const TextStyle timeText = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: textMeta,
  );

  /// Sender name (D6) — 12 / 400 silver.
  static const TextStyle senderNameText = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textSecondary,
  );

  /// Sender name when the kinship relationship is unresolved (D3) —
  /// orange 12 / 500.
  static const TextStyle senderNameUnresolved = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: KinrelColors.orange,
  );

  /// Relationship tag pill label (D6) — 11 / 500; the color is
  /// replaced with the sender's kinship color at usage.
  static const TextStyle relationshipTag = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: textPrimary,
  );

  /// Thinking-of-you card text (D11) — 13.
  static const TextStyle thinkingText = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: textPrimary,
  );

  /// Centered pill label — date chips (D8), unread divider (D10).
  static const TextStyle pillText = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textSecondary,
  );

  /// Unread divider pill — same shape as the date chip but lighter
  /// text (D10).
  static const TextStyle unreadPillText = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textPrimary,
  );

  /// Composer placeholder — "Message" (D12).
  static const TextStyle composerHint = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: textMeta,
  );

  /// Composer input text — matches messageText sizing.
  static const TextStyle composerText = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: textPrimary,
    height: 1.35,
  );

  /// Overflow / context menu label (D17).
  static const TextStyle menuText = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 13.5,
    fontWeight: FontWeight.w400,
    color: textPrimary,
  );

  // ── v143 / Signature §A — Additional typography ───────────────────────
  //
  // Time: 11 / 400 / textMeta (already declared above as `timeText`).
  // Label: 13 / 400. Small label: 11 / 500. Marker text: 12 / 400.
  // Never italic, never monospace in chat.

  /// v143 — Label (13 / 400 / textPrimary). Used inside the ghost
  /// bubble, gallery section headers, etc.
  static const TextStyle labelText = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: textPrimary,
  );

  /// v143 — Small label (11 / 500). Used for the relationship dot +
  /// name title row in the reply quote, the passed-along label, and
  /// similar small caption labels. Color is overridable at the call
  /// site (e.g. replyQuoteNameText uses the readable kinship color).
  static const TextStyle smallLabelText = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: textPrimary,
  );

  /// v143 — Marker text (12 / 400 / textSecondary). Used inside the
  /// date marker, unread marker, and collapsed-ghost row.
  static const TextStyle markerText = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textSecondary,
  );

  /// v143 — Ghost bubble label (13 / 400 / textSubtitle). Used by
  /// DeletedMessageGhost's "You took this back" / "NAME took this back".
  static const TextStyle ghostLabel = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: textSubtitle,
  );

  /// v143 — Passed-along label (11 / 500 / textMeta). Used above the
  /// bubble content when the message is forwarded.
  static const TextStyle passedAlongText = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: textMeta,
  );

  /// v143 — Typing indicator text (12 / 400 / textSubtitle). Used by
  /// the linked-nodes typing bubble ("NAME is typing").
  static const TextStyle typingText = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textSubtitle,
  );

  /// v143 — Reply quote name (11 / 500). Color is overridable per
  /// caller (the readable kinship color variant). Default is
  /// textPrimary for standalone use (e.g. gallery legend rows).
  static const TextStyle replyQuoteName = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: textPrimary,
  );

  /// v143 — Reply quote text (12 / 400 / textSecondary, height 1.3).
  static const TextStyle replyQuoteText = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textSecondary,
    height: 1.3,
  );

  // ── C. Sizes & metrics ───────────────────────────────────────────────

  /// Bubble corner radius — 14 on all four corners (D3/D4/D5).
  static const double bubbleRadius = 14;

  /// Max bubble width as a fraction of screen width (D3/D5).
  static const double bubbleMaxWidthFactor = 0.80;

  /// Sent-bubble border width (D5).
  static const double sentBorderWidth = 0.75;

  /// Kinship band strip width on received group bubbles (D3).
  static const double bandWidth = 3;

  /// Hairline border width for cards (D11/D18).
  static const double cardBorderWidth = 0.5;

  /// Header height (D1, D14).
  static const double headerHeight = 56;

  /// Header avatar diameter (D1).
  static const double avatarSize = 34;

  /// Header action icons — phone, more_vert (D1).
  static const double headerIconSize = 22;

  /// Composer icons — emoji, attach, heart, mic/send (D12).
  static const double composerIconSize = 20;

  /// Menu icons inside the D17 card.
  static const double menuIconSize = 20;

  /// Read-receipt tick size (D7).
  static const double tickSize = 13;

  /// Composer send/mic circle diameter (D12).
  static const double sendButtonSize = 40;

  /// Composer input capsule corner radius (D12).
  static const double composerRadius = 20;

  /// Overflow / context menu card width (D17).
  static const double menuWidth = 210;

  /// Overflow / context menu corner radius (D17).
  static const double menuRadius = 12;

  /// Thinking-of-you heart icon (D11).
  static const double iconHeart = 18;

  /// System-notice sparkle icon (D9).
  static const double iconSparkle = 14;

  /// Minimum tap target for every interactive element.
  static const double tapTarget = 48;

  // ── v143 / Signature §A — Additional sizes ───────────────────────────

  /// Date / unread marker row: vertical padding.
  static const double dateMarkerVPadding = 6;

  /// Date / unread marker: 6x6 node circle.
  static const double dateMarkerNodeSize = 6;

  /// Date / unread marker: gap between line and node, node and label,
  /// label and line.
  static const double dateMarkerGap = 8;
  static const double dateMarkerNodeLabelGap = 6;

  /// Date / unread marker: line thickness.
  static const double dateMarkerLineThickness = 1;

  /// Delivery mark CustomPainter bounds (§C).
  static const double deliveryMarkWidth = 18;
  static const double deliveryMarkHeight = 10;
  static const double deliveryMarkGapBefore = 6; // gap after the time

  /// Ghost bubble (§B).
  static const double ghostIconWidth = 22;
  static const double ghostIconHeight = 16;
  static const double ghostIconTextGap = 8;
  static const double ghostVPadding = 8;
  static const double ghostHPadding = 10;
  static const double ghostLeftPaddingGroup = 14; // band-side, received group
  static const double ghostLeftPaddingDirect = 10; // received direct
  static const double ghostTimeGap = 6; // gap between label and time

  /// Reply quote (§G).
  static const double replyBandWidth = 3;
  static const double replyRadius = 8;
  static const double replyTopPad = 4;
  static const double replyRightPad = 8;
  static const double replyBottomPad = 4;
  static const double replyLeftPad = 12;
  static const double replyBottomMargin = 4;

  /// Typing indicator (§H).
  static const double typingPainterWidth = 46;
  static const double typingPainterHeight = 12;
  static const double typingNodeRadius = 2.6;
  static const double typingGap = 10;

  /// Passed-along label (§F).
  static const double passedAlongIconSize = 13;
  static const double passedAlongGap = 4;
  static const double passedAlongBottomMargin = 2;

  // ── Helpers ──────────────────────────────────────────────────────────

  /// Pill label color for a kinship band color — the band color
  /// lifted slightly toward white so 11/500 text stays legible on the
  /// 12 percent tinted pill background (D6).
  static Color kinshipPillText(Color c) =>
      Color.lerp(c, Colors.white, 0.12)!.withValues(alpha: 1);

  /// v143 / Signature §A — `blendOver(background, color, amount)`.
  ///
  /// Mixes `color` over `background` at `amount` (0..1) and returns an
  /// OPAQUE color. Equivalent to: `color * amount + background * (1 - amount)`
  /// with alpha forced to 1. Use this instead of `Color.withValues(alpha:)`
  /// whenever you need a "faded" color in the chat — it stays flat (no
  /// alpha compositing surprises over wallpapers or stacked layers) and
  /// is consistent across the whole signature palette.
  ///
  /// Example: `blendOver(ChatUi.chatBackground, KinrelColors.ember, 0.55)`
  /// is the border/icon color used by the own-message ghost (Section B).
  static Color blendOver(Color background, Color color, double amount) {
    final mixed = Color.lerp(background, color, amount);
    if (mixed == null) return color;
    // Force opaque — both inputs are opaque, but Color.lerp leaves the
    // alpha channel at its interpolated value. Force 1.0 so callers can
    // use the result as a solid fill or border.
    return mixed.withValues(alpha: 1);
  }

  /// v143 / Signature §A — Readable text variant of a kinship color for
  /// small labels. Blends the kinship color 20% toward white so 11/500
  /// text on a dark bubble stays legible (e.g. parent #3B82F6 → ~#6FA3F8).
  static Color readableKinshipLabel(Color c) =>
      Color.lerp(c, Colors.white, 0.20)!.withValues(alpha: 1);
}
