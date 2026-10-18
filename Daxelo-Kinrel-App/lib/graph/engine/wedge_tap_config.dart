// lib/graph/engine/wedge_tap_config.dart
//
// DAXELO KINREL — Wedge tap behaviour flags.
//
// These two constants gate the old focus/camera/badge behaviour so it
// can be restored by flipping one constant. When false (the default),
// tapping a person only expands/collapses it — no camera zoom-fit,
// no dimming, no selection glow, and no gray "+N" count pills on
// collapsed nodes.
//
// Setting kWedgeTapFocusEnabled = true restores the old behaviour:
//   • Tap focuses the person, dims other nodes, zooms the camera.
//   • The three-state tap machine runs (collapsed → expand+focus,
//     expanded-not-focused → focus, focused+expanded → collapse).
//   • Gray "+N" count pills appear on collapsed nodes with connections.
//
// Setting kWedgeShowCountBadges = true restores the gray "+N" corner
// pills on collapsed nodes (independent of the focus flag).

/// true = old behaviour (camera zoom-fit, dim others, focus state
/// machine on tap). false = tap only expands/collapses (the approved
/// preview's `tap()` function — one tap, always).
const bool kWedgeTapFocusEnabled = false;

/// true = gray "+N" pill on collapsed nodes. false = no pills (the
/// approved preview uses only the dashed "+N" node).
const bool kWedgeShowCountBadges = false;

/// true = on expand or +N tap, run ONE camera move: WedgeCameraFit.fit
/// over the expanded person, its newly shown children and its +N bubble
/// only (not the parent, not the rest of the graph). On collapse, do
/// not move the camera. This is independent of kWedgeTapFocusEnabled
/// (which controls focus/dim/selection). When false, the camera never
/// moves on tap at all.
const bool kWedgeFitOnExpand = true;
