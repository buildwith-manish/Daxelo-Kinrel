// lib/core/constants/app_tokens.dart
//
// DAXELO KINREL — AppTokens: the single canonical design-token system.
//
// Grounded in the existing orange/amber brand identity (Indian-family
// warmth, not generic SaaS-card defaults). This file consolidates the
// three previously-parallel token systems into one source of truth:
//
//   • KinrelColors (brand_colors.dart, 60+ raw colors)
//   • FamilyHubType/Space/Surface (design_system.dart, 4 sizes)
//   • KinrelThemeExtension (app_theme.dart, ~15 colors + 3 radii)
//
// New code + consolidated screens reference AppTokens.* directly. Old
// code keeps working — KinrelColors / KinrelSpacing / KinrelRadius /
// KinrelTypography are NOT removed, just deprecated as the "primary"
// source of truth. AppTokens is the contract.
//
// ─────────────────────────────────────────────────────────────────────
// DESIGN PRINCIPLES (per Phase 1 brief — "premium app" feel via system-
// wide consistency, NOT individual screen polish)
// ─────────────────────────────────────────────────────────────────────
//
//   1. Single-accent color — orange (#E8612A) carries every CTA /
//      active state / brand moment. Amber (#F59240) is the warm
//      companion used only in gradients + glows. Gold (#D4AF37) is the
//      celebration color — used ONLY for trophy/badge/streak-milestone
//      moments, never as a regular accent.
//
//   2. Single semantic-accent set (small, named, not ad-hoc):
//      • orange  — primary action, wins/streak, brand moments
//      • gold    — achievement/trophy celebration (rare)
//      • purple  — challenges/quests (inherited from existing use)
//      • green   — success / owned / completed
//      • red     — destructive / error / leave
//      • amber   — warm gradient companion, never a standalone accent
//
//   3. Single type scale — 5 sizes (display / header / title / body /
//      caption / micro). Outfit for display + header, DMSans for
//      everything else, DMMono for technical/numeric micro-labels.
//
//   4. Single spacing scale — multiples of 4 (4 / 8 / 12 / 16 / 20 /
//      24 / 32 / 48). Documented as `AppSpacing.*`.
//
//   5. Single radius scale — 4 named radii (sm 6, md 10, lg 14, xl 18,
//      pill 9999). Plus 2 documented card-tier radii (card=14, hero=18).
//
//   6. Three card treatments only (per Phase 1 brief, "2-3 MAX"):
//      • AppCard.hero    — used ONCE per screen for the single most
//                         important thing. Gradient bg, accent border,
//                         soft accent glow, radius 18, padding 16.
//      • AppCard.standard — most content cards. Solid darkCard bg,
//                         hairline border (white 5%), radius 14,
//                         padding 14.
//      • AppCard.compact — list rows (leaderboard, moments). Solid
//                         darkCard bg, hairline border (white 5%),
//                         radius 12, padding horizontal 12 vertical 10.
//                         Can collapse to "flat (no decoration) +
//                         Divider" for inline lists.
//
//   7. Single icon language — Material Symbols Outlined for everything
//      functional. No emoji in headers (✨, 📋, 🧡 — all gone). The
//      Kinrel symbol (hero_section.dart) is the only non-Material icon
//      and stays as the brand mark.
//
//   8. Motion answers a user's action, never decorates on load. Three
//      motion patterns documented in AppMotion:
//      • AppMotion.tap       — 150ms easeOut, used for every interactive
//                            feedback (button press, chip tap, optimistic
//                            action confirmation).
//      • AppMotion.transition — 300ms easeOut, screen pushes + hero
//                            transitions.
//      • AppMotion.celebrate — 600ms spring, used ONLY for orchestrated
//                            celebration moments (PB reveal, badge
//                            unlock, streak milestone).
//
// ─────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import 'brand_colors.dart';
import 'brand_spacing.dart';
import 'brand_typography.dart';

// ═══════════════════════════════════════════════════════════════════════
// SECTION 1 — APP COLOR
// ═══════════════════════════════════════════════════════════════════════
//
// Six named colors, anchored to the existing brand identity. These
// are the ONLY colors a new feature should reach for. Existing raw
// constants in KinrelColors (textWhite, darkCard, etc.) are kept as
// the implementation — AppColor re-exports them as named semantic
// tokens.

