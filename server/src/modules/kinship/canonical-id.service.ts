/**
 * Daxelo-Kinrel v3.0 — Canonical Relationship ID Layer
 * ══════════════════════════════════════════════════════════════════════
 *
 * Spec §4 — All user-facing kinship terms, colloquial names, and regional
 * variants MUST map to a Canonical Relationship ID before entering the
 * engine.
 *
 * Canonical IDs:
 *   • PARENT           — covers father, mother, son, daughter
 *   • SPOUSE           — covers husband, wife
 *   • ADOPTIVE_PARENT  — covers adoptive father, adoptive mother
 *   • STEP_PARENT      — covers step father, step mother
 *
 * Derived terms (grandfather, uncle, cousin, nephew, in-laws, etc.) are
 * tagged as DERIVED so the Relationship Normalizer can trace them back to
 * the missing fundamental edge(s) the user needs to add.
 *
 * The synonym table covers English + 7 major Indian languages:
 *   hi (Hindi), mr (Marathi), ta (Tamil), te (Telugu),
 *   kn (Kannada), bn (Bengali), gu (Gujarati).
 *
 * Adding term #5,397 in any language requires only a new synonym entry —
 * no engine changes (spec §7.1).
 */

import { Injectable, Logger } from '@nestjs/common';

// ── Canonical IDs (spec §4.1) ─────────────────────────────────────────

export type CanonicalId =
  | 'PARENT'
  | 'SPOUSE'
  | 'ADOPTIVE_PARENT'
  | 'STEP_PARENT'
  | 'DERIVED'      // grandfather, uncle, cousin, in-law, etc. — do NOT store
  | 'UNKNOWN';     // not recognized — ask user for clarification

/**
 * Result of normalizing a user-input term to a Canonical ID.
 * Carries enough context for the Relationship Normalizer to either
 * store the fundamental edge directly OR prompt the user for the
 * missing fundamental edge that would complete the graph.
 */
export interface CanonicalResolution {
  canonicalId: CanonicalId;
  /** True when the input maps to a derived term (grandfather, uncle, cousin). */
  isDerived: boolean;
  /** Direction hint for parent-class edges: 'forward' = from→to is parent, 'reverse' = to→from is parent (i.e., user said 'son'/'daughter'). */
  direction?: 'forward' | 'reverse';
  /** Locale-matched raw input echoed back for UI confirmation. */
  matchedInput: string;
  /** Detected language code (e.g. 'en', 'hi', 'ta'). */
  matchedLocale: string;
  /** English label for UI display. */
  englishLabel: string;
  /**
   * For DERIVED terms only: the missing fundamental edge(s) that the user
   * must add to complete the graph. Each entry describes a single
   * fundamental edge that, once added, would allow the engine to derive
   * the requested relationship.
   *
   * Example: input="grandfather" → missingEdges=[{ edge: 'parent', fromPersonId: 'A', toPersonId: 'father-of-A', note: 'Add parent edge from A to their father; grandfather will be derived automatically.' }]
   */
  missingEdges?: Array<{
    edge: 'parent' | 'spouse' | 'adoptive_parent' | 'step_parent';
    note: string;
  }>;
}

// ── Synonym Database ───────────────────────────────────────────────────
//
// Format: [term, direction]
//   direction = 'forward'  → A's [parent/spouse] is B  (A→B)
//   direction = 'reverse'   → A's [child] is B           (B→A i.e. B is parent of A)
//
// We keep the lookup key lowercase + ASCII-folded for fast normalization.

interface SynonymEntry {
  term: string;        // lowercased
  canonicalId: CanonicalId;
  direction: 'forward' | 'reverse';
  englishLabel: string;
  isDerived?: boolean;
  missingEdges?: Array<{ edge: 'parent' | 'spouse' | 'adoptive_parent' | 'step_parent'; note: string }>;
}

// Helper: build a record keyed by lowercased term.
function buildIndex(entries: SynonymEntry[]): Record<string, SynonymEntry> {
  const out: Record<string, SynonymEntry> = {};
  for (const e of entries) out[e.term.toLowerCase()] = e;
  return out;
}

// ── English Synonyms ──────────────────────────────────────────────────

