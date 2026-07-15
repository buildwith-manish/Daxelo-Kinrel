// lib/graph/rendering/graph_lighting.dart
//
// DAXELO KINREL — Graph Lighting Contract (v91, 2026-07-12)
//
// ONE shared visual lighting language for the entire Kinrel graph.
// Every painter that renders a physical 2.5D element — nodes, edges,
// midpoint beads, hearts, selected-edge sweeps — MUST source its
// shadow direction, highlight direction, blur sigma, and alpha from
// this contract so the graph reads as a single coherent material world.
//
// GLOBAL LIGHT SOURCE:  TOP-LEFT
// GLOBAL SHADOW DIRECTION: BOTTOM-RIGHT
//
// Do NOT scatter magic offsets across painters. If a new physical
// element needs lighting, add a constant here and reference it there.

import 'package:flutter/material.dart';

/// Lightweight, immutable visual lighting contract for the Kinrel graph.
///
/// This is NOT a lighting engine — it is a small set of constants that
/// ensure the Obsidian Glass node painter, the relationship thread
/// painter, the midpoint bead/heart painter, and the selected-edge
/// sweep painter all agree on:
///
///   • light direction (top-left)
///   • shadow direction (bottom-right)
///   • shadow blur sigma per LOD
///   • highlight ridge alpha per LOD
///
/// All values are tuned for 1:1 device scale on a representative
/// Android phone (≈390×844 logical px viewport).
class GraphLighting {
  GraphLighting._();

  // ── Global light + shadow directions ──────────────────────────────────

  /// Global light source direction. Painters do NOT translate by this
  /// directly — it is the conceptual direction light travels INTO the
  /// scene. Highlights appear on the TOP-LEFT of every physical element.
  static const Alignment lightSource = Alignment(-1.0, -1.0);

  /// Physical shadow offset applied to every element that casts a shadow.
  /// Down-right per the global top-left light source.
  ///
  /// Used by:
  ///   • relationship thread contact shadow (PASS 1)
  ///   • midpoint bead shadow
  ///   • spouse heart shadow
  ///   • selected-edge contact shadow (PASS A, stronger)
  static const Offset shadowOffset = Offset(1.5, 2.0);

  /// Highlight ridge offset. The thin top-left light ridge on a
  /// relationship thread is drawn by translating the canvas by this
  /// offset before stroking the same cached Path.
  ///
  /// Negative = up-left = towards the light source.
  static const Offset highlightOffset = Offset(-0.6, -0.7);

  // ── Shadow sigma per LOD ──────────────────────────────────────────────

  /// Blur sigma for contact shadows at FULL LOD.
  ///
  /// Used by relationship threads, midpoint beads, and selected-edge
  /// contact shadows when the graph is at full visual quality.
  static const double fullShadowSigma = 2.8;

  /// Blur sigma for contact shadows at CHIP LOD.
  /// Conservative — keeps CHIP-tier painting cheap on large graphs.
  static const double chipShadowSigma = 1.6;

  /// At DOT LOD, no MaskFilter blur is applied to normal edges per the
  /// performance guardrails (PART 22). This constant is provided for
  /// documentation; painters should skip blur entirely at DOT LOD.

  // ── Ridge alpha per LOD ───────────────────────────────────────────────

  /// Alpha for the directional light ridge at FULL LOD.
  static const double fullRidgeAlpha = 0.26;

  /// Alpha for the directional light ridge at CHIP LOD.
  static const double chipRidgeAlpha = 0.14;

  // ── Shadow alpha ──────────────────────────────────────────────────────

  /// Standard contact shadow alpha for relationship threads and
  /// midpoint beads. Neutral black, cast down-right.
  static const double shadowAlpha = 0.26;

  /// Stronger contact shadow alpha for SELECTED edges. The selected
  /// edge's PASS A shadow uses this to lift it slightly off the canvas
  /// without resorting to a colored neon halo.
  static const double selectedShadowAlpha = 0.34;

  // ── Selected-edge interaction aura ────────────────────────────────────

  /// Kinrel-orange interaction aura alpha for selected edges. This is
  /// an INTERACTION accent (PASS D) — it must NOT replace the
  /// relationship category colour (PASS B).
  static const double selectedAuraAlpha = 0.16;

  /// Blur sigma for the selected-edge interaction aura.
  static const double selectedAuraSigma = 3.0;

  /// Extra stroke width added to the body width for the selected-edge
  /// interaction aura.
  static const double selectedAuraWidthDelta = 3.0;

  // ── Edge sweep (one-shot) ─────────────────────────────────────────────

  /// Fraction of the selected edge's PathMetric length occupied by the
  /// travelling highlight segment during the one-shot sweep.
  static const double sweepSegmentFraction = 0.06;

  /// One-shot sweep duration in milliseconds. The sweep runs ONCE when
  /// `selectedEdgeId` changes; it never repeats.
  static const int sweepDurationMs = 650;

  // ── Midpoint bead / heart ─────────────────────────────────────────────

  /// Bead radius multiplier — scales with effective edge stroke width.
  /// `beadR = (effectiveStrokeWidth * beadRadiusMultiplier).clamp(min, max)`.
  static const double beadRadiusMultiplier = 1.45;
  static const double beadRadiusMin = 3.8;
  static const double beadRadiusMax = 5.8;

  /// Heart bounding-box size multiplier — scales with stroke width.
  static const double heartSizeMultiplier = 4.2;
  static const double heartSizeMin = 11.0;
  static const double heartSizeMax = 16.0;

  // ── Effective stroke widths ───────────────────────────────────────────

  /// Minimum effective stroke width for a relationship thread body.
  static const double bodyWidthMin = 2.2;

  /// Maximum effective stroke width for a relationship thread body.
  static const double bodyWidthMax = 4.5;

  /// Returns the effective body width for an edge, clamped to the
  /// graph lighting contract range. Used by the edge painter and the
  /// midpoint bead scaler so both stay in sync.
  static double clampBodyWidth(double styleStrokeWidth) {
    return styleStrokeWidth.clamp(bodyWidthMin, bodyWidthMax);
  }

  /// Returns the effective bead radius for a given effective stroke
  /// width, clamped to the lighting contract range.
  static double beadRadiusFor(double effectiveStrokeWidth) {
    return (effectiveStrokeWidth * beadRadiusMultiplier)
        .clamp(beadRadiusMin, beadRadiusMax);
  }

  /// Returns the effective heart bounding-box size for a given
  /// effective stroke width, clamped to the lighting contract range.
  static double heartSizeFor(double effectiveStrokeWidth) {
    return (effectiveStrokeWidth * heartSizeMultiplier)
        .clamp(heartSizeMin, heartSizeMax);
  }

  /// Linearly interpolates [base] towards white by [t], used for the
  /// directional light ridge and the sweep highlight segment.
  static Color ridgeColor(Color base, {double t = 0.55}) {
    return Color.lerp(base, Colors.white, t)!;
  }
}
