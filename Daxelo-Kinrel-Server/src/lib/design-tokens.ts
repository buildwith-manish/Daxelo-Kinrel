/**
 * KINREL — Design Tokens
 *
 * Single source of truth for all design tokens.
 * Mirrors the Flutter AppTokens for cross-platform consistency.
 * Brand spec: kinrel-brand-complete.zip v4.0
 *
 * Pack 01: Design System — Token-driven design for 14 Indian languages
 */

// ── Spacing Tokens ──────────────────────────────────────────────────
export const spacing = {
  xs: 4,
  sm: 8,
  md: 12,
  lg: 16,
  xl: 20,
  xxl: 24,
  xxxl: 32,
  huge: 48,
} as const;

// Semantic spacing aliases
export const semanticSpacing = {
  screenHorizontal: spacing.lg,       // 16
  screenVertical: spacing.xl,         // 20
  cardPadding: spacing.lg,            // 16
  cardInnerGap: spacing.md,           // 12
  sectionGap: spacing.xxl,            // 24
  listItemGap: spacing.sm,            // 8
  formFieldGap: spacing.md,           // 12
  chipGap: spacing.xs,                // 4
  avatarSize: 40,
  avatarSizeLarge: 64,
  iconButtonSize: 48,                 // Material tap target
} as const;

// ── Radius Tokens ───────────────────────────────────────────────────
export const radius = {
  none: 0,
  xs: 4,
  sm: 8,
  md: 12,
  lg: 16,
  xl: 20,
  xxl: 28,
  full: 9999,
} as const;

// Semantic radius aliases
export const semanticRadius = {
  cardRadius: radius.lg,              // 16
  buttonRadius: radius.sm,            // 8
  inputRadius: radius.sm,             // 8
  dialogRadius: radius.xxl,           // 28
  bottomSheetRadius: radius.xxl,      // 28
  chipRadius: radius.xs,              // 4
  fabRadius: radius.full,             // circle
} as const;

// ── Motion Tokens ───────────────────────────────────────────────────
export const motion = {
  instant: 50,
  fast: 150,
  normal: 300,
  slow: 500,
  deliberate: 800,
  ceremonial: 1200,
  lingering: 1200,
} as const;

// Motion curves
export const curves = {
  easeOut: [0.33, 1, 0.68, 1] as const,        // easeOutCubic
  easeIn: [0.32, 0, 0.67, 0] as const,          // easeInCubic
  spring: [0.68, -0.6, 0.32, 1.6] as const,     // elasticOut
  linear: [0, 0, 1, 1] as const,
  decelerate: [0, 0, 0.2, 1] as const,          // Material decelerate
  accelerate: [0.4, 0, 1, 1] as const,          // Material accelerate
} as const;

// ── Opacity Tokens ──────────────────────────────────────────────────
export const opacity = {
  disabled: 0.38,
  hint: 0.60,
  secondary: 0.70,
  primary: 1.00,
  scrim: 0.32,
  hover: 0.08,
  focus: 0.12,
  pressed: 0.12,
  dragged: 0.16,
} as const;

// ── Elevation Tokens ────────────────────────────────────────────────
export const elevation = {
  none: 0,
  sm: 1,
  md: 3,
  lg: 6,
  xl: 12,
} as const;

// Elevation shadow maps
export const shadows = {
  none: 'none',
  sm: '0 1px 2px 0 rgb(0 0 0 / 0.05)',
  md: '0 4px 6px -1px rgb(0 0 0 / 0.1), 0 2px 4px -2px rgb(0 0 0 / 0.1)',
  lg: '0 10px 15px -3px rgb(0 0 0 / 0.1), 0 4px 6px -4px rgb(0 0 0 / 0.1)',
  xl: '0 20px 25px -5px rgb(0 0 0 / 0.1), 0 8px 10px -6px rgb(0 0 0 / 0.1)',
} as const;

