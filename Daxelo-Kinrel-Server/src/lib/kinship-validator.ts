/**
 * KINREL — Kinship Validator
 *
 * Lightweight validation of relationship keys against the kinship module.
 * Used by API routes to validate user-submitted relationship types.
 */

import { ALL_RELATIONSHIP_KEYS, normalizeRelationshipKey } from '@/lib/kinship'

// Build a Set for O(1) lookup at module load time
const VALID_KEYS = new Set(ALL_RELATIONSHIP_KEYS)

/**
 * Check if a relationship key is valid (after normalization).
 * Accepts both new format (fathers_elder_brother) and legacy (chacha).
 */
export function isValidRelationshipKey(key: string): boolean {
  const normalized = normalizeRelationshipKey(key)
  return VALID_KEYS.has(normalized)
}

/**
 * Normalize and validate — returns the normalized key or null if invalid.
 */
export function validateAndNormalizeKey(key: string): string | null {
  const normalized = normalizeRelationshipKey(key)
  return VALID_KEYS.has(normalized) ? normalized : null
}
