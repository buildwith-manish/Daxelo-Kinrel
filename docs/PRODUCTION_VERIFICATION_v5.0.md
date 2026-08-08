# Daxelo v5.0 Part 1 — Production Verification Protocol

> **Status:** Code fixes complete. **Awaiting your production evidence.**
> Part 2 (visual) is BLOCKED until this protocol is completed and the
> screenshots below are attached.

---

## One-sentence root cause (paste this at the top of the PR)

Production shipped `pmtiles://{{PMTILES_URL}}` as the openmaptiles source URL
in the bundled style JSON; on **web** the `{{PMTILES_URL}}` placeholder was
never substituted (the web code path passed the raw asset path to maplibre
without calling `_applyPmtilesSource`), and on **native** the
`String.fromEnvironment('PMTILES_URL', defaultValue: 'http://localhost:8080/mumbai.pmtiles')`
shipped because no `--dart-define=PMTILES_URL=...` was passed at build time —
so production requested either literally `pmtiles://{{PMTILES_URL}}` (web,
which pmtiles.js cannot resolve because `{{PMTILES_URL}}` is not a URL) or
`pmtiles://http://localhost:8080/mumbai.pmtiles` (native, which fails because
the user's device has no such server), producing zero vector tiles and a black
screen with only the natural_earth raster background visible (that source has
a plain HTTPS URL and loads independently).

---

## What was changed (summary for PR description)

| File | Change |
|---|---|
| `assets/map_styles/kinrel_dark_style.json` | `openmaptiles` source changed from `pmtiles://{{PMTILES_URL}}` to OpenFreeMap ZYX tiles `https://tiles.openfreemap.org/planet/{z}/{x}/{y}.pbf`. Works on all platforms out of the box. |
| `lib/features/family_map/presentation/family_map_screen.dart` | (1) `_kPmtilesSourceUrl` default changed from localhost to empty string — PMTiles is now opt-in via `--dart-define`. (2) Added `_probeAndPatchPmtilesSource()` — real HTTP HEAD probe via dio before passing style to MapLibre. (3) Added `_kOfflineFloorStyleJson` — minimal style with NO external sources, hard floor below which black-screen is impossible. (4) Watchdog reduced 10s → 6s + chained 3-tier fallback (PMTiles → OpenFreeMap → offline floor). (5) Decoupled AvatarMarkerOverlay + HouseholdClusterOverlay gates from `_styleLoaded` to `_mapController != null` — markers render even if style fails. (6) Rewrote `_buildStyleLoadError` with honest tier label + "Use Offline Mode" escape hatch button. (7) Manual retry resets all fallback flags. |
| `pmtiles/config/sources.json` | Updated `_comment` to reflect new architecture. `active` is now informational only (app doesn't read it at runtime). |
| `worklog.md` | Full root-cause analysis + fix log. |

---

## What you need to do — IN THIS ORDER

### A. Build + deploy

1. **Build the app for production:**
   ```bash
   cd Daxelo-Kinrel-App
   # Web (NO --dart-define — uses OpenFreeMap default)
   flutter build web --release
   # Android
   flutter build apk --release
   # iOS
   flutter build ios --release
   ```
   Do **NOT** pass `--dart-define=PMTILES_URL=...` for this verification —
   we're testing the default OpenFreeMap path that ships out of the box.

2. **Deploy to your production URL** (Vercel / your CDN / TestFlight /
   Play Internal Testing — whatever your live production is).

### B. Production screenshot — happy path (1 screenshot)

3. Open the **production URL** in a browser (or the production app on a real
   device). Navigate to the family map screen.

4. Wait up to 6 seconds. The map should render with:
   - Vector tiles visible (roads, buildings, water, parks)
   - Family member avatar markers visible
   - "Loading family map…" gone
   - No black screen

5. **Screenshot this.** Save as:
   `screenshots/v5.0-part1/01-production-happy-path.png`

### C. Staging screenshot — fallback chain (3 screenshots)

You need a staging environment that mirrors production but where you can
deliberately break things. The cleanest way is to run the production build
locally and use Chrome DevTools to block requests.

6. **Stage 1 — PMTiles probe failure (simulate misconfigured PMTiles):**
   - Build with a deliberately bad PMTiles URL:
     ```bash
     flutter build web --release --dart-define=PMTILES_URL=https://example.com/nonexistent.pmtiles
     ```
   - Serve locally: `python3 -m http.server 8000 --directory build/web`
   - Open `http://localhost:8000` in Chrome
   - Open DevTools → Console
   - **Expected:** Within ~3 seconds, console logs:
     ```
     ⚠️ FamilyMap: PMTiles source probe failed (...) — falling back to OpenFreeMap
     ```
   - The map then loads via OpenFreeMap. **Screenshot the working map +
     console log.** Save as:
     `screenshots/v5.0-part1/02-staging-pmtiles-probe-fallback.png`

7. **Stage 2 — OpenFreeMap also fails (simulate total CDN outage):**
   - Same build as step 6
   - In Chrome DevTools → Network tab → click "Block request URL"
   - Add block pattern: `*openfreemap.org*`
   - Reload the page
   - **Expected:** Within ~12 seconds total (6s PMTiles probe + 6s OpenFreeMap
     watchdog), the map falls back to the offline floor style — dark
     background + family markers visible, no vector tiles. The error UI
     shows: "All map sources failed — showing offline mode" + Retry + Use
     Offline Mode buttons.
   - **Screenshot the offline floor + error UI.** Save as:
     `screenshots/v5.0-part1/03-staging-offline-floor.png`

8. **Stage 3 — Family markers decoupled verification:**
   - Same setup as Stage 2 (OpenFreeMap blocked)
   - **Expected:** Even though tiles never load, family member avatar
     markers ARE visible (positioned over the dark background). The "0
     members located" symptom from the v5.0 incident does NOT occur —
     markers appear as soon as `onMapCreated` fires.
   - **Screenshot showing family markers on dark background with no
     tiles.** Save as:
     `screenshots/v5.0-part1/04-staging-markers-decoupled.png`

### D. Acceptance checklist (paste into PR)

Copy/paste this block into the PR description and tick each box. **Every
tick must link to a real artifact** (screenshot path, CI URL, or commit
hash) — no exceptions.

```markdown
## v5.0 Part 1 Acceptance Criteria

- [ ] Root cause stated in one sentence at the top of this PR
      (see "One-sentence root cause" above)
- [ ] Production reverted to known-working source as mitigation
      — commit: <PASTE COMMIT HASH of style JSON change>
- [ ] Fallback rebuilt to trigger on real error signals (HTTP probe),
      not just a timer — commit: <PASTE COMMIT HASH of _probeAndPatchPmtilesSource>
- [ ] Fallback chain has a hard floor (bundled offline style) below which
      black-screen is impossible — commit: <PASTE COMMIT HASH of _kOfflineFloorStyleJson>
- [ ] Family markers load independently of basemap tile success
      — screenshot: screenshots/v5.0-part1/04-staging-markers-decoupled.png
- [ ] Production screenshot showing a fully working map, attached as evidence
      — screenshot: screenshots/v5.0-part1/01-production-happy-path.png
- [ ] Staging screenshot showing the fallback chain actually triggering
      at each tier — screenshots:
        - screenshots/v5.0-part1/02-staging-pmtiles-probe-fallback.png
        - screenshots/v5.0-part1/03-staging-offline-floor.png
```

---

## What happens if a screenshot fails

If Stage 1 (PMTiles probe fallback) doesn't trigger:
- Check that `--dart-define=PMTILES_URL=...` was actually passed at build time
- Check the browser console for the probe log line
- If the probe doesn't fire at all, the dio import may have failed silently —
  check `pubspec.yaml` has `dio: ^5.8.0+1` (it does as of this commit)

If Stage 2 (OpenFreeMap also fails) doesn't reach the offline floor:
- The watchdog is 6s per tier. Total wait is up to 12s + retry overhead.
- Check that the network block pattern actually matches OpenFreeMap requests
  (look at the Network tab for the actual URLs being requested)
- If the watchdog fires but the floor style doesn't render, check that
  `_kOfflineFloorStyleJson` is valid JSON (it is — see worklog)

If Stage 3 (markers decoupled) shows "0 members located" still:
- The decoupling only applies to `AvatarMarkerOverlay` and
  `HouseholdClusterOverlay`. The `HomeMarkerOverlay`, `PlaceCalloutOverlay`,
  `MapSearchBar`, and `MapControlStack` are STILL gated on `_styleLoaded`
  intentionally — they don't make sense without a map. Only the family
  member markers are critical for the "0 members located" symptom.
- If markers still don't appear, check that `_mapController != null` after
  `onMapCreated` fires — the controller is set in `_onMapCreated` and
  should be non-null even if the style fails to load.

---

## After Part 1 is verified

Once all 7 acceptance criteria are ticked with real artifacts, Part 2
(visual implementation) can begin. The v5.0 doc states this explicitly:

> "Part 1 must be fixed and verified in production — not locally, not in
> an emulator — before Part 2 begins. A map with zero tiles rendering
> cannot be evaluated for visual quality."

Do not start Part 2 work until the user attaches the 4 screenshots above
and confirms the production URL is working.
