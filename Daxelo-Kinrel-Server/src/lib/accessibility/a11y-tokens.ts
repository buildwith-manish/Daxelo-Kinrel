/**
 * DAXELO KINREL — Accessibility Design Tokens
 *
 * Complete accessibility token system for WCAG 2.1 AA/AAA compliance,
 * Indian cultural context, and multi-script support.
 *
 * Pack 06: Accessibility — Token-driven accessible design
 */

// ── Focus Tokens ───────────────────────────────────────────────────
export const FocusTokens = {
  /** Focus ring color — high-visibility blue that passes WCAG on both light and dark */
  color: '#1565C0',
  /** Focus ring width in pixels */
  width: 3.0,
  /** Offset from the element boundary in pixels */
  offset: 2.0,
  /** Border radius of the focus ring in pixels */
  borderRadius: 4.0,
  /** Only show focus ring for keyboard navigation, not mouse clicks */
  keyboardOnly: true,
} as const;

export type FocusTokenKey = keyof typeof FocusTokens;

// ── Touch Target Tokens ────────────────────────────────────────────
export const TouchTargetTokens = {
  /** Minimum touch target size in dp (WCAG 2.5.5) */
  minimum: 48,
  /** Comfortable touch target for frequent interactions */
  comfortable: 56,
  /** Large touch target for elderly or motor-impaired users */
  large: 64,
  /** Minimum spacing between adjacent touch targets in dp */
  minimumSpacing: 8,
} as const;

export type TouchTargetTokenKey = keyof typeof TouchTargetTokens;

// ── Spacing Tokens (4dp base scale) ───────────────────────────────
export const SpacingTokens = {
  /** 4dp */
  xs: 4,
  /** 8dp */
  sm: 8,
  /** 12dp */
  md: 12,
  /** 16dp */
  lg: 16,
  /** 24dp */
  xl: 24,
  /** 32dp */
  xxl: 32,
  /** 48dp */
  xxxl: 48,
  /** Minimum spacing for interactive elements (dp) */
  interactiveMin: 8,
  /** Padding around touch targets (dp) */
  touchPadding: 12,
  /** Gap between form fields (dp) */
  formFieldGap: 16,
  /** Gap between major sections (dp) */
  sectionGap: 24,
} as const;

export type SpacingTokenKey = keyof typeof SpacingTokens;

// ── Motion Tokens ─────────────────────────────────────────────────
export const MotionTokens = {
  /** Instant feedback — 50ms */
  instant: 50,
  /** Fast transition — 150ms */
  fast: 150,
  /** Normal transition — 300ms */
  normal: 300,
  /** Slow transition — 500ms */
  slow: 500,

  // ── Reduced motion alternatives (prefers-reduced-motion) ──────
  /** Reduced: instant → 0ms */
  reducedInstant: 0,
  /** Reduced: fast → 0ms */
  reducedFast: 0,
  /** Reduced: normal → 50ms */
  reducedNormal: 50,
  /** Reduced: slow → 100ms */
  reducedSlow: 100,
} as const;

export type MotionTokenKey = keyof typeof MotionTokens;

/**
 * Returns the appropriate duration based on prefers-reduced-motion.
 * When reduced motion is preferred, durations are shortened significantly
 * to prevent vestibular discomfort while maintaining basic feedback.
 */
export function duration(
  level: 'instant' | 'fast' | 'normal' | 'slow',
  prefersReducedMotion: boolean
): number {
  if (prefersReducedMotion) {
    const reducedMap: Record<string, number> = {
      instant: MotionTokens.reducedInstant,
      fast: MotionTokens.reducedFast,
      normal: MotionTokens.reducedNormal,
      slow: MotionTokens.reducedSlow,
    };
    return reducedMap[level];
  }
  const standardMap: Record<string, number> = {
    instant: MotionTokens.instant,
    fast: MotionTokens.fast,
    normal: MotionTokens.normal,
    slow: MotionTokens.slow,
  };
  return standardMap[level];
}

// ── High Contrast Tokens ──────────────────────────────────────────
export const HighContrastTokens = {
  /** Pure black background for maximum contrast */
  background: '#000000',
  /** Pure white text — 21:1 contrast ratio on black */
  textOnBlack: '#FFFFFF',
  /** Contrast ratio of white on black */
  contrastRatio: 21 as number,
  /** Bright yellow focus ring — maximum visibility on any background */
  focusRing: '#FFFF00',
  /** High-contrast error — bright red */
  error: '#FF0000',
  /** High-contrast success — bright green */
  success: '#00FF00',
  /** High-contrast warning — bright orange */
  warning: '#FF8800',
  /** High-contrast info — bright cyan */
  info: '#00FFFF',
  /** High-contrast link — bright blue */
  link: '#00AAFF',
  /** Disabled text — still visible but clearly muted */
  disabled: '#767676',
} as const;

export type HighContrastTokenKey = keyof typeof HighContrastTokens;

// ── Color Blind Safe Tokens ───────────────────────────────────────
/**
 * Wong palette — 8 colors designed to be distinguishable by people
 * with the most common forms of color vision deficiency
 * (deuteranopia, protanopia, tritanopia).
 *
 * Reference: Wong, B. (2011) Points of view: Color blindness.
 * Nature Methods, 8, 441.
 */
export const ColorBlindSafeTokens = {
  /** Wong palette — 8 distinct colors for data visualization */
  wongPalette: {
    blue: '#0072B2',
    orange: '#E69F00',
    green: '#009E73',
    red: '#D55E00',
    purple: '#CC79A7',
    cyan: '#56B4E9',
    yellow: '#F0E442',
    black: '#000000',
  } as const,

  /** Gender indicator colors — distinguishable in all CVD types */
  genderIndicators: {
    male: '#0072B2',       // Wong blue
    female: '#CC79A7',     // Wong purple/pink
    other: '#E69F00',      // Wong orange
  } as const,

  /**
   * Severity indicators with both color AND icon pairing.
   * Never rely on color alone — always pair with icon/label.
   */
  severityWithIcon: {
    mild: {
      color: '#009E73',    // Wong green
      icon: 'info',        // ℹ or CircleInfo
      label: 'Mild',
    },
    moderate: {
      color: '#E69F00',    // Wong orange
      icon: 'warning',     // ⚠ or TriangleAlert
      label: 'Moderate',
    },
    severe: {
      color: '#D55E00',    // Wong red-orange
      icon: 'error',       // ✕ or CircleX
      label: 'Severe',
    },
    critical: {
      color: '#000000',    // Wong black
      icon: 'alert',       // ‼ or AlertTriangle
      label: 'Critical',
    },
  } as const,

  /**
   * Relationship line colors — distinguishable for family tree
   * visualization with CVD-safe palette
   */
  relationshipLines: {
    parent: '#0072B2',     // Blue — parent connections
    spouse: '#D55E00',     // Red-orange — spouse connections
    sibling: '#009E73',    // Green — sibling connections
    child: '#56B4E9',      // Cyan — child connections
  } as const,
} as const;

export type ColorBlindSafeTokenKey = keyof typeof ColorBlindSafeTokens;

// ── Aggregated Export ─────────────────────────────────────────────
/**
 * Complete accessibility token set — import everything at once
 * or import individual token groups.
 */
export const a11yTokens = {
  focus: FocusTokens,
  touchTarget: TouchTargetTokens,
  spacing: SpacingTokens,
  motion: MotionTokens,
  highContrast: HighContrastTokens,
  colorBlindSafe: ColorBlindSafeTokens,
} as const;
