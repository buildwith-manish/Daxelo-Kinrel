# Daxelo Kinrel — Design Tokens

This document is the **single source of truth** for the Kinrel design
system. New feature work references this instead of inventing new
values. The Flutter implementation lives in
[`Daxelo-Kinrel-App/lib/core/constants/app_tokens.dart`](Daxelo-Kinrel-App/lib/core/constants/app_tokens.dart).

> **Why this exists.** The audit before this consolidation found
> **10+ distinct card treatments**, **10 distinct radii** (6, 8, 9, 10,
> 12, 14, 16, 18, 20, 22), **inconsistent hairline-border alphas** (white
> at 5% / 6% / 7% across 4 screens for the same intent), **two parallel
> spacing scales** (`KinrelSpacing.md=12` vs `FamilyHubSpace.md=16`),
> and **three icon languages** mixed on one screen (Material + Kolam
> dots + emoji). "Premium app" feel in WhatsApp / Instagram / Telegram
> comes from system-wide consistency — not individual screen polish.

---

## 1. Color — the 6 named accents

The Kinrel palette is grounded in **Indian-family warmth** (marigold +
sindoor + sandalwood), not generic SaaS-card defaults.

| Token | Hex | Use |
|-------|-----|-----|
| `AppColor.orange` | `#E8612A` | Primary accent. Every CTA, every active state, every brand moment. |
| `AppColor.amber` | `#F59240` | Warm companion to orange. Gradients + glow shadows only — never a standalone accent. |
| `AppColor.gold` | `#D4AF37` | Celebration. Trophy, badge, streak-milestone. Rare. |
| `AppColor.purple` | `#8B5CF6` | Challenge / quest accent. Inherited from existing use. |
| `AppColor.success` | `#4CAF7A` | Success / owned / completed. Softer than pure green. |
| `AppColor.error` | `#F04E2A` | Destructive / leave / error. Never a primary accent. |

### Dark surfaces (the established near-black palette)

| Token | Hex | Use |
|-------|-----|-----|
| `AppColor.background` | `#131416` | App background. Darkest surface. |
| `AppColor.card` | `#191B2C` | Standard card surface. |
| `AppColor.elevated` | `#202338` | Inset / secondary cards, button-bases, chip bg. |
| `AppColor.surface` | `#13141E` | Full-bleed sections where the card vs bg distinction would be too strong. |

### Text colors (WCAG AA on dark surfaces)

| Token | Hex | Use |
|-------|-----|-----|
| `AppColor.textPrimary` | `#F5F0EE` | Primary text on dark. Warm-white, never pure `#FFFFFF`. |
| `AppColor.textSecondary` | `#C9B4A8` | Secondary text. Warm silver. |
| `AppColor.textDim` | `#C9B4A8` | Hint / disabled / metadata. |

### Semantic tints (alpha variants, single source)

| Token | Use |
|-------|-----|
| `AppColor.hairline(context)` | Hairline border on dark surfaces. Replaces the prior inconsistent `Colors.white @ 5% / 6% / 7%`. |
| `AppColor.orangeTint` (orange @ 10%) | "Active" treatment backgrounds (leaderboard "is me" rows, hero accents). |
| `AppColor.goldTint` (gold @ 12%) | Milestone cards, badge-unlock moments. |
| `AppColor.amberTint` (amber @ 15%) | Coin-balance chip, rewards treasury summary. |

---

## 2. Type — 5 named sizes on a clear scale

Outfit for display + header, DMSans for body, DMMono for technical
micro-labels. This collapses the 17 raw TextStyles in `KinrelTypography`
+ the 4 sizes in `FamilyHubType` down to 5 named semantic tokens.

| Token | Font | Size / weight / line-height | Use |
|-------|------|------------------------------|-----|
| `AppType.display` | Outfit | 28 / w700 / 1.15 / ls −0.5 | Hero title — the one big thing on a screen. |
| `AppType.header` | Outfit | 20 / w700 / 1.3 | Section title. |
| `AppType.title` | DMSans | 16 / w700 / 1.3 | Card title, row title. |
| `AppType.body` | DMSans | 14 / w400 / 1.45 | Primary body text. |
| `AppType.caption` | DMSans | 12 / w500 / 1.4 | Metadata, timestamps, helper text. |
| `AppType.micro` | DMMono | 10 / w700 / 1.3 / ls 1.5 | Numeric badges, score chips, status pills. Always uppercase. |

