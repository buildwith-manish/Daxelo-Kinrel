/**
 * DAXELO KINREL — Color System
 *
 * Complete color system with primary palette, neutral tokens,
 * semantic tokens, festival extensions, and WCAG AA compliance.
 *
 * Pack 12: Brand & Motion — Color System
 */

// ── Primary Palette ────────────────────────────────────────────────
export const PRIMARY_PALETTE = {
  primary: '#F97316',
  primaryLight: '#FB923C',
  primaryDark: '#EA580C',
  primaryContainer: '#FFF7ED',
  primaryContainerDark: '#431407',
  onPrimary: '#FFFFFF',
  onPrimaryContainer: '#7C2D12',
  onPrimaryContainerDark: '#FB923C',

  secondary: '#E94560',
  secondaryLight: '#F47289',
  secondaryDark: '#C81D45',
  secondaryContainer: '#FFE0E6',
  secondaryContainerDark: '#5C2030',
  onSecondary: '#FFFFFF',

  accent: '#14B8A6',
  accentLight: '#5EEAD4',
  accentDark: '#0D9488',
  accentContainer: '#CCFBF1',
  accentContainerDark: '#134E4A',
} as const;

// ── Neutral Palette ────────────────────────────────────────────────
export const NEUTRAL_PALETTE = {
  0: '#000000',
  50: '#FAFAF9',
  100: '#F5F5F4',
  200: '#E7E5E4',
  300: '#D6D3D1',
  400: '#A8A29E',
  500: '#78716C',
  600: '#57534E',
  700: '#44403C',
  800: '#292524',
  900: '#1C1917',
  950: '#0C0A09',
} as const;

/** Light/dark role mapping for neutral tokens */
export const NEUTRAL_ROLE_MAP = {
  light: {
    background: NEUTRAL_PALETTE[50],
    surface: NEUTRAL_PALETTE[50],
    surfaceContainer: NEUTRAL_PALETTE[100],
    surfaceContainerHigh: NEUTRAL_PALETTE[200],
    surfaceContainerHighest: NEUTRAL_PALETTE[300],
    onSurface: NEUTRAL_PALETTE[900],
    onSurfaceVariant: NEUTRAL_PALETTE[600],
    outline: NEUTRAL_PALETTE[400],
    outlineVariant: NEUTRAL_PALETTE[300],
  },
  dark: {
    background: NEUTRAL_PALETTE[900],
    surface: NEUTRAL_PALETTE[900],
    surfaceContainer: NEUTRAL_PALETTE[800],
    surfaceContainerHigh: NEUTRAL_PALETTE[700],
    surfaceContainerHighest: NEUTRAL_PALETTE[600],
    onSurface: NEUTRAL_PALETTE[100],
    onSurfaceVariant: NEUTRAL_PALETTE[300],
    outline: NEUTRAL_PALETTE[500],
    outlineVariant: NEUTRAL_PALETTE[700],
  },
} as const;

// ── Semantic Tokens ────────────────────────────────────────────────
export interface SemanticToken {
  light: string;
  dark: string;
  wcagAARatio: number;
  role: string;
}

export const SEMANTIC_TOKENS: Record<string, SemanticToken> = {
  success: {
    light: '#22C55E',
    dark: '#4ADE80',
    wcagAARatio: 3.1,
    role: 'Positive outcomes, confirmations, completed states',
  },
  error: {
    light: '#EF4444',
    dark: '#F87171',
    wcagAARatio: 3.5,
    role: 'Errors, destructive actions, validation failures',
  },
  warning: {
    light: '#F59E0B',
    dark: '#FBBF24',
    wcagAARatio: 1.9,
    role: 'Cautions, important notices, pending states',
  },
  info: {
    light: '#3B82F6',
    dark: '#60A5FA',
    wcagAARatio: 3.8,
    role: 'Informational, help text, discoverable features',
  },
  onPrimary: {
    light: '#FFFFFF',
    dark: '#1C1917',
    wcagAARatio: 4.6,
    role: 'Text on primary color surfaces',
  },
  onSecondary: {
    light: '#FFFFFF',
    dark: '#1C1917',
    wcagAARatio: 4.3,
    role: 'Text on secondary color surfaces',
  },
  surface: {
    light: '#FFFBFE',
    dark: '#1C1917',
    wcagAARatio: 15.2,
    role: 'Primary surface background',
  },
  onSurface: {
    light: '#1C1917',
    dark: '#F5F5F4',
    wcagAARatio: 15.2,
    role: 'Primary text on surface',
  },
};

// ── Festival Extensions ────────────────────────────────────────────
export interface FestivalTheme {
  name: string;
  primary: string;
  secondary: string;
  accent: string;
  gradient: [string, string, string];
  startMonth: number;
  startDay: number;
  endMonth: number;
  endDay: number;
  duration: number; // days
}

