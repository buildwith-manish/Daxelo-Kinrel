# Performance & Smoothness Pass — Baseline Report (Step 1)

**Branch**: `perf/smoothness-pass` (created from `main` at `938e8c34`)
**Date**: 2026-09-20
**Environment**: Local Linux x64 (Flutter 3.44.2 installed at `/home/z/flutter-sdk/flutter`)

---

## 1. Flutter SDK version + Impeller status

| Item | Value |
|------|-------|
| Flutter SDK | **3.44.2** (channel stable, revision `c9a6c48423`, 2026-06-10) |
| Dart | 3.12.2 |
| CI pin (`.github/workflows/ci.yml`, `deploy-web.yml`) | `3.44.2` ✅ matches local |
| Impeller on Android | **ON by default** (Flutter ≥3.27 enables Impeller on Android; 3.44.2 is well past that) |
| Impeller on iOS | **ON by default** (Flutter ≥3.10 enables Impeller on iOS) |
| `AndroidManifest.xml` Impeller metadata | None — app relies on the Flutter 3.44.2 default (Impeller enabled) |
| `ios/Runner/Info.plist` `FLTEnableImpeller` | None (no iOS folder in this checkout — iOS config not inspectable) |

**Conclusion**: Impeller is already the active renderer on both platforms for this Flutter version. No action needed.

---

## 2. APK size + breakdown

**Could not run locally** — `flutter build apk --analyze-size` requires:
- Android SDK (not installed: `No Android SDK found. Try setting the ANDROID_HOME environment variable.`)
- Native build toolchain for `thermion_dart` (clang/cmake/ninja — see section 7)

**Proxy from CI**: The most recent successful `Build Signed Release APK` run on commit `938e8c34` (run ID 35512415168) produced a web build artifact of **32.9 MB** (33,922,557 bytes). The APK build itself failed (same native-toolchain issue affects the size-analyze step). Recommend running `flutter build apk --analyze-size` in your local dev env to capture the APK size baseline before step 5 (image loading) so we can compare the before/after.

---

## 3. `flutter analyze` baseline (warning count)

**Ran locally** (with build_runner code-gen completed):

```
1383 issues found. (ran in 47.9s)
```

**Breakdown by severity**:
- Errors: **0**
- Warnings: **0**
- Infos: **1382** (one line is the summary)

**Breakdown by lint rule (top 20)**:

| Count | Lint rule |
|------:|-----------|
| 500 | `sort_constructors_first` |
| 241 | `unawaited_futures` |
| 231 | `deprecated_member_use` |
| 80 | `avoid_print` |
| 60 | `use_build_context_synchronously` |
| 51 | `unintended_html_in_doc_comment` |
| 51 | `curly_braces_in_flow_control_structures` |
| 27 | `no_leading_underscores_for_local_identifiers` |
| 25 | `prefer_final_locals` |
| 17 | `prefer_initializing_formals` |
| 16 | `unnecessary_brace_in_string_interps` |
| 13 | `camel_case_types` |
| 9 | `prefer_final_fields` |
| 7 | `prefer_single_quotes` |
| 7 | `prefer_interpolation_to_compose_strings` |
| 6 | `use_key_in_widget_constructors` |
| 5 | `depend_on_referenced_packages` |
| 4 | `prefer_conditional_assignment` |
| 4 | `avoid_web_libraries_in_flutter` |
| 3 | `dangling_library_doc_comments` |

### ⚠️ Step 8 prerequisite finding — `prefer_const_constructors` is DISABLED

`analysis_options.yaml` currently has:

```yaml
linter:
  rules:
    prefer_const_constructors: false        # ← disabled
    prefer_const_declarations: false        # ← disabled
    prefer_const_constructors_in_immutables: false  # ← disabled
    unnecessary_const: false                # ← disabled

analyzer:
  errors:
    prefer_const_constructors: ignore       # ← also ignored at analyzer level
    prefer_const_declarations: ignore
    prefer_const_constructors_in_immutables: ignore
    unnecessary_const: ignore
```

The user's step 8 says *"Confirm prefer_const_constructors and prefer_const_literals_to_create_immutables are enabled in analysis_options.yaml"*. They are **NOT** enabled — they are explicitly disabled and ignored. Enabling them would surface a very large number of new lints across the codebase (likely 1000+), so step 8 needs a decision: either (a) enable the rules and fix hot widgets only, accepting that the lint count will go UP before it goes down, or (b) leave the rules disabled and skip the const-constructor pass entirely. **Flagging this for your decision before step 8.**

---

