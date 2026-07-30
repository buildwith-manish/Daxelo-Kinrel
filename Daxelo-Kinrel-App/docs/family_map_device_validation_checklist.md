# Family Map — Device Validation Checklist

> **Status:** The four validation points (pins, reliability, styling, performance)
> were audited via code review + headless MapLibre rendering on 2026-07-30.
> Points 2 (reliability) and 3 (styling) were empirically verified.
> **Points 1 (pins) and 4 (performance) were NOT visually verified** because
> the avatar/home/callout pins are Flutter widgets that cannot render in
> headless MapLibre, and performance in SwiftShader software rendering is
> not representative of real-device GPU performance.
>
> This checklist must be completed on a real device (or emulator with
> hardware GPU) before the Family Map can be considered fully validated.

## Prerequisites

- [ ] Flutter SDK installed (`flutter doctor` passes)
- [ ] A physical device or emulator with **hardware GPU** (not SwiftShader)
  - Android: any real phone, or emulator with `-gpu host` (not `-gpu swiftshader`)
  - iOS: any real iPhone, or simulator (simulator uses the Mac's GPU)
- [ ] The app built from commit `32e28c3b` (or later on `main`)
- [ ] A family with at least 5 members + 3 family-places (home, school, etc.)
  so pins + callouts are visible

---

## Point 1 — Pin clarity (REQUIRES DEVICE)

This was only code-audited, not visually verified. The avatar/home/callout
pins are Flutter widgets (`AvatarMarkerOverlay`, `HomeMarkerOverlay`,
`PlaceCalloutOverlay`) that render on top of the MapLibre canvas — they
cannot render in headless MapLibre GL JS.

### Avatar pins (family member markers)
- [ ] Pins render at the correct lat/lng for each family member
- [ ] Each pin shows the member's **photo** (not a blank circle)
- [ ] Each pin has a **colored ring** — orange (#E8612A) unselected, gold (#E8B941) selected
- [ ] Pin background is `KinrelColors.darkCard` (#191B2C) — should match app cards
- [ ] Tapping a pin opens the member bottom sheet + enters Focus Mode
- [ ] Long-pressing a pin opens the Family Journey animation
- [ ] Live pins (user actively sharing location) show the teal shimmer
- [ ] **Zoom 11-13:** pins are visible but small; no clipping
- [ ] **Zoom 14-16:** pins are clearly legible; photos recognizable
- [ ] **Zoom 17+:** pins don't overlap or clip at street level
- [ ] **Pan/zoom:** pins track their lat/lng correctly (don't drift)

### Home pin
- [ ] The current home place shows a **pulsing gold ring** + orange dot + home icon
- [ ] Pulse animation is smooth (2400ms cycle, scale 1.0 → 1.6)
- [ ] Tapping the home pin flies to it
- [ ] Toggling the "Family homes" layer off hides the home pin

### POI callouts (school, park, etc.)
- [ ] Below zoom 12: compact **dots** render (max 24, clustered)
- [ ] Above zoom 12: full **chip callouts** render (max 8, nearest to center)
- [ ] Each chip shows the correct **per-type icon + color**:
  - current_home → home icon, orange
  - school → school icon, blue-grey
  - wedding → heart icon, orange
  - memorial → flower icon, amber
  - birthplace → child-care icon, gold
  - etc. (12 types total — see `place_callout_overlay.dart:445-508`)
- [ ] Chips don't overlap each other at zoom 15-16
- [ ] Tapping a chip flies to the place

### Overlap / clipping
- [ ] At zoom 14+, household clustering works (nearby members collapse into a stacked-avatar cluster)
- [ ] At zoom 17+, individual pins don't clip off the screen edge
- [ ] Pins + callouts don't visually collide (callouts should float above buildings)

---

## Point 2 — Reliability (empirically verified, but confirm on device)

The watchdog/fallback was empirically tested in headless Chromium:
- Valid OpenFreeMap source: tiles load, idle reached, no watchdog needed ✅
- Broken source: watchdog fired at 8s, swapped to OpenFreeMap, recovered ✅

Confirm on device:
- [ ] App loads consistently (no blank screen on 3 consecutive launches)
- [ ] "Loading family map…" appears briefly then disappears (not stuck)
- [ ] If on cellular with poor signal: map still loads (may be slow, but not stuck)
- [ ] Force-kill the app + relaunch: state restores correctly
- [ ] Toggle dark/light map: both load without blank screen

---

## Point 3 — On-brand styling (empirically verified, but confirm on device)

The style JSON colors were empirically verified via pixel sampling:
- background #131416 (KinrelColors.darkBackground) ✅
- building fill #13141E (KinrelColors.darkSurface) ✅
- outline #202338 (KinrelColors.darkElevated) ✅

Confirm on device:
- [ ] Map background matches the app's Scaffold background (no visible seam)
- [ ] Building fill matches app card surfaces (visual consistency)
- [ ] Avatar pin ring is the same orange as app CTAs
- [ ] No hardcoded colors that look "off" compared to the rest of the app

---

## Point 4 — Performance (REQUIRES DEVICE)

Performance was measured in headless Chromium with SwiftShader (software
rendering, no GPU). Results:
- **Pan:** p50 = 16.7ms (60fps steady-state), but 9/44 frames >100ms
- **Zoom:** p50 = 533ms (dominated by tile-decode spikes)

**These numbers are NOT representative of real-device performance.**
SwiftShader software rendering is ~10x slower than a mobile GPU for
WebGL workloads. The p50 = 16.7ms suggests the render path is fundamentally
sound, but the spike pattern could be GPU-bound (hardware GPU would help
a lot) or CPU-bound (tile decode, hardware GPU would help less). Only a
real device test can tell.

### Test on a mid-tier device (Snapdragon 6xx class, ~$200-300 phone)
- [ ] **Pan (drag):** smooth, no visible stutter for 10 seconds of continuous dragging
- [ ] **Zoom (pinch):** smooth, no freeze frames during pinch-zoom
- [ ] **Pin tap:** responsive (<200ms from tap to bottom sheet appearing)
- [ ] **50+ pins:** pan/zoom still smooth (this is what the off-screen culling fix targets)
- [ ] **Background location sharing:** no frame drops when live-location glow updates
- [ ] **Low-tier device (optional):** if available, confirm DeviceTier.low disables
  animations + warm-glow layers without crashing

### What the culling + RepaintBoundary fix should improve
The off-screen culling fix in `avatar_marker_overlay.dart` (commit `32e28c3b`)
skips widget construction for pins outside the viewport. This should be
most noticeable on large families (50+ pins) during pan/zoom — previously
every pin was rebuilt every frame even if off-screen. Confirm:
- [ ] With 50+ pins: pan is noticeably smoother than before the fix
- [ ] With 50+ pins: zoom is noticeably smoother than before the fix
- [ ] Pins appearing/disappearing at screen edges during pan is not jarring

---

## How to run the app for this checklist

```bash
cd Daxelo-Kinrel-App

# Android (real device or emulator with hardware GPU)
flutter run --release -d <device-id>

# iOS (real device or simulator)
flutter run --release -d <device-id>

# Web (use a real browser, not headless)
flutter run -d chrome --release
```

For web testing, open Chrome DevTools → toggle device toolbar → select
a mid-tier device profile (e.g. "Pixel 5") + enable CPU throttling (4x)
to approximate a mobile CPU. Note: this still uses your desktop GPU, so
it's not a perfect mobile simulation — but it's closer than SwiftShader.

---

## Sign-off

Once all checkboxes above are completed, update this file with the
verification date + device used, and the Family Map can be considered
fully validated.

- **Verified by:** _______________
- **Date:** _______________
- **Device(s) used:** _______________
- **Notes:** _______________