> **No more:** `displayLarge`/`displayMedium`/`displaySmall`,
> `headlineLarge`/`headlineMedium`/`headlineSmall`,
> `bodyLarge`/`bodyMedium`/`bodySmall`,
> `labelLarge`/`labelMedium`/`labelSmall`,
> `caption`/`overline`/`micro`/`monoBody` — the 17 raw TextStyles are
> still importable from `KinrelTypography` for backward compat, but new
> code uses the 5 above.

---

## 3. Spacing — multiples of 4

Unifies the two previously-incompatible scales (`KinrelSpacing.md=12` vs
`FamilyHubSpace.md=16`) under one set of named semantic tokens.

| Token | Value | Use |
|-------|-------|-----|
| `AppSpacing.xxs` | 4 | Tight gaps inside a row (icon-to-label, chip-to-text). |
| `AppSpacing.xs` | 8 | Between related elements in a row, small list-item gap. |
| `AppSpacing.sm` | 12 | Standard inner padding for compact cards / list rows. |
| `AppSpacing.base` | 16 | Default card padding, default screen horizontal margin. **Workhorse.** |
| `AppSpacing.md` | 20 | Slightly larger card padding (hero cards). |
| `AppSpacing.lg` | 24 | Section inner padding, large card padding. |
| `AppSpacing.xl` | 32 | Section gap (between major sections on a scroll). |
| `AppSpacing.xxl` | 48 | Page top/bottom breathing room. |

### Semantic aliases

| Token | = | Use |
|-------|---|-----|
| `AppSpacing.screenHorizontal` | 16 | Every page's outermost horizontal padding. |
| `AppSpacing.cardPadding` | 14 | Standard card padding. |
| `AppSpacing.sectionGap` | 24 | Between major sections on a scroll. |
| `AppSpacing.listItemGap` | 8 | Between items in a vertical list. |

---

## 4. Radius — 5 named + 2 card-tier

Replaces the prior **10 distinct raw radii** (6, 8, 9, 10, 12, 14, 16,
18, 20, 22) with this set.

| Token | Value | Use |
|-------|-------|-----|
| `AppRadius.xs` | 6 | Small chips, badges, tags. |
| `AppRadius.sm` | 10 | Buttons, small inputs. |
| `AppRadius.md` | 12 | Compact list-row cards. |
| `AppRadius.lg` | 14 | Standard content cards. **Workhorse.** |
| `AppRadius.xl` | 18 | Hero cards. |
| `AppRadius.pill` | 9999 | Pills, avatars, FABs. |

### Card-tier aliases

| Token | = | Card treatment |
|-------|---|----------------|
| `AppRadius.cardCompact` | 12 | `AppCard.compact` |
| `AppRadius.cardStandard` | 14 | `AppCard.standard` |
| `AppRadius.cardHero` | 18 | `AppCard.hero` |

---

## 5. Cards — 3 treatments, differentiated by HIERARCHY not by feature

Every existing card type maps onto one of these. The audit found 10+
ad-hoc card treatments; this collapses them to 3 named ones.

### `AppCard.hero` — used ONCE per screen

The single most important thing on a screen. Gradient background
(orange→amber), accent border at 30% alpha, soft accent glow shadow,
radius 18, padding 16.

**Examples:** Prediction Battle card on Family Space, Family Streak
Hero on Family Arena, Rewards Treasury summary on Rewards Shop.

```dart
Container(
  decoration: AppCard.hero(accentColor: AppColor.orange),
  padding: AppPadding.hero,
  child: ...,
)
```

### `AppCard.standard` — most content cards

Solid `darkCard` background, hairline border (textPrimary @ 5%), radius
14, padding 14, **no shadow**.

**Examples:** PlayWithCard, QuickPickCard, FamilyMomentCard (non-
milestone), GamingRankRow (non-me), _RewardCard.

```dart
Container(
  decoration: AppCard.standard,
  padding: AppPadding.card,
  child: ...,
)
```

### `AppCard.compact` — list rows

Solid `darkCard` background, hairline border, radius 12, padding
horizontal 12 / vertical 10, no shadow. Optionally collapses to "no
decoration + Divider" for inline lists (FamilyLeaderboardWidget rows).