## 4. `flutter test` baseline

**Could not run locally** — `flutter test` fails with:

```
System not configured correctly: No compiler configured on host 'linux_x64' with target 'linux_x64'.
...
Building native assets failed.
```

This is the `thermion_dart` package (3D rendering, used by the Kinrel Cameo feature) requiring clang/cmake/ninja — none of which can be installed in this sandbox (no sudo, no apt write access). The CI workflow (`ci.yml → flutter-test` job) installs them via `sudo apt-get install -y clang cmake ninja-build libdrm-dev libgbm-dev libegl-dev libgl-dev libgles-dev libc++-19-dev ...` so tests run successfully on GitHub Actions.

**Test verification strategy for this branch**: each push to `perf/smoothness-pass` will trigger the `CI` workflow which runs both `flutter analyze --no-fatal-infos` and `flutter test`. I will check the CI results on each commit and report pass/fail in the worklog. If `flutter test` fails on a commit, I will treat it as a regression and fix before moving on.

---

## 5. Supabase dashboard info (read/write pattern proxy)

Used the Supabase Management API + REST API with the service-role key to query table row counts and identify the hot-path tables/RPCs for the 3 confirmed games.

### Table row counts (proxy for current write volume)

| Table | Rows |
|-------|-----:|
| `stickman_heist_games` | 5 |
| `stickman_heist_players` | 7 |
| `tugofwar_games` | 0 |
| `tugofwar_players` | (table exists, 0 rows in current dataset) |
| `ghost_painter_rounds` | 0 |
| `ghost_painter_strokes` | (table exists) |
| `ghost_painter_guesses` | (table exists) |

### Hot-path DB calls per game (current state, after recent migrations)

