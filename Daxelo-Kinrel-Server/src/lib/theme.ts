/**
 * DAXELO KINREL — Theme Configuration
 *
 * Light and dark theme definitions with KINREL brand colors.
 * Matches Flutter BrandTheme v2 for cross-platform consistency.
 *
 * Pack 01: Design System — Theming & Dark Mode
 */

import { brandColors } from './design-tokens'

// ── Light Theme ─────────────────────────────────────────────────────
export const lightTheme = {
  colors: {
    // Brand
    primary: brandColors.primary,
    primaryContainer: brandColors.primaryContainer,
    onPrimary: brandColors.onPrimary,
    onPrimaryContainer: brandColors.onPrimaryContainer,

    // Secondary
    secondary: brandColors.secondary,
    secondaryContainer: brandColors.secondaryContainer,
    onSecondary: brandColors.onSecondary,

    // Accent
    accent: brandColors.accent,
    accentContainer: brandColors.accentContainer,

    // Semantic
    success: brandColors.success,
    warning: brandColors.warning,
    error: brandColors.error,
    info: brandColors.info,

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
    premiumGold: brandColors.premiumGold,

    // Glass
    glassBackground: 'rgba(255, 255, 255, 0.15)',
    glassBorder: 'rgba(255, 255, 255, 0.33)',

    // Shimmer
    shimmerBase: '#E7E5E4',
    shimmerHighlight: '#F5F5F4',

    // Tree visualization
    treeNodeBackground: '#FFF7ED',
    treeNodeBorder: '#FED7AA',
    treeLineParent: brandColors.primary,
    treeLineSpouse: brandColors.secondary,
    treeLineSibling: brandColors.accent,

    // Avatar
    avatarFallbackBg: '#FED7AA',
    avatarFallbackText: brandColors.primary,
  },
} as const

// ── Dark Theme ──────────────────────────────────────────────────────
export const darkTheme = {
  colors: {
    // Brand
    primary: brandColors.primaryDark,
    primaryContainer: '#431407',
    onPrimary: '#1C1917',
    onPrimaryContainer: '#FB923C',

    // Secondary
    secondary: '#FB7185',
    secondaryContainer: '#5C2030',
    onSecondary: '#1C1917',

    // Accent
    accent: '#5EEAD4',
    accentContainer: '#134E4A',

    // Semantic
    success: '#4ADE80',
    warning: '#FBBF24',
    error: '#F87171',
    info: '#60A5FA',

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
    treeLineParent: brandColors.primaryDark,
    treeLineSpouse: '#FB7185',
    treeLineSibling: '#5EEAD4',

    // Avatar
    avatarFallbackBg: '#44403C',
    avatarFallbackText: brandColors.primaryDark,
  },
} as const

// ── Festival Color Extensions ───────────────────────────────────────
export const festivalColors = {
  diwali: {
    primary: '#FFD700',
    secondary: '#FF6B00',
    accent: '#FF1493',
    gradient: ['#FFD700', '#FF6B00', '#FF1493'],
  },
  holi: {
    primary: '#FF6B6B',
    secondary: '#4ECDC4',
    accent: '#9B59B6',
    gradient: ['#FF6B6B', '#4ECDC4', '#9B59B6'],
  },
  eid: {
    primary: '#2ECC71',
    secondary: '#F1C40F',
    accent: '#3498DB',
    gradient: ['#2ECC71', '#F1C40F', '#3498DB'],
  },
  navratri: {
    primary: '#E74C3C',
    secondary: '#FFD700',
    accent: '#9B59B6',
    gradient: ['#E74C3C', '#FFD700', '#9B59B6'],
  },
  pongal: {
    primary: '#F39C12',
    secondary: '#E74C3C',
    accent: '#2ECC71',
    gradient: ['#F39C12', '#E74C3C', '#2ECC71'],
  },
  onam: {
    primary: '#27AE60',
    secondary: '#F1C40F',
    accent: '#E74C3C',
    gradient: ['#27AE60', '#F1C40F', '#E74C3C'],
  },
  baisakhi: {
    primary: '#FF9800',
    secondary: '#4CAF50',
    accent: '#F44336',
    gradient: ['#FF9800', '#4CAF50', '#F44336'],
  },
  christmas: {
    primary: '#C62828',
    secondary: '#2E7D32',
    accent: '#FFD700',
    gradient: ['#C62828', '#2E7D32', '#FFD700'],
  },
} as const

// ── Color Blind Safe Palette ────────────────────────────────────────
export const colorBlindSafePalette = {
  blue: '#0072B2',
  orange: '#E69F00',
  green: '#009E73',
  red: '#D55E00',
  purple: '#CC79A7',
  cyan: '#56B4E9',
  yellow: '#F0E442',
  black: '#000000',
} as const

// ── High Contrast Mode ──────────────────────────────────────────────
export const highContrastColors = {
  focusRing: '#FFFF00',
  textOnDark: '#FFFFFF',
  textOnLight: '#000000',
  errorFocus: '#FF0000',
} as const

// ── Theme Type ──────────────────────────────────────────────────────
export type ThemeMode = 'light' | 'dark' | 'system'

export function getThemeForMode(mode: 'light' | 'dark') {
  return mode === 'dark' ? darkTheme : lightTheme
}