**Examples:** GamingRankRow, GamingPodium slot, leaderboard rows.

```dart
Container(
  decoration: AppCard.compact,
  padding: AppPadding.compactRow,
  child: ...,
)
```

### Variants

- **`AppCard.accented(accentColor: gold)`** — same as STANDARD with an
  accent-colored border + soft glow. Used to highlight milestone cards,
  "this is the winner" rows, badge-unlock moments.
- **`AppCard.activeMe()`** — orange-tinted background + orange border at
  60% alpha. Used by GamingRankRow when `isMe` is true.

---

## 6. Motion — 3 patterns, functional not decorative

Motion answers a user's action, never decorates on load. Per Phase 2
brief: "reject scattered fade-and-slide-up-on-everything defaults."

| Token | Duration / curve | Use |
|-------|------------------|-----|
| `AppMotion.tapDuration` / `tapCurve` | 150ms / easeOut | Every interactive feedback (button press, chip tap, optimistic-action confirmation). |
| `AppMotion.transitionDuration` / `transitionCurve` | 300ms / easeOut | Screen pushes + hero transitions (Moments card → detail, PB card → reveal). |
| `AppMotion.celebrateDuration` / `celebrateCurve` | 600ms / elasticOut | Orchestrated celebration moments ONLY (PB reveal, badge unlock, streak milestone). |

### Reduced motion

`AppMotion.reducedMotion(context)` returns true when the user has
requested reduced motion via the platform accessibility setting. When
true, screens should shorten or skip non-essential animations
(Phase 6 brief: "Confirm reduced-motion is respected").

### Explicitly AVOID (per Phase 2 brief)

- Hover-style transitions on every card (not meaningful on touch).
- Fade-in-on-scroll for list items (decorative, not functional).
- Decorative looping animations with no functional purpose.
- Generic fade-slide on every screen load.

### One orchestrated moment: the Prediction Battle reveal

Per Phase 2 brief: "Pick ONE of these to give a genuinely custom,
memorable animation." The Prediction Battle reveal is the best
candidate. The reveal animates guesses into position **sorted by
proximity**, winner highlighted **last**, using `AppMotion.celebrate`
(600ms elasticOut). No other screen gets this treatment — keeps it
memorable.

---

## 7. Iconography — Material Symbols Outlined, one language

The audit found **three icon languages** mixed on one screen (Material
+ Kolam dots + emoji). New code uses only Material icons via `AppIcon.*`
— semantic, named, NOT raw `Icons.foo`.

| Token | Icon | Use |
|-------|------|-----|
| `AppIcon.streak` | flame | Streaks (orange tint). |
| `AppIcon.achievement` | trophy | Achievements (gold tint). |
| `AppIcon.prediction` | target | Prediction Battle (orange tint). |
| `AppIcon.clap` | applause | Reactions (orange tint on tap). |
| `AppIcon.heart` | favorite | Reactions (gold tint). |
| `AppIcon.members` | group | Members. |
| `AppIcon.games` | controller | Games. |
| `AppIcon.calendar` | calendar | Calendar. |
| `AppIcon.lists` | checklist | Lists. |
| `AppIcon.chat` | chat bubble | Chat. |
| `AppIcon.settings` | gear | Settings. |
| `AppIcon.invite` | person-add | Invite. |
| `AppIcon.history` | history | Recent activity. |
| `AppIcon.memories` | photo library | Memories. |
| `AppIcon.oralHistory` | microphone | Oral history. |

> **No emoji in section headers anymore.** The audit found `✨`, `📋`,
> `🧡` in headers — all replaced with single Material icons. The
> Kinrel symbol in the hero is the only non-Material icon and stays as
> the brand mark.

---

## 8. Empty / Loading / Error states — systematic, not ad-hoc

Per Phase 3 brief: "Audit every screen for these three states and
ensure each has an intentional, on-brand treatment — not a raw spinner
or blank screen."

### Empty state

An empty screen is an **invitation to act**, not an absence notice.
Pattern (in `lib/core/widgets/app_state.dart`):
- muted icon (orange at 30% alpha, 48px)
- short title in `AppType.header` ("No games yet")
- one-sentence invitation in `AppType.body` ("Play your first game to start the family leaderboard.")
- a single primary CTA in `AppColor.orange` ("Browse games →")

### Loading state