**stickman_heist** — **ALREADY MIGRATED to Broadcast** (commit `aa46b5a9`, merged via PR #68 on 2026-09-20). Verified:
- `grep -c "Timer.periodic.*_input" stickman_heist_provider.dart` = 0 (no input polling)
- `grep -c "sendBroadcastMessage\|onBroadcast" stickman_heist_provider.dart` = 16 (Broadcast in use)
- Per the commit message: ~110 DB ops/sec per match → ~0 DB ops/sec in steady state. Only durable calls remaining: createGame/joinGame/leaveGame/startGame + ONE final `fn_stickmanheist_broadcast_state` RPC at match completion to persist winnerUserIds + endReason + completedAt + status.

**tugofwar** — **NOT migrated**. Current hot-path DB calls:
- DB WRITE: `client.rpc('fn_tugofwar_pull', params: {p_game_id, p_taps})` every **400ms** (2.5 writes/sec per player) — taps are batched client-side and flushed via this RPC
- DB READ: state arrives via `onPostgresChanges` listener on `tugofwar_games` + `tugofwar_players` (already pub/sub, NOT a poll — good)
- Per match at 4 players: ~10 DB writes/sec from `fn_tugofwar_pull` calls
- The 2s `_watchdogTimer` is local-only (no DB calls) — fine

**ghost_painter** — **NOT migrated**. Current hot-path DB calls:
- DB WRITE: `client.from('ghost_painter_strokes').insert(batch)` every **100ms** while drawing (drawer's strokes batched into the `ghost_painter_strokes` table)
- DB READ: strokes + guesses + rounds arrive via 4× `onPostgresChanges` listeners (already pub/sub, NOT a poll — good)
- Per active drawing round: ~10 DB writes/sec from stroke flushes
- The 1s `_countdownTimer` is local-only (no DB calls) — fine

### Migration scope for step 3 (after your go-ahead)

| Game | Hot-path DB call to remove | Replace with | Estimated DB ops/sec savings per match |
|------|---------------------------|--------------|----------------------------------------|
| tugofwar | `fn_tugofwar_pull` RPC every 400ms | `channel.sendBroadcastMessage('tap', {taps, team})` every 400ms — host tallies locally and broadcasts `state` every 200ms | ~10 → 0 |
| ghost_painter | `ghost_painter_strokes` insert every 100ms | `channel.sendBroadcastMessage('stroke', {points, seq})` every 100ms — host (drawer) broadcasts, guessers render directly | ~10 → 0 |

---

## 6. ⚠️ Critical findings about prior work — please read before step 2/3/4

While gathering the baseline, I discovered that **two prior commits on main have already done parts of the requested work**. This changes the scope:

### Commit `aa46b5a9` — "perf(stickman_heist,sos,bingo): migrate hot-path DB-polling to Realtime Broadcast (Item 2 batch 1)"

Merged via PR #68 on 2026-09-20 (today, ~3 hours before this session). Files changed (5 files, +290/-123 lines):
- `lib/features/games/stickman_heist/stickman_heist_provider.dart` — **stickman_heist fully migrated to Broadcast** (your step 2 ✅ DONE)
- `lib/features/games/stickman_heist/stickman_heist_engine.dart` — engine changes to support Broadcast
- `lib/features/games/stickman_heist/stickman_heist_models.dart` — model changes
- `lib/features/games/sos/sos_provider.dart` — sos lobby poll removed (your step 4 "Category B sos_provider 5s lobby poll" ✅ DONE — but migrated to Broadcast, not just deleted)
- `lib/features/games/bingo/bingo_provider.dart` — bingo safety poll removed (your step 4 "Category B bingo_provider 10s safety poll" ✅ DONE — but migrated to Broadcast, not just deleted)

### Commit `cd75d330` — "perf(sync,notifications): remove duplicate polling timers + dead code (Item 7 P0/P2)"

Files changed (3 files, +19/-164 lines):
- `lib/core/database/sync/sync_engine.dart` — duplicate 5-min sync timer removed (your step 4 "sync_engine.dart:454" ✅ DONE)
- `lib/core/database/sync/sync_service.dart` — **deleted entirely** (your step 4 "Delete sync_service.dart entirely" ✅ DONE)
- `lib/features/notifications/presentation/notifications_screen.dart` — duplicate 10s timer removed (your step 4 "notifications_screen.dart:84" ✅ DONE)

### What this means for the remaining steps

| User's step | Status | Action |
|-------------|--------|--------|
| Step 1 (baseline) | Done in this report | — |
| **Step 2 (stickman_heist → Broadcast)** | **✅ ALREADY DONE** in `aa46b5a9` | Skip — no work needed. Manual playtest still recommended. |
| Step 3a (tugofwar → Broadcast) | NOT done | Proceed after your go-ahead |
| Step 3b (ghost_painter → Broadcast) | NOT done | Proceed after your go-ahead |
| Step 4 (delete dead/duplicate timers) | **✅ ALREADY DONE** for sync_engine, sync_service, notifications_screen, sos_provider, bingo_provider | Verify only — no code changes needed |
| Step 5 (image loading) | NOT done | Proceed |
| Step 6 (list rendering) | NOT done | Proceed |
| Step 7 (main-thread work) | NOT done | Proceed |
| Step 8 (const constructors) | NOT done, **but rules are disabled** | Decision needed (see section 3 above) |
| Step 9 (audit truthordare) | NOT done | Proceed |

### Recommended next actions

Given the above, I recommend we **skip step 2 entirely** (stickman_heist is done) and **skip step 4** (all 5 items are done) and proceed directly to:

1. **Step 3 — tugofwar + ghost_painter migration to Broadcast** (the actual remaining Category-A work, after your go-ahead)
2. **Step 5 — image loading** (the biggest scroll-jank contributor per your audit)
3. **Step 6 — list rendering** (the second biggest scroll-jank contributor)
4. **Step 7 — main-thread work + skeletons**
5. **Step 8 — decision needed first**: enable `prefer_const_constructors` and accept lint count goes up before down, OR skip step 8 entirely
6. **Step 9 — truthordare audit**

**If you'd still like me to do a manual-code-review pass on the already-merged stickman_heist migration** (to confirm it's solid before we move on), I can do that as a read-only audit and report any concerns. Just say the word.

---

## 7. Local environment limitations (important — please read)

To set expectations on what I can and cannot verify locally:

| Capability | Local? | Notes |
|------------|--------|-------|
| `flutter analyze` | ✅ Yes | Working — baseline captured above |
| `flutter test` | ❌ No | Blocked by `thermion_dart` native build (no clang/cmake/ninja in sandbox). Will rely on GitHub Actions CI per-commit. |
| `flutter build apk --analyze-size` | ❌ No | No Android SDK + no native toolchain. Recommend you run this locally before/after step 5. |
| Code edits + git commit + push to `perf/smoothness-pass` | ✅ Yes | Working |
| Live scroll / smoothness verification | ❌ No | Per your instruction: "Where you cannot verify something live... say so explicitly rather than asserting it's fixed" — I will follow this. |

---

**Ready for your direction on:**
1. Skip step 2 (already done) — proceed to step 3?
2. Skip step 4 (already done) — proceed to step 5?
3. Step 8 — enable `prefer_const_constructors` and accept higher lint count, or skip?
4. Want me to do a read-only audit of the already-merged stickman_heist migration first?