// ── Typography Tokens ───────────────────────────────────────────────
export const typography = {
  displayLarge:  { fontSize: 32, fontWeight: 800, lineHeight: 1.2, letterSpacing: -0.5 },
  displayMedium: { fontSize: 28, fontWeight: 700, lineHeight: 1.2, letterSpacing: -0.5 },
  displaySmall:  { fontSize: 24, fontWeight: 700, lineHeight: 1.2, letterSpacing: -0.5 },
  headlineLarge: { fontSize: 22, fontWeight: 700, lineHeight: 1.2, letterSpacing: -0.5 },
  headlineMedium:{ fontSize: 20, fontWeight: 600, lineHeight: 1.4, letterSpacing: 0 },
  headlineSmall: { fontSize: 18, fontWeight: 600, lineHeight: 1.4, letterSpacing: 0 },
  titleLarge:    { fontSize: 16, fontWeight: 600, lineHeight: 1.4, letterSpacing: 0.5 },
  titleMedium:   { fontSize: 14, fontWeight: 500, lineHeight: 1.4, letterSpacing: 0.5 },
  titleSmall:    { fontSize: 12, fontWeight: 500, lineHeight: 1.4, letterSpacing: 1.0 },
  bodyLarge:     { fontSize: 16, fontWeight: 400, lineHeight: 1.6, letterSpacing: 0 },
  bodyMedium:    { fontSize: 14, fontWeight: 400, lineHeight: 1.6, letterSpacing: 0 },
  bodySmall:     { fontSize: 12, fontWeight: 400, lineHeight: 1.6, letterSpacing: 0 },
  labelLarge:    { fontSize: 14, fontWeight: 600, lineHeight: 1.4, letterSpacing: 1.0 },
  labelMedium:   { fontSize: 12, fontWeight: 500, lineHeight: 1.4, letterSpacing: 1.0 },
  labelSmall:    { fontSize: 10, fontWeight: 500, lineHeight: 1.4, letterSpacing: 1.5 },
} as const;

// ── Line Height Tokens ──────────────────────────────────────────────
export const lineHeight = {
  tight: 1.2,
  normal: 1.4,
  relaxed: 1.6,
  loose: 1.8,
} as const;

// ── Letter Spacing Tokens ───────────────────────────────────────────
export const letterSpacing = {
  tight: -0.5,
  normal: 0,
  wide: 0.5,
  wider: 1.0,
  wideUppercase: 1.5,
} as const;

// ── Indian Script Font Families ─────────────────────────────────────
export const scriptFonts: Record<string, string> = {
  en: 'Outfit',
  hi: 'Noto Sans Devanagari',
  bn: 'Noto Sans Bengali',
  ta: 'Noto Sans Tamil',
  te: 'Noto Sans Telugu',
  kn: 'Noto Sans Kannada',
  ml: 'Noto Sans Malayalam',
  gu: 'Noto Sans Gujarati',
  mr: 'Noto Sans Devanagari',
  pa: 'Noto Sans Gurmukhi',
  or: 'Noto Sans Oriya',
  ur: 'Noto Sans Arabic',
  as: 'Noto Sans Bengali',
  sa: 'Noto Sans Devanagari',
} as const;

// RTL scripts
export const rtlScripts = new Set(['ur', 'ar'])

// Font size preference scaling
export const fontScaleFactors = {
  small: 0.85,
  medium: 1.0,
  large: 1.15,
  extraLarge: 1.3,
} as const;

// ── Breakpoint Tokens ───────────────────────────────────────────────
export const breakpoints = {
  compact: 600,
  medium: 840,
  expanded: 1200,
  large: 1600,
} as const;

// ── Z-Index Tokens ──────────────────────────────────────────────────
export const zIndex = {
  base: 0,
  dropdown: 10,
  sticky: 20,
  overlay: 30,
  modal: 40,
  popover: 50,
  toast: 60,
  tooltip: 70,
} as const;

// ── Type-safe Tailwind config bridge ────────────────────────────────
export const tailwindTokens = {
  spacing: Object.fromEntries(
    Object.entries(spacing).map(([k, v]) => [k, `${v}px`])
  ),
  borderRadius: Object.fromEntries(
    Object.entries({ ...radius, ...semanticRadius }).map(([k, v]) => [k, `${v}px`])
  ),
  transitionDuration: Object.fromEntries(
    Object.entries(motion).map(([k, v]) => [k, `${v}ms`])
  ),
} as const;

// ── Brand Color Palette ─────────────────────────────────────────────
// Source: kinrel-brand-complete.zip v4.0 — brand-tokens.css

