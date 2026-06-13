// =============================================================================
// graph_canvas_config.dart — V2.1 K-Graph Blueprint: Canvas Layout & Sizing
// =============================================================================
//
// Defines every numeric constant that governs the K-Graph canvas geometry:
// - Canvas dimensions and zoom constraints
// - Level-of-detail (LOD) thresholds
// - Grid pattern spacing
// - Node dimensions and ring widths
// - Generation Y positions and inter-generation spacing
// - Horizontal spacing (spouse, sibling, branch gaps)
//
// All values are `const` and the class has a private constructor to prevent
// instantiation — access members directly via `GraphCanvasConfig.xxx`.
// =============================================================================

/// Layout and sizing constants for the K-Graph canvas.
///
/// These values are referenced by the layout engine, paint delegates,
/// interaction handlers, and zoom controllers. Changing any value here
/// will affect the graph's visual appearance and/or interaction behaviour.
class GraphCanvasConfig {
  GraphCanvasConfig._();

  // ── Canvas Dimensions ────────────────────────────────────────────────────

  /// Logical width of the scrollable graph canvas in logical pixels.
  static const double canvasWidth = 1400.0;

  /// Logical height of the scrollable graph canvas in logical pixels.
  static const double canvasHeight = 920.0;

  // ── Zoom Constraints ─────────────────────────────────────────────────────

  /// Minimum zoom scale the user can pinch/scroll to.
  static const double minZoom = 0.3;

  /// Maximum zoom scale the user can pinch/scroll to.
  static const double maxZoom = 2.5;

  /// Default zoom scale when the graph first loads.
  static const double defaultZoom = 1.0;

  /// Zoom step applied per button press (zoom-in / zoom-out controls).
  static const double zoomStep = 0.15;

  /// Zoom step applied per mouse-wheel / trackpad scroll event.
  static const double wheelZoomStep = 0.07;

  // ── Level-of-Detail (LOD) ────────────────────────────────────────────────

  /// Zoom threshold below which the canvas switches to a minimal rendering
  /// mode (e.g. simplified nodes, no text labels).
  static const double lodMinimalZoom = 0.4;

  // ── Grid Pattern ─────────────────────────────────────────────────────────

  /// Spacing between grid dots in logical pixels.
  static const double gridSpacing = 40.0;

  /// Radius of each grid dot in logical pixels.
  static const double gridDotRadius = 1.0;

  // ── Node Dimensions ──────────────────────────────────────────────────────

  /// Diameter of the "self" (ego) node — slightly larger to stand out.
  static const double selfNodeSize = 88.0;

  /// Diameter of all non-self nodes.
  static const double defaultNodeSize = 76.0;

  /// Border ring width when a node is selected.
  static const double selectedRingWidth = 3.0;

  /// Border ring width when a node is hovered.
  static const double hoveredRingWidth = 2.5;

  /// Default border ring width (no interaction state).
  static const double defaultRingWidth = 2.0;

  /// Radius of the outer glow / halo effect around a node.
  static const double glowExtent = 16.0;

  /// Size (width & height) of the relationship badge icon on a node.
  static const double badgeSize = 20.0;

  /// Border width of the relationship badge.
  static const double badgeBorderWidth = 2.0;

  // ── Generation Y Positions ───────────────────────────────────────────────

  /// Fixed Y positions for each generation level in the hierarchical layout.
  ///
  /// Key = generation index:
  /// - `0`: Grandparents (top)
  /// - `1`: Parents
  /// - `2`: Self & siblings (centre)
  /// - `3`: Children (bottom)
  static const Map<int, double> generationYPositions = {
    0: 140.0, // Grandparents
    1: 350.0, // Parents
    2: 580.0, // Self & siblings
    3: 780.0, // Children
  };

  /// Vertical spacing between generations when a generation index is not
  /// present in [generationYPositions] (fallback for deeper trees).
  static const double generationFallbackSpacing = 200.0;

  // ── Horizontal Spacing ───────────────────────────────────────────────────

  /// Horizontal gap between spouses / partners in the same generation.
  static const double spouseGap = 150.0;

  /// Horizontal gap between siblings in the same generation.
  static const double siblingGap = 180.0;

  /// Horizontal gap between separate family branches (e.g. two sets of
  /// grandparents side by side).
  static const double branchGap = 280.0;
}
