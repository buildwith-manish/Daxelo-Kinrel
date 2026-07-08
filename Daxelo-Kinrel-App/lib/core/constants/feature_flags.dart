// lib/core/constants/feature_flags.dart
//
// DAXELO KINREL — Compile-time feature flags.
//
// Keep flags here (not scattered through the app) so they are easy to audit
// and flip. Flags are `const` so the analyzer/tree-shaker can fully remove the
// disabled path from release builds.

// v68: kUseV21Engine has been removed. FamilyGraphEngineView is now the
// sole graph renderer — the old FamilyGraphWidget (v40) has been deleted.
// All graph screens render FamilyGraphEngineView directly.

// ── Step 5: previously-missing screens ─────────────────────────────────────
// Each new screen/feature is gated so it can be merged dark and enabled per
// feature once verified locally (flutter analyze + flutter test, and a manual
// smoke test on device). All default to false → zero change to the live app.

/// Graph share/export (capture the graph to a PNG and share it).
const bool kEnableGraphShareExport = true;

/// Avatar photo picker (camera / gallery) when adding or editing a person.
const bool kEnablePhotoPicker = true;

/// Join-a-family via QR code (generate a join code + scan to join).
/// Scanning requires the `mobile_scanner` package (see pubspec.yaml).
const bool kEnableQrJoin = true;

/// In-app profile editing and "add relative" flows.
const bool kEnableProfileEditing = true;

/// Language picker for kinship term display (7 Indian languages).
const bool kEnableLanguagePicker = true;

/// Audio pronunciation of kinship terms via flutter_tts.
const bool kEnableAudioPronunciation = true;

/// AURA — Ancestral Unified Relationship Archetype.
/// Gates the AURA nav entry, the home-screen cover replacement, and the
/// /aura route so the feature can ship dark and be turned on per build.
/// Backend (server/src/aura/*) is already live; this flag controls only
/// the Flutter UI surface.
const bool kEnableAura = true;
