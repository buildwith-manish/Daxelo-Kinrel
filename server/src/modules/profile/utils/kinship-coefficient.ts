/**
 * Kinship Coefficient Computation
 * ══════════════════════════════════════════════════════════════════════
 *
 * Computes the coefficient of relationship (r) — a measure of genetic
 * relatedness between two persons based on their kinship path.
 *
 * The coefficient follows Wright's formula: r = (0.5)^n where n is the
 * number of meiosis events (parent-child links) connecting two persons
 * through their most recent common ancestor.
 *
 * For direct lineal relationships (parent, grandparent), n = number of
 * generations between them.
 *
 * For collateral relationships (siblings, cousins), n = number of
 * generations UP to common ancestor + generations DOWN to target.
 *
 * Spouse/marital connections contribute 0 to genetic relatedness
 * but serve as path connectors for in-law relationships.
 */

import { RelationshipStep } from '../../graph/graph-engine.service';

// ── Known Coefficients for Computed Terms ────────────────────────────
// Maps resolved kinship terms directly to their coefficient of relationship.
// This is the primary lookup — path-based computation serves as fallback.

export const KINSHIP_COEFFICIENTS: Record<string, number> = {
  // ── Self ──────────────────────────────────────────────────────────
  self: 1.0,

  // ── Immediate Family (r = 0.5) ───────────────────────────────────
  father: 0.5,
  mother: 0.5,
  son: 0.5,
  daughter: 0.5,
  brother: 0.5,
  sister: 0.5,
  elder_brother: 0.5,
  younger_brother: 0.5,
  elder_sister: 0.5,
  younger_sister: 0.5,

  // ── Grandparents / Grandchildren (r = 0.25) ──────────────────────
  grandfather: 0.25,
  grandmother: 0.25,
  grandson: 0.25,
  granddaughter: 0.25,
  paternal_grandfather: 0.25,
  paternal_grandmother: 0.25,
  maternal_grandfather: 0.25,
  maternal_grandmother: 0.25,

  // ── Aunts / Uncles / Nephews / Nieces (r = 0.25) ────────────────
  uncle: 0.25,
  aunt: 0.25,
  nephew: 0.25,
  niece: 0.25,
  fathers_brother: 0.25,
  fathers_sister: 0.25,
  mothers_brother: 0.25,
  mothers_sister: 0.25,
  nephew_brothers_son: 0.25,
  niece_brothers_daughter: 0.25,
  nephew_sisters_son: 0.25,
  niece_sisters_daughter: 0.25,

  // ── First Cousins (r = 0.125) ────────────────────────────────────
  cousin: 0.125,
  cousin_paternal_male: 0.125,
  cousin_paternal_female: 0.125,
  cousin_maternal_male: 0.125,
  cousin_maternal_female: 0.125,

  // ── Great Grandparents / Great Grandchildren (r = 0.125) ────────
  great_grandfather: 0.125,
  great_grandmother: 0.125,
  great_grandson: 0.125,
  great_granddaughter: 0.125,

  // ── Cousins Once Removed (r = 0.0625) ────────────────────────────
  cousin_once_removed: 0.0625,

  // ── Second Cousins (r = 0.03125) ─────────────────────────────────
  second_cousin: 0.03125,

  // ── Third Cousins (r = 0.0078125) ────────────────────────────────
  third_cousin: 0.0078125,

  // ── Half-Siblings / Step (r = 0.25) ──────────────────────────────
  step_brother: 0.25,
  step_sister: 0.25,
  stepfather: 0,
  stepmother: 0,
  stepson: 0,
  stepdaughter: 0,

  // ── Spouse / In-Laws (r = 0 — no genetic relationship) ──────────
  husband: 0,
  wife: 0,
  father_in_law: 0,
  mother_in_law: 0,
  brother_in_law: 0,
  sister_in_law: 0,
  son_in_law: 0,
  daughter_in_law: 0,
  co_brother_in_law: 0,
  co_sister_in_law: 0,

  // ── By Marriage (r = 0) ──────────────────────────────────────────
  fathers_brothers_wife: 0,
  fathers_sisters_husband: 0,
  mothers_brothers_wife: 0,
  mothers_sisters_husband: 0,
  elder_brothers_wife: 0,
  younger_brothers_wife: 0,
  sisters_husband: 0,
  husbands_father: 0,
  husbands_mother: 0,
  wives_father: 0,
  wives_mother: 0,
  sons_wife: 0,
  daughters_husband: 0,

  // ── Generic ──────────────────────────────────────────────────────
  uncle_generic: 0.25,
  aunt_generic: 0.25,
};

// ── Direction weights for path-based coefficient computation ─────────
// "up" = going to parent generation (meiosis event)
// "down" = going to child generation (meiosis event)
// "sideways" = sibling or spouse (no direct meiosis, but sibling
//              implies shared ancestry)

const DIRECTION_MEIOSIS_COUNT: Record<string, number> = {
  up: 1,    // Each parent link = 1 meiosis
  down: 1,  // Each child link = 1 meiosis
  sideways: 0, // Sibling/spouse links don't add meiosis directly
};

/**
 * Compute the coefficient of relationship from a resolved kinship term.
 * Falls back to path-based computation if the term is not in the lookup table.
 *
 * @param computedTerm - The resolved kinship term (e.g., "cousin", "uncle")
 * @param path - The relationship path steps (used for fallback computation)
 * @returns Coefficient of relationship (0.0 to 1.0)
 */
