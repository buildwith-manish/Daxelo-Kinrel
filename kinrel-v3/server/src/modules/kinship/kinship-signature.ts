/**
 * Daxelo-Kinrel — KinshipSignature (spec §6)
 * ===========================================
 * Runtime-only structured data describing a kinship relationship.
 *
 * CRITICAL: This object is NEVER persisted to the database.
 * It is computed on-demand by GraphEngineService and consumed by
 * KinshipService to look up the localized term.
 *
 * The signatureKey is the deterministic lookup key for KinshipVocabulary.
 * Same graph + same Person A + same Person B = same signatureKey. Always.
 */

export type Side = "paternal" | "maternal" | "none";
export type Consanguinity = "blood" | "half" | "step" | "adoptive" | "inLaw" | "foster" | "spiritual";
export type GenderAnchor = "male" | "female" | "neutral";
export type Seniority = "elder" | "younger" | "twin" | "none";
export type Temporal = "current" | "former" | "late";

// Traversal primitives — only these are allowed (spec §5).
// Forbidden primitives: BROTHER, SISTER, UNCLE, AUNT, COUSIN, GRANDFATHER.
export type Primitive =
  | "UP_PARENT"
  | "DOWN_CHILD"
  | "SPOUSE"
  | "UP_ADOPTIVE_PARENT"
  | "DOWN_ADOPTIVE_CHILD"
  | "UP_STEP_PARENT"
  | "DOWN_STEP_CHILD"
  | "UP_FOSTER_PARENT"
  | "DOWN_FOSTER_CHILD"
  | "UP_SPIRITUAL_PARENT"
  | "DOWN_SPIRITUAL_CHILD";

export interface KinshipSignature {
  generationDelta: number;        // -8 .. +8
  pathPattern: string;            // primitives joined by "_"  (spec §6.1 grammar)
  side: Side;                     // spec §6.3 — set by first UP_PARENT
  consanguinity: Consanguinity;   // spec §6.4 — full / half / step / adoptive / inLaw / foster / spiritual
  genderAnchor: GenderAnchor;     // derived from target Person.gender
  seniority: Seniority;           // sibling birth order (spec §6.4)
  removal: number;                // cousin removal (spec §6.5)
  doubleKinship: boolean;         // double first cousins etc. (spec §6.5)
  temporal: Temporal;             // current | former | late (NEW v3.1 — spec §6)
}

export function signatureKey(s: KinshipSignature): string {
  return [
    `g=${s.generationDelta}`,
    `p=${s.pathPattern}`,
    `s=${s.side}`,
    `c=${s.consanguinity}`,
    `x=${s.genderAnchor}`,
    `r=${s.removal}`,
    `sn=${s.seniority}`,
    `d=${s.doubleKinship ? 1 : 0}`,
    `t=${s.temporal}`,
  ].join("|");
}

// ---------------------------------------------------------------------------
// Path pattern utilities (spec §6.1)
// ---------------------------------------------------------------------------

export function buildPathPattern(primitives: Primitive[]): string {
  return primitives.join("_");
}

export function parsePathPattern(pattern: string): Primitive[] {
  return pattern.split("_").filter(Boolean) as Primitive[];
}

/**
 * Count UP vs DOWN primitives to compute generationDelta (spec §6).
 * Each UP_PARENT decrements gen, each DOWN_CHILD increments.
 * SPOUSE is gen-neutral.
 */
export function computeGenerationDelta(pattern: string): number {
  const primitives = parsePathPattern(pattern);
  let delta = 0;
  for (const p of primitives) {
    if (p.startsWith("UP_")) delta -= 1;
    else if (p.startsWith("DOWN_")) delta += 1;
    // SPOUSE → 0
  }
  return delta;
}

/**
 * Determine side from path pattern (spec §6.3).
 * Side is set by the FIRST UP_PARENT (or UP_ADOPTIVE_PARENT / UP_STEP_PARENT).
 * The side paternal/maternal is then resolved at runtime by looking at
 * the gender of the parent at that step.
 *
 * This function returns the LITERAL side token only when known from the
 * pattern alone; in most cases the engine must consult the graph.
 */
export function inferSideFromPattern(pattern: string): Side {
  if (!pattern.includes("UP_")) return "none";
  // We cannot resolve paternal vs maternal from the pattern alone.
  // The engine must set this by inspecting the actual parent's gender
  // at the first UP step.
  return "none"; // engine overrides
}