/// The single canonical color system for the Kinrel app.
///
/// Do NOT reach into KinrelColors.* directly in new code — use
/// `AppColor.*` instead. This indirection lets us swap the underlying
/// palette (e.g., add a light theme variant) without touching every
/// screen.
class AppColor {
  AppColor._();

  // ── Brand accents (the 6 named colors) ──────────────────────────────

  /// Primary accent. Every CTA, every active state, every brand moment.
  /// Hex `#E8612A` — warm terracotta, the color of marigold + sindoor.
  static const Color orange = KinrelColors.orange;

  /// Warm companion to orange. Used ONLY in gradients + glow shadows,
  /// never as a standalone accent. Hex `#F59240`.
  static const Color amber = KinrelColors.amber;

  /// Celebration color. Trophy, badge, streak-milestone. Rare. Hex
  /// `#D4AF37` — marigold-gold, not yellow.
  static const Color gold = KinrelColors.gold;

  /// Challenge/quest accent. Inherited from existing use (gaming
  /// challenges, prediction battle "moment" frame).
  static const Color purple = KinrelColors.extendedPurple;

  /// Success / owned / completed. Hex `#4CAF7A` — softer than pure green.
  static const Color success = KinrelColors.success;

  /// Destructive / error / leave. Hex `#F04E2A` — same warm tone as
  /// orange, but a different hue family so it reads as "stop" not
  /// "go". Never used as a primary accent.
  static const Color error = KinrelColors.error;

  // ── Dark surfaces (the established near-black palette) ──────────────

  /// App background. Hex `#131416`. The darkest surface in the system.
  static const Color background = KinrelColors.darkBackground;

  /// Standard card surface. Hex `#191B2C`. ~85% L* difference from
  /// background — reads as a raised card against the page.
  static const Color card = KinrelColors.darkCard;

  /// Elevated/muted surface. Hex `#202338`. Used for inset/secondary
  /// cards, button-bases, chip backgrounds.
  static const Color elevated = KinrelColors.darkElevated;

  /// Between background and card. Hex `#13141E`. Used for full-bleed
  /// sections where the card vs background distinction would be too
  /// strong.
  static const Color surface = KinrelColors.darkSurface;

  // ── Text colors (WCAG AA against dark surfaces) ────────────────────

  /// Primary text on dark. Hex `#F5F0EE` — warm-white, never pure #FFF.
  static const Color textPrimary = KinrelColors.textWhite;

  /// Secondary text on dark. Hex `#C9B4A8` — warm silver.
  static const Color textSecondary = KinrelColors.textSilver;

  /// Hint / disabled / metadata text. Hex `#C9B4A8` (raised from
  /// #8A7A72 in KIN-08 for WCAG AA compliance).
  static const Color textDim = KinrelColors.textDim;

  // ── Semantic accent helpers (alpha variants, single source) ───────

  /// Hairline border color — `textPrimary @ 5%` alpha. The single
  /// value to use for "subtle card border on dark surfaces". Replaces
  /// the prior inconsistent `Colors.white @ 0.05 / 0.06 / 0.07` across
  /// four screens.
  static Color hairline(BuildContext context) =>
      textPrimary.withValues(alpha: 0.05);

  /// Orange-tinted background for "active" treatments — used by
  /// leaderboard "is me" rows, hero accents. `orange @ 10%` alpha.
  static const Color orangeTint = Color(0x1AE8612A);

  /// Gold-tinted background for milestone cards — used by Family
  /// Moments milestone entries, badge unlocks. `gold @ 12%` alpha.
  static const Color goldTint = Color(0x1FD4AF37);

  /// Amber-tinted background — used by coin-balance chip, rewards
  /// treasury summary. `amber @ 15%` alpha.
  static const Color amberTint = Color(0x26F59240);

  // ── Gradients (3 named, anchored to brand) ─────────────────────────

  /// The hero gradient. Orange → amber, topLeft → bottomRight. Used
  /// ONLY on the single hero element per screen — never as decoration.
  static const LinearGradient brandGradient =
      KinrelGradients.igniteGradient;

  /// The celebration gradient. Gold → amber → orange, topLeft →
  /// bottomRight. Used ONLY for celebration moments (PB reveal,
  /// achievement badge).
  static const LinearGradient celebrationGradient =
      KinrelGradients.achievementGradient;

