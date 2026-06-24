// lib/core/constants/feature_flags.dart
//
// DAXELO KINREL — Compile-time feature flags.
//
// Keep flags here (not scattered through the app) so they are easy to audit
// and flip. Flags are `const` so the analyzer/tree-shaker can fully remove the
// disabled path from release builds.

/// When `true`, the family graph screen renders the V2.1 culling engine
/// ([FamilyGraphEngineView]) instead of the v40 `InteractiveViewer`
/// ([FamilyGraphWidget]).
///
/// The engine path adds viewport culling (scales to 500/1000/2000+ nodes),
/// position memory, expand/collapse, realtime invalidation and an offline
/// banner — but it must be verified before shipping.
///
/// Leave this `false` until you have run, locally:
///   flutter analyze
///   flutter test test/graph/
/// and profiled a large family on-device (`flutter run --profile`). See
/// docs/graph/PATH_B_REWIRE.md. The v40 path remains the safe fallback, so
/// flipping this flag is fully reversible.
const bool kUseV21Engine = false;