const ENGLISH_SYNONYMS: SynonymEntry[] = [
  // PARENT (forward) — A's parent is B
  { term: 'father',          canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Father' },
  { term: 'dad',              canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Father' },
  { term: 'daddy',            canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Father' },
  { term: 'papa',             canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Father' },
  { term: 'pa',               canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Father' },
  { term: 'pop',              canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Father' },
  { term: 'mother',          canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Mother' },
  { term: 'mom',              canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Mother' },
  { term: 'mommy',            canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Mother' },
  { term: 'mama',             canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Mother' },
  { term: 'ma',               canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Mother' },
  { term: 'mum',              canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Mother' },
  { term: 'mummy',            canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Mother' },
  { term: 'parent',           canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Parent' },

  // PARENT (reverse) — A's child is B → user said 'son'/'daughter' about B from A's perspective
  { term: 'son',              canonicalId: 'PARENT', direction: 'reverse', englishLabel: 'Son' },
  { term: 'daughter',         canonicalId: 'PARENT', direction: 'reverse', englishLabel: 'Daughter' },
  { term: 'child',            canonicalId: 'PARENT', direction: 'reverse', englishLabel: 'Child' },
  { term: 'kid',              canonicalId: 'PARENT', direction: 'reverse', englishLabel: 'Child' },

  // SPOUSE
  { term: 'husband',         canonicalId: 'SPOUSE', direction: 'forward', englishLabel: 'Husband' },
  { term: 'wife',            canonicalId: 'SPOUSE', direction: 'forward', englishLabel: 'Wife' },
  { term: 'spouse',          canonicalId: 'SPOUSE', direction: 'forward', englishLabel: 'Spouse' },
  { term: 'partner',         canonicalId: 'SPOUSE', direction: 'forward', englishLabel: 'Partner' },
  { term: 'married to',      canonicalId: 'SPOUSE', direction: 'forward', englishLabel: 'Spouse' },

  // ADOPTIVE_PARENT
  { term: 'adoptive father',     canonicalId: 'ADOPTIVE_PARENT', direction: 'forward', englishLabel: 'Adoptive Father' },
  { term: 'adoptive mother',     canonicalId: 'ADOPTIVE_PARENT', direction: 'forward', englishLabel: 'Adoptive Mother' },
  { term: 'adoptive parent',     canonicalId: 'ADOPTIVE_PARENT', direction: 'forward', englishLabel: 'Adoptive Parent' },
  { term: 'adopted father',      canonicalId: 'ADOPTIVE_PARENT', direction: 'forward', englishLabel: 'Adoptive Father' },
  { term: 'adopted mother',      canonicalId: 'ADOPTIVE_PARENT', direction: 'forward', englishLabel: 'Adoptive Mother' },

  // STEP_PARENT
  { term: 'step father',         canonicalId: 'STEP_PARENT', direction: 'forward', englishLabel: 'Step Father' },
  { term: 'stepfather',          canonicalId: 'STEP_PARENT', direction: 'forward', englishLabel: 'Step Father' },
  { term: 'step mother',         canonicalId: 'STEP_PARENT', direction: 'forward', englishLabel: 'Step Mother' },
  { term: 'stepmother',          canonicalId: 'STEP_PARENT', direction: 'forward', englishLabel: 'Step Mother' },
  { term: 'step parent',         canonicalId: 'STEP_PARENT', direction: 'forward', englishLabel: 'Step Parent' },

  // DERIVED — must NOT be stored. The normalizer will trace back to the
  // missing fundamental edge(s) and ask the user.
  {
    term: 'grandfather', canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Grandfather',
    isDerived: true,
    missingEdges: [{ edge: 'parent', note: 'Add a parent edge from this person to their father. The grandfather will be derived automatically from the existing parent edge.' }],
  },
  {
    term: 'grandmother', canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Grandmother',
    isDerived: true,
    missingEdges: [{ edge: 'parent', note: 'Add a parent edge from this person to their mother. The grandmother will be derived automatically from the existing parent edge.' }],
  },
  {
    term: 'grandparent', canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Grandparent',
    isDerived: true,
    missingEdges: [{ edge: 'parent', note: 'Add a parent edge from this person to their parent. The grandparent will be derived automatically.' }],
  },
  {
    term: 'uncle', canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Uncle',
    isDerived: true,
    missingEdges: [{ edge: 'parent', note: 'Add a parent edge from this person to their parent. The uncle (parent\'s brother) will be derived automatically.' }],
  },
  {
    term: 'aunt', canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Aunt',
    isDerived: true,
    missingEdges: [{ edge: 'parent', note: 'Add a parent edge from this person to their parent. The aunt (parent\'s sister) will be derived automatically.' }],
  },
  {
    term: 'cousin', canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Cousin',
    isDerived: true,
    missingEdges: [{ edge: 'parent', note: 'Add parent edges to connect both persons to their respective parents (who are siblings). The cousin relationship will be derived automatically.' }],
  },
  {
    term: 'nephew', canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Nephew',
    isDerived: true,
    missingEdges: [{ edge: 'parent', note: 'Add a parent edge from this person to your sibling. The nephew relationship will be derived automatically.' }],
  },
  {
    term: 'niece', canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Niece',
    isDerived: true,
    missingEdges: [{ edge: 'parent', note: 'Add a parent edge from this person to your sibling. The niece relationship will be derived automatically.' }],
  },
  {
    term: 'brother', canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Brother',
    isDerived: true,
    missingEdges: [{ edge: 'parent', note: 'Add a shared parent edge for both siblings. The brother relationship will be derived automatically from the shared parent.' }],
  },
  {
    term: 'sister', canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Sister',
    isDerived: true,
    missingEdges: [{ edge: 'parent', note: 'Add a shared parent edge for both siblings. The sister relationship will be derived automatically from the shared parent.' }],
  },
  {
    term: 'sibling', canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Sibling',
    isDerived: true,
    missingEdges: [{ edge: 'parent', note: 'Add a shared parent edge for both siblings. The sibling relationship will be derived automatically from the shared parent.' }],
  },
  {
    term: 'great grandfather', canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Great Grandfather',
    isDerived: true,
    missingEdges: [{ edge: 'parent', note: 'Add parent edges linking this person up to their grandparent. The great-grandfather will be derived automatically.' }],
  },
  {
    term: 'great grandmother', canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Great Grandmother',
    isDerived: true,
    missingEdges: [{ edge: 'parent', note: 'Add parent edges linking this person up to their grandparent. The great-grandmother will be derived automatically.' }],
  },
  {
    term: 'grandson', canonicalId: 'DERIVED', direction: 'reverse', englishLabel: 'Grandson',
    isDerived: true,
    missingEdges: [{ edge: 'parent', note: 'Add parent edges linking this person down to their grandchild. The grandson relationship will be derived automatically.' }],
  },
  {
    term: 'granddaughter', canonicalId: 'DERIVED', direction: 'reverse', englishLabel: 'Granddaughter',
    isDerived: true,
    missingEdges: [{ edge: 'parent', note: 'Add parent edges linking this person down to their grandchild. The granddaughter relationship will be derived automatically.' }],
  },
  {
    term: 'father in law', canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Father-in-Law',
    isDerived: true,
    missingEdges: [{ edge: 'spouse', note: 'Add a spouse edge first, then add the parent edge for the spouse. The father-in-law will be derived automatically.' }],
  },
  {
    term: 'mother in law', canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Mother-in-Law',
    isDerived: true,
    missingEdges: [{ edge: 'spouse', note: 'Add a spouse edge first, then add the parent edge for the spouse. The mother-in-law will be derived automatically.' }],
  },
  {
    term: 'brother in law', canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Brother-in-Law',
    isDerived: true,
    missingEdges: [{ edge: 'spouse', note: 'Add spouse edges and/or parent edges linking the two persons. The brother-in-law will be derived automatically.' }],
  },
  {
    term: 'sister in law', canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Sister-in-Law',
    isDerived: true,
    missingEdges: [{ edge: 'spouse', note: 'Add spouse edges and/or parent edges linking the two persons. The sister-in-law will be derived automatically.' }],
  },
  {
    term: 'son in law', canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Son-in-Law',
    isDerived: true,
    missingEdges: [{ edge: 'spouse', note: 'Add a spouse edge between this person\'s child and the target. The son-in-law will be derived automatically.' }],
  },
  {
    term: 'daughter in law', canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Daughter-in-Law',
    isDerived: true,
    missingEdges: [{ edge: 'spouse', note: 'Add a spouse edge between this person\'s child and the target. The daughter-in-law will be derived automatically.' }],
  },
];

// ── Hindi Synonyms (hi) ───────────────────────────────────────────────

const HINDI_SYNONYMS: SynonymEntry[] = [
  { term: 'पिता',          canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Father' },
  { term: 'पापा',          canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Father' },
  { term: 'बाप',           canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Father' },
  { term: 'माता',          canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Mother' },
  { term: 'माँ',           canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Mother' },
  { term: 'मम्मी',         canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Mother' },
  { term: 'पुत्र',         canonicalId: 'PARENT', direction: 'reverse', englishLabel: 'Son' },
  { term: 'बेटा',          canonicalId: 'PARENT', direction: 'reverse', englishLabel: 'Son' },
  { term: 'पुत्री',        canonicalId: 'PARENT', direction: 'reverse', englishLabel: 'Daughter' },
  { term: 'बेटी',          canonicalId: 'PARENT', direction: 'reverse', englishLabel: 'Daughter' },
  { term: 'पति',           canonicalId: 'SPOUSE', direction: 'forward', englishLabel: 'Husband' },
  { term: 'पत्नी',         canonicalId: 'SPOUSE', direction: 'forward', englishLabel: 'Wife' },
  { term: 'जीवनसाथी',      canonicalId: 'SPOUSE', direction: 'forward', englishLabel: 'Spouse' },
  { term: 'दादा',          canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Grandfather (Paternal)',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'parent edge from this person to their father; dadaji will be derived.' }] },
  { term: 'दादी',          canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Grandmother (Paternal)',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'parent edge from this person to their mother; dadaji will be derived.' }] },
  { term: 'नाना',          canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Grandfather (Maternal)',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'parent edge from this person to their mother\'s father; nanaji will be derived.' }] },
  { term: 'नानी',          canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Grandmother (Maternal)',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'parent edge from this person to their mother\'s mother; naniji will be derived.' }] },
  { term: 'चाचा',          canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Uncle (Paternal)',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'parent edge from this person to their father; chacha will be derived.' }] },
  { term: 'मामा',          canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Uncle (Maternal)',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'parent edge from this person to their mother; mama will be derived.' }] },
  { term: 'बुआ',           canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Aunt (Paternal)',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'parent edge from this person to their father; bua will be derived.' }] },
  { term: 'मौसी',          canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Aunt (Maternal)',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'parent edge from this person to their mother; mausi will be derived.' }] },
  { term: 'भाई',           canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Brother',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'shared parent edge for both siblings; bhai will be derived.' }] },
  { term: 'बहन',           canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Sister',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'shared parent edge for both siblings; bahen will be derived.' }] },
  { term: 'ससुर',          canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Father-in-Law',
    isDerived: true, missingEdges: [{ edge: 'spouse', note: 'spouse edge first, then parent edge; sasur will be derived.' }] },
  { term: 'सास',           canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Mother-in-Law',
    isDerived: true, missingEdges: [{ edge: 'spouse', note: 'spouse edge first, then parent edge; saas will be derived.' }] },
  // Hindi (Latin transliteration — most users type in English keyboard)
  { term: 'pita',           canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Father' },
  { term: 'papa',           canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Father' },
  { term: 'baap',           canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Father' },
  { term: 'mata',           canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Mother' },
  { term: 'maa',            canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Mother' },
  { term: 'mummy',          canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Mother' },
  { term: 'beta',           canonicalId: 'PARENT', direction: 'reverse', englishLabel: 'Son' },
  { term: 'beti',           canonicalId: 'PARENT', direction: 'reverse', englishLabel: 'Daughter' },
  { term: 'pati',           canonicalId: 'SPOUSE', direction: 'forward', englishLabel: 'Husband' },
  { term: 'patni',          canonicalId: 'SPOUSE', direction: 'forward', englishLabel: 'Wife' },
  { term: 'dada',           canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Grandfather (Paternal)',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'parent edge from this person to their father; dadaji will be derived.' }] },
  { term: 'dadi',           canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Grandmother (Paternal)',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'parent edge from this person to their father; dadaji will be derived.' }] },
  { term: 'nana',           canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Grandfather (Maternal)',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'parent edge from this person to their mother\'s father; nanaji will be derived.' }] },
  { term: 'nani',           canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Grandmother (Maternal)',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'parent edge from this person to their mother\'s mother; naniji will be derived.' }] },
  { term: 'chacha',         canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Uncle (Paternal)',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'parent edge from this person to their father; chacha will be derived.' }] },
  { term: 'mama',           canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Uncle (Maternal)',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'parent edge from this person to their mother; mama will be derived.' }] },
  { term: 'bua',            canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Aunt (Paternal)',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'parent edge from this person to their father; bua will be derived.' }] },
  { term: 'mausi',          canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Aunt (Maternal)',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'parent edge from this person to their mother; mausi will be derived.' }] },
  { term: 'bhai',           canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Brother',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'shared parent edge for both siblings; bhai will be derived.' }] },
  { term: 'bahen',          canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Sister',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'shared parent edge for both siblings; bahen will be derived.' }] },
  { term: 'behena',         canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Sister',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'shared parent edge for both siblings; bahen will be derived.' }] },
  { term: 'sasur',          canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Father-in-Law',
    isDerived: true, missingEdges: [{ edge: 'spouse', note: 'spouse edge first, then parent edge; sasur will be derived.' }] },
  { term: 'saas',           canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Mother-in-Law',
    isDerived: true, missingEdges: [{ edge: 'spouse', note: 'spouse edge first, then parent edge; saas will be derived.' }] },
];

// ── Tamil Synonyms (ta) ───────────────────────────────────────────────

const TAMIL_SYNONYMS: SynonymEntry[] = [
  // Tamil (native script)
  { term: 'தந்தை',         canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Father' },
  { term: 'அப்பா',         canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Father' },
  { term: 'அம்மா',         canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Mother' },
  { term: 'தாய்',           canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Mother' },
  { term: 'மகன்',          canonicalId: 'PARENT', direction: 'reverse', englishLabel: 'Son' },
  { term: 'மகள்',          canonicalId: 'PARENT', direction: 'reverse', englishLabel: 'Daughter' },
  { term: 'கணவன்',         canonicalId: 'SPOUSE', direction: 'forward', englishLabel: 'Husband' },
  { term: 'மனைவி',         canonicalId: 'SPOUSE', direction: 'forward', englishLabel: 'Wife' },
  { term: 'தாத்தா',        canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Grandfather',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'parent edge; thatha will be derived.' }] },
  { term: 'பாட்டி',        canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Grandmother',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'parent edge; paatti will be derived.' }] },
  { term: 'சித்தப்பா',      canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Uncle (Paternal)',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'parent edge; chithappa will be derived.' }] },
  { term: 'மாமா',          canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Uncle (Maternal)',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'parent edge; mama will be derived.' }] },
  { term: 'அத்தை',         canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Aunt (Paternal)',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'parent edge; athai will be derived.' }] },
  { term: 'சகோதரன்',      canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Brother',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'shared parent edge; sagodaran will be derived.' }] },
  { term: 'சகோதரி',       canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Sister',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'shared parent edge; sagodari will be derived.' }] },
  // Tamil (Latin transliteration — most users type in English keyboard)
  { term: 'appa',           canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Father' },
  { term: 'appan',          canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Father' },
  { term: 'amma',           canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Mother' },
  { term: 'thanthai',       canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Father' },
  { term: 'thai',           canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Mother' },
  { term: 'magan',          canonicalId: 'PARENT', direction: 'reverse', englishLabel: 'Son' },
  { term: 'magal',          canonicalId: 'PARENT', direction: 'reverse', englishLabel: 'Daughter' },
  { term: 'kanavan',        canonicalId: 'SPOUSE', direction: 'forward', englishLabel: 'Husband' },
  { term: 'manaivi',        canonicalId: 'SPOUSE', direction: 'forward', englishLabel: 'Wife' },
  { term: 'thatha',         canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Grandfather',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'parent edge; thatha will be derived.' }] },
  { term: 'paatti',         canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Grandmother',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'parent edge; paatti will be derived.' }] },
  { term: 'chithappa',      canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Uncle (Paternal)',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'parent edge; chithappa will be derived.' }] },
  { term: 'mama',           canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Uncle (Maternal)',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'parent edge; mama will be derived.' }] },
  { term: 'athai',          canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Aunt (Paternal)',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'parent edge; athai will be derived.' }] },
  { term: 'sagodaran',      canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Brother',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'shared parent edge; sagodaran will be derived.' }] },
  { term: 'sagodari',       canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Sister',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'shared parent edge; sagodari will be derived.' }] },
];

// ── Telugu Synonyms (te) ──────────────────────────────────────────────

const TELUGU_SYNONYMS: SynonymEntry[] = [
  { term: 'తండ్రి',        canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Father' },
  { term: 'నాన్న',         canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Mother' },
  { term: 'కొడుకు',        canonicalId: 'PARENT', direction: 'reverse', englishLabel: 'Son' },
  { term: 'కూతురు',        canonicalId: 'PARENT', direction: 'reverse', englishLabel: 'Daughter' },
  { term: 'భర్త',          canonicalId: 'SPOUSE', direction: 'forward', englishLabel: 'Husband' },
  { term: 'భార్య',         canonicalId: 'SPOUSE', direction: 'forward', englishLabel: 'Wife' },
  { term: 'తాత',           canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Grandfather',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'parent edge; thatha will be derived.' }] },
  { term: 'అమ్మమ్మ',       canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Grandmother',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'parent edge; ammamma will be derived.' }] },
];

// ── Kannada Synonyms (kn) ─────────────────────────────────────────────

const KANNADA_SYNONYMS: SynonymEntry[] = [
  { term: 'ತಂದೆ',          canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Father' },
  { term: 'ತಾಯಿ',          canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Mother' },
  { term: 'ಮಗ',            canonicalId: 'PARENT', direction: 'reverse', englishLabel: 'Son' },
  { term: 'ಮಗಳು',          canonicalId: 'PARENT', direction: 'reverse', englishLabel: 'Daughter' },
  { term: 'ಗಂಡ',           canonicalId: 'SPOUSE', direction: 'forward', englishLabel: 'Husband' },
  { term: 'ಹೆಂಡತಿ',       canonicalId: 'SPOUSE', direction: 'forward', englishLabel: 'Wife' },
  { term: 'ಅಜ್ಜ',          canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Grandfather',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'parent edge; ajja will be derived.' }] },
  { term: 'ಅಜ್ಜಿ',         canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Grandmother',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'parent edge; ajji will be derived.' }] },
];

// ── Bengali Synonyms (bn) ─────────────────────────────────────────────

const BENGALI_SYNONYMS: SynonymEntry[] = [
  { term: 'পিতা',          canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Father' },
  { term: 'বাবা',          canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Father' },
  { term: 'মাতা',          canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Mother' },
  { term: 'মা',            canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Mother' },
  { term: 'ছেলে',          canonicalId: 'PARENT', direction: 'reverse', englishLabel: 'Son' },
  { term: 'মেয়ে',         canonicalId: 'PARENT', direction: 'reverse', englishLabel: 'Daughter' },
  { term: 'স্বামী',        canonicalId: 'SPOUSE', direction: 'forward', englishLabel: 'Husband' },
  { term: 'স্ত্রী',         canonicalId: 'SPOUSE', direction: 'forward', englishLabel: 'Wife' },
  { term: 'দাদু',          canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Grandfather',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'parent edge; dadu will be derived.' }] },
  { term: 'দিদা',          canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Grandmother',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'parent edge; dida will be derived.' }] },
];

// ── Marathi Synonyms (mr) ──────────────────────────────────────────────

const MARATHI_SYNONYMS: SynonymEntry[] = [
  { term: 'वडील',          canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Father' },
  { term: 'आई',            canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Mother' },
  { term: 'मुलगा',         canonicalId: 'PARENT', direction: 'reverse', englishLabel: 'Son' },
  { term: 'मुलगी',         canonicalId: 'PARENT', direction: 'reverse', englishLabel: 'Daughter' },
  { term: 'पती',           canonicalId: 'SPOUSE', direction: 'forward', englishLabel: 'Husband' },
  { term: 'पत्नी',         canonicalId: 'SPOUSE', direction: 'forward', englishLabel: 'Wife' },
  { term: 'आजोबा',        canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Grandfather',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'parent edge; ajoba will be derived.' }] },
  { term: 'आजी',           canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Grandmother',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'parent edge; aaji will be derived.' }] },
];

// ── Gujarati Synonyms (gu) ─────────────────────────────────────────────

const GUJARATI_SYNONYMS: SynonymEntry[] = [
  { term: 'પિતા',         canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Father' },
  { term: 'માતા',         canonicalId: 'PARENT', direction: 'forward', englishLabel: 'Mother' },
  { term: 'દીકરો',        canonicalId: 'PARENT', direction: 'reverse', englishLabel: 'Son' },
  { term: 'દીકરી',        canonicalId: 'PARENT', direction: 'reverse', englishLabel: 'Daughter' },
  { term: 'પતિ',          canonicalId: 'SPOUSE', direction: 'forward', englishLabel: 'Husband' },
  { term: 'પત્ની',        canonicalId: 'SPOUSE', direction: 'forward', englishLabel: 'Wife' },
  { term: 'દાદા',          canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Grandfather',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'parent edge; dada will be derived.' }] },
  { term: 'દાદી',          canonicalId: 'DERIVED', direction: 'forward', englishLabel: 'Grandmother',
    isDerived: true, missingEdges: [{ edge: 'parent', note: 'parent edge; dadi will be derived.' }] },
];

// ── Service ───────────────────────────────────────────────────────────

/**
 * Indexes synonyms by locale for O(1) lookup.
 * Falls back to English if the requested locale has no match.
 */
@Injectable()
export class CanonicalIdService {
  private readonly logger = new Logger(CanonicalIdService.name);

  private readonly indexes: Record<string, Record<string, SynonymEntry>> = {
    en: buildIndex(ENGLISH_SYNONYMS),
    hi: buildIndex(HINDI_SYNONYMS),
    ta: buildIndex(TAMIL_SYNONYMS),
    te: buildIndex(TELUGU_SYNONYMS),
    kn: buildIndex(KANNADA_SYNONYMS),
    bn: buildIndex(BENGALI_SYNONYMS),
    mr: buildIndex(MARATHI_SYNONYMS),
    gu: buildIndex(GUJARATI_SYNONYMS),
  };

  /**
   * Normalize a user-input kinship term to its Canonical Relationship ID.
   *
   * Spec §4.3:
   *   1. Look up in locale-specific synonym table.
   *   2. If not found, fall back to English.
   *   3. If still not found, return UNKNOWN so the caller can ask the user
   *      to pick from the four fundamental edges.
   */
  normalizeToCanonical(input: string, locale: string = 'en'): CanonicalResolution {
    const trimmed = (input ?? '').trim();
    if (!trimmed) {
      return {
        canonicalId: 'UNKNOWN',
        isDerived: false,
        matchedInput: '',
        matchedLocale: locale,
        englishLabel: 'Unknown',
      };
    }

    const lower = trimmed.toLowerCase();

    // Step 1: try requested locale
    let entry = this.indexes[locale]?.[lower];

    // Step 2: fall back to English
    if (!entry && locale !== 'en') {
      entry = this.indexes['en']?.[lower];
    }

    // Step 3: try English as primary (in case locale is unknown)
    if (!entry) {
      entry = this.indexes['en']?.[lower];
    }

    if (!entry) {
      return {
        canonicalId: 'UNKNOWN',
        isDerived: false,
        matchedInput: trimmed,
        matchedLocale: locale,
        englishLabel: 'Unknown',
      };
    }

    return {
      canonicalId: entry.canonicalId,
      isDerived: entry.isDerived === true,
      direction: entry.direction,
      matchedInput: trimmed,
      matchedLocale: locale,
      englishLabel: entry.englishLabel,
      missingEdges: entry.missingEdges,
    };
  }

  /**
   * List all canonical IDs that the engine can store.
   * Useful for the manual picker UI when auto-detection fails.
   */
  listFundamentalCanonicalIds(): CanonicalId[] {
    return ['PARENT', 'SPOUSE', 'ADOPTIVE_PARENT', 'STEP_PARENT'];
  }

  /**
   * Returns the list of supported locales (for the UI language picker).
   */
  listSupportedLocales(): string[] {
    return Object.keys(this.indexes);
  }
}
