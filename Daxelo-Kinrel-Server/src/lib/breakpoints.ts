/**
 * DAXELO KINREL — Breakpoint System
 *
 * Responsive breakpoints matching Flutter AppBreakpoints for cross-platform consistency.
 *
 * Pack 01: Design System — Layout & Spacing
 */

import { spacing } from './design-tokens'

// ── Breakpoint Definitions ──────────────────────────────────────────
export const breakpoints = {
  compact: 600,    // Phone portrait
  medium: 840,     // Phone landscape / small tablet
  expanded: 1200,  // Tablet portrait
  large: 1600,     // Tablet landscape / desktop
} as const

// ── Responsive Helpers ──────────────────────────────────────────────
export function columnsForWidth(width: number): number {
  if (width < breakpoints.compact) return 4
  if (width < breakpoints.medium) return 8
  return 12
}

export function gutterForWidth(width: number): number {
  if (width < breakpoints.compact) return spacing.sm
  if (width < breakpoints.medium) return spacing.md
  return spacing.lg
}

export function marginForWidth(width: number): number {
  if (width < breakpoints.compact) return spacing.lg
  if (width < breakpoints.medium) return spacing.xxl
  if (width < breakpoints.expanded) return spacing.xxxl
  return spacing.huge
}

// ── Device Type Detection ───────────────────────────────────────────
export type DeviceType = 'phone' | 'tablet' | 'desktop'

export function deviceForWidth(width: number): DeviceType {
  if (width < breakpoints.compact) return 'phone'
  if (width < breakpoints.expanded) return 'tablet'
  return 'desktop'
}

// ── Tailwind Breakpoint Config ──────────────────────────────────────
export const tailwindBreakpoints = {
  sm: `${breakpoints.compact}px`,
  md: `${breakpoints.medium}px`,
  lg: `${breakpoints.expanded}px`,
  xl: `${breakpoints.large}px`,
} as const