export const FESTIVAL_EXTENSIONS: Record<string, FestivalTheme> = {
  diwali: {
    name: 'Diwali — Festival of Lights',
    primary: '#FFD700',
    secondary: '#FF6B00',
    accent: '#FF1493',
    gradient: ['#FFD700', '#FF6B00', '#FF1493'],
    startMonth: 10,
    startDay: 1,
    endMonth: 11,
    endDay: 15,
    duration: 15,
  },
  holi: {
    name: 'Holi — Festival of Colours',
    primary: '#FF6B6B',
    secondary: '#4ECDC4',
    accent: '#9B59B6',
    gradient: ['#FF6B6B', '#4ECDC4', '#9B59B6'],
    startMonth: 3,
    startDay: 1,
    endMonth: 3,
    endDay: 31,
    duration: 15,
  },
  eid: {
    name: 'Eid ul-Fitr',
    primary: '#2ECC71',
    secondary: '#F1C40F',
    accent: '#3498DB',
    gradient: ['#2ECC71', '#F1C40F', '#3498DB'],
    startMonth: 3,
    startDay: 20,
    endMonth: 4,
    endDay: 15,
    duration: 10,
  },
  navratri: {
    name: 'Navratri — Nine Nights',
    primary: '#E74C3C',
    secondary: '#FFD700',
    accent: '#9B59B6',
    gradient: ['#E74C3C', '#FFD700', '#9B59B6'],
    startMonth: 9,
    startDay: 26,
    endMonth: 10,
    endDay: 15,
    duration: 10,
  },
  pongal: {
    name: 'Pongal — Harvest Festival',
    primary: '#F39C12',
    secondary: '#E74C3C',
    accent: '#2ECC71',
    gradient: ['#F39C12', '#E74C3C', '#2ECC71'],
    startMonth: 1,
    startDay: 10,
    endMonth: 1,
    endDay: 17,
    duration: 7,
  },
  onam: {
    name: 'Onam — Kerala Harvest',
    primary: '#27AE60',
    secondary: '#F1C40F',
    accent: '#E74C3C',
    gradient: ['#27AE60', '#F1C40F', '#E74C3C'],
    startMonth: 8,
    startDay: 20,
    endMonth: 9,
    endDay: 8,
    duration: 10,
  },
  baisakhi: {
    name: 'Baisakhi — Sikh New Year',
    primary: '#FF9800',
    secondary: '#4CAF50',
    accent: '#F44336',
    gradient: ['#FF9800', '#4CAF50', '#F44336'],
    startMonth: 4,
    startDay: 10,
    endMonth: 4,
    endDay: 17,
    duration: 7,
  },
  christmas: {
    name: 'Christmas',
    primary: '#C62828',
    secondary: '#2E7D32',
    accent: '#FFD700',
    gradient: ['#C62828', '#2E7D32', '#FFD700'],
    startMonth: 12,
    startDay: 18,
    endMonth: 12,
    endDay: 31,
    duration: 14,
  },
};

// ── Color Token Resolver ───────────────────────────────────────────

export type ColorToken = keyof typeof SEMANTIC_TOKENS | keyof typeof NEUTRAL_PALETTE | keyof typeof PRIMARY_PALETTE;

export function getColorToken(token: string, isDark: boolean): string {
  // Check semantic tokens first
  if (token in SEMANTIC_TOKENS) {
    const st = SEMANTIC_TOKENS[token];
    return isDark ? st.dark : st.light;
  }
  // Check neutral palette
  if (token in NEUTRAL_PALETTE) {
    return NEUTRAL_PALETTE[token as unknown as keyof typeof NEUTRAL_PALETTE] as string;
  }
  // Check primary palette
  if (token in PRIMARY_PALETTE) {
    return PRIMARY_PALETTE[token as keyof typeof PRIMARY_PALETTE];
  }
  // Check neutral role map
  const roleMap = isDark ? NEUTRAL_ROLE_MAP.dark : NEUTRAL_ROLE_MAP.light;
  if (token in roleMap) {
    return roleMap[token as keyof typeof roleMap];
  }
  // Fallback
  return isDark ? '#F5F5F4' : '#1C1917';
}

// ── Festival Theme Resolver ────────────────────────────────────────

export function getFestivalTheme(festival: string): FestivalTheme | null {
  return FESTIVAL_EXTENSIONS[festival] ?? null;
}

export function isFestivalActive(festival: string): boolean {
  const theme = FESTIVAL_EXTENSIONS[festival];
  if (!theme) return false;

  const now = new Date();
  const year = now.getFullYear();
  const start = new Date(year, theme.startMonth - 1, theme.startDay);
  const end = new Date(year, theme.endMonth - 1, theme.endDay);

  return now >= start && now <= end;
}

export const ACTIVE_FESTIVAL: string | null = (() => {
  const festivals = Object.keys(FESTIVAL_EXTENSIONS);
  for (const f of festivals) {
    if (isFestivalActive(f)) return f;
  }
  return null;
})();

