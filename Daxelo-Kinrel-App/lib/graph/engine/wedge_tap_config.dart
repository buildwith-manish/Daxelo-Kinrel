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

/// true = in wedge mode, nodes ALWAYS render at Lod.full (the Pseudo3D
/// body with initials/avatar, name + relation labels, badges). Never
/// mini/micro/dot. The old LOD swap (force-mini above 40 visible nodes,
/// mini below zoom 0.90) is gated behind this flag — set false to
/// restore it.
const bool kWedgeAlwaysFullNodes = true;

/// true = enforce the node budget (kWedgeNodeBudget = 150). When false
/// (the default), the budget-collapse loop is skipped and "Budget reached"
/// never appears. Every member is reachable by expanding one branch at a
/// time — nothing auto-collapses.
const bool kWedgeEnforceBudget = false;

/// true = accordion expansion: expanded branches stay open until the
/// user taps a node in a DIFFERENT branch (which closes the old branch
/// and opens the new one). Tapping an expanded node collapses it AND
/// every expansion under it. Ancestors of the newly opened branch stay
/// open. When false, any number of branches can be open simultaneously.
const bool kWedgeAccordionMode = true;

/// true = declutter edges: tree edges always drawn; couple edges drawn
/// when adjacent; other cross-links faint (alpha ≤ 0.12) when ≤ 40
/// visible nodes, hidden when > 40. Midpoint dots/hearts hidden when
/// zoom < 0.5 or visible nodes > 40. When false, all edges drawn.
const bool kWedgeDeclutterEdges = true;