export const brandColors = {
  // ── Kinrel Orange Accents ──────────────────────────────
  orange:  '#E8612A',   // Primary CTA / icon nodes
  amber:   '#F59240',   // Highlights, glow
  ember:   '#C44A18',   // Depth, gradient end

  // ── Backgrounds (dark-first) ──────────────────────────
  bg:       '#13141E',   // App background
  card:     '#191B2C',   // Card surfaces
  elevated: '#202338',   // Elevated / muted surfaces
  border:   'rgba(255, 255, 255, 0.10)',

  // ── Text ──────────────────────────────────────────────
  white:  '#F5F0EE',   // Foreground text — 14.5:1 contrast ✓
  silver: '#C9B4A8',   // Body text — 5.1:1 contrast ✓
  dim:    '#8A7A72',   // Disabled / placeholder only

  // ── Semantic Colors ───────────────────────────────────
  error:   '#F04E2A',
  success: '#4CAF7A',
  warning: '#F5A623',
  info:    '#60A5FA',

  // ── Glow ──────────────────────────────────────────────
  glow: 'rgba(232, 97, 42, 0.28)',

  // ── Light Mode Overrides ──────────────────────────────
  lightBg:       '#FFFAF8',
  lightCard:     '#FFFFFF',
  lightElevated: '#F5EDE8',
  lightBorder:   'rgba(0, 0, 0, 0.08)',
  lightWhite:    '#1A0A00',   // text inverts to dark on light bg
  lightSilver:   '#7A5040',
  lightDim:      '#B08060',
  lightOrange:   '#C44A18',  // slightly darker for legibility
} as const;

// ── Brand Gradients ──────────────────────────────────────────────────
export const brandGradients = {
  ignite:   'linear-gradient(135deg, #E8612A 0%, #F59240 100%)',   // Primary CTA buttons
  heritage: 'linear-gradient(135deg, #E8612A 0%, #C44A18 100%)',   // Depth sections
  wordmark: 'linear-gradient(135deg, #F5F0EE 0%, #E8612A 100%)',   // Splash / hero wordmark
} as const;

// ── Brand Typography ─────────────────────────────────────────────────
export const brandFonts = {
  display: "'Outfit', sans-serif",      // Display, wordmark, hero headings
  body:    "'DM Sans', sans-serif",     // All UI body text, labels, buttons
  mono:    "'DM Mono', monospace",       // Tags, metadata, code
} as const;

// ── Letter spacing rules (brand spec) ────────────────────────────────
export const brandLetterSpacing = {
  wordmarkXsSm:   '0.08em',   // wordmark at xs, sm sizes
  wordmarkMdUp:   '0.14em',   // wordmark at md and above
  bylineDaxelo:   '0.26em',   // "by Daxelo" subtitle
  bylineAllCaps:  '0.28em',   // "BY DAXELO" all-caps sub
} as const;

// ── Logo Size Reference ──────────────────────────────────────────────
export const logoSizes = {
  xs: { iconPx: 28, fontPx: 16.8, use: 'Compact / small screens' },
  sm: { iconPx: 36, fontPx: 22.4, use: 'App bar' },
  md: { iconPx: 48, fontPx: 28.0, use: 'Standard — onboarding, cards' },
  lg: { iconPx: 64, fontPx: 39.2, use: 'Auth screens' },
  xl: { iconPx: 96, fontPx: 56.0, use: 'Splash, about' },
} as const;

// ── Festival Color Extensions ────────────────────────────────────────
export const festivalColors = {
  diwali:   { primary: '#FFB800', secondary: '#FF6B00', accent: '#8B0000' },
  holi:     { primary: '#FF1493', secondary: '#00CED1', accent: '#7FFF00' },
  eid:      { primary: '#00703C', secondary: '#C5A028', accent: '#FFFFFF' },
  navratri: { primary: '#FF4500', secondary: '#FF8C00', accent: '#FFD700' },
  onam:     { primary: '#FF6600', secondary: '#FFCC00', accent: '#00AA44' },
  baisakhi: { primary: '#FFD700', secondary: '#FF4500', accent: '#006400' },
  pongal:   { primary: '#FF8C00', secondary: '#228B22', accent: '#FFD700' },
  durga:    { primary: '#FF0000', secondary: '#FF6600', accent: '#FFFF00' },
} as const;

// ── ColorBlind-Safe Palette ──────────────────────────────────────────
export const colorblindSafe = {
  // Deuteranopia-safe substitutes
  crimsonSubstitute: '#0066CC',
  saffronSubstitute: '#FF6600',
  // High contrast mode: min 7:1 ratio, all interactive 4.5:1
} as const;