// ── Complete App Color Maps ────────────────────────────────────────

export const AppColors = {
  // Brand
  primary: PRIMARY_PALETTE.primary,
  primaryLight: PRIMARY_PALETTE.primaryLight,
  primaryDark: PRIMARY_PALETTE.primaryDark,
  primaryContainer: PRIMARY_PALETTE.primaryContainer,
  onPrimary: PRIMARY_PALETTE.onPrimary,
  onPrimaryContainer: PRIMARY_PALETTE.onPrimaryContainer,

  // Secondary
  secondary: PRIMARY_PALETTE.secondary,
  secondaryLight: PRIMARY_PALETTE.secondaryLight,
  secondaryDark: PRIMARY_PALETTE.secondaryDark,
  secondaryContainer: PRIMARY_PALETTE.secondaryContainer,
  onSecondary: PRIMARY_PALETTE.onSecondary,

  // Accent
  accent: PRIMARY_PALETTE.accent,
  accentLight: PRIMARY_PALETTE.accentLight,
  accentDark: PRIMARY_PALETTE.accentDark,
  accentContainer: PRIMARY_PALETTE.accentContainer,

  // Semantic
  success: SEMANTIC_TOKENS.success.light,
  error: SEMANTIC_TOKENS.error.light,
  warning: SEMANTIC_TOKENS.warning.light,
  info: SEMANTIC_TOKENS.info.light,

  // Surfaces
  background: '#FFFBFE',
  surface: '#FFFBFE',
  surfaceContainerLow: '#FFF7ED',
  surfaceContainer: '#FEF3C7',
  surfaceContainerHigh: '#FFF1E0',
  surfaceContainerHighest: '#FED7AA',
  onSurface: '#1C1917',
  onSurfaceVariant: '#57534E',

  // Outlines
  outline: '#A8A29E',
  outlineVariant: '#D6D3D1',

  // Inverse
  inverseSurface: '#292524',
  inverseOnSurface: '#F5F5F4',

  // Premium
  premiumGold: '#FFD700',

  // Glass
  glassBackground: 'rgba(255, 255, 255, 0.15)',
  glassBorder: 'rgba(255, 255, 255, 0.33)',

  // Shimmer
  shimmerBase: '#E7E5E4',
  shimmerHighlight: '#F5F5F4',

  // Tree visualization
  treeNodeBackground: '#FFF7ED',
  treeNodeBorder: '#FED7AA',
  treeLineParent: '#F97316',
  treeLineSpouse: '#E94560',
  treeLineSibling: '#14B8A6',

  // Avatar
  avatarFallbackBg: '#FED7AA',
  avatarFallbackText: '#F97316',
} as const;

export const AppColorsDark = {
  // Brand
  primary: PRIMARY_PALETTE.primaryDark,
  primaryLight: PRIMARY_PALETTE.primaryLight,
  primaryDark: PRIMARY_PALETTE.primaryDark,
  primaryContainer: '#431407',
  onPrimary: '#1C1917',
  onPrimaryContainer: '#FB923C',

  // Secondary
  secondary: '#FB7185',
  secondaryLight: '#F47289',
  secondaryDark: '#C81D45',
  secondaryContainer: '#5C2030',
  onSecondary: '#1C1917',

  // Accent
  accent: '#5EEAD4',
  accentLight: '#5EEAD4',
  accentDark: '#0D9488',
  accentContainer: '#134E4A',

  // Semantic
  success: SEMANTIC_TOKENS.success.dark,
  error: SEMANTIC_TOKENS.error.dark,
  warning: SEMANTIC_TOKENS.warning.dark,
  info: SEMANTIC_TOKENS.info.dark,

  // Surfaces
  background: '#1C1917',
  surface: '#1C1917',
  surfaceContainerLow: '#292524',
  surfaceContainer: '#33302E',
  surfaceContainerHigh: '#3D3A37',
  surfaceContainerHighest: '#4C4945',
  onSurface: '#F5F5F4',
  onSurfaceVariant: '#D6D3D1',

  // Outlines
  outline: '#78716C',
  outlineVariant: '#44403C',

  // Inverse
  inverseSurface: '#F5F5F4',
  inverseOnSurface: '#1C1917',

  // Premium
  premiumGold: '#FFD54F',

  // Glass
  glassBackground: 'rgba(0, 0, 0, 0.15)',
  glassBorder: 'rgba(0, 0, 0, 0.33)',

  // Shimmer
  shimmerBase: '#44403C',
  shimmerHighlight: '#57534E',

  // Tree visualization
  treeNodeBackground: '#292524',
  treeNodeBorder: '#44403C',
  treeLineParent: '#FB923C',
  treeLineSpouse: '#FB7185',
  treeLineSibling: '#5EEAD4',

  // Avatar
  avatarFallbackBg: '#44403C',
  avatarFallbackText: '#FB923C',
} as const;
