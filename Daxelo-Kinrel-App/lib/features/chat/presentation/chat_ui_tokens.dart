// lib/features/chat/presentation/chat_ui_tokens.dart
//
// DAXELO KINREL — Chat UI Tokens (Chat UI Reference / Kin Thread)
//
// ONE source of truth for every color, typography style, icon size and
// metric used by the shared chat UI (group + direct chat render the
// SAME widgets). No chat widget may hard-code a Color(…) / size /
// TextStyle — everything comes from here plus the existing KinrelColors,
// KinrelSpacing and KinrelRadius tokens.
//
// Flat style only: solid colors, NO shadows, NO blur, NO gradients,
// NO Opacity/ColorFiltered widgets and NO monospace font anywhere in
// the chat. Kinship colors reuse the graph node palette via the
// existing kinshipCategoryColor helper (chat_meta.dart) — there is no
// second mapping in this file.

import 'package:flutter/material.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';

/// Chat UI design tokens (Chat UI Reference spec, sections A–C).
class ChatUi {
  ChatUi._();

  // ── A. Surfaces ──────────────────────────────────────────────────────

  /// Screen + wallpaper base — #131416.
  static const Color chatBackground = KinrelColors.darkBackground;

  /// Header, composer bar, selection bar — #13141E.
  static const Color chatBar = KinrelColors.darkSurface;

  /// Composer field, date chip, notices, collapsed rows — #191B2C.
  static const Color chatCard = KinrelColors.darkCard;

  /// Received bubble, result card, floating date chip, unread pill — #2A2D48.
  static const Color chatReceived = Color(0xFF2A2D48);

  /// Sent bubble — #34201A.
  static const Color chatSent = Color(0xFF34201A);

  /// Sent bubble border — ember #C44A18 at 28% alpha (0x47).
  static const Color chatSentBorder = Color(0x47C44A18);
  static const double sentBorderWidth = 0.75;

  /// Reaction bar + overflow menu — #1F2236.
  /// ("Thinking of you" moment uses chatCard.)
  static const Color chatMenu = Color(0xFF1F2236);
  static const Color chatMenuBorder = Color(0xFF343853);
  static const double menuBorderWidth = 0.5;

  /// Selected-row tint — orange #E8612A at 18% alpha (0x2E).
  static const Color chatSelectedRow = Color(0x2EE8612A);

  /// Card hairline border — #2E3150 at 0.5 dp.
  static const Color chatCardBorder = Color(0xFF2E3150);
  static const double cardBorderWidth = 0.5;

  // ── A. Text colors ───────────────────────────────────────────────────

  /// Primary message + strong text — #ECEAF2.
  static const Color textPrimary = Color(0xFFECEAF2);

  /// Pill text, subtitles in cards, icons — #B9BDD0.
  static const Color textSecondary = Color(0xFFB9BDD0);

  /// Message time — #8E92A8.
  static const Color textMeta = Color(0xFF8E92A8);

  /// Header subtitle, muted rows — #9AA0B8.
  static const Color textSubtitle = Color(0xFF9AA0B8);

  /// Composer hint + its icons — #7C84A0.
  static const Color textHint = Color(0xFF7C84A0);

  /// Sender name — Kinrel silver #C9B4A8.
  static const Color senderNameColor = KinrelColors.textSilver;

  /// Brand accent — buttons, links, mic button, hearts.
  static const Color accent = KinrelColors.orange;

  /// Pressed ripple on rows and icon buttons — white at 8%.
  static const Color pressedRipple = Color(0x14FFFFFF);

  // ── A. Kinship pill contrast ─────────────────────────────────────────
  // Pill text color equals the band (graph node) color, EXCEPT
  // grandparent and extended which get lighter variants for contrast.

  /// Text color for a relationship tag pill whose band color is
  /// [bandColor] (a KinrelColors.node* value). Grandparent indigo
  /// (#6366F1) → #8B8DF5; extended slate (#64748B) → #94A3B8.
  static Color kinshipPillText(Color bandColor) {
    if (bandColor == const Color(0xFF6366F1)) return const Color(0xFF8B8DF5);
    if (bandColor == const Color(0xFF64748B)) return const Color(0xFF94A3B8);
    return bandColor;
  }

  // ── A. Reaction icon colors (bar layout reference) ───────────────────
  // The real reactions stay emoji glyphs; these colors are the icon
  // equivalents used for Semantics/decoration if ever needed.

  static const Color reactionHeart = Color(0xFFEC4899);
  static const Color reactionThumbsUp = Color(0xFF3B82F6);
  static const Color reactionLaugh = Color(0xFFF59E0B);
  static const Color reactionSurprised = Color(0xFFF59E0B);
  static const Color reactionSad = Color(0xFFF59E0B);
  static const Color reactionPlus = Color(0xFF9AA0B8);

  // ── B. Typography (dp = sp at scale 1.0; never weight ≥ 600) ────────
  // Fonts come from KinrelTypography (body = DMSans, display = Outfit).
  // NEVER a monospace font anywhere in the chat.

