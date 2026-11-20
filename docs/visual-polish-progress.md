# Visual polish progress

Branch: `fix/visual-polish` (Flutter app only, `Daxelo-Kinrel-App/lib/**`).
Status values: `not started` | `in progress (<resume note>)` | `done (merged <sha>)`.

## Findings read before starting

- Canonical tokens live in `lib/core/constants/brand_colors.dart` (`KinrelColors`, `KinrelGradients`),
  `brand_typography.dart`, `brand_spacing.dart`, `app_tokens.dart` (NOT under `lib/core/theme/`).
  `lib/core/theme/app_theme.dart` holds `KinrelThemeExtension`, which is built from `KinrelColors`.
- Access pattern actually used app-wide: `KinrelColors.<token>` static consts (410 files).
  `Theme.of(context).extension<KinrelThemeExtension>()` is used in **zero** files outside its definition,
  so Part 1 uses `KinrelColors.*` (no new access pattern invented).
- Baseline: `Flutter Analyze` was RED on main (10 pre-existing warnings in
  `chat/presentation/widgets/family_event_card.dart` and `blocked_message_placeholder.dart`:
  dead `?? 0` on non-nullable ints, missing `const`). Fixed in the first commit on this branch so
  CI can go green; this is the only change outside the four parts.
- Other CI jobs (Backend CI, Flutter Test) were red/cancelled on the base before this branch;
  see per-part notes for what was actually observed.

## Part 1 - color token sweep
Status: not started
Files touched: (none yet)
Ambiguous / needs human look: (none yet)

## Part 2 - loading-state standardization
Status: not started
Files touched: (none yet)

## Part 3 - accessibility pass
Status: not started
Files touched: (none yet)
Contrast failures for design decision: (none yet)
Fixed-height containers that would clip under text scale: (none yet)

## Part 4 - flourishes
Status: not started
Files touched: (none yet)
