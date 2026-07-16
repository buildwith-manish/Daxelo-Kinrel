# B1 Verification APK — Download + Install Guide

## Step 1: Trigger the workflow

1. Go to `https://github.com/buildwith-manish/Daxelo-Kinrel`
2. Click **Actions** tab
3. Left sidebar → **Build B1 Verification APK**
4. **Run workflow** dropdown (top right) → choose branch (`feat/cameo-thermion-b1` or `main` after merge) → build mode `release` → **Run workflow**

Build takes ~20-30 min. Watch progress by clicking the running workflow.

## Step 2: Download the APK

1. Click the completed workflow run (green checkmark)
2. Scroll to **Artifacts** (bottom of run summary)
3. Three artifacts:
   - `kinrel-b1-verification-release-apk` — release APK (recommended)
   - `kinrel-b1-verification-debug-apk` — debug APK (diagnostics)
   - `b1-build-logs` — build logs
4. Click `kinrel-b1-verification-release-apk` → downloads a `.zip` → unzip to get `app-release.apk`

APK is ~50-80 MB (includes Filament native libs for arm64 + arm32).

## Step 3: Prepare your Android device

**Requirements:**
- Android arm64 device (Pixel 7 / Samsung S23 / equivalent)
- Android 13+ (API 33+)
- GPU: Mali-G710 / Adreno 730 / equivalent (OpenGL ES 3.0+)

**Enable "Install from unknown sources":**
Settings → Apps → Special access → Install unknown apps → select your file manager/browser → toggle ON

## Step 4: Install the APK

### Option A: Direct install (no computer)
1. Transfer `app-release.apk` to phone (USB/cloud/email)
2. Open file manager → tap `app-release.apk` → Install → Install anyway
3. Tap Open to launch

### Option B: adb install (if USB debugging enabled)
```bash
adb devices
adb install path/to/app-release.apk
```

## Step 5: Run the B1 verification

### Open the B1 screen

The `/b1-verify` route is NOT in normal navigation. Open it via:

```bash
adb shell am start -n <package>/.MainActivity -d "kinrel://b1-verify"
```

(Replace `<package>` with the actual applicationId from `android/app/build.gradle`.)

Or add a temporary debug button to the home screen:
```dart
ElevatedButton(
  onPressed: () => context.go('/b1-verify'),
  child: const Text('B1 Verify'),
),
```

### Read the in-app report

The B1 screen auto-runs all 8 criteria:
1. Filament engine initializes — PASS/FAIL with engine name
2. Capabilities pass B1 gate — all capability flags
3. GLB loads into Filament — load time in ms
4. Morph target names discovered — all 4 names
5. Morph weights applied — acceptance + time
6. renderPortrait() produces bytes — byte count + time
7. Portrait is a valid image — PNG/RGBA format + dimensions
8. Visual mesh deformation — MANUAL (confirm with sliders)

### Verify morph targets visually

Below the criteria cards:
- **Live Thermion viewport** — renders the synthetic head GLB
- **4 morph target sliders** — `blink_left`, `blink_right`, `smile`, `jaw_open`

For each morph target:
1. Move slider to **1.0** — mesh should visibly deform
2. Move slider to **0.0** — mesh should return to neutral
3. If deformation visible, tap **Mark Visual PASS (criterion 8)**

### Check portrait thumbnail

Below sliders: 128×128 thumbnail of `renderPortrait()` output + byte count + dimensions + format. If blank/black, Filament rendered nothing — FAIL.

### Copy the report

Tap **Copy icon** (top right) → full report copied to clipboard. Paste into worklog or conversation.

## Step 6: Record device specs

```bash
adb shell getprop ro.product.model
adb shell getprop ro.build.version.release
adb shell dumpsys SurfaceFlinger | grep -iE "GLES|GL_RENDERER|GL_VENDOR"
adb shell getprop ro.product.cpu.abi
```

Add these to the report so results are attributable to a known device class.

## Troubleshooting

- **App crashes on launch**: `adb logcat | grep -iE "flutter|thermion|filament"` — most likely `libthermion_dart.so` missing or wrong ABI
- **B1 screen shows "Filament failed to init"**: error message tells you why (GPU context creation failed, etc.)
- **Morph sliders don't deform**: check live viewport is rendering; if yes, fork bug in setMorphWeights
- **renderPortrait() returns empty**: headless swap chain failed; check `adb logcat` for Filament render errors

## Artifact retention

- APK artifacts: 30 days
- Build logs: 14 days
- After retention expires, re-trigger the workflow for fresh artifacts