export function computeKinshipCoefficient(
  computedTerm: string,
  path?: RelationshipStep[],
): number {
  // Strategy 1: Direct lookup from known coefficients
  const normalisedTerm = computedTerm.toLowerCase().replace(/[^a-z_]/g, '_');

  if (normalisedTerm in KINSHIP_COEFFICIENTS) {
    return KINSHIP_COEFFICIENTS[normalisedTerm];
  }

  // Try partial match (e.g., "cousin_paternal_male" might not match but "cousin" does)
  const baseTerm = normalisedTerm.split('_')[0];
  if (baseTerm in KINSHIP_COEFFICIENTS) {
    return KINSHIP_COEFFICIENTS[baseTerm];
  }

  // Strategy 2: Path-based computation
  if (path && path.length > 0) {
    return computeFromPath(path);
  }

  // Strategy 3: Distance-based fallback (r ≈ (0.5)^distance)
  // This is a rough approximation for unknown relationship types
  return 0;
}

/**
 * Compute coefficient from a relationship path by counting meiosis events.
 *
 * For collateral relationships (through common ancestor), the coefficient
 * is (0.5)^(up_steps + down_steps). Spouse steps in the path are
 * connector steps and don't contribute to the meiosis count.
 *
 * For sibling relationships (sideways), we need special handling:
 * Full siblings share both parents, so the path through one parent
 * gives r = 0.25, and through both parents r = 0.5.
 *
 * Since BFS finds the shortest path, sibling connections are typically
 * represented as direct sideways links, and the coefficient is known
 * from the lookup table. This path-based method handles edge cases.
 */
function computeFromPath(path: RelationshipStep[]): number {
  let meiosisCount = 0;
  let hasSidewaysStep = false;

  for (const step of path) {
    if (step.direction === 'up' || step.direction === 'down') {
      meiosisCount += DIRECTION_MEIOSIS_COUNT[step.direction];
    } else if (step.direction === 'sideways') {
      // Check if it's a sibling step (not spouse)
      const key = step.relationshipType;
      if (key === 'brother' || key === 'sister' ||
          key === 'elder_brother' || key === 'younger_brother' ||
          key === 'elder_sister' || key === 'younger_sister') {
        hasSidewaysStep = true;
      }
      // Spouse steps are connectors — no meiosis
    }
  }

  if (meiosisCount === 0) {
    // Pure sideways connection (e.g., spouse, sibling through direct link)
    if (hasSidewaysStep) {
      // Full sibling via direct link — shares both parents
      return 0.5;
    }
    // Spouse — no genetic relationship
    return 0;
  }

  return Math.pow(0.5, meiosisCount);
}

/**
 * Classify the relationship type into blood, marital, or affinal.
 *
 * - Blood: genetically related (parent, child, sibling, cousin, etc.)
 * - Marital: connected through marriage (spouse, in-laws)
 * - Affinal: connected through marriage of a relative (co-in-laws, etc.)
 */
export function classifyRelationship(
  computedTerm: string,
  path?: RelationshipStep[],
): 'blood' | 'marital' | 'affinal' {
  const term = computedTerm.toLowerCase();

  // Marital — direct spouse connection
  const maritalTerms = new Set([
    'husband', 'wife', 'spouse',
  ]);
  if (maritalTerms.has(term)) return 'marital';

  // Affinal — in-law and by-marriage connections
  const affinalPatterns = [
    'in_law', 'in-law', 'co_brother', 'co_sister',
    'sons_wife', 'daughters_husband',
    'husbands_father', 'husbands_mother',
    'wives_father', 'wives_mother',
    'fathers_brothers_wife', 'fathers_sisters_husband',
    'mothers_brothers_wife', 'mothers_sisters_husband',
    'brothers_wife', 'sisters_husband',
  ];
  for (const pattern of affinalPatterns) {
    if (term.includes(pattern)) return 'affinal';
  }

  // Step-relationships are classified by their nature
  if (term.startsWith('step')) {
    if (term.includes('father') || term.includes('mother')) return 'affinal';
    if (term.includes('brother') || term.includes('sister')) return 'blood'; // half-sibling
    return 'affinal';
  }

  // Everything else is blood relationship
  return 'blood';
}

/**
 * Determine the lineage path (paternal, maternal, or neutral).
 * Based on the first "up" step in the relationship path.
 */
export function determineLineage(path?: RelationshipStep[]): 'paternal' | 'maternal' | 'neutral' {
  if (!path || path.length === 0) return 'neutral';

  for (const step of path) {
    if (step.direction === 'up') {
      const key = step.relationshipType;
      if (key === 'father' || key === 'paternal_grandfather' || key === 'fathers_brother' || key === 'fathers_sister') {
        return 'paternal';
      }
      if (key === 'mother' || key === 'maternal_grandfather' || key === 'maternal_grandmother' || key === 'mothers_brother' || key === 'mothers_sister') {
        return 'maternal';
      }
    }
    if (step.direction === 'sideways') {
      const key = step.relationshipType;
      if (key === 'husband' || key === 'wife') continue; // Skip spouse connectors
      break; // Don't look past the first non-spouse sideways step
    }
  }

  return 'neutral';
}