  /// The deep-fire gradient. Near-black → orange glow. Used ONLY on
  /// full-screen premium surfaces (the Family Space background,
  /// festival banners) — never as a card decoration.
  static const LinearGradient deepGradient = KinrelGradients.deepFireGradient;
}

// ═══════════════════════════════════════════════════════════════════════
// SECTION 2 — APP TYPE
// ═══════════════════════════════════════════════════════════════════════
//
// 5 named sizes on a clear scale. Outfit for display + header, DMSans
// for body, DMMono for technical micro-labels.
//
// This collapses the 17 raw TextStyles in KinrelTypography + the 4
// sizes in FamilyHubType down to 5 named semantic tokens.

class AppType {
  AppType._();

  /// Display — hero title, the one big thing on a screen.
  /// Outfit 28 / w700 / textPrimary / ls −0.5 / h 1.15.
  static const TextStyle display = TextStyle(
    fontFamily: KinrelTypography.displayFont,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: AppColor.textPrimary,
    letterSpacing: -0.5,
    height: 1.15,
  );

  /// Header — section title.
  /// Outfit 20 / w700 / textPrimary / h 1.3.
  static const TextStyle header = TextStyle(
    fontFamily: KinrelTypography.displayFont,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: AppColor.textPrimary,
    height: 1.3,
  );

  /// Title — card title, row title.
  /// DMSans 16 / w700 / textPrimary / h 1.3.
  static const TextStyle title = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColor.textPrimary,
    height: 1.3,
  );

  /// Body — primary body text.
  /// DMSans 14 / w400 / textSecondary / h 1.45.
  static const TextStyle body = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColor.textSecondary,
    height: 1.45,
  );

  /// Caption — metadata, timestamps, helper text.
  /// DMSans 12 / w500 / textDim / h 1.4.
  static const TextStyle caption = TextStyle(
    fontFamily: KinrelTypography.bodyFont,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColor.textDim,
    height: 1.4,
  );

  /// Micro — numeric badges, score chips, status pills.
  /// DMMono 10 / w700 / h 1.3. Always uppercase + letter-spacing 1.5
  /// for technical-data feel.
  static const TextStyle micro = TextStyle(
    fontFamily: KinrelTypography.monoFont,
    fontSize: 10,
    fontWeight: FontWeight.w700,
    color: AppColor.textDim,
    letterSpacing: 1.5,
    height: 1.3,
  );
}

// ═══════════════════════════════════════════════════════════════════════
// SECTION 3 — APP SPACING
// ═══════════════════════════════════════════════════════════════════════
//
// Multiples of 4. This unifies the two previously-incompatible scales
// (KinrelSpacing.md=12 vs FamilyHubSpace.md=16) under one set of named
// semantic tokens.

class AppSpacing {
  AppSpacing._();

  /// 4 — tight gaps inside a row (icon-to-label, chip-to-text).
  static const double xxs = 4;

  /// 8 — between related elements in a row, small list-item gap.
  static const double xs = 8;

  /// 12 — standard inner padding for compact cards / list rows.
  static const double sm = 12;

  /// 16 — default card padding, default screen horizontal margin.
  /// This is the workhorse spacing value.
  static const double base = 16;

  /// 20 — slightly larger card padding (used by hero cards).
  static const double md = 20;

  /// 24 — section inner padding, large card padding.
  static const double lg = 24;

  /// 32 — section gap (between major sections on a scroll).
  static const double xl = 32;

  /// 48 — page top/bottom breathing room (above the first section,
  /// below the last).
  static const double xxl = 48;

  // ── Semantic aliases ────────────────────────────────────────────────

  /// Screen horizontal margin = 16. Use on every page's outermost
  /// horizontal padding so all screens align column-to-column.
  static const double screenHorizontal = base;

  /// Standard card padding = 14. (Slightly less than base 16 so cards
  /// with text content don't balloon; matches existing Play With /
  /// Quick Picks card padding.)
  static const double cardPadding = 14;

  /// Section gap = 24. The space between major sections on a scroll
  /// view (e.g., between Highlights and Prediction Battle on the
  /// Family Space).
  static const double sectionGap = lg;

  /// List item gap = 8. Between items in a vertical list (leaderboard
  /// rows, moments entries).
  static const double listItemGap = xs;
}

