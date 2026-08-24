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

/// Kinrel Cameo — the 3D character system fallback avatar.
///
/// When enabled, surfaces that show a user's avatar will render the
/// deterministic Kinrel Cameo portrait (CameoAvatar) when no photo URL
/// is available, instead of a plain initial letter.
///
/// Gating: The 3D runtime (B1 prototype) is NOT yet shipped. This flag
/// enables the 2D fallback portrait painter (CameoPortraitPainter) which
/// renders the SAME Kinrel visual identity (warm ivory key + ember rim,
/// heirloom vignette, age-band-appropriate silhouette) as a 2D
/// CustomPainter today. When B1 passes, the 3D renderer will replace the
/// painter internally without changing any call sites.
///
/// Set to `true` to make Cameo visible in the app. Set to `false` to
/// keep the legacy initial-letter fallback (zero change to existing UI).
const bool kEnableCameoFallback = true;

/// Kinrel Cameo — live 3D rendering on eligible surfaces.
///
/// When enabled AND the 3D renderer (Thermion/Filament) initializes
/// successfully, the CameoLive3DAvatar widget will render real-time
/// 3D characters on Studio, Profile hero, and Journey surfaces.
///
/// When disabled, or when 3D init fails, all surfaces fall back to the
/// 2D CameoAvatar (CameoPortraitPainter) — zero broken views.
///
/// This flag is separate from [kEnableCameoFallback] because the 2D
/// Cameo system is production-ready, while the 3D system is still in
/// B1 verification. Set to `true` only when B1 passes on real hardware.
const bool kEnableLive3DCameo = false;

/// Language picker for kinship term display (7 Indian languages).
const bool kEnableLanguagePicker = true;

/// Audio pronunciation of kinship terms via flutter_tts.
const bool kEnableAudioPronunciation = true;

/// v5.17: Auto kinship inference — when enabled, creating a relationship
/// (e.g. "X is Y's sister") automatically derives implied edges (X is
/// also Y's parents' daughter, Y's grandparents' granddaughter, etc.).
///
/// v5.18: Re-enabled after fixing the labelAtoB directional-convention
/// bug (v5.17) and updating the inference engine to use the canonical
/// convention (v5.18).
///
/// v5.63: DISABLED. The user reported that creating a relationship
/// (e.g. "JD is MA's father") silently auto-created an ADDITIONAL
/// unrequested relationship (HD↔JD spouse edge) without confirmation.
/// The user wants full control over which relationships get created —
/// nothing should be added automatically.
///
/// The inference engine itself (inferKinshipEdges in
/// automatic_kinship_inference.dart) is correct and useful — it
/// identifies likely relationships. The problem is that
/// _runKinshipInference() in family_provider.dart takes those
/// suggestions and BULK-INSERTs them as Relationship rows without
/// asking the user.
///
/// To re-enable as a SUGGESTION flow (option (b) from the user's
/// request): refactor _runKinshipInference() to RETURN the inferred
/// edges instead of inserting them, then surface them in the UI as
/// "Based on this, HD and JD might be spouses — would you like to
/// add this relationship?" prompts that the user can accept or
/// dismiss. The SpouseInferenceEngine (v4) already follows this
/// pattern — see lib/core/kinship/v4/spouse_inference_engine.dart.
///
/// For now, this flag is false — NO automatic edges are created.
const bool kEnableAutoKinshipInference = false;

/// Kinrel — Family Relationship Intelligence.
/// Gates the Kinrel nav entry, the home-screen cover replacement, and the
/// /kinrel route so the feature can ship dark and be turned on per build.
/// Backend (server/src/kinrel-intelligence/*) is already live; this flag controls only
/// the Flutter UI surface.
const bool kEnableKinrel = true;

/// v5.55: TEMPORARY debug flag — shows an on-screen dialog with the actual
/// runtime values of relKey, result.id, linkToPersonId, widget.fromGraph
/// right before createRelationship() is called. This helps diagnose why
/// the relationship edge is not being created.
///
/// Set to `false` to remove the debug dialog after diagnosis is complete.
const bool kShowRelationshipDebugBanner = false;

/// v5.76: TEMPORARY debug flag — shows an on-screen banner on the graph
/// showing the current auth user ID, resolved viewerPersonId, and which
/// node is getting isViewer=true. This helps diagnose why the viewer-
/// relative perspective is not working for non-creator accounts.
///
/// v5.88: RE-ENABLED to diagnose a regression where all nodes lost
/// their color coding after the v5.87 step-parent term-mapping fix.
/// The v5.87 code change only touched structural_kinship_classifier.dart
/// (which is NOT used by viewer resolution), so the regression must be
/// from the manual DB fix that changed Manish's anchor linkedUserId.
/// This banner will help confirm whether Auth ID / Viewer Person ID
/// is null and which Persons are linked to which auth users.
///
/// Set to `false` to remove the debug banner after diagnosis is complete.
const bool kShowViewerDebugBanner = true;
