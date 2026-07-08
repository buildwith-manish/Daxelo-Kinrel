// server/src/aura/aura-parameter-generator.service.ts
//
// AURA — Parameter Generator (Symbol Math)
//
// Maps graph metrics + archetype → visual symbol parameters.
// Every function here is a pure mathematical transformation — no randomness.
// Given the same metrics + archetype, the output is always identical.
//
// Parameters generated:
//   - ringCount           (1–8,    driven by generationDepth)
//   - spokeCount          (3–12,   driven by distinctLineages + memberCount)
//   - innerPatternType    (lotus|grid|diamond|star|web|spiral, driven by archetype)
//   - outerRingRadiusPct  (0.50–0.95, driven by graphDiameter)
//   - patternComplexity   (1–10,   driven by clusteringCoefficient × memberCount)
//   - primaryColorHex     (derived from dominant language hue)
//   - secondaryColorHex   (derived from 2nd language hue, or rotated)
//   - accentColorHex      (derived from weighted avg of remaining languages)
//   - pulseSpeedMs        (2000–6000ms, driven by avgDegree)
//
// This file has zero NestJS dependencies — it can be unit-tested in isolation
// (same pattern as graph-metrics.ts and archetype-classifier.service.ts).

import { GraphMetrics } from './graph-metrics';
import { ArchetypeKey } from './archetype-classifier.service';

// ─────────────────────────────────────────────────────────────────────────
// TYPES
// ─────────────────────────────────────────────────────────────────────────

export type InnerPattern =
  | 'lotus'
  | 'grid'
  | 'diamond'
  | 'star'
  | 'web'
  | 'spiral';

export interface AuraSymbolParameters {
  // Geometry
  ringCount: number;            // 1–8  (driven by generationDepth)
  spokeCount: number;           // 3–12 (driven by distinctLineages + memberCount)
  innerPatternType: InnerPattern;
  outerRingRadiusPct: number;   // 0.50–0.95 (driven by graphDiameter)
  patternComplexity: number;    // 1–10 (driven by clusteringCoefficient × memberCount)

  // Color (all hex strings, lowercase, 7 chars including #)
  primaryColorHex: string;
  secondaryColorHex: string;
  accentColorHex: string;

  // Animation
  pulseSpeedMs: number;         // 2000–6000ms (driven by avgDegree)
}

// ─────────────────────────────────────────────────────────────────────────
// CONSTANTS
// ─────────────────────────────────────────────────────────────────────────

// Language color palette — ISO-639-1 code → base hue (HSL degrees).
// Hues are blended proportionally from the languageDistribution map.
// All 14 app languages are included. Add new codes here without schema changes.
const LANGUAGE_HUES: Record<string, number> = {
  hi: 30,   // Hindi       — Saffron/Marigold
  ta: 280,  // Tamil       — Royal Purple
  te: 180,  // Telugu      — Teal
  mr: 340,  // Marathi     — Deep Rose
  gu: 45,   // Gujarati    — Amber Gold
  bn: 120,  // Bengali     — Forest Green
  pa: 20,   // Punjabi     — Warm Ochre
  ml: 200,  // Malayalam   — Deep Blue
  kn: 50,   // Kannada     — Golden
  or: 160,  // Odia        — Jade
  as: 95,   // Assamese    — Moss Green
  sd: 260,  // Sindhi      — Indigo
  ur: 320,  // Urdu        — Plum
  en: 210,  // English     — Steel Blue (fallback)
};

// Archetype → inner pattern mapping
const ARCHETYPE_PATTERNS: Record<ArchetypeKey, InnerPattern> = {
  banyan:      'web',      // Dense interconnected web
  river_delta: 'spiral',   // Outward spiral
  confluence:  'star',     // Multiple points meeting
  spine:       'grid',     // Linear grid
  lotus:       'lotus',    // Unfolding petals
  forest:      'diamond',  // Distributed diamonds
};

// ─────────────────────────────────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────────────────────────────────

export class AuraParameterGeneratorService {
  /**
   * Generate the full AURA symbol parameters from graph metrics + archetype.
   * Pure function — same inputs always produce the same outputs.
   */
  generate(metrics: GraphMetrics, archetypeKey: ArchetypeKey): AuraSymbolParameters {
    return {
      ringCount: this.computeRingCount(metrics.generationDepth),
      spokeCount: this.computeSpokeCount(metrics.distinctLineages, metrics.memberCount),
      innerPatternType: ARCHETYPE_PATTERNS[archetypeKey],
      outerRingRadiusPct: this.computeOuterRadius(metrics.graphDiameter),
      patternComplexity: this.computePatternComplexity(
        metrics.clusteringCoefficient,
        metrics.memberCount,
      ),
      ...this.computeColorPalette(metrics.languageDistribution),
      pulseSpeedMs: this.computePulseSpeed(metrics.avgDegree),
    };
  }

  // ── Ring Count: generationDepth → 1–8 rings ───────────────
  // 1 generation  → 2 rings (minimum visual structure)
  // 2 generations → 3 rings
  // 3 generations → 4 rings
  // 4 generations → 5 rings
  // 5 generations → 6 rings
  // 6+ generations → 6–8 rings (logarithmic to avoid overcrowding)