// ═══════════════════════════════════════════════════════════════════════
// SECTION 4 — APP RADIUS
// ═══════════════════════════════════════════════════════════════════════
//
// 5 named radii. Plus 2 documented card-tier radii used by the 3
// card treatments. Replaces the prior 10 distinct raw radii (6, 8, 9,
// 10, 12, 14, 16, 18, 20, 22) with this set.

class AppRadius {
  AppRadius._();

  /// 6 — small chips, badges, tags.
  static const double xs = 6;

  /// 10 — buttons, small inputs.
  static const double sm = 10;

  /// 12 — compact list-row cards (leaderboard, moments).
  static const double md = 12;

  /// 14 — standard content cards (Play With, Quick Picks, Moments).
  /// This is the workhorse radius.
  static const double lg = 14;

  /// 18 — hero cards (Prediction Battle, Family Streak Hero, Rewards
  /// Treasury summary).
  static const double xl = 18;

  /// 9999 — pills, avatars, FABs, fully-rounded chips.
  static const double pill = 9999;

  // ── Card-tier aliases (Phase 1 brief: "documented 2-value scale for
  //    hierarchy, larger radius for hero elements") ──────────────────

  /// Compact list-row card radius = 12. Used by AppCard.compact.
  static const double cardCompact = md;

  /// Standard content card radius = 14. Used by AppCard.standard.
  static const double cardStandard = lg;

  /// Hero card radius = 18. Used by AppCard.hero (the single most
  /// important thing on a screen).
  static const double cardHero = xl;
}

// ═══════════════════════════════════════════════════════════════════════
// SECTION 5 — APP CARD
// ═══════════════════════════════════════════════════════════════════════
//
// Three card treatments, differentiated by HIERARCHY not by feature.
// Every existing card type must map onto one of these — see the
// migration table at the bottom of this file.
//
// Per Phase 1 brief: "2-3 card treatments MAX (not one per feature),
// differentiated by hierarchy/purpose". This collapses the 10+ ad-hoc
// card treatments in the audit down to 3 named ones.

class AppCard {
  AppCard._();

