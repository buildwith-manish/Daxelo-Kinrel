/**
 * KINREL Mirror — Design System Tokens
 * Cross-platform design tokens matching the Flutter app tokens.
 * Brand spec: kinrel-brand-complete.zip v4.0
 */

// ── Spacing Tokens ──────────────────────────────────────────────────
export const spacing = {
  xs: 4, sm: 8, md: 12, lg: 16, xl: 20, xxl: 24, xxxl: 32, huge: 48,
} as const;

export const semanticSpacing = {
  screenHorizontal: spacing.lg,
  screenVertical: spacing.xl,
  cardPadding: spacing.lg,
  cardInnerGap: spacing.md,
  sectionGap: spacing.xxl,
  listItemGap: spacing.sm,
  formFieldGap: spacing.md,
  chipGap: spacing.xs,
  avatarSize: 40,
  avatarSizeLarge: 64,
  iconButtonSize: 48,
} as const;

// ── Radius Tokens ───────────────────────────────────────────────────
export const radius = {
  none: 0, xs: 4, sm: 8, md: 12, lg: 16, xl: 20, xxl: 28, full: 9999,
} as const;

export const semanticRadius = {
  cardRadius: radius.lg,
  buttonRadius: radius.sm,
  inputRadius: radius.sm,
  dialogRadius: radius.xxl,
  bottomSheetRadius: radius.xxl,
  chipRadius: radius.xs,
  fabRadius: radius.full,
} as const;

// ── Motion Tokens ───────────────────────────────────────────────────
export const motion = {
  instant: 50, fast: 150, normal: 300, slow: 500, deliberate: 800, ceremonial: 1200, lingering: 1200,
} as const;

export const curves = {
  easeOut: [0.33, 1, 0.68, 1] as const,
  easeIn: [0.32, 0, 0.67, 0] as const,
  spring: [0.68, -0.6, 0.32, 1.6] as const,
  linear: [0, 0, 1, 1] as const,
  decelerate: [0, 0, 0.2, 1] as const,
  accelerate: [0.4, 0, 1, 1] as const,
} as const;

// ── Opacity Tokens ──────────────────────────────────────────────────
export const opacity = {
  disabled: 0.38, hint: 0.60, secondary: 0.70, primary: 1.00,
  scrim: 0.32, hover: 0.08, focus: 0.12, pressed: 0.12, dragged: 0.16,
} as const;

// ── Elevation Tokens ────────────────────────────────────────────────
export const elevation = { none: 0, sm: 1, md: 3, lg: 6, xl: 12 } as const;

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

// ── Indian Script Font Families ─────────────────────────────────────
export const scriptFonts: Record<string, string> = {
  en: 'Outfit', hi: 'Noto Sans Devanagari', bn: 'Noto Sans Bengali',
  ta: 'Noto Sans Tamil', te: 'Noto Sans Telugu', kn: 'Noto Sans Kannada',
  ml: 'Noto Sans Malayalam', gu: 'Noto Sans Gujarati', mr: 'Noto Sans Devanagari',
  pa: 'Noto Sans Gurmukhi', or: 'Noto Sans Oriya', ur: 'Noto Sans Arabic',
  as: 'Noto Sans Bengali', sa: 'Noto Sans Devanagari',
} as const;

export const rtlScripts = new Set(['ur', 'ar']);

export const fontScaleFactors = {
  small: 0.85, medium: 1.0, large: 1.15, extraLarge: 1.3,
} as const;

// ── Breakpoint Tokens ───────────────────────────────────────────────
export const breakpoints = {
  compact: 600, medium: 840, expanded: 1200, large: 1600,
} as const;

// ── Z-Index Tokens ──────────────────────────────────────────────────
export const zIndex = {
  base: 0, dropdown: 10, sticky: 20, overlay: 30, modal: 40,
  popover: 50, toast: 60, tooltip: 70,
} as const;

// ── Brand Color Palette ─────────────────────────────────────────────
export const brandColors = {
  orange: '#E8612A', amber: '#F59240', ember: '#C44A18',
  bg: '#13141E', card: '#191B2C', elevated: '#202338',
  border: 'rgba(255, 255, 255, 0.10)',
  white: '#F5F0EE', silver: '#C9B4A8', dim: '#8A7A72',
  error: '#F04E2A', success: '#4CAF7A', warning: '#F5A623', info: '#60A5FA',
  glow: 'rgba(232, 97, 42, 0.28)',
  lightBg: '#FFFAF8', lightCard: '#FFFFFF', lightElevated: '#F5EDE8',
  lightBorder: 'rgba(0, 0, 0, 0.08)', lightWhite: '#1A0A00',
  lightSilver: '#7A5040', lightDim: '#B08060', lightOrange: '#C44A18',
} as const;

// ── Brand Gradients ──────────────────────────────────────────────────
export const brandGradients = {
  ignite: 'linear-gradient(135deg, #E8612A 0%, #F59240 100%)',
  heritage: 'linear-gradient(135deg, #E8612A 0%, #C44A18 100%)',
  wordmark: 'linear-gradient(135deg, #F5F0EE 0%, #E8612A 100%)',
} as const;

// ── Brand Typography ─────────────────────────────────────────────────
export const brandFonts = {
  display: "'Outfit', sans-serif",
  body: "'DM Sans', sans-serif",
  mono: "'DM Mono', monospace",
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

// ── Semantic Color Map (Tailwind bridge) ─────────────────────────────
export const semanticColors = {
  primary: brandColors.orange,
  primaryForeground: brandColors.white,
  secondary: brandColors.elevated,
  secondaryForeground: brandColors.silver,
  muted: brandColors.elevated,
  mutedForeground: brandColors.dim,
  accent: brandColors.amber,
  accentForeground: brandColors.white,
  destructive: brandColors.error,
  background: brandColors.bg,
  foreground: brandColors.white,
  card: brandColors.card,
  cardForeground: brandColors.white,
  popover: brandColors.card,
  popoverForeground: brandColors.white,
  border: brandColors.border,
  input: brandColors.border,
  ring: brandColors.orange,
} as const;

// ── Tailwind CSS Variables Bridge ────────────────────────────────────
export const tailwindBridge = {
  colors: {
    background: brandColors.bg,
    foreground: brandColors.white,
    card: { DEFAULT: brandColors.card, foreground: brandColors.white },
    popover: { DEFAULT: brandColors.card, foreground: brandColors.white },
    primary: { DEFAULT: brandColors.orange, foreground: brandColors.white },
    secondary: { DEFAULT: brandColors.elevated, foreground: brandColors.silver },
    muted: { DEFAULT: brandColors.elevated, foreground: brandColors.dim },
    accent: { DEFAULT: brandColors.amber, foreground: brandColors.white },
    destructive: { DEFAULT: brandColors.error, foreground: brandColors.white },
    border: brandColors.border,
    input: brandColors.border,
    ring: brandColors.orange,
  },
} as const;
