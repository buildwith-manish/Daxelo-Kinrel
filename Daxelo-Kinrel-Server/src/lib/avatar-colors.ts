/**
 * DAXELO KINREL — Avatar Color System
 *
 * Culturally-aware default avatar colors that complement Indian skin tones.
 * Deterministic color selection based on person name — same person always gets same color.
 *
 * Pack 01: Design System — Icons & Imagery
 */

export const avatarPalette = [
  '#E8A87C', // Warm sand
  '#D4A574', // Golden brown
  '#C68B59', // Bronze
  '#85CDCA', // Teal
  '#E27D60', // Coral
  '#C38D9E', // Dusty rose
  '#41B3A3', // Green teal
  '#E8D21D', // Saffron gold
  '#E85D75', // Pink
  '#6C5B7B', // Plum
  '#F97316', // Orange brand
  '#14B8A6', // Teal brand
] as const

/**
 * Deterministic color selection based on person name.
 * Same person always gets same color.
 */
export function avatarColorForName(name: string): string {
  let hash = 0
  for (let i = 0; i < name.length; i++) {
    const char = name.charCodeAt(i)
    hash = ((hash << 5) - hash) + char
    hash = hash & hash // Convert to 32-bit integer
  }
  const index = Math.abs(hash) % avatarPalette.length
  return avatarPalette[index]
}

/**
 * Light variant for background
 */
export function avatarLightVariant(hex: string, alpha: number = 0.15): string {
  const r = parseInt(hex.slice(1, 3), 16)
  const g = parseInt(hex.slice(3, 5), 16)
  const b = parseInt(hex.slice(5, 7), 16)
  return `rgba(${r}, ${g}, ${b}, ${alpha})`
}

/**
 * Get initials from name (up to 2 characters)
 */
export function getInitials(name: string): string {
  if (!name) return '?'
  const parts = name.trim().split(/\s+/)
  if (parts.length >= 2) {
    return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase()
  }
  return name[0].toUpperCase()
}