  /// Message text — body 14 / 400 / height 1.4 / textPrimary.
  static const TextStyle messageText = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: textPrimary,
  );

  /// Header title — display 16 / 500.
  static const TextStyle headerTitle = TextStyle(
    fontFamily: KinrelTypography.displayFont,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: textPrimary,
  );

  /// Header subtitle — body 12 / 400 / textSubtitle.
  static const TextStyle headerSubtitle = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textSubtitle,
  );

  /// Sender name — body 12 / 400 / senderName color.
  ///
  /// NOTE: When the sender's kinship relationship to the viewer has been
  /// resolved (K-Graph edge found, category classified, color picked),
  /// the chat bubble overrides this color with the sender's kinship
  /// category color so the name visually pairs with the relationship
  /// label rendered beside it (chat UI reference screenshot:
  /// "Papa • Father" — both spans colored with the parent blue).
  static const TextStyle senderNameText = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: senderNameColor,
  );

  /// Sender name — RESOLVED kinship variant (chat UI reference screenshot).
  ///
  /// Same typography as [senderNameText] but a heavier weight (500) so
  /// the name pops visually beside the "•" separator and the
  /// relationship label. The COLOR is NOT baked in here — the bubble
  /// supplies the kinship color via TextStyle.copyWith so a single
  /// style works for every relationship category (parent blue, sibling
  /// purple, grandparent indigo, spouse orange, etc.).
  static const TextStyle senderNameKinship = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 12,
    fontWeight: FontWeight.w500,
  );

  /// Relationship label rendered beside the sender name (chat UI
  /// reference screenshot: "Papa • Father"). Same typography family
  /// as the sender name, slightly lighter weight (400) so the NAME
  /// reads as the primary identifier and the relationship as the
  /// qualifier. The COLOR is supplied by the caller from the sender's
  /// kinship category color (parent blue, grandparent indigo, etc.).
  static const TextStyle relationshipLabel = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 12,
    fontWeight: FontWeight.w400,
  );

  /// "•" separator between the sender name and the relationship label
  /// (chat UI reference screenshot). Same size as the surrounding
  /// text, lighter color so the separator visually recedes between
  /// the two coloured spans. The caller may also tint it with the
  /// kinship color via copyWith for a stronger visual tie.
  static const TextStyle nameRelationSeparator = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textMeta,
  );

  /// Relationship tag — body 11 / 500 (color = kinship pill color).
  static const TextStyle relationshipTag = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 11,
    fontWeight: FontWeight.w500,
  );

  /// Unresolved-relationship sender name — orange 12 / 500.
  static const TextStyle senderNameUnresolved = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: accent,
  );

  /// Message time — body 11 / 400 / textMeta.
  static const TextStyle timeText = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: textMeta,
  );

  /// Date chip, notices, unread pill text — body 12 / 400.
  static const TextStyle pillText = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textSecondary,
  );

  /// Floating date chip text — body 12 / 400 / textPrimary.
  static const TextStyle floatingDateText = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textPrimary,
  );

  /// Unread pill text — body 12 / 400 / textPrimary.
  static const TextStyle unreadPillText = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textPrimary,
  );

  /// Selection count — display 18 / 500.
  static const TextStyle selectionCount = TextStyle(
    fontFamily: KinrelTypography.displayFont,
    fontSize: 18,
    fontWeight: FontWeight.w500,
    color: textPrimary,
  );

  /// Overflow menu item label — body 14 / 400 / textPrimary.
  static const TextStyle menuItem = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: textPrimary,
  );

  /// Button label (Join / Rematch) — body 13 / 500 / orange.
  static const TextStyle buttonLabel = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: accent,
  );

  /// Composer hint — body 14 / 400 / textHint.
  static const TextStyle composerHint = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: textHint,
  );

  /// Game invite title — body 14 / 500 / textPrimary.
  static const TextStyle inviteTitle = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: textPrimary,
  );

  /// Game invite players line — body 12 / 400 / textSecondary.
  static const TextStyle invitePlayers = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textSecondary,
  );

  /// Expired one-liner text — body 13 / 400 / textSubtitle.
  static const TextStyle inviteExpired = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: textSubtitle,
  );

  /// "Thinking of you" moment text — body 13 / 400 / textPrimary.
  static const TextStyle thinkingText = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: textPrimary,
  );

  // ── C. Icon sizes (dp, Material family) ─────────────────────────────

  static const double iconHeaderBack = 22;
  static const double iconHeaderPhone = 22;
  static const double iconHeaderMore = 22;
  static const double iconComposerEmoji = 20;
  static const double iconComposerAttach = 20;
  static const double iconComposerMic = 20;
  static const double iconComposerSend = 20;
  static const double iconComposerThinking = 20;
  static const double iconSelectionClose = 22;
  static const double iconSelectionReply = 22;
  static const double iconSelectionForward = 22;
  static const double iconSelectionDelete = 22;
  static const double iconSelectionMore = 22;
  static const double iconMenu = 20; // copy, star, pin, info, share
  static const double iconSparkle = 14; // auto_awesome
  static const double iconFamilyTree = 13; // account_tree
  static const double iconTicks = 13; // done_all
  static const double iconTrophy = 22; // emoji_events outline
  static const double iconGameLine = 16; // sports_esports outline
  static const double iconGameTile = 22;
  static const double iconGrid = 22; // grid_3x3
  static const double iconChevronDown = 16;
  static const double iconHeart = 18;

  // ── Layout metrics ───────────────────────────────────────────────────

  /// Minimum tap target for every icon button (even smaller icons).
  static const double tapTarget = 48;

  /// Header / selection bar height.
  static const double barHeight = 56;

  /// Header avatar circle.
  static const double headerAvatar = 34;

  /// Bubble corner radius (all four corners — no tails).
  static const double bubbleRadius = 14;

  /// Kinship band width inside the received bubble's rounded clip.
  static const double bandWidth = 3;

  /// Max bubble width as a fraction of the row.
  static const double bubbleMaxWidthFactor = 0.80;

  /// Overflow menu card width.
  static const double menuWidth = 210;
}
