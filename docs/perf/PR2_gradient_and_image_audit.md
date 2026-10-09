# PR 2 — Gradient Migration + Image Decode Audit

**Issue**: [#98 — perf(flat): PR 2 — gradient migration script + image decode audit](https://github.com/buildwith-manish/Daxelo-Kinrel/issues/98)
**Branch**: `chore/pr98-image-decode-audit` (stacked on `perf/flat-gradients`)
**Date**: 2026-10-09
**Scope**: Two independent deliverables — (A) a one-shot codemod that migrates decorative gradients to `KinrelFx.gradient(...)` so flat mode drops them, and (B) a static audit script that flags image-decode call sites missing `cacheWidth` / `cacheHeight` / `ResizeImage`.

> Both scripts are idempotent and ship with `--help`, dry-run-by-default, JSON/MD output modes, and auto-detected repo root. Neither script touches Flutter source unless `--apply` is passed.

---

## A. Gradient migration script — `scripts/migrate_app_gradients.py`

### Why

PR #95 ("flat UI core switch + chat + graph") introduced the `KinrelFx` master switch (`lib/core/theme/kinrel_fx.dart`): when `RICH_FX` is unset (the default), `KinrelFx.gradient(g)` returns `null` and the caller's `BoxDecoration.color` takes over. PR #96 ("apply flat rules to the rest of the app") migrated the chat module. This script automates the same migration for the remaining feature modules so a future designer can flip the entire look with one `--dart-define`.

### Strategy

For every `.dart` file under `lib/features/` (excluding `lib/features/chat`, already done in #95, and `lib/graph`, done in #97):

1. Insert `import '../.../core/theme/kinrel_fx.dart';` if not already present (inserted immediately after the last `core/...` import to keep the import block grouped).
2. For every line whose first non-whitespace token is `gradient:`, wrap the gradient expression as `gradient: KinrelFx.gradient(<expr>),` — provided:
   - it is NOT already wrapped in `KinrelFx.gradient(`
   - it does NOT reference an exempt brand gradient (word-boundary match against `igniteGradient`, `ctaGradient`, `sunriseGradient`, `heritageGradient`, `wordmarkGradient`, `signOutGradient`, `signOutGradientDark`, `achievementGradient`)
   - it is NOT a `Paint()..shader =` / `createShader` line (CustomPainter context — must stay decorated)
   - it is NOT a `ShaderMask` `shaderCallback:` line
   - the expression is a single-line constructor call ending in `),` OR a simple identifier reference ending in `,` (multi-line expressions are skipped for manual review)

### Bug fixes vs. the initial commit on `perf/flat-gradients`

The first revision of the script (commit `b07278b5`) had four portability / correctness bugs. This branch fixes all four:

| # | Bug | Symptom | Fix |
|---|-----|--------|-----|
| 1 | **Hardcoded absolute `REPO_ROOT`** (`/home/z/my-project/workspace/Daxelo-Kinrel/Daxelo-Kinrel-App`) | Script only ran on the original author's machine; failed everywhere else (including CI) with `FileNotFoundError`. | `find_repo_root()` walks up from `__file__` until it finds `Daxelo-Kinrel-App/lib/features/`. Falls back to CWD. Override with `--repo-root`. |
| 2 | **Dead `is_exempt_gradient()` function** — defined but never called; the inline check `any(name in line for name in EXEMPT_GRADIENT_NAMES)` was a substring match that would skip a gradient if the line happened to mention `igniteGradient` in a comment. | Comment-only false exemptions. | Rewrote `is_exempt_gradient()` to strip `// ...` comments first, then word-boundary regex match. Actually called from `wrap_gradients()`. |
| 3 | **`ensure_import()` substring check `if "kinrel_fx.dart" in content`** — matched anywhere in the file, including a comment, a string literal, or a `kinrel_fx_test.dart` reference. | Import silently skipped when it shouldn't be. | Replaced with `re.search(r"""^\s*import\s+['"][^'"]*kinrel_fx\.dart['"]\s*;""", content, re.MULTILINE)` — only matches a real import statement. |
| 4 | **No const-context awareness** — wrapping `gradient: KinrelGradients.timelineGradient,` inside `const BoxDecoration(...)` produced `gradient: KinrelFx.gradient(KinrelGradients.timelineGradient),` — but `KinrelFx.gradient()` is a non-const static method, so the surrounding `const BoxDecoration` would no longer compile. | `flutter analyze` would fail with "Const variables must be constant value" on the 3 wrap sites that live inside const decorations. | `_strip_const_from_deco()` scans backwards up to 30 lines for `const BoxDecoration(` / `ShapeDecoration(` / `FlutterLogoDecoration(`, verifies the gradient line is INSIDE that decoration's body via paren-depth tracking, and strips the `const ` keyword from the opening line. 3 of 43 wraps trigger a const strip. |

Plus: `argparse` for `--apply` / `--repo-root` / `--format {text,json}` / `--help`, and a JSON output mode for CI artifacts.

### Dry-run results (against `main` @ `8ddcc749`)

```
$ python3 scripts/migrate_app_gradients.py
DRY RUN — 34 files, 43 gradient sites wrapped.
repo_root: /home/z/my-project/repos/Daxelo-Kinrel/Daxelo-Kinrel-App

  lib/features/hot_seat/presentation/hot_seat_screen.dart: 1 wrap (+import)
  lib/features/memories/presentation/memories_screen.dart: 2 wraps
  lib/features/relation_riddles/presentation/relation_riddle_screen.dart: 1 wrap (+import)
  lib/features/gaming_ecosystem/presentation/gaming_leaderboard_screen.dart: 1 wrap (+import)
  ... (30 more)
```

The script reports the file path + wrap count + whether the import was added. The dry-run output is stable across runs (idempotent — running it twice produces the same report).

### Applying the migration

```bash
# 1. Dry-run to review the proposed changes
python3 scripts/migrate_app_gradients.py
# 2. Apply in place
python3 scripts/migrate_app_gradients.py --apply
# 3. Verify with flutter analyze (the wraps are type-safe; KinrelFx.gradient
#    returns Gradient?, which BoxDecoration accepts)
cd Daxelo-Kinrel-App && flutter analyze lib/features
# 4. Commit
git add -A && git commit -m "perf(flat): apply gradient migration to lib/features"
```

> The script is intentionally conservative: multi-line gradient expressions and ternaries are skipped (logged for manual review) so a `--apply` run cannot produce broken code. The 43 single-line sites are all safe mechanical wraps.

### Exempt brand gradients

The following gradients are intentionally NOT migrated because they ARE the brand look (primary orange CTA, KINREL wordmark, achievement badge, sign-out button):

- `KinrelGradients.igniteGradient` (primary CTA)
- `KinrelGradients.ctaGradient` (secondary CTA)
- `KinrelGradients.sunriseGradient` (onboarding / hero)
- `KinrelGradients.heritageGradient` (about page)
- `KinrelGradients.wordmarkGradient` (KINREL logo)
- `KinrelGradients.signOutGradient` + `signOutGradientDark`
- `KinrelGradients.achievementGradient`

These are exempt at the **identifier level** (word-boundary regex), so a comment mentioning `igniteGradient` does NOT incorrectly suppress the migration of a different gradient on the same line.

---

## B. Image decode audit script — `scripts/audit_image_decode.py`

### Why

The Flutter `Image` widget decodes its source at **native resolution** by default. A 12 MP phone photo (4032×3024) loaded via `Image.network(url)` allocates a ~46 MB RGBA bitmap — even if it's shown in a 96×96 avatar. The decode step is the #1 cause of GPU memory spikes and jank on mid-tier Android.

Flutter ships two mitigations:
1. **`cacheWidth` / `cacheHeight`** on `Image.network`, `Image.asset`, `Image.memory`, `Image.file`, and `Image(image:...)` — the decode step allocates only the requested size.
2. **`ResizeImage(provider, width: w, height: h)`** — wraps a bare `NetworkImage` / `AssetImage` / `FileImage` / `MemoryImage` so it can be consumed by `DecorationImage`, `CircleAvatar(backgroundImage:)`, etc. (which don't accept `cacheWidth` directly).

The git log shows `cacheWidth` sweeps were done in `perf/raster` tiers E–L (commits `9ba6cdee`, `58f2d3cc`, etc.). This script is the **static audit** that catches regressions: any new `Image.network(url)` without `cacheWidth` added after the sweep is flagged.

### Rules

| Rule ID | Severity | Trigger | Suggestion |
|---------|----------|---------|------------|
| `image-direct-no-cache-width` | HIGH | `Image.network/asset/memory/file(...)` missing both `cacheWidth` AND `cacheHeight` (or `cacheWidth` alone — height auto-derived) | Pass `cacheWidth: <logical px>`. |
| `image-widget-no-cache-width` | HIGH | `Image(image: <provider>)` missing `cacheWidth` (the outer `Image()` can downscale even when the inner provider cannot) | Pass `cacheWidth: <logical px>` to the outer `Image()`. |
| `bare-provider-no-resize` | MEDIUM | `NetworkImage(url)` / `AssetImage(name)` / `FileImage(file)` / `MemoryImage(bytes)` NOT wrapped in `ResizeImage(...)` (would be consumed by `DecorationImage` / `CircleAvatar` / `Image(image:)` at native resolution) | Wrap in `ResizeImage(provider, width: w, height: h)`. Add `// audit-image-decode: ignore-file` at the top of the file for legitimate full-res use cases. |

### Skipped (to keep the signal-to-noise ratio high)

- `test/`, `integration_test/` — test fixtures don't need optimization
- `*_test.dart` files
- Generated: `*.g.dart`, `*.freezed.dart`, `*.gr.dart`
- Files with `// audit-image-decode: ignore-file` in the first 5 lines (escape hatch for legitimate full-res use)
- **Comment matches** — the script strips `//` and `/* */` comments before pattern-matching, so a doc comment mentioning `Image.memory(` is NOT flagged
- **`CachedNetworkImage(`** — word-boundary regex prevents the `NetworkImage(` rule from matching the `NetworkImage` substring inside `CachedNetworkImage` (which is a different class from the `cached_network_image` package and has its own `memCacheWidth` / `cacheWidth` parameter)

### Audit results (against `main` @ `8ddcc749`)

```
$ python3 scripts/audit_image_decode.py
=== Image Decode Audit ===
repo_root: /home/z/my-project/repos/Daxelo-Kinrel/Daxelo-Kinrel-App
files with findings: 16
total findings: 19
by severity: HIGH=8, MEDIUM=11, INFO=0
```

| Severity | Count | Notes |
|----------|-------|-------|
| HIGH | 8 | All `Image.file` / `Image.memory` calls in profile, stories, family, chat, cameo screens — these decode at native resolution. |
| MEDIUM | 11 | Bare `NetworkImage(...)` / `MemoryImage(...)` calls feeding `CircleAvatar(backgroundImage:)`, `DecorationImage`, and PDF rendering. |
| INFO | 0 | — |

**Top offenders (HIGH)** — these are the regressions to fix in a follow-up PR:

| File | Line | Call | Why it matters |
|------|------|------|----------------|
| `lib/features/profile/presentation/contact_support_screen.dart` | 432 | `Image.file(...)` | Bug-report attachment preview — could decode a 12 MP photo at full resolution. |
| `lib/features/profile/presentation/report_bug_screen.dart` | 514 | `Image.file(...)` | Same — bug report screenshot preview. |
| `lib/features/stories/presentation/add_story_sheet.dart` | 456, 485 | `Image.file(...)` ×2 | Story image picker — decodes the full camera roll photo. |
| `lib/features/family/presentation/widgets/memory_crop_editor.dart` | 350 | `Image.memory(...)` | Memory crop editor — decodes the full-res bytes before the crop is applied. |
| `lib/features/family/presentation/widgets/image_crop_editor.dart` | 196 | `Image.memory(...)` | Same — generic image crop editor. |
| `lib/features/chat/presentation/widgets/wallpaper_image_native.dart` | 20 | `Image.file(...)` | Chat wallpaper picker — decodes at native res. |
| `lib/features/cameo/presentation/b1_verification_screen.dart` | 617 | `Image.memory(b, width: 128, height: 128, ...)` | Verification screen — has `width:`/`height:` (display dims) but NOT `cacheWidth` (decode dims). |

### Output formats

```bash
# Text (default) — for terminal
python3 scripts/audit_image_decode.py
# JSON — for CI gating (exits non-zero on HIGH findings)
python3 scripts/audit_image_decode.py --format json > audit.json
# Markdown — for PR description
python3 scripts/audit_image_decode.py --format md > docs/perf/image-decode-audit.md
```

The JSON and MD formats include the file path, line, column, rule ID, snippet, and remediation suggestion for every finding.

---

## Next steps

1. **Merge this PR** to land both scripts. The migration script is dry-run-by-default — running it accidentally is a no-op.
2. **Apply the gradient migration** in a separate commit on top of this PR: `python3 scripts/migrate_app_gradients.py --apply && flutter analyze lib/features`. The 43 wraps are mechanical and safe.
3. **Triage the 8 HIGH image-decode findings** — these are the high-ROI fixes (each one prevents a 40+ MB allocation on the Android graphics thread). Suggested order: stories > profile (bug report) > chat wallpaper > family crop editors > cameo verification.
4. **Wire the audit into CI** — add a step to `.github/workflows/perf-gate.yml`:
   ```yaml
   - name: Image decode audit (HIGH findings fail)
     working-directory: Daxelo-Kinrel-App
     run: python3 ../scripts/audit_image_decode.py --format json
   ```
   The script exits non-zero on HIGH findings, so this becomes a regression gate.

---

## Reproducing this report

```bash
git checkout chore/pr98-image-decode-audit
# Gradient migration (dry-run):
python3 scripts/migrate_app_gradients.py
# Image decode audit:
python3 scripts/audit_image_decode.py
# Markdown audit report:
python3 scripts/audit_image_decode.py --format md
```

Both scripts auto-detect the repo root from `__file__`. Override with `--repo-root /path/to/Daxelo-Kinrel-App` if invoked out-of-tree.
