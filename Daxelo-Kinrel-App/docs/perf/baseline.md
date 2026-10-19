# Performance Baseline (Phase 0)

**Date:** 2026-10-20
**Branch:** graph-layout
**Commit:** edacd006

## Static Metrics (measured without a device)

### Asset sizes

| Asset | Size | Notes |
|-------|------|-------|
| `assets/icons/games/*.png` (20 icons) | 9.9 MB | 1024×1024 PNGs, 400-700 KB each — Phase 8 target |
| `assets/data/kinship_terms.json` | 956 KB | 5,363 terms — Phase 3 target (isolate) |
| `assets/data/kinship_core.json` | 196 KB | Small — keep as-is |
| `assets/fonts/` | 4.8 MB | Noto Sans/Serif — Phase 8 optional |
| **Total assets** | **17 MB** | |

### Code metrics (actual usage sites, not including comments)

| Metric | Count | Phase |
|--------|-------|-------|
| `CachedNetworkImage(` usages | 51 | Phase 2 |
| `Image.network(` usages | 6 | Phase 2 |
| `Opacity(` widgets | 38 | Phase 4 |
| `BackdropFilter(` calls | 4 | Phase 4 |
| `shouldRepaint => true` | 8 | Phase 5 |
| `DefaultCacheManager` refs | 2 | Phase 2 |
| Hardcoded secrets in scripts | 3 files | Phase 1 |

### Known issues found during baseline

1. **`main.dart` line ~285:** `DefaultCacheManager().emptyCache()` wipes the entire image cache on every app launch. The comment says "no-op; just warming" but `emptyCache()` actually deletes every cached file. This means every image is re-downloaded on every launch — a massive performance + data-usage regression. (Phase 2)

2. **Game icons:** 9.9 MB of 1024×1024 PNGs. These are displayed at ~80-120px in the UI. Converting to 256px WebP @ q88 would reduce to ~1-2 MB total (90% reduction). (Phase 8)

3. **Kinship JSON:** 956 KB parsed on the UI thread at startup (`jsonDecode` in `kinship_service.dart` lines ~98/111/175/182). With 5,363 terms, this is likely >8ms on a low-end device. (Phase 3)

4. **8 painters with `shouldRepaint => true`:** every parent rebuild triggers a full repaint of the canvas, even when the painter's inputs haven't changed. (Phase 5)

5. **Hardcoded secrets:** Supabase service_role JWT in `scripts/e2e-test.js` + `scripts/e2e-verify.js`, Turso token in `scripts/setup_turso_table.py`. Blocker for release. (Phase 1)

## Dynamic Metrics (REQUIRES physical device)

> **⚠ NOT MEASURED — requires a low-end physical Android device in profile mode.**
>
> The following numbers must be filled in by running:
> ```bash
> cd Daxelo-Kinrel-App
> flutter build apk --profile --target-platform android-arm64
> # install on device, then:
> flutter test integration_test/perf_baseline_test.dart --profile
> ```
>
> The integration test (`integration_test/perf_baseline_test.dart`) is
> written and ready — it captures avg/p95 build + raster ms and
> janky-frame % for 5 flows: onboarding, home scroll, graph pan/zoom,
> chat scroll (500 msgs), add-person sheet.

### Target flows

| Flow | Avg build ms | P95 build ms | Avg raster ms | P95 raster ms | Janky % | Status |
|------|-------------|--------------|--------------|---------------|---------|--------|
| (a) Onboarding first frame | — | — | — | — | — | NOT MEASURED |
| (b) Home scroll (60f) | — | — | — | — | — | NOT MEASURED |
| (c) Graph pan/zoom | — | — | — | — | — | NOT MEASURED (needs mock harness) |
| (d) Chat scroll 500 | — | — | — | — | — | NOT MEASURED (needs Drift seed) |
| (e) Add-person sheet | — | — | — | — | — | NOT MEASURED |

### Startup

| Metric | Value | Status |
|--------|-------|--------|
| Time to first frame (TTFF) | — | NOT MEASURED (run `flutter run --profile --trace-startup`) |
| `adb shell am start -W` cold start | — | NOT MEASURED |

### Binary size

| Metric | Value | Status |
|--------|-------|--------|
| Release APK size | — | NOT MEASURED (run `flutter build apk --release`) |
| Release AAB size | — | NOT MEASURED (run `flutter build appbundle --release`) |

## What I could NOT do (honest disclosure)

1. **Could not run integration tests on a physical device** — no Android device is available in this environment. The test file is written and ready; the owner must run it on a real device to fill in the dynamic metrics.

2. **Could not build the release APK** — the `thermion_dart` native build requires `clang` which is not installable in this sandbox (no sudo). The owner must build on a machine with clang installed (`sudo apt-get install clang cmake ninja-build libc++-19-dev`).

3. **Could not measure TTFF** — requires `flutter run --profile --trace-startup` on a real device.

4. **The integration tests for (c) graph and (d) chat are placeholders** — they need a mock Supabase/Drift harness to inject 100+ members / 500 messages. The patterns exist in `test/features/family/wedge_e2e_visual_test.dart` (mock notifier) and can be adapted.

## Methodology for the owner

1. **Prerequisites:** a low-end physical Android phone (e.g. 2-4 GB RAM, Android 10+), USB debugging enabled, `clang cmake ninja-build` installed on the build machine.

2. **Build profile APK:**
   ```bash
   cd Daxelo-Kinrel-App
   flutter build apk --profile --target-platform android-arm64
   ```

3. **Install on device:**
   ```bash
   flutter install --profile
   ```

4. **Run the baseline test:**
   ```bash
   flutter test integration_test/perf_baseline_test.dart --profile
   ```

5. **Record TTFF:**
   ```bash
   flutter run --profile --trace-startup --target-platform android-arm64
   # Read "timeToFirstFrameMicros" from the startup trace
   ```

6. **Record APK/AAB size:**
   ```bash
   flutter build apk --release
   ls -lh build/app/outputs/flutter-apk/app-release.apk
   flutter build appbundle --release
   ls -lh build/app/outputs/bundle/release/app-release.aab
   ```

7. **Fill in the tables above** with the measured numbers. These are the "before" baseline for the final report.

---

*This baseline was generated as part of the Phase 0 performance audit. Subsequent phases will fill in the "after" numbers in `docs/perf/REPORT.md`.*
