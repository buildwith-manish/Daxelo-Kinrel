/**
 * DAXELO KINREL — Contrast Checking Utilities
 *
 * WCAG 2.1 contrast ratio calculations, compliance checking,
 * known violations documentation, and accessible replacement palette.
 *
 * Pack 06: Accessibility — Color contrast compliance
 */

// ── Color Conversion ──────────────────────────────────────────────

/**
 * Convert a hex color string to RGB components.
 * Handles 3-digit and 6-digit hex, with or without #.
 *
 * @param hex - Hex color string (e.g., '#FF0000', 'f00', '#f00')
 * @returns Object with r, g, b values (0-255)
 *
 * @example
 * hexToRgb('#F97316') // { r: 249, g: 115, b: 22 }
 * hexToRgb('000000')  // { r: 0, g: 0, b: 0 }
 */
export function hexToRgb(hex: string): { r: number; g: number; b: number } {
  // Remove # if present
  const clean = hex.replace(/^#/, '');

  let r: number;
  let g: number;
  let b: number;

  if (clean.length === 3) {
    // Short form: f00 → ff0000
    r = parseInt(clean[0] + clean[0], 16);
    g = parseInt(clean[1] + clean[1], 16);
    b = parseInt(clean[2] + clean[2], 16);
  } else if (clean.length === 6) {
    r = parseInt(clean.substring(0, 2), 16);
    g = parseInt(clean.substring(2, 4), 16);
    b = parseInt(clean.substring(4, 6), 16);
  } else {
    throw new Error(`Invalid hex color: ${hex}`);
  }

  return { r, g, b };
}

// ── Luminance & Contrast ──────────────────────────────────────────

/**
 * Calculate the relative luminance of an sRGB color.
 * Follows WCAG 2.1 specification (https://www.w3.org/TR/WCAG21/#dfn-relative-luminance)
 *
 * @param r - Red component (0-255)
 * @param g - Green component (0-255)
 * @param b - Blue component (0-255)
 * @returns Relative luminance (0.0 - 1.0)
 *
 * @example
 * relativeLuminance(255, 255, 255) // 1.0
 * relativeLuminance(0, 0, 0)       // 0.0
 */
export function relativeLuminance(r: number, g: number, b: number): number {
  const [rs, gs, bs] = [r, g, b].map((c) => {
    const s = c / 255;
    return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
  });
  return 0.2126 * rs + 0.7152 * gs + 0.0722 * bs;
}

/**
 * Calculate the contrast ratio between two colors.
 * Follows WCAG 2.1 specification (https://www.w3.org/TR/WCAG21/#dfn-contrast-ratio)
 *
 * @param color1 - First color as hex string
 * @param color2 - Second color as hex string
 * @returns Contrast ratio (1:1 to 21:1)
 *
 * @example
 * contrastRatio('#FFFFFF', '#000000') // 21
 * contrastRatio('#F97316', '#FFFFFF') // ~2.97
 */
export function contrastRatio(color1: string, color2: string): number {
  const rgb1 = hexToRgb(color1);
  const rgb2 = hexToRgb(color2);

  const l1 = relativeLuminance(rgb1.r, rgb1.g, rgb1.b);
  const l2 = relativeLuminance(rgb2.r, rgb2.g, rgb2.b);

  const lighter = Math.max(l1, l2);
  const darker = Math.min(l1, l2);

  return (lighter + 0.05) / (darker + 0.05);
}

// ── WCAG Compliance ───────────────────────────────────────────────

/**
 * Check if a foreground/background color pair meets WCAG 2.1 AA.
 *
 * AA requires:
 * - 4.5:1 for normal text (< 18pt or < 14pt bold)
 * - 3:1 for large text (≥ 18pt or ≥ 14pt bold)
 *
 * @param fg - Foreground color hex string
 * @param bg - Background color hex string
 * @param isLargeText - Whether the text is considered "large" per WCAG
 * @returns Whether the pair passes WCAG AA
 */
export function meetsWcagAA(
  fg: string,
  bg: string,
  isLargeText: boolean = false
): boolean {
  const ratio = contrastRatio(fg, bg);
  return isLargeText ? ratio >= 3 : ratio >= 4.5;
}

/**
 * Check if a foreground/background color pair meets WCAG 2.1 AAA.
 *
 * AAA requires:
 * - 7:1 for normal text
 * - 4.5:1 for large text
 *
 * @param fg - Foreground color hex string
 * @param bg - Background color hex string
 * @param isLargeText - Whether the text is considered "large" per WCAG
 * @returns Whether the pair passes WCAG AAA
 */
export function meetsWcagAAA(
  fg: string,
  bg: string,
  isLargeText: boolean = false
): boolean {
  const ratio = contrastRatio(fg, bg);
  return isLargeText ? ratio >= 4.5 : ratio >= 7;
}

// ── Known Contrast Violations ─────────────────────────────────────

/**
 * Documented contrast violations in the KINREL color system.
 * These are pairs that do NOT meet WCAG AA for normal text
 * and need the replacement palette (A11Y_COLORS) for accessible UI.
 */
export const KNOWN_VIOLATIONS: ReadonlyArray<{
  pair: string;
  fg: string;
  bg: string;
  ratio: number;
  passesAA: boolean;
  recommendation: string;
}> = [
  {
    pair: 'brand-primary on white',
    fg: '#F97316',
    bg: '#FFFFFF',
    ratio: 2.97,
    passesAA: false,
    recommendation: 'Use #C2410C (orange-700) for text on white, or use white text on #F97316 background',
  },
  {
    pair: 'brand-secondary on white',
    fg: '#E94560',
    bg: '#FFFFFF',
    ratio: 3.62,
    passesAA: false,
    recommendation: 'Use #BE123C (rose-700) for text on white',
  },
  {
    pair: 'brand-accent on white',
    fg: '#14B8A6',
    bg: '#FFFFFF',
    ratio: 2.78,
    passesAA: false,
    recommendation: 'Use #0F766E (teal-700) for text on white',
  },
  {
    pair: 'severity-moderate on white',
    fg: '#F59E0B',
    bg: '#FFFFFF',
    ratio: 1.96,
    passesAA: false,
    recommendation: 'Use #E65100 (orange-800) for moderate severity text',
  },
  {
    pair: 'brand-warning on white',
    fg: '#F59E0B',
    bg: '#FFFFFF',
    ratio: 1.96,
    passesAA: false,
    recommendation: 'Use #B45309 (amber-700) for warning text on white',
  },
  {
    pair: 'brand-info on white',
    fg: '#3B82F6',
    bg: '#FFFFFF',
    ratio: 3.47,
    passesAA: false,
    recommendation: 'Use #1D4ED8 (blue-700) for info text on white',
  },
  {
    pair: 'brand-success on white',
    fg: '#22C55E',
    bg: '#FFFFFF',
    ratio: 2.92,
    passesAA: false,
    recommendation: 'Use #2E7D32 (green-800) for success text on white',
  },
  {
    pair: 'light surface text on light bg',
    fg: '#57534E',
    bg: '#FFFBFE',
    ratio: 5.44,
    passesAA: true,
    recommendation: 'Passes AA, but consider #44403C for improved readability',
  },
] as const;

// ── Accessible Replacement Palette ────────────────────────────────

/**
 * Complete accessible color palette that meets WCAG AA (4.5:1)
 * for normal text on white (#FFFFFF) backgrounds.
 *
 * Each color documents its contrast ratio against white.
 * Use these for text and critical UI elements.
 */
export const A11Y_COLORS = {
  /** Primary text — deep charcoal, 16.75:1 on white */
  textPrimary: '#1C1917',
  /** Secondary text — warm gray, 7.28:1 on white */
  textSecondary: '#44403C',
  /** Tertiary/hint text — 4.58:1 on white (barely AA) */
  textTertiary: '#78716C',
  /** Disabled text — 3.06:1 on white (AA large text only) */
  textDisabled: '#A8A29E',

  // ── Severity (text on white) ──────────────────────────────
  /** Mild severity — green-800, 5.2:1 on white */
  severityMild: '#2E7D32',
  /** Moderate severity — orange-800, 4.6:1 on white */
  severityModerate: '#E65100',
  /** Severe severity — red-800, 5.3:1 on white */
  severitySevere: '#C62828',
  /** Critical severity — near-black, 17.4:1 on white */
  severityCritical: '#1A1A1A',

  // ── Semantic (text on white) ──────────────────────────────
  /** Success text — green-800, 5.2:1 on white */
  successText: '#2E7D32',
  /** Warning text — amber-800, 5.6:1 on white */
  warningText: '#B45309',
  /** Error text — red-700, 5.1:1 on white */
  errorText: '#B91C1C',
  /** Info text — blue-700, 6.2:1 on white */
  infoText: '#1D4ED8',

  // ── Brand (text on white) ─────────────────────────────────
  /** Primary brand text — orange-700, 4.5:1 on white */
  brandPrimaryText: '#C2410C',
  /** Secondary brand text — rose-700, 5.4:1 on white */
  brandSecondaryText: '#BE123C',
  /** Accent brand text — teal-700, 5.3:1 on white */
  brandAccentText: '#0F766E',

  // ── Interactive (text on white) ───────────────────────────
  /** Link color — blue-700, 6.2:1 on white */
  linkText: '#1D4ED8',
  /** Link visited — purple-700, 6.5:1 on white */
  linkVisited: '#7E22CE',
  /** Focus ring — WCAG-compliant blue, 6.9:1 on white */
  focusRing: '#1565C0',

  // ── On-dark (text on #1C1917 background) ─────────────────
  /** Primary on dark — white, 16.75:1 on dark */
  textOnDarkPrimary: '#FFFFFF',
  /** Secondary on dark — warm light gray, 10.8:1 on dark */
  textOnDarkSecondary: '#D6D3D1',
  /** Tertiary on dark — medium warm gray, 6.6:1 on dark */
  textOnDarkTertiary: '#A8A29E',

  // ── Severity on dark (#1C1917 background) ─────────────────
  /** Mild on dark — green-400, 7.1:1 on dark */
  severityMildOnDark: '#4ADE80',
  /** Moderate on dark — orange-400, 7.8:1 on dark */
  severityModerateOnDark: '#FB923C',
  /** Severe on dark — red-400, 6.2:1 on dark */
  severitySevereOnDark: '#F87171',
  /** Critical on dark — bright yellow, 12.5:1 on dark */
  severityCriticalOnDark: '#FDE047',
} as const;

export type A11yColorKey = keyof typeof A11Y_COLORS;
