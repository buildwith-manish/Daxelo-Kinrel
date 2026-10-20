# Raster Cost Inventory (Phase 4)

**Date:** 2026-10-20

## BackdropFilter + ImageFilter.blur (4 real usages)

| File:Line | Sigma | In scroll? | Notes |
|-----------|-------|------------|-------|
| `lib/core/theme/kinrel_fx.dart:109` | variable (KinrelFx) | no (static surfaces) | KinrelGlass — already tier-aware |
| `lib/core/theme/kinrel_fx.dart:116` | variable | no | Same widget, fallback path |
| `lib/features/family/presentation/widgets/stats_panel.dart:208` | `blurSigma` | no (bottom bar) | Stats panel — static, not scroll |
| `lib/shared/widgets/dk_components.dart:1100` | `blurSigma` | no (card surfaces) | DK components |

**Chat background blur** (`lib/features/chat/presentation/widgets/chat_background.dart:265,289`) — inside a scroll area. Uses `ImageFilter.blur` for the chat wallpaper. This is the most expensive blur in the app because it's behind a scrolling list.

**Family insights blur** (`lib/features/family/presentation/widgets/family_insights_dashboard.dart:121`) — static dashboard, not scroll.

## saveLayer (2 usages)

| File:Line | In scroll? | Notes |
|-----------|------------|-------|
| `lib/core/utils/shader_warmup.dart:169` | no (warmup only) | Pre-warms the blur shader — do NOT touch |
| `lib/features/games/memorymatch/memorymatch_card_faces.dart:170` | no (game card) | Game card flip animation — keep |

## Opacity widgets (38 real usages, top 20 shown)

Most are in non-scroll contexts (game screens, overlays, premium cards). The ones in scroll areas are the priority targets:

| File:Line | In scroll? | Replacement |
|-----------|------------|-------------|
| `lib/features/family/presentation/path_finder_screen.dart:393,413` | yes (list) | `Color.withValues(alpha:)` on the child |
| `lib/features/gamification/presentation/achievements_screen.dart:957` | yes (list) | `Color.withValues(alpha:)` |
| `lib/features/family/presentation/person_detail_sheet.dart:1442` | no (sheet) | `AnimatedOpacity` or `Color.withValues` |
| `lib/features/family/presentation/premium/hero_section.dart:194,289,329` | no (hero) | `Color.withValues` |

## BoxShadow (314 usages — too many to list individually)

The priority is shadows inside **list items** (ListView.builder children). Most shadows are in:
- Card widgets (`dk_components.dart`, `feed_post_card.dart`)
- Chat bubbles (`message_bubble.dart`)
- Game tiles

**Rule applied:** inside list items, use at most one cheap shadow (blurRadius <= 8) or none. Keep hero cards and primary buttons as-is.

## Action plan

1. Build `KinrelGlass` widget in `kinrel_fx.dart` — tier-aware: real `BackdropFilter` on high + non-scroll; solid translucent fill on mid/low + scroll.
2. Replace `Opacity(` with `Color.withValues(alpha:)` where static, `AnimatedOpacity` where animated.
3. Remove `saveLayer` from `bounce_button.dart` (use `Transform.scale` only).
4. Cap list-item shadows at `blurRadius: 8`.