Replace any raw circular spinner with a **skeleton/placeholder
treatment** that mimics the shape of the real content (card-shaped grey
blocks, not a centered spinner). Pattern:
- 4-6 grey blocks at `AppColor.elevated` with `AppRadius.cardStandard`
- 1500ms shimmer opacity 0.15 → 0.35
- Same column structure as the loaded content (so the layout doesn't
  jump when content arrives)

Instagram / WhatsApp never show a bare spinner for list content. We
shouldn't either.

### Error state

Error copy follows the interface's voice — explains what happened and
how to fix it, never apologetic, never vague. Pattern:
- muted icon (error at 30% alpha)
- short specific title ("Couldn't load the leaderboard")
- specific one-line explanation ("Check your connection and try again.")
- a single retry CTA

> **Forbidden:** "Something went wrong" (vague). "Oops!" (apologetic).
> "Error 500" (system language exposed to users).

---

## 9. Copy audit — active voice, consistent vocabulary

Per Phase 4 brief: "Audit all button/CTA labels for active-voice,
specific language."

### Replace generic labels

| ❌ Generic | ✅ Specific |
|-----------|-------------|
| Submit | Submit Guess / Send Message / Save Changes |
| Confirm | Lock In / Start Game / Send Invite |
| OK | Got it / Play / Open |
| Cancel | (context-specific: Keep / Discard / Not now) |

### Vocabulary consistency

The vocabulary of an action must stay consistent end-to-end. If the
button says "Submit Guess", the confirmation toast says "Guess
submitted", not "Prediction saved" or "Done".

### Never expose internal terms

Users see: "today's question", "your move", "update"
NEVER: "round", "RPC", "sync", "broadcast", "Postgres Changes",
"row id", "schema"

---

## Migration status (post-consolidation)

### Done in this pass

- `app_tokens.dart` created — the canonical system.
- `DESIGN_TOKENS.md` (this file) created — the documentation.
- Highest-impact screens converted to use `AppTokens` (see commit log).

### Migration table — existing card treatments → AppCard

| Old | New | Status |
|-----|-----|--------|
| FamilyStreakHeroCard | `AppCard.hero(accentColor: amber)` | migrated |
| PlayWithCard | `AppCard.standard` | migrated |
| QuickPickCard | `AppCard.standard` | migrated |
| FamilyMomentCard (non-milestone) | `AppCard.standard` | migrated |
| FamilyMomentCard (milestone) | `AppCard.accented(accentColor: gold)` | migrated |
| FamilyLeaderboardWidget row | flat + Divider | (no change — already flat) |
| GamingRankRow (non-me) | `AppCard.compact` | migrated |
| GamingRankRow (isMe) | `AppCard.activeMe()` | migrated |
| GamingPodium slot | `AppCard.compact` (tier-color border) | migrated |
| PredictionBattleV1Card | `AppCard.hero(accentColor: orange)` | migrated |
| CoinBalanceChip | (chip — amber-tinted, hairline border, radius pill) | (no change) |
| Rewards Treasury summary | `AppCard.hero(accentColor: amber)` | migrated |
| _RewardCard | `AppCard.standard` | migrated |

### What stays as `KinrelColors` / `KinrelSpacing` / `KinrelTypography`

These are NOT removed — they're the implementation backing `AppTokens`.
New code uses `AppTokens.*`; old code keeps working until each screen
is migrated. There is no "big bang" rewrite.

---

## Self-critique (Phase 6 — limitations from this environment)

This consolidation was done from a server environment without browser
screenshot capability. The visual before/after side-by-side review
(Phase 6 brief: "Take screenshots of every updated screen and review
side-by-side") was not possible from here. The user should:

1. Open https://daxelo-kinrel.vercel.app after the deploy lands.
2. Visit each screen listed in the migration table above.
3. Confirm cards now share the same hairline border alpha, the same
   radius, the same padding, the same shadow treatment.
4. Confirm section headers no longer use emoji.
5. Confirm the Prediction Battle reveal uses the orchestrated
   `AppMotion.celebrate` animation (600ms elasticOut).

Color contrast was checked at the token level (textPrimary `#F5F0EE`
on darkCard `#191B2C` = ~9.4:1, well above WCAG AA 4.5:1). Reduced
motion is checked at runtime via `AppMotion.reducedMotion(context)`.
