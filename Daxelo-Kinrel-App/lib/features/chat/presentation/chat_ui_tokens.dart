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

  // ── Helpers ──────────────────────────────────────────────────────────

  /// Pill label color for a kinship band color — the band color
  /// lifted slightly toward white so 11/500 text stays legible on the
  /// 12 percent tinted pill background (D6).
  static Color kinshipPillText(Color c) =>
      Color.lerp(c, Colors.white, 0.12)!.withValues(alpha: 1);
}