  /// HERO treatment — used ONCE per screen for the single most
  /// important thing.
  ///
  /// Visual: gradient background (orange→amber), accent border at
  /// 30% alpha (width 1), soft accent glow shadow (blur 20, offset
  /// (0,6)), radius 18, padding 16.
  ///
  /// Examples: PredictionBattleV1Card on Family Space, FamilyStreak
  /// HeroCard on Family Arena, Rewards Treasury summary on Rewards
  /// Shop.
  static BoxDecoration hero({
    Color accentColor = AppColor.orange,
    Color? backgroundColor,
  }) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          backgroundColor ?? accentColor.withValues(alpha: 0.18),
          AppColor.card,
        ],
      ),
      borderRadius: BorderRadius.circular(AppRadius.cardHero),
      border: Border.all(
        color: accentColor.withValues(alpha: 0.30),
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: accentColor.withValues(alpha: 0.15),
          blurRadius: 20,
          spreadRadius: 1,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  /// STANDARD treatment — most content cards.
  ///
  /// Visual: solid darkCard background, hairline border (textPrimary
  /// at 5% alpha, width 1), radius 14, padding 14, NO shadow.
  ///
  /// Examples: PlayWithCard, QuickPickCard, FamilyMomentCard (non-
  /// milestone), GamingRankRow (non-me), _RewardCard.
  static const BoxDecoration standard = BoxDecoration(
    color: AppColor.card,
    borderRadius: BorderRadius.all(Radius.circular(AppRadius.cardStandard)),
    border: Border(
      top: BorderSide(color: Color(0x0DF5F0EE), width: 1),
      // textPrimary @ 5%
      left: BorderSide(color: Color(0x0DF5F0EE), width: 1),
      right: BorderSide(color: Color(0x0DF5F0EE), width: 1),
      bottom: BorderSide(color: Color(0x0DF5F0EE), width: 1),
    ),
  );

  /// COMPACT treatment — list rows (leaderboard, moments).
  ///
  /// Visual: solid darkCard background, hairline border (textPrimary
  /// at 5% alpha, width 1), radius 12, padding horizontal 12 / vertical
  /// 10, NO shadow. Optionally collapses to "no decoration + Divider"
  /// for inline lists (FamilyLeaderboardWidget rows).
  static const BoxDecoration compact = BoxDecoration(
    color: AppColor.card,
    borderRadius: BorderRadius.all(Radius.circular(AppRadius.cardCompact)),
    border: Border(
      top: BorderSide(color: Color(0x0DF5F0EE), width: 1),
      left: BorderSide(color: Color(0x0DF5F0EE), width: 1),
      right: BorderSide(color: Color(0x0DF5F0EE), width: 1),
      bottom: BorderSide(color: Color(0x0DF5F0EE), width: 1),
    ),
  );

  /// ACCENTED variant — same as STANDARD but with an accent-colored
  /// border (orange at 60% alpha, width 1.5). Used to highlight "this
  /// is me" / "this is the active one" rows (e.g., GamingRankRow when
  /// `isMe` is true, FamilyMomentCard when milestone).
  static BoxDecoration accented({
    Color accentColor = AppColor.gold,
  }) {
    return BoxDecoration(
      color: AppColor.card,
      borderRadius: BorderRadius.circular(AppRadius.cardStandard),
      border: Border.all(
        color: accentColor.withValues(alpha: 0.35),
        width: 1.5,
      ),
      boxShadow: [
        BoxShadow(
          color: accentColor.withValues(alpha: 0.12),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  /// "Active-me" variant — same as ACCENTED but uses orange (the
  /// primary brand accent) instead of gold. Used by GamingRankRow
  /// when `isMe` is true to highlight the viewer's own row.
  static BoxDecoration activeMe() {
    return BoxDecoration(
      color: AppColor.orangeTint,
      borderRadius: BorderRadius.circular(AppRadius.cardStandard),
      border: Border.all(
        color: AppColor.orange.withValues(alpha: 0.60),
        width: 1.5,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SECTION 6 — APP MOTION
// ═══════════════════════════════════════════════════════════════════════
//
// Three motion patterns. Motion answers a user's action, never
// decorates on load.
//
// Per Phase 2 brief: "reject scattered fade-and-slide-up-on-everything
// defaults. Motion should answer a user's action, not decorate on load."

class AppMotion {
  AppMotion._();

  /// TAP — 150ms easeOut. Used for every interactive feedback:
  /// button press, chip tap, optimistic-action confirmation
  /// (reaction emoji briefly scales up then settles, guess submission
  /// shows "submitted" instantly).
  static const Duration tapDuration = Duration(milliseconds: 150);
  static const Curve tapCurve = Curves.easeOut;

  /// TRANSITION — 300ms easeOut. Screen pushes + hero transitions
  /// (Family Moments card → detail, Prediction Battle card → reveal).
  static const Duration transitionDuration = Duration(milliseconds: 300);
  static const Curve transitionCurve = Curves.easeOut;

  /// CELEBRATE — 600ms spring. Used ONLY for orchestrated celebration
  /// moments: Prediction Battle reveal (guesses animating into
  /// position sorted by proximity, winner highlighted last), badge
  /// unlock, streak milestone. Per Phase 2 brief: "one orchestrated
  /// moment per design — pick ONE, not spread animation effort thin."
  static const Duration celebrateDuration = Duration(milliseconds: 600);
  static const Curve celebrateCurve = Curves.elasticOut;

  /// Returns true if the user has requested reduced motion (via the
  /// platform accessibility setting). When true, screens should
  /// shorten or skip non-essential animations per Phase 6 brief
  /// ("Confirm reduced-motion is respected").
  static bool reducedMotion(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);
}

// ═══════════════════════════════════════════════════════════════════════
// SECTION 7 — APP PADDING
// ═══════════════════════════════════════════════════════════════════════
//
// Pre-built EdgeInsets for the most common padding patterns, anchored
// to AppSpacing. Saves every screen from inventing its own padding
// tuple.

class AppPadding {
  AppPadding._();

  /// Standard card padding = all 14. Used by AppCard.standard.
  static const EdgeInsets card = EdgeInsets.all(AppSpacing.cardPadding);

  /// Hero card padding = all 16. Used by AppCard.hero.
  static const EdgeInsets hero = EdgeInsets.all(AppSpacing.base);

  /// Compact list-row padding = horizontal 12 / vertical 10. Used by
  /// AppCard.compact.
  static const EdgeInsets compactRow =
      EdgeInsets.symmetric(horizontal: 12, vertical: 10);

  /// Screen horizontal margin = horizontal 16. Used on every page's
  /// outermost horizontal padding so all screens align column-to-column.
  static const EdgeInsets screenHorizontal =
      EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal);

  /// Section gap = vertical 24. Used between major sections on a
  /// scroll view.
  static const EdgeInsets sectionGap =
      EdgeInsets.symmetric(vertical: AppSpacing.sectionGap);
}

// ═══════════════════════════════════════════════════════════════════════
// SECTION 8 — APP ICON
// ═══════════════════════════════════════════════════════════════════════
//
// Single icon language: Material Symbols Outlined. The audit found
// emoji + Kolam dots + Material mixed on one screen. New code uses
// only Material icons via AppIcon.* — semantic, named, NOT raw
// `Icons.foo`.
//
// Per Phase 1 brief: "Confirm a single icon style/weight is used
// consistently (flame for streaks, trophy for achievements, target
// for Prediction Battle, heart/clap for reactions)".

class AppIcon {
  AppIcon._();

  /// Streaks — flame icon, orange tint.
  static const IconData streak = Icons.local_fire_department_outlined;

  /// Achievements — trophy icon, gold tint.
  static const IconData achievement = Icons.emoji_events_outlined;

  /// Prediction Battle — target icon, orange tint. (Material doesn't
  /// ship a `target_not_rounded` — `gps_fixed` is the existing icon
  /// used across the PB screens, kept for consistency.)
  static const IconData prediction = Icons.gps_fixed;

  /// Reactions (clap) — applause icon, orange tint on tap. (Material
  /// doesn't ship a `clap` icon — `sign_language_outlined` is the
  /// closest hand-related icon and reads well as a clap.)
  static const IconData clap = Icons.sign_language_outlined;

  /// Reactions (heart) — favorite icon, gold tint. (`Icons.favorite_outline`
  /// is the existing form used across the codebase — `favorite_outline_rounded`
  /// is not a Material Symbols name.)
  static const IconData heart = Icons.favorite_outline;

  /// Members — group icon.
  static const IconData members = Icons.people_outline_rounded;

  /// Games — controller icon.
  static const IconData games = Icons.sports_esports_outlined;

  /// Calendar — calendar icon.
  static const IconData calendar = Icons.calendar_today_outlined;

  /// Lists — checklist icon.
  static const IconData lists = Icons.checklist_rounded;

  /// Chat — chat bubble icon.
  static const IconData chat = Icons.chat_bubble_outline_rounded;

  /// Settings — gear icon.
  static const IconData settings = Icons.settings_outlined;

  /// Invite — person-add icon.
  static const IconData invite = Icons.person_add_outlined;

  /// History / recent — history icon.
  static const IconData history = Icons.history_rounded;

  /// Memories — photo library icon.
  static const IconData memories = Icons.photo_library_outlined;

  /// Oral history — microphone icon.
  static const IconData oralHistory = Icons.mic_none_rounded;
}

// ═══════════════════════════════════════════════════════════════════════
// MIGRATION TABLE — how existing card treatments map onto AppCard
// ═══════════════════════════════════════════════════════════════════════
//
// 1. FamilyStreakHeroCard      → AppCard.hero(accentColor: amber)
// 2. PlayWithCard              → AppCard.standard
// 3. QuickPickCard             → AppCard.standard
// 4. FamilyMomentCard (non-ms) → AppCard.standard
// 5. FamilyMomentCard (ms)     → AppCard.accented(accentColor: gold)
// 6. FamilyLeaderboardWidget   → flat + Divider (compact collapsed)
// 7. GamingRankRow (non-me)    → AppCard.compact
// 8. GamingRankRow (isMe)      → AppCard.activeMe()
// 9. GamingPodium slot         → AppCard.compact (with tier-color border)
// 10. PredictionBattleV1Card   → AppCard.hero(accentColor: orange)
// 11. CoinBalanceChip          → (chip, not a card — use AppColor.amberTint
//                                + hairline border + radius pill)
// 12. Rewards Treasury summary → AppCard.hero(accentColor: amber)
// 13. _RewardCard              → AppCard.standard
// 14. _RewardCard "Owned"      → (chip, success-tinted, radius sm)
// 15. _RewardCard "Redeem"     → (button, amber solid, radius sm)