  computeRingCount(generationDepth: number): number {
    if (generationDepth <= 1) return 2;
    if (generationDepth <= 5) return generationDepth + 1;
    // Log scale for large families: 5 + log2(depth - 4), clamped to 8
    return Math.min(8, Math.round(5 + Math.log2(generationDepth - 4)));
  }

  // ── Spoke Count: distinctLineages + memberCount → 3–12 spokes ─
  // More lineages = more spokes. Member count adds sub-spokes.

  computeSpokeCount(distinctLineages: number, memberCount: number): number {
    const baseSpokes = Math.min(8, Math.max(3, distinctLineages + 2));
    // Add extra spokes for large families (every 20 members adds 1)
    const bonusSpokes = Math.min(4, Math.floor(memberCount / 20));
    return Math.min(12, baseSpokes + bonusSpokes);
  }

  // ── Outer Ring Radius: graphDiameter → 0.50–0.95 ──────────
  // Tight family (low diameter) → compact symbol (smaller radius)
  // Dispersed family (high diameter) → expansive symbol (larger radius)

  computeOuterRadius(graphDiameter: number): number {
    // Normalize diameter to 0–1 range (assuming typical max diameter ~12)
    const normalized = Math.min(1.0, graphDiameter / 12);
    return 0.5 + normalized * 0.45; // maps to 0.50–0.95
  }

  // ── Pattern Complexity: clustering × log(memberCount) → 1–10 ─
  // High clustering + many members = dense, complex inner pattern

  computePatternComplexity(
    clusteringCoefficient: number,
    memberCount: number,
  ): number {
    const logMembers = Math.log10(Math.max(1, memberCount));
    const raw = clusteringCoefficient * logMembers * 4;
    return Math.min(10, Math.max(1, Math.round(raw)));
  }

  // ── Color Palette: language ratios → 3 colors ──────────────
  // Algorithm:
  // 1. Find the dominant language (highest ratio) → primary hue
  // 2. Find the second-highest ratio language → secondary hue
  // 3. Blend the rest → accent hue (weighted average)
  // 4. Convert hues to rich, saturated hex colors
  //
  // Edge cases:
  //   - No languages (empty ratios) → primary=30 (saffron), secondary=150, accent=270
  //   - Only one language → secondary = primary+120, accent = primary+240 (color triad)

  computeColorPalette(
    ratios: Record<string, number>,
  ): Pick<AuraSymbolParameters, 'primaryColorHex' | 'secondaryColorHex' | 'accentColorHex'> {
    const entries = Object.entries(ratios)
      .map(([lang, ratio]) => ({ lang, ratio, hue: LANGUAGE_HUES[lang] ?? 0 }))
      .sort((a, b) => b.ratio - a.ratio);

    const [first, second, ...rest] = entries;

    // Primary: dominant language hue, high saturation, mid-dark lightness
    const primaryHue = first?.hue ?? 30; // fallback: saffron
    const secondaryHue = second?.hue ?? (primaryHue + 120) % 360;

    // Accent: weighted average hue of remaining languages
    const restTotal = rest.reduce((s, e) => s + e.ratio, 0);
    const accentHue =
      restTotal > 0
        ? rest.reduce((s, e) => s + (e.hue * e.ratio) / restTotal, 0)
        : (primaryHue + 240) % 360;

    return {
      primaryColorHex: this.hslToHex(primaryHue, 0.7, 0.45),
      secondaryColorHex: this.hslToHex(secondaryHue, 0.6, 0.35),
      accentColorHex: this.hslToHex(accentHue, 0.55, 0.5),
    };
  }

  // ── Pulse Speed: avgDegree → 2000–6000ms ──────────────────
  // High connectivity → faster pulse (family feels more alive)
  // Low connectivity → slower, meditative pulse

  computePulseSpeed(avgDegree: number): number {
    // Assume typical avgDegree range 0–8
    const normalized = Math.min(1.0, avgDegree / 8);
    // High avgDegree → low pulse ms (faster)
    return Math.round(6000 - normalized * 4000); // 6000ms → 2000ms
  }

  // ── Color Math: HSL → Hex ─────────────────────────────────

  /**
   * Convert HSL color values to a hex string.
   *
   * @param hDeg  Hue in degrees (0–360)
   * @param s     Saturation, 0.0–1.0
   * @param l     Lightness, 0.0–1.0
   * @returns     Hex string like "#a1b2c3" (lowercase, 7 chars)
   */
  hslToHex(hDeg: number, s: number, l: number): string {
    // Normalize hue to [0, 360)
    const h = ((hDeg % 360) + 360) % 360;

    // Standard HSL to RGB conversion
    const c = (1 - Math.abs(2 * l - 1)) * s;
    const x = c * (1 - Math.abs(((h / 60) % 2) - 1));
    const m = l - c / 2;

    let r = 0, g = 0, b = 0;
    if (h < 60)       { r = c; g = x; b = 0; }
    else if (h < 120) { r = x; g = c; b = 0; }
    else if (h < 180) { r = 0; g = c; b = x; }
    else if (h < 240) { r = 0; g = x; b = c; }
    else if (h < 300) { r = x; g = 0; b = c; }
    else              { r = c; g = 0; b = x; }

    const toHex = (v: number) =>
      Math.round((v + m) * 255).toString(16).padStart(2, '0');
    return `#${toHex(r)}${toHex(g)}${toHex(b)}`;
  }
}
