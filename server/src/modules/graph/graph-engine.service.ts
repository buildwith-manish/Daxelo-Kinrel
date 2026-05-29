/**
 * Daxelo-Kinrel Graph Engine Service
 * ══════════════════════════════════════════════════════════════════════
 *
 * The CORE of the platform — stores only 8 core relationship types and
 * computes ALL kinship terms dynamically via graph traversal.
 *
 * Core Relationship Types (ONLY these are stored in the database):
 *   father, mother, son, daughter, brother, sister, husband, wife
 *
 * All other kinship terms (grandfather, uncle, cousin, etc.) are
 * derived at query time by traversing the family graph and composing
 * core relationship steps into resolved kinship terms.
 *
 * Architecture:
 *   1. buildGraph()       — Load raw relationships from DB → adjacency list
 *   2. findPath()         — BFS shortest path between any two persons
 *   3. resolveKinship()   — Walk the path → compose kinship term
 *   4. getAllRelationships() — Compute every derived relationship for a person
 *   5. getAncestors()     — Traverse upward (parent links)
 *   6. getDescendants()   — Traverse downward (child links)
 */

import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

// ── Exported Types ────────────────────────────────────────────────────

export interface PathResult {
  found: boolean;
  path: RelationshipStep[];
  distance: number;
  kinshipTerm?: string;
  kinshipTermHindi?: string;
}

export interface RelationshipStep {
  personId: string;
  personName: string;
  relationshipType: string; // Core type: father, mother, etc.
  direction: 'up' | 'down' | 'sideways';
}

export interface KinshipResult {
  term: string; // "cousin"
  termHindi: string; // "चचेरा भाई"
  confidence: number; // 0-1
  path: RelationshipStep[];
  genderSpecific: boolean; // Whether the term is gender-specific
}

export interface ComputedRelationship {
  personId: string;
  personName: string;
  relationshipKey: string; // Stored key
  computedTerm: string; // Computed term like "cousin"
  computedTermHindi: string;
  distance: number;
  path: RelationshipStep[];
}

export interface PersonNode {
  personId: string;
  name: string;
  gender?: string;
  depth: number;
  relationship: string;
}

// ── Internal Types ────────────────────────────────────────────────────

interface AdjacencyEntry {
  neighborId: string;
  relationshipKey: string;
  direction: 'up' | 'down' | 'sideways';
}

interface PersonRecord {
  id: string;
  name: string;
  gender: string | null;
}

interface KinshipLookupEntry {
  term: string;
  termHindi: string;
  genderSpecific: boolean;
  confidence: number;
}

// ── Service Implementation ────────────────────────────────────────────

@Injectable()
export class GraphEngineService {
  private readonly logger = new Logger(GraphEngineService.name);

  // ── Core Relationship Types ──────────────────────────────────────────
  // ONLY these 8 types are stored in the database. Everything else is
  // computed dynamically via graph traversal.

  static readonly CORE_TYPES = [
    'father',
    'mother',
    'son',
    'daughter',
    'brother',
    'sister',
    'husband',
    'wife',
  ] as const;

  // ── Inverse Mapping for Bidirectional Traversal ──────────────────────
  // Given a relationship from A→B, what is the relationship from B→A?
  // Some inverses are gender-dependent (e.g., father → son/daughter).

  static readonly INVERSE_MAP: Record<string, string> = {
    father: 'child', // child is gender-normalized later
    mother: 'child',
    son: 'parent', // parent is gender-normalized later
    daughter: 'parent',
    brother: 'sibling',
    sister: 'sibling',
    husband: 'wife',
    wife: 'husband',
  };

  // ── Direction Classification ─────────────────────────────────────────
  // "up" = going to an older generation (parent, grandparent)
  // "down" = going to a younger generation (child, grandchild)
  // "sideways" = same generation or lateral (sibling, spouse)

  private static readonly DIRECTION_MAP: Record<string, 'up' | 'down' | 'sideways'> = {
    father: 'up',
    mother: 'up',
    son: 'down',
    daughter: 'down',
    brother: 'sideways',
    sister: 'sideways',
    husband: 'sideways',
    wife: 'sideways',
  };

  // ── Kinship Composition Rules ────────────────────────────────────────
  // Maps a sequence of core relationship keys (joined with →) to a
  // resolved kinship term. The target person's gender is used to
  // disambiguate gender-specific terms.
  //
  // Format: path_key → { male: {...}, female: {...}, neutral: {...} }

  private static readonly KINSHIP_RULES: Record<
    string,
    { male: KinshipLookupEntry; female: KinshipLookupEntry; neutral: KinshipLookupEntry }
  > = {
    // ── Grandparents (2 steps up) ────────────────────────────────────
    'father→father': {
      male: { term: 'grandfather', termHindi: 'दादा', genderSpecific: false, confidence: 1.0 },
      female: { term: 'grandfather', termHindi: 'दादा', genderSpecific: false, confidence: 1.0 },
      neutral: { term: 'grandfather', termHindi: 'दादा', genderSpecific: false, confidence: 1.0 },
    },
    'father→mother': {
      male: { term: 'grandmother', termHindi: 'दादी', genderSpecific: false, confidence: 1.0 },
      female: { term: 'grandmother', termHindi: 'दादी', genderSpecific: false, confidence: 1.0 },
      neutral: { term: 'grandmother', termHindi: 'दादी', genderSpecific: false, confidence: 1.0 },
    },
    'mother→father': {
      male: { term: 'grandfather', termHindi: 'नाना', genderSpecific: false, confidence: 1.0 },
      female: { term: 'grandfather', termHindi: 'नाना', genderSpecific: false, confidence: 1.0 },
      neutral: { term: 'grandfather', termHindi: 'नाना', genderSpecific: false, confidence: 1.0 },
    },
    'mother→mother': {
      male: { term: 'grandmother', termHindi: 'नानी', genderSpecific: false, confidence: 1.0 },
      female: { term: 'grandmother', termHindi: 'नानी', genderSpecific: false, confidence: 1.0 },
      neutral: { term: 'grandmother', termHindi: 'नानी', genderSpecific: false, confidence: 1.0 },
    },

    // ── Uncles / Aunts (parent → sibling) ────────────────────────────
    'father→brother': {
      male: { term: 'uncle', termHindi: 'चाचा', genderSpecific: true, confidence: 1.0 },
      female: { term: 'uncle', termHindi: 'चाचा', genderSpecific: true, confidence: 1.0 },
      neutral: { term: 'uncle', termHindi: 'चाचा', genderSpecific: true, confidence: 1.0 },
    },
    'father→sister': {
      male: { term: 'aunt', termHindi: 'बुआ', genderSpecific: true, confidence: 1.0 },
      female: { term: 'aunt', termHindi: 'बुआ', genderSpecific: true, confidence: 1.0 },
      neutral: { term: 'aunt', termHindi: 'बुआ', genderSpecific: true, confidence: 1.0 },
    },
    'mother→brother': {
      male: { term: 'uncle', termHindi: 'मामा', genderSpecific: true, confidence: 1.0 },
      female: { term: 'uncle', termHindi: 'मामा', genderSpecific: true, confidence: 1.0 },
      neutral: { term: 'uncle', termHindi: 'मामा', genderSpecific: true, confidence: 1.0 },
    },
    'mother→sister': {
      male: { term: 'aunt', termHindi: 'मौसी', genderSpecific: true, confidence: 1.0 },
      female: { term: 'aunt', termHindi: 'मौसी', genderSpecific: true, confidence: 1.0 },
      neutral: { term: 'aunt', termHindi: 'मौसी', genderSpecific: true, confidence: 1.0 },
    },

    // ── Cousins (uncle/aunt → child) ─────────────────────────────────
    // father → brother → son/daughter = paternal cousin
    'father→brother→son': {
      male: { term: 'cousin', termHindi: 'चचेरा भाई', genderSpecific: true, confidence: 1.0 },
      female: { term: 'cousin', termHindi: 'चचेरा भाई', genderSpecific: true, confidence: 1.0 },
      neutral: { term: 'cousin', termHindi: 'चचेरा भाई', genderSpecific: true, confidence: 1.0 },
    },
    'father→brother→daughter': {
      male: { term: 'cousin', termHindi: 'चचेरी बहन', genderSpecific: true, confidence: 1.0 },
      female: { term: 'cousin', termHindi: 'चचेरी बहन', genderSpecific: true, confidence: 1.0 },
      neutral: { term: 'cousin', termHindi: 'चचेरी बहन', genderSpecific: true, confidence: 1.0 },
    },
    'father→sister→son': {
      male: { term: 'cousin', termHindi: 'फुफेरा भाई', genderSpecific: true, confidence: 1.0 },
      female: { term: 'cousin', termHindi: 'फुफेरा भाई', genderSpecific: true, confidence: 1.0 },
      neutral: { term: 'cousin', termHindi: 'फुफेरा भाई', genderSpecific: true, confidence: 1.0 },
    },
    'father→sister→daughter': {
      male: { term: 'cousin', termHindi: 'फुफेरी बहन', genderSpecific: true, confidence: 1.0 },
      female: { term: 'cousin', termHindi: 'फुफेरी बहन', genderSpecific: true, confidence: 1.0 },
      neutral: { term: 'cousin', termHindi: 'फुफेरी बहन', genderSpecific: true, confidence: 1.0 },
    },
    'mother→brother→son': {
      male: { term: 'cousin', termHindi: 'ममेरा भाई', genderSpecific: true, confidence: 1.0 },
      female: { term: 'cousin', termHindi: 'ममेरा भाई', genderSpecific: true, confidence: 1.0 },
      neutral: { term: 'cousin', termHindi: 'ममेरा भाई', genderSpecific: true, confidence: 1.0 },
    },
    'mother→brother→daughter': {
      male: { term: 'cousin', termHindi: 'ममेरी बहन', genderSpecific: true, confidence: 1.0 },
      female: { term: 'cousin', termHindi: 'ममेरी बहन', genderSpecific: true, confidence: 1.0 },
      neutral: { term: 'cousin', termHindi: 'ममेरी बहन', genderSpecific: true, confidence: 1.0 },
    },
    'mother→sister→son': {
      male: { term: 'cousin', termHindi: 'मौसेरा भाई', genderSpecific: true, confidence: 1.0 },
      female: { term: 'cousin', termHindi: 'मौसेरा भाई', genderSpecific: true, confidence: 1.0 },
      neutral: { term: 'cousin', termHindi: 'मौसेरा भाई', genderSpecific: true, confidence: 1.0 },
    },
    'mother→sister→daughter': {
      male: { term: 'cousin', termHindi: 'मौसेरी बहन', genderSpecific: true, confidence: 1.0 },
      female: { term: 'cousin', termHindi: 'मौसेरी बहन', genderSpecific: true, confidence: 1.0 },
      neutral: { term: 'cousin', termHindi: 'मौसेरी बहन', genderSpecific: true, confidence: 1.0 },
    },

    // ── Nephew / Niece (sibling → child) ─────────────────────────────
    'brother→son': {
      male: { term: 'nephew', termHindi: 'भतीजा', genderSpecific: true, confidence: 1.0 },
      female: { term: 'nephew', termHindi: 'भतीजा', genderSpecific: true, confidence: 1.0 },
      neutral: { term: 'nephew', termHindi: 'भतीजा', genderSpecific: true, confidence: 1.0 },
    },
    'brother→daughter': {
      male: { term: 'niece', termHindi: 'भतीजी', genderSpecific: true, confidence: 1.0 },
      female: { term: 'niece', termHindi: 'भतीजी', genderSpecific: true, confidence: 1.0 },
      neutral: { term: 'niece', termHindi: 'भतीजी', genderSpecific: true, confidence: 1.0 },
    },
    'sister→son': {
      male: { term: 'nephew', termHindi: 'भांजा', genderSpecific: true, confidence: 1.0 },
      female: { term: 'nephew', termHindi: 'भांजा', genderSpecific: true, confidence: 1.0 },
      neutral: { term: 'nephew', termHindi: 'भांजा', genderSpecific: true, confidence: 1.0 },
    },
    'sister→daughter': {
      male: { term: 'niece', termHindi: 'भांजी', genderSpecific: true, confidence: 1.0 },
      female: { term: 'niece', termHindi: 'भांजी', genderSpecific: true, confidence: 1.0 },
      neutral: { term: 'niece', termHindi: 'भांजी', genderSpecific: true, confidence: 1.0 },
    },

    // ── Great Grandparents (3 steps up) ──────────────────────────────
    'father→father→father': {
      male: { term: 'great_grandfather', termHindi: 'परदादा', genderSpecific: false, confidence: 1.0 },
      female: { term: 'great_grandfather', termHindi: 'परदादा', genderSpecific: false, confidence: 1.0 },
      neutral: { term: 'great_grandfather', termHindi: 'परदादा', genderSpecific: false, confidence: 1.0 },
    },
    'father→father→mother': {
      male: { term: 'great_grandmother', termHindi: 'परदादी', genderSpecific: false, confidence: 1.0 },
      female: { term: 'great_grandmother', termHindi: 'परदादी', genderSpecific: false, confidence: 1.0 },
      neutral: { term: 'great_grandmother', termHindi: 'परदादी', genderSpecific: false, confidence: 1.0 },
    },
    'father→mother→father': {
      male: { term: 'great_grandfather', termHindi: 'परनाना', genderSpecific: false, confidence: 1.0 },
      female: { term: 'great_grandfather', termHindi: 'परनाना', genderSpecific: false, confidence: 1.0 },
      neutral: { term: 'great_grandfather', termHindi: 'परनाना', genderSpecific: false, confidence: 1.0 },
    },
    'father→mother→mother': {
      male: { term: 'great_grandmother', termHindi: 'परनानी', genderSpecific: false, confidence: 1.0 },
      female: { term: 'great_grandmother', termHindi: 'परनानी', genderSpecific: false, confidence: 1.0 },
      neutral: { term: 'great_grandmother', termHindi: 'परनानी', genderSpecific: false, confidence: 1.0 },
    },
    'mother→father→father': {
      male: { term: 'great_grandfather', termHindi: 'नाना के पिता', genderSpecific: false, confidence: 0.95 },
      female: { term: 'great_grandfather', termHindi: 'नाना के पिता', genderSpecific: false, confidence: 0.95 },
      neutral: { term: 'great_grandfather', termHindi: 'नाना के पिता', genderSpecific: false, confidence: 0.95 },
    },
    'mother→father→mother': {
      male: { term: 'great_grandmother', termHindi: 'नाना की माँ', genderSpecific: false, confidence: 0.95 },
      female: { term: 'great_grandmother', termHindi: 'नाना की माँ', genderSpecific: false, confidence: 0.95 },
      neutral: { term: 'great_grandmother', termHindi: 'नाना की माँ', genderSpecific: false, confidence: 0.95 },
    },
    'mother→mother→father': {
      male: { term: 'great_grandfather', termHindi: 'नानी के पिता', genderSpecific: false, confidence: 0.95 },
      female: { term: 'great_grandfather', termHindi: 'नानी के पिता', genderSpecific: false, confidence: 0.95 },
      neutral: { term: 'great_grandfather', termHindi: 'नानी के पिता', genderSpecific: false, confidence: 0.95 },
    },
    'mother→mother→mother': {
      male: { term: 'great_grandmother', termHindi: 'नानी की माँ', genderSpecific: false, confidence: 0.95 },
      female: { term: 'great_grandmother', termHindi: 'नानी की माँ', genderSpecific: false, confidence: 0.95 },
      neutral: { term: 'great_grandmother', termHindi: 'नानी की माँ', genderSpecific: false, confidence: 0.95 },
    },

    // ── In-Laws (via spouse → parent) ────────────────────────────────
    'husband→father': {
      male: { term: 'father_in_law', termHindi: 'ससुर', genderSpecific: false, confidence: 1.0 },
      female: { term: 'father_in_law', termHindi: 'ससुर', genderSpecific: false, confidence: 1.0 },
      neutral: { term: 'father_in_law', termHindi: 'ससुर', genderSpecific: false, confidence: 1.0 },
    },
    'husband→mother': {
      male: { term: 'mother_in_law', termHindi: 'सास', genderSpecific: false, confidence: 1.0 },
      female: { term: 'mother_in_law', termHindi: 'सास', genderSpecific: false, confidence: 1.0 },
      neutral: { term: 'mother_in_law', termHindi: 'सास', genderSpecific: false, confidence: 1.0 },
    },
    'wife→father': {
      male: { term: 'father_in_law', termHindi: 'ससुर', genderSpecific: false, confidence: 1.0 },
      female: { term: 'father_in_law', termHindi: 'ससुर', genderSpecific: false, confidence: 1.0 },
      neutral: { term: 'father_in_law', termHindi: 'ससुर', genderSpecific: false, confidence: 1.0 },
    },
    'wife→mother': {
      male: { term: 'mother_in_law', termHindi: 'सास', genderSpecific: false, confidence: 1.0 },
      female: { term: 'mother_in_law', termHindi: 'सास', genderSpecific: false, confidence: 1.0 },
      neutral: { term: 'mother_in_law', termHindi: 'सास', genderSpecific: false, confidence: 1.0 },
    },

    // ── Brother-in-Law / Sister-in-Law ───────────────────────────────
    // Via sister's husband
    'sister→husband': {
      male: { term: 'brother_in_law', termHindi: 'जीजा', genderSpecific: false, confidence: 1.0 },
      female: { term: 'brother_in_law', termHindi: 'जीजा', genderSpecific: false, confidence: 1.0 },
      neutral: { term: 'brother_in_law', termHindi: 'जीजा', genderSpecific: false, confidence: 1.0 },
    },
    // Via brother's wife
    'brother→wife': {
      male: { term: 'sister_in_law', termHindi: 'भाभी', genderSpecific: true, confidence: 1.0 },
      female: { term: 'sister_in_law', termHindi: 'भाभी', genderSpecific: true, confidence: 1.0 },
      neutral: { term: 'sister_in_law', termHindi: 'भाभी', genderSpecific: true, confidence: 1.0 },
    },
    // Via wife's brother
    'wife→brother': {
      male: { term: 'brother_in_law', termHindi: 'साला', genderSpecific: true, confidence: 1.0 },
      female: { term: 'brother_in_law', termHindi: 'साला', genderSpecific: true, confidence: 1.0 },
      neutral: { term: 'brother_in_law', termHindi: 'साला', genderSpecific: true, confidence: 1.0 },
    },
    // Via wife's sister
    'wife→sister': {
      male: { term: 'sister_in_law', termHindi: 'साली', genderSpecific: true, confidence: 1.0 },
      female: { term: 'sister_in_law', termHindi: 'साली', genderSpecific: true, confidence: 1.0 },
      neutral: { term: 'sister_in_law', termHindi: 'साली', genderSpecific: true, confidence: 1.0 },
    },
    // Via husband's brother
    'husband→brother': {
      male: { term: 'brother_in_law', termHindi: 'देवर', genderSpecific: true, confidence: 1.0 },
      female: { term: 'brother_in_law', termHindi: 'देवर', genderSpecific: true, confidence: 1.0 },
      neutral: { term: 'brother_in_law', termHindi: 'देवर', genderSpecific: true, confidence: 1.0 },
    },
    // Via husband's sister
    'husband→sister': {
      male: { term: 'sister_in_law', termHindi: 'ननद', genderSpecific: true, confidence: 1.0 },
      female: { term: 'sister_in_law', termHindi: 'ननद', genderSpecific: true, confidence: 1.0 },
      neutral: { term: 'sister_in_law', termHindi: 'ननद', genderSpecific: true, confidence: 1.0 },
    },

    // ── Son-in-Law / Daughter-in-Law (via child → spouse) ───────────
    'son→wife': {
      male: { term: 'daughter_in_law', termHindi: 'बहू', genderSpecific: false, confidence: 1.0 },
      female: { term: 'daughter_in_law', termHindi: 'बहू', genderSpecific: false, confidence: 1.0 },
      neutral: { term: 'daughter_in_law', termHindi: 'बहू', genderSpecific: false, confidence: 1.0 },
    },
    'daughter→husband': {
      male: { term: 'son_in_law', termHindi: 'दामाद', genderSpecific: false, confidence: 1.0 },
      female: { term: 'son_in_law', termHindi: 'दामाद', genderSpecific: false, confidence: 1.0 },
      neutral: { term: 'son_in_law', termHindi: 'दामाद', genderSpecific: false, confidence: 1.0 },
    },

    // ── Uncle/Aunt's spouse ──────────────────────────────────────────
    'father→brother→wife': {
      male: { term: 'aunt', termHindi: 'चाची', genderSpecific: true, confidence: 1.0 },
      female: { term: 'aunt', termHindi: 'चाची', genderSpecific: true, confidence: 1.0 },
      neutral: { term: 'aunt', termHindi: 'चाची', genderSpecific: true, confidence: 1.0 },
    },
    'father→sister→husband': {
      male: { term: 'uncle', termHindi: 'फूफा', genderSpecific: true, confidence: 1.0 },
      female: { term: 'uncle', termHindi: 'फूफा', genderSpecific: true, confidence: 1.0 },
      neutral: { term: 'uncle', termHindi: 'फूफा', genderSpecific: true, confidence: 1.0 },
    },
    'mother→brother→wife': {
      male: { term: 'aunt', termHindi: 'मामी', genderSpecific: true, confidence: 1.0 },
      female: { term: 'aunt', termHindi: 'मामी', genderSpecific: true, confidence: 1.0 },
      neutral: { term: 'aunt', termHindi: 'मामी', genderSpecific: true, confidence: 1.0 },
    },
    'mother→sister→husband': {
      male: { term: 'uncle', termHindi: 'मौसा', genderSpecific: true, confidence: 1.0 },
      female: { term: 'uncle', termHindi: 'मौसा', genderSpecific: true, confidence: 1.0 },
      neutral: { term: 'uncle', termHindi: 'मौसा', genderSpecific: true, confidence: 1.0 },
    },

    // ── Grandchild (2 steps down) ────────────────────────────────────
    'son→son': {
      male: { term: 'grandson', termHindi: 'पोता', genderSpecific: true, confidence: 1.0 },
      female: { term: 'grandson', termHindi: 'पोता', genderSpecific: true, confidence: 1.0 },
      neutral: { term: 'grandson', termHindi: 'पोता', genderSpecific: true, confidence: 1.0 },
    },
    'son→daughter': {
      male: { term: 'granddaughter', termHindi: 'पोती', genderSpecific: true, confidence: 1.0 },
      female: { term: 'granddaughter', termHindi: 'पोती', genderSpecific: true, confidence: 1.0 },
      neutral: { term: 'granddaughter', termHindi: 'पोती', genderSpecific: true, confidence: 1.0 },
    },
    'daughter→son': {
      male: { term: 'grandson', termHindi: 'नाती', genderSpecific: true, confidence: 1.0 },
      female: { term: 'grandson', termHindi: 'नाती', genderSpecific: true, confidence: 1.0 },
      neutral: { term: 'grandson', termHindi: 'नाती', genderSpecific: true, confidence: 1.0 },
    },
    'daughter→daughter': {
      male: { term: 'granddaughter', termHindi: 'नातिनी', genderSpecific: true, confidence: 1.0 },
      female: { term: 'granddaughter', termHindi: 'नातिनी', genderSpecific: true, confidence: 1.0 },
      neutral: { term: 'granddaughter', termHindi: 'नातिनी', genderSpecific: true, confidence: 1.0 },
    },

    // ── Great Grandchild (3 steps down) ──────────────────────────────
    'son→son→son': {
      male: { term: 'great_grandson', termHindi: 'परपोता', genderSpecific: true, confidence: 1.0 },
      female: { term: 'great_grandson', termHindi: 'परपोता', genderSpecific: true, confidence: 1.0 },
      neutral: { term: 'great_grandson', termHindi: 'परपोता', genderSpecific: true, confidence: 1.0 },
    },
    'son→son→daughter': {
      male: { term: 'great_granddaughter', termHindi: 'परपोती', genderSpecific: true, confidence: 1.0 },
      female: { term: 'great_granddaughter', termHindi: 'परपोती', genderSpecific: true, confidence: 1.0 },
      neutral: { term: 'great_granddaughter', termHindi: 'परपोती', genderSpecific: true, confidence: 1.0 },
    },
    'son→daughter→son': {
      male: { term: 'great_grandson', termHindi: 'परनाती', genderSpecific: true, confidence: 0.95 },
      female: { term: 'great_grandson', termHindi: 'परनाती', genderSpecific: true, confidence: 0.95 },
      neutral: { term: 'great_grandson', termHindi: 'परनाती', genderSpecific: true, confidence: 0.95 },
    },
    'son→daughter→daughter': {
      male: { term: 'great_granddaughter', termHindi: 'परनातिनी', genderSpecific: true, confidence: 0.95 },
      female: { term: 'great_granddaughter', termHindi: 'परनातिनी', genderSpecific: true, confidence: 0.95 },
      neutral: { term: 'great_granddaughter', termHindi: 'परनातिनी', genderSpecific: true, confidence: 0.95 },
    },
    'daughter→son→son': {
      male: { term: 'great_grandson', termHindi: 'वंशज', genderSpecific: true, confidence: 0.9 },
      female: { term: 'great_grandson', termHindi: 'वंशज', genderSpecific: true, confidence: 0.9 },
      neutral: { term: 'great_grandson', termHindi: 'वंशज', genderSpecific: true, confidence: 0.9 },
    },
    'daughter→son→daughter': {
      male: { term: 'great_granddaughter', termHindi: 'वंशज', genderSpecific: true, confidence: 0.9 },
      female: { term: 'great_granddaughter', termHindi: 'वंशज', genderSpecific: true, confidence: 0.9 },
      neutral: { term: 'great_granddaughter', termHindi: 'वंशज', genderSpecific: true, confidence: 0.9 },
    },
    'daughter→daughter→son': {
      male: { term: 'great_grandson', termHindi: 'वंशज', genderSpecific: true, confidence: 0.9 },
      female: { term: 'great_grandson', termHindi: 'वंशज', genderSpecific: true, confidence: 0.9 },
      neutral: { term: 'great_grandson', termHindi: 'वंशज', genderSpecific: true, confidence: 0.9 },
    },
    'daughter→daughter→daughter': {
      male: { term: 'great_granddaughter', termHindi: 'वंशज', genderSpecific: true, confidence: 0.9 },
      female: { term: 'great_granddaughter', termHindi: 'वंशज', genderSpecific: true, confidence: 0.9 },
      neutral: { term: 'great_granddaughter', termHindi: 'वंशज', genderSpecific: true, confidence: 0.9 },
    },

    // ── Co-Brother/Sister-in-Law (spouse's sibling's spouse) ─────────
    'wife→sister→husband': {
      male: { term: 'co_brother_in_law', termHindi: 'समंधी', genderSpecific: false, confidence: 1.0 },
      female: { term: 'co_brother_in_law', termHindi: 'समंधी', genderSpecific: false, confidence: 1.0 },
      neutral: { term: 'co_brother_in_law', termHindi: 'समंधी', genderSpecific: false, confidence: 1.0 },
    },
    'husband→brother→wife': {
      male: { term: 'co_sister_in_law', termHindi: 'भाभी', genderSpecific: false, confidence: 1.0 },
      female: { term: 'co_sister_in_law', termHindi: 'भाभी', genderSpecific: false, confidence: 1.0 },
      neutral: { term: 'co_sister_in_law', termHindi: 'भाभी', genderSpecific: false, confidence: 1.0 },
    },

    // ── Second Cousin (parent's cousin's child) ──────────────────────
    // father → brother → son → son (paternal uncle's grandson)
    'father→brother→son→son': {
      male: { term: 'second_cousin', termHindi: 'दूर का चचेरा भाई', genderSpecific: true, confidence: 0.9 },
      female: { term: 'second_cousin', termHindi: 'दूर का चचेरा भाई', genderSpecific: true, confidence: 0.9 },
      neutral: { term: 'second_cousin', termHindi: 'दूर का चचेरा भाई', genderSpecific: true, confidence: 0.9 },
    },
    'father→brother→son→daughter': {
      male: { term: 'second_cousin', termHindi: 'दूर की चचेरी बहन', genderSpecific: true, confidence: 0.9 },
      female: { term: 'second_cousin', termHindi: 'दूर की चचेरी बहन', genderSpecific: true, confidence: 0.9 },
      neutral: { term: 'second_cousin', termHindi: 'दूर की चचेरी बहन', genderSpecific: true, confidence: 0.9 },
    },
    'father→brother→daughter→son': {
      male: { term: 'second_cousin', termHindi: 'दूर का चचेरा भाई', genderSpecific: true, confidence: 0.9 },
      female: { term: 'second_cousin', termHindi: 'दूर का चचेरा भाई', genderSpecific: true, confidence: 0.9 },
      neutral: { term: 'second_cousin', termHindi: 'दूर का चचेरा भाई', genderSpecific: true, confidence: 0.9 },
    },
    'father→brother→daughter→daughter': {
      male: { term: 'second_cousin', termHindi: 'दूर की चचेरी बहन', genderSpecific: true, confidence: 0.9 },
      female: { term: 'second_cousin', termHindi: 'दूर की चचेरी बहन', genderSpecific: true, confidence: 0.9 },
      neutral: { term: 'second_cousin', termHindi: 'दूर की चचेरी बहन', genderSpecific: true, confidence: 0.9 },
    },
    'mother→brother→son→son': {
      male: { term: 'second_cousin', termHindi: 'दूर का ममेरा भाई', genderSpecific: true, confidence: 0.9 },
      female: { term: 'second_cousin', termHindi: 'दूर का ममेरा भाई', genderSpecific: true, confidence: 0.9 },
      neutral: { term: 'second_cousin', termHindi: 'दूर का ममेरा भाई', genderSpecific: true, confidence: 0.9 },
    },
    'mother→brother→son→daughter': {
      male: { term: 'second_cousin', termHindi: 'दूर की ममेरी बहन', genderSpecific: true, confidence: 0.9 },
      female: { term: 'second_cousin', termHindi: 'दूर की ममेरी बहन', genderSpecific: true, confidence: 0.9 },
      neutral: { term: 'second_cousin', termHindi: 'दूर की ममेरी बहन', genderSpecific: true, confidence: 0.9 },
    },
    'mother→brother→daughter→son': {
      male: { term: 'second_cousin', termHindi: 'दूर का ममेरा भाई', genderSpecific: true, confidence: 0.9 },
      female: { term: 'second_cousin', termHindi: 'दूर का ममेरा भाई', genderSpecific: true, confidence: 0.9 },
      neutral: { term: 'second_cousin', termHindi: 'दूर का ममेरा भाई', genderSpecific: true, confidence: 0.9 },
    },
    'mother→brother→daughter→daughter': {
      male: { term: 'second_cousin', termHindi: 'दूर की ममेरी बहन', genderSpecific: true, confidence: 0.9 },
      female: { term: 'second_cousin', termHindi: 'दूर की ममेरी बहन', genderSpecific: true, confidence: 0.9 },
      neutral: { term: 'second_cousin', termHindi: 'दूर की ममेरी बहन', genderSpecific: true, confidence: 0.9 },
    },

    // ── Third Cousin (grandparent's second cousin's child) ───────────
    // father → father → brother → son → son
    'father→father→brother→son→son': {
      male: { term: 'third_cousin', termHindi: 'तीसरा चचेरा भाई', genderSpecific: true, confidence: 0.8 },
      female: { term: 'third_cousin', termHindi: 'तीसरा चचेरा भाई', genderSpecific: true, confidence: 0.8 },
      neutral: { term: 'third_cousin', termHindi: 'तीसरा चचेरा भाई', genderSpecific: true, confidence: 0.8 },
    },
    'father→father→brother→son→daughter': {
      male: { term: 'third_cousin', termHindi: 'तीसरी चचेरी बहन', genderSpecific: true, confidence: 0.8 },
      female: { term: 'third_cousin', termHindi: 'तीसरी चचेरी बहन', genderSpecific: true, confidence: 0.8 },
      neutral: { term: 'third_cousin', termHindi: 'तीसरी चचेरी बहन', genderSpecific: true, confidence: 0.8 },
    },
    'father→father→brother→daughter→son': {
      male: { term: 'third_cousin', termHindi: 'तीसरा चचेरा भाई', genderSpecific: true, confidence: 0.8 },
      female: { term: 'third_cousin', termHindi: 'तीसरा चचेरा भाई', genderSpecific: true, confidence: 0.8 },
      neutral: { term: 'third_cousin', termHindi: 'तीसरा चचेरा भाई', genderSpecific: true, confidence: 0.8 },
    },
    'father→father→brother→daughter→daughter': {
      male: { term: 'third_cousin', termHindi: 'तीसरी चचेरी बहन', genderSpecific: true, confidence: 0.8 },
      female: { term: 'third_cousin', termHindi: 'तीसरी चचेरी बहन', genderSpecific: true, confidence: 0.8 },
      neutral: { term: 'third_cousin', termHindi: 'तीसरी चचेरी बहन', genderSpecific: true, confidence: 0.8 },
    },

    // ── Cousin once removed (uncle/aunt → grandchild) ────────────────
    // NOTE: father→brother→son→son/daughter and mother→brother→son→son/daughter
    // are already mapped as second_cousin above. The "cousin once removed"
    // interpretation is handled by the progressive composition fallback.
    'father→sister→son→son': {
      male: { term: 'cousin_once_removed', termHindi: 'फुफेरे भाई का बेटा', genderSpecific: true, confidence: 0.85 },
      female: { term: 'cousin_once_removed', termHindi: 'फुफेरे भाई का बेटा', genderSpecific: true, confidence: 0.85 },
      neutral: { term: 'cousin_once_removed', termHindi: 'फुफेरे भाई का बेटा', genderSpecific: true, confidence: 0.85 },
    },
    'father→sister→son→daughter': {
      male: { term: 'cousin_once_removed', termHindi: 'फुफेरे भाई की बेटी', genderSpecific: true, confidence: 0.85 },
      female: { term: 'cousin_once_removed', termHindi: 'फुफेरे भाई की बेटी', genderSpecific: true, confidence: 0.85 },
      neutral: { term: 'cousin_once_removed', termHindi: 'फुफेरे भाई की बेटी', genderSpecific: true, confidence: 0.85 },
    },
    'father→sister→daughter→son': {
      male: { term: 'cousin_once_removed', termHindi: 'फुफेरी बहन का बेटा', genderSpecific: true, confidence: 0.85 },
      female: { term: 'cousin_once_removed', termHindi: 'फुफेरी बहन का बेटा', genderSpecific: true, confidence: 0.85 },
      neutral: { term: 'cousin_once_removed', termHindi: 'फुफेरी बहन का बेटा', genderSpecific: true, confidence: 0.85 },
    },
    'father→sister→daughter→daughter': {
      male: { term: 'cousin_once_removed', termHindi: 'फुफेरी बहन की बेटी', genderSpecific: true, confidence: 0.85 },
      female: { term: 'cousin_once_removed', termHindi: 'फुफेरी बहन की बेटी', genderSpecific: true, confidence: 0.85 },
      neutral: { term: 'cousin_once_removed', termHindi: 'फुफेरी बहन की बेटी', genderSpecific: true, confidence: 0.85 },
    },
    'mother→sister→son→son': {
      male: { term: 'cousin_once_removed', termHindi: 'मौसेरे भाई का बेटा', genderSpecific: true, confidence: 0.85 },
      female: { term: 'cousin_once_removed', termHindi: 'मौसेरे भाई का बेटा', genderSpecific: true, confidence: 0.85 },
      neutral: { term: 'cousin_once_removed', termHindi: 'मौसेरे भाई का बेटा', genderSpecific: true, confidence: 0.85 },
    },
    'mother→sister→son→daughter': {
      male: { term: 'cousin_once_removed', termHindi: 'मौसेरे भाई की बेटी', genderSpecific: true, confidence: 0.85 },
      female: { term: 'cousin_once_removed', termHindi: 'मौसेरे भाई की बेटी', genderSpecific: true, confidence: 0.85 },
      neutral: { term: 'cousin_once_removed', termHindi: 'मौसेरे भाई की बेटी', genderSpecific: true, confidence: 0.85 },
    },
    'mother→sister→daughter→son': {
      male: { term: 'cousin_once_removed', termHindi: 'मौसेरी बहन का बेटा', genderSpecific: true, confidence: 0.85 },
      female: { term: 'cousin_once_removed', termHindi: 'मौसेरी बहन का बेटा', genderSpecific: true, confidence: 0.85 },
      neutral: { term: 'cousin_once_removed', termHindi: 'मौसेरी बहन का बेटा', genderSpecific: true, confidence: 0.85 },
    },
    'mother→sister→daughter→daughter': {
      male: { term: 'cousin_once_removed', termHindi: 'मौसेरी बहन की बेटी', genderSpecific: true, confidence: 0.85 },
      female: { term: 'cousin_once_removed', termHindi: 'मौसेरी बहन की बेटी', genderSpecific: true, confidence: 0.85 },
      neutral: { term: 'cousin_once_removed', termHindi: 'मौसेरी बहन की बेटी', genderSpecific: true, confidence: 0.85 },
    },
    // ── Step-relationships (parent → spouse → child) ─────────────────
    'father→wife→son': {
      male: { term: 'step_brother', termHindi: 'सौतेला भाई', genderSpecific: true, confidence: 0.8 },
      female: { term: 'step_brother', termHindi: 'सौतेला भाई', genderSpecific: true, confidence: 0.8 },
      neutral: { term: 'step_brother', termHindi: 'सौतेला भाई', genderSpecific: true, confidence: 0.8 },
    },
    'father→wife→daughter': {
      male: { term: 'step_sister', termHindi: 'सौतेली बहन', genderSpecific: true, confidence: 0.8 },
      female: { term: 'step_sister', termHindi: 'सौतेली बहन', genderSpecific: true, confidence: 0.8 },
      neutral: { term: 'step_sister', termHindi: 'सौतेली बहन', genderSpecific: true, confidence: 0.8 },
    },
    'mother→husband→son': {
      male: { term: 'step_brother', termHindi: 'सौतेला भाई', genderSpecific: true, confidence: 0.8 },
      female: { term: 'step_brother', termHindi: 'सौतेला भाई', genderSpecific: true, confidence: 0.8 },
      neutral: { term: 'step_brother', termHindi: 'सौतेला भाई', genderSpecific: true, confidence: 0.8 },
    },
    'mother→husband→daughter': {
      male: { term: 'step_sister', termHindi: 'सौतेली बहन', genderSpecific: true, confidence: 0.8 },
      female: { term: 'step_sister', termHindi: 'सौतेली बहन', genderSpecific: true, confidence: 0.8 },
      neutral: { term: 'step_sister', termHindi: 'सौतेली बहन', genderSpecific: true, confidence: 0.8 },
    },
  };

  // ── In-Law extended paths (4+ steps) ─────────────────────────────────
  // These are less common but needed for completeness

  private static readonly EXTENDED_INLAW_RULES: Record<
    string,
    { male: KinshipLookupEntry; female: KinshipLookupEntry; neutral: KinshipLookupEntry }
  > = {
    // Spouse's sibling's child
    'wife→brother→son': {
      male: { term: 'nephew_in_law', termHindi: 'साले का बेटा', genderSpecific: true, confidence: 0.9 },
      female: { term: 'nephew_in_law', termHindi: 'साले का बेटा', genderSpecific: true, confidence: 0.9 },
      neutral: { term: 'nephew_in_law', termHindi: 'साले का बेटा', genderSpecific: true, confidence: 0.9 },
    },
    'wife→brother→daughter': {
      male: { term: 'niece_in_law', termHindi: 'साले की बेटी', genderSpecific: true, confidence: 0.9 },
      female: { term: 'niece_in_law', termHindi: 'साले की बेटी', genderSpecific: true, confidence: 0.9 },
      neutral: { term: 'niece_in_law', termHindi: 'साले की बेटी', genderSpecific: true, confidence: 0.9 },
    },
    'wife→sister→son': {
      male: { term: 'nephew_in_law', termHindi: 'साली का बेटा', genderSpecific: true, confidence: 0.9 },
      female: { term: 'nephew_in_law', termHindi: 'साली का बेटा', genderSpecific: true, confidence: 0.9 },
      neutral: { term: 'nephew_in_law', termHindi: 'साली का बेटा', genderSpecific: true, confidence: 0.9 },
    },
    'wife→sister→daughter': {
      male: { term: 'niece_in_law', termHindi: 'साली की बेटी', genderSpecific: true, confidence: 0.9 },
      female: { term: 'niece_in_law', termHindi: 'साली की बेटी', genderSpecific: true, confidence: 0.9 },
      neutral: { term: 'niece_in_law', termHindi: 'साली की बेटी', genderSpecific: true, confidence: 0.9 },
    },
    'husband→brother→son': {
      male: { term: 'nephew_in_law', termHindi: 'देवर का बेटा', genderSpecific: true, confidence: 0.9 },
      female: { term: 'nephew_in_law', termHindi: 'देवर का बेटा', genderSpecific: true, confidence: 0.9 },
      neutral: { term: 'nephew_in_law', termHindi: 'देवर का बेटा', genderSpecific: true, confidence: 0.9 },
    },
    'husband→brother→daughter': {
      male: { term: 'niece_in_law', termHindi: 'देवर की बेटी', genderSpecific: true, confidence: 0.9 },
      female: { term: 'niece_in_law', termHindi: 'देवर की बेटी', genderSpecific: true, confidence: 0.9 },
      neutral: { term: 'niece_in_law', termHindi: 'देवर की बेटी', genderSpecific: true, confidence: 0.9 },
    },
    'husband→sister→son': {
      male: { term: 'nephew_in_law', termHindi: 'ननद का बेटा', genderSpecific: true, confidence: 0.9 },
      female: { term: 'nephew_in_law', termHindi: 'ननद का बेटा', genderSpecific: true, confidence: 0.9 },
      neutral: { term: 'nephew_in_law', termHindi: 'ननद का बेटा', genderSpecific: true, confidence: 0.9 },
    },
    'husband→sister→daughter': {
      male: { term: 'niece_in_law', termHindi: 'ननद की बेटी', genderSpecific: true, confidence: 0.9 },
      female: { term: 'niece_in_law', termHindi: 'ननद की बेटी', genderSpecific: true, confidence: 0.9 },
      neutral: { term: 'niece_in_law', termHindi: 'ननद की बेटी', genderSpecific: true, confidence: 0.9 },
    },
  };

  // ── Cache for built graphs (in-memory, per family) ────────────────────
  // Keyed by familyId, stores adjacency list + person map.
  // TTL-based invalidation would be ideal in production; here we use
  // a simple version counter that increments on any write to the family.

  private graphCache = new Map<
    string,
    {
      adjacency: Map<string, AdjacencyEntry[]>;
      personMap: Map<string, PersonRecord>;
      builtAt: number;
      ttlMs: number;
    }
  >();

  private static readonly DEFAULT_CACHE_TTL_MS = 60_000; // 1 minute

  constructor(private prisma: PrismaService) {}

  // ══════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ══════════════════════════════════════════════════════════════════════

  /**
   * Build adjacency list from database relationships.
   *
   * Returns a Map where each key is a personId and the value is an
   * array of adjacency entries (neighbor + relationship type + direction).
   *
   * The graph is bidirectional — for every stored relationship A→B,
   * we also create an inverse edge B→A using the INVERSE_MAP.
   *
   * Caching: Results are cached in-memory for DEFAULT_CACHE_TTL_MS.
   *          Call with `{ forceRefresh: true }` to bypass cache.
   */
  async buildGraph(
    familyId: string,
    options: { forceRefresh?: boolean; ttlMs?: number } = {},
  ): Promise<Map<string, AdjacencyEntry[]>> {
    const cacheKey = familyId;
    const cached = this.graphCache.get(cacheKey);
    const ttlMs = options.ttlMs ?? GraphEngineService.DEFAULT_CACHE_TTL_MS;

    if (!options.forceRefresh && cached && Date.now() - cached.builtAt < cached.ttlMs) {
      this.logger.debug(`Graph cache hit for family ${familyId}`);
      return cached.adjacency;
    }

    this.logger.debug(`Building graph for family ${familyId}`);

    // Load all active, non-deleted persons
    const persons = await this.prisma.person.findMany({
      where: { familyId, deletedAt: null },
      select: { id: true, name: true, gender: true },
    });

    const personMap = new Map<string, PersonRecord>(
      persons.map((p) => [p.id, { id: p.id, name: p.name, gender: p.gender }]),
    );

    const activePersonIds = new Set(persons.map((p) => p.id));

    // Load all active relationships
    const relationships = await this.prisma.relationship.findMany({
      where: { familyId, isActive: true },
      select: {
        fromPersonId: true,
        toPersonId: true,
        relationshipKey: true,
      },
    });

    // Build adjacency list with bidirectional edges
    const adjacency = new Map<string, AdjacencyEntry[]>();

    const addEdge = (
      fromId: string,
      toId: string,
      relKey: string,
      direction: 'up' | 'down' | 'sideways',
    ) => {
      if (!activePersonIds.has(fromId) || !activePersonIds.has(toId)) return;
      if (fromId === toId) return; // Skip self-loops

      if (!adjacency.has(fromId)) {
        adjacency.set(fromId, []);
      }
      adjacency.get(fromId)!.push({ neighborId: toId, relationshipKey: relKey, direction });
    };

    for (const rel of relationships) {
      const fromId = rel.fromPersonId;
      const toId = rel.toPersonId;
      const key = rel.relationshipKey;

      if (!activePersonIds.has(fromId) || !activePersonIds.has(toId)) continue;
      if (fromId === toId) continue;

      // Forward edge: fromPerson --[key]--> toPerson
      const forwardDir = GraphEngineService.DIRECTION_MAP[key] ?? 'sideways';
      addEdge(fromId, toId, key, forwardDir);

      // Inverse edge: toPerson --[inverseKey]--> fromPerson
      const inverseKey = this.computeInverseKey(key, personMap.get(fromId)?.gender ?? null);
      const inverseDir = this.invertDirection(forwardDir);
      addEdge(toId, fromId, inverseKey, inverseDir);
    }

    // Cache the result
    this.graphCache.set(cacheKey, {
      adjacency,
      personMap,
      builtAt: Date.now(),
      ttlMs,
    });

    this.logger.debug(
      `Built graph for family ${familyId}: ${personMap.size} persons, ${adjacency.size} nodes`,
    );

    return adjacency;
  }

  /**
   * BFS shortest path between two persons.
   *
   * Uses breadth-first search to find the shortest relationship path
   * from `fromPersonId` to `toPersonId` in the family graph.
   *
   * Returns a PathResult with:
   *  - found: whether a path exists
   *  - path: ordered list of RelationshipStep objects
   *  - distance: number of edges
   *  - kinshipTerm: resolved English kinship term (if path found)
   *  - kinshipTermHindi: resolved Hindi kinship term (if path found)
   */
  async findPath(
    familyId: string,
    fromPersonId: string,
    toPersonId: string,
  ): Promise<PathResult> {
    if (fromPersonId === toPersonId) {
      const person = await this.getPersonRecord(familyId, fromPersonId);
      return {
        found: true,
        path: person
          ? [
              {
                personId: person.id,
                personName: person.name,
                relationshipType: 'self',
                direction: 'sideways',
              },
            ]
          : [],
        distance: 0,
        kinshipTerm: 'self',
        kinshipTermHindi: 'स्वयं',
      };
    }

    const adjacency = await this.buildGraph(familyId);
    const cached = this.graphCache.get(familyId);
    const personMap = cached?.personMap ?? new Map<string, PersonRecord>();

    // Validate that both persons exist
    if (!personMap.has(fromPersonId)) {
      throw new NotFoundException(`Person ${fromPersonId} not found in family ${familyId}`);
    }
    if (!personMap.has(toPersonId)) {
      throw new NotFoundException(`Person ${toPersonId} not found in family ${familyId}`);
    }

    // BFS with path tracking
    const visited = new Set<string>();
    const queue: Array<{
      personId: string;
      steps: RelationshipStep[];
    }> = [
      {
        personId: fromPersonId,
        steps: [],
      },
    ];
    visited.add(fromPersonId);

    while (queue.length > 0) {
      const current = queue.shift()!;

      const neighbors = adjacency.get(current.personId) ?? [];
      for (const neighbor of neighbors) {
        if (visited.has(neighbor.neighborId)) continue;

        visited.add(neighbor.neighborId);

        const personRecord = personMap.get(neighbor.neighborId);
        const step: RelationshipStep = {
          personId: neighbor.neighborId,
          personName: personRecord?.name ?? 'Unknown',
          relationshipType: neighbor.relationshipKey,
          direction: neighbor.direction,
        };

        const newSteps = [...current.steps, step];

        if (neighbor.neighborId === toPersonId) {
          // Found the target — resolve kinship term
          const targetGender = personMap.get(toPersonId)?.gender ?? null;
          const kinshipResult = this.resolveKinship(newSteps, targetGender);

          return {
            found: true,
            path: newSteps,
            distance: newSteps.length,
            kinshipTerm: kinshipResult.term,
            kinshipTermHindi: kinshipResult.termHindi,
          };
        }

        queue.push({ personId: neighbor.neighborId, steps: newSteps });
      }
    }

    // No path found
    this.logger.debug(
      `No path found between ${fromPersonId} and ${toPersonId} in family ${familyId}`,
    );

    return {
      found: false,
      path: [],
      distance: -1,
    };
  }

  /**
   * Convert a path of RelationshipStep objects to a kinship term.
   *
   * This is the core algorithm:
   * 1. Extract the sequence of relationship types from the path
   * 2. Try to match against the KINSHIP_RULES lookup table (exact match)
   * 3. If no exact match, try progressive prefix matching (longest prefix first)
   * 4. If still no match, compose a descriptive term from the path
   *
   * @param path - Array of RelationshipStep objects (the traversal path)
   * @param targetGender - Gender of the target person (for gender-specific terms)
   */
  resolveKinship(path: RelationshipStep[], targetGender?: string | null): KinshipResult {
    if (path.length === 0) {
      return {
        term: 'self',
        termHindi: 'स्वयं',
        confidence: 1.0,
        path,
        genderSpecific: false,
      };
    }

    // Step 1: Build the path key (e.g., "father→brother→son")
    const pathKey = path.map((step) => step.relationshipType).join('→');

    // Step 2: Try exact match in KINSHIP_RULES
    const exactMatch =
      GraphEngineService.KINSHIP_RULES[pathKey] ??
      GraphEngineService.EXTENDED_INLAW_RULES[pathKey];

    if (exactMatch) {
      const genderKey = this.normalizeGenderKey(targetGender);
      const entry = exactMatch[genderKey];
      return {
        term: entry.term,
        termHindi: entry.termHindi,
        confidence: entry.confidence,
        path,
        genderSpecific: entry.genderSpecific,
      };
    }

    // Step 3: Try progressive prefix matching (longest first)
    // This handles cases where the exact path isn't in the lookup but
    // a prefix of it matches a known composition.
    const prefixResult = this.tryProgressiveComposition(path, targetGender);
    if (prefixResult) {
      return prefixResult;
    }

    // Step 4: No match found — compose a descriptive term
    return this.composeDescriptiveTerm(path, targetGender);
  }

  /**
   * Get all relationships for a person — both stored and computed.
   *
   * This method traverses the entire family graph starting from
   * `personId` and computes the kinship term for every reachable person.
   *
   * @param familyId - The family to search within
   * @param personId - The person whose relationships to compute
   * @param maxDepth - Maximum traversal depth (default: 6)
   */
  async getAllRelationships(
    familyId: string,
    personId: string,
    maxDepth: number = 6,
  ): Promise<ComputedRelationship[]> {
    const adjacency = await this.buildGraph(familyId);
    const cached = this.graphCache.get(familyId);
    const personMap = cached?.personMap ?? new Map<string, PersonRecord>();

    if (!personMap.has(personId)) {
      throw new NotFoundException(`Person ${personId} not found in family ${familyId}`);
    }

    const results: ComputedRelationship[] = [];

    // BFS to find all reachable persons within maxDepth
    const visited = new Set<string>([personId]);
    const queue: Array<{
      currentId: string;
      steps: RelationshipStep[];
      depth: number;
    }> = [];

    // Seed queue with immediate neighbors
    const neighbors = adjacency.get(personId) ?? [];
    for (const neighbor of neighbors) {
      if (visited.has(neighbor.neighborId)) continue;

      const personRecord = personMap.get(neighbor.neighborId);
      const step: RelationshipStep = {
        personId: neighbor.neighborId,
        personName: personRecord?.name ?? 'Unknown',
        relationshipType: neighbor.relationshipKey,
        direction: neighbor.direction,
      };

      queue.push({ currentId: neighbor.neighborId, steps: [step], depth: 1 });
    }

    while (queue.length > 0) {
      const current = queue.shift()!;

      if (visited.has(current.currentId)) continue;
      visited.add(current.currentId);

      // Resolve kinship term for this path
      const targetGender = personMap.get(current.currentId)?.gender ?? null;
      const kinshipResult = this.resolveKinship(current.steps, targetGender);

      const personRecord = personMap.get(current.currentId);
      results.push({
        personId: current.currentId,
        personName: personRecord?.name ?? 'Unknown',
        relationshipKey: current.steps.map((s) => s.relationshipType).join('→'),
        computedTerm: kinshipResult.term,
        computedTermHindi: kinshipResult.termHindi,
        distance: current.depth,
        path: current.steps,
      });

      // Continue BFS if within depth limit
      if (current.depth < maxDepth) {
        const nextNeighbors = adjacency.get(current.currentId) ?? [];
        for (const neighbor of nextNeighbors) {
          if (visited.has(neighbor.neighborId)) continue;

          const nextRecord = personMap.get(neighbor.neighborId);
          const nextStep: RelationshipStep = {
            personId: neighbor.neighborId,
            personName: nextRecord?.name ?? 'Unknown',
            relationshipType: neighbor.relationshipKey,
            direction: neighbor.direction,
          };

          queue.push({
            currentId: neighbor.neighborId,
            steps: [...current.steps, nextStep],
            depth: current.depth + 1,
          });
        }
      }
    }

    return results;
  }

  /**
   * Get ancestors (going up the tree through parent links).
   *
   * Traverses the graph upward via father/mother edges,
   * collecting all ancestors up to `maxDepth` generations.
   */
  async getAncestors(
    familyId: string,
    personId: string,
    maxDepth: number = 5,
  ): Promise<PersonNode[]> {
    const adjacency = await this.buildGraph(familyId);
    const cached = this.graphCache.get(familyId);
    const personMap = cached?.personMap ?? new Map<string, PersonRecord>();

    if (!personMap.has(personId)) {
      throw new NotFoundException(`Person ${personId} not found in family ${familyId}`);
    }

    const ancestors: PersonNode[] = [];
    const visited = new Set<string>([personId]);

    // DFS upward through parent edges
    const stack: Array<{ id: string; depth: number; relationship: string }> = [];

    // Seed with parent edges
    const neighbors = adjacency.get(personId) ?? [];
    for (const neighbor of neighbors) {
      if (neighbor.direction === 'up' && !visited.has(neighbor.neighborId)) {
        stack.push({
          id: neighbor.neighborId,
          depth: 1,
          relationship: neighbor.relationshipKey,
        });
      }
    }

    while (stack.length > 0) {
      const current = stack.pop()!;

      if (visited.has(current.id) || current.depth > maxDepth) continue;
      visited.add(current.id);

      const personRecord = personMap.get(current.id);
      if (!personRecord) continue;

      ancestors.push({
        personId: current.id,
        name: personRecord.name,
        gender: personRecord.gender ?? undefined,
        depth: current.depth,
        relationship: current.relationship,
      });

      // Continue upward
      const parentEdges = (adjacency.get(current.id) ?? []).filter(
        (e) => e.direction === 'up',
      );
      for (const edge of parentEdges) {
        if (!visited.has(edge.neighborId)) {
          stack.push({
            id: edge.neighborId,
            depth: current.depth + 1,
            relationship: edge.relationshipKey,
          });
        }
      }
    }

    // Sort by depth then name
    return ancestors.sort((a, b) => a.depth - b.depth || a.name.localeCompare(b.name));
  }

  /**
   * Get descendants (going down the tree through child links).
   *
   * Traverses the graph downward via son/daughter edges,
   * collecting all descendants up to `maxDepth` generations.
   */
  async getDescendants(
    familyId: string,
    personId: string,
    maxDepth: number = 5,
  ): Promise<PersonNode[]> {
    const adjacency = await this.buildGraph(familyId);
    const cached = this.graphCache.get(familyId);
    const personMap = cached?.personMap ?? new Map<string, PersonRecord>();

    if (!personMap.has(personId)) {
      throw new NotFoundException(`Person ${personId} not found in family ${familyId}`);
    }

    const descendants: PersonNode[] = [];
    const visited = new Set<string>([personId]);

    // BFS downward through child edges
    const queue: Array<{ id: string; depth: number; relationship: string }> = [];

    // Seed with child edges
    const neighbors = adjacency.get(personId) ?? [];
    for (const neighbor of neighbors) {
      if (neighbor.direction === 'down' && !visited.has(neighbor.neighborId)) {
        queue.push({
          id: neighbor.neighborId,
          depth: 1,
          relationship: neighbor.relationshipKey,
        });
      }
    }

    while (queue.length > 0) {
      const current = queue.shift()!;

      if (visited.has(current.id) || current.depth > maxDepth) continue;
      visited.add(current.id);

      const personRecord = personMap.get(current.id);
      if (!personRecord) continue;

      descendants.push({
        personId: current.id,
        name: personRecord.name,
        gender: personRecord.gender ?? undefined,
        depth: current.depth,
        relationship: current.relationship,
      });

      // Continue downward
      const childEdges = (adjacency.get(current.id) ?? []).filter(
        (e) => e.direction === 'down',
      );
      for (const edge of childEdges) {
        if (!visited.has(edge.neighborId)) {
          queue.push({
            id: edge.neighborId,
            depth: current.depth + 1,
            relationship: edge.relationshipKey,
          });
        }
      }
    }

    // Sort by depth then name
    return descendants.sort((a, b) => a.depth - b.depth || a.name.localeCompare(b.name));
  }

  /**
   * Invalidate the graph cache for a specific family.
   * Call this whenever relationships are added/updated/deleted.
   */
  invalidateCache(familyId: string): void {
    this.graphCache.delete(familyId);
    this.logger.debug(`Graph cache invalidated for family ${familyId}`);
  }

  /**
   * Invalidate all graph caches.
   */
  invalidateAllCaches(): void {
    this.graphCache.clear();
    this.logger.debug('All graph caches invalidated');
  }

  // ══════════════════════════════════════════════════════════════════════
  // PRIVATE HELPERS
  // ══════════════════════════════════════════════════════════════════════

  /**
   * Compute the inverse relationship key for bidirectional traversal.
   *
   * For gender-dependent inverses (e.g., father → son/daughter),
   * we use the target person's gender to determine the correct term.
   * If gender is unknown, we use a generic term.
   */
  private computeInverseKey(
    forwardKey: string,
    fromPersonGender: string | null,
  ): string {
    switch (forwardKey) {
      case 'father':
        return fromPersonGender === 'female' ? 'daughter' : 'son';
      case 'mother':
        return fromPersonGender === 'female' ? 'daughter' : 'son';
      case 'son':
        return fromPersonGender === 'female' ? 'mother' : 'father';
      case 'daughter':
        return fromPersonGender === 'female' ? 'mother' : 'father';
      case 'brother':
        return fromPersonGender === 'female' ? 'sister' : 'brother';
      case 'sister':
        return fromPersonGender === 'female' ? 'sister' : 'brother';
      case 'husband':
        return 'wife';
      case 'wife':
        return 'husband';
      default:
        // For non-core relationship keys stored in the database
        // (e.g., grandfather, uncle, cousin), apply similar logic
        return this.computeExtendedInverseKey(forwardKey, fromPersonGender);
    }
  }

  /**
   * Compute inverse keys for extended (non-core) relationship types.
   * These may already exist in the database from the RelationshipsService.
   */
  private computeExtendedInverseKey(
    forwardKey: string,
    fromPersonGender: string | null,
  ): string {
    // Handle common extended keys that might be in the database
    const EXTENDED_INVERSE: Record<string, string> = {
      grandfather: fromPersonGender === 'female' ? 'granddaughter' : 'grandson',
      grandmother: fromPersonGender === 'female' ? 'granddaughter' : 'grandson',
      grandson: 'grandfather',
      granddaughter: 'grandmother',
      uncle: fromPersonGender === 'female' ? 'niece' : 'nephew',
      aunt: fromPersonGender === 'female' ? 'niece' : 'nephew',
      nephew: fromPersonGender === 'female' ? 'aunt' : 'uncle',
      niece: fromPersonGender === 'female' ? 'aunt' : 'uncle',
      cousin: 'cousin',
      father_in_law: fromPersonGender === 'female' ? 'daughter_in_law' : 'son_in_law',
      mother_in_law: fromPersonGender === 'female' ? 'daughter_in_law' : 'son_in_law',
      son_in_law: fromPersonGender === 'female' ? 'mother_in_law' : 'father_in_law',
      daughter_in_law: fromPersonGender === 'female' ? 'mother_in_law' : 'father_in_law',
      brother_in_law: 'brother_in_law',
      sister_in_law: 'sister_in_law',
      great_grandfather: fromPersonGender === 'female' ? 'great_granddaughter' : 'great_grandson',
      great_grandmother: fromPersonGender === 'female' ? 'great_granddaughter' : 'great_grandson',
      paternal_grandfather: fromPersonGender === 'female' ? 'granddaughter' : 'grandson',
      paternal_grandmother: fromPersonGender === 'female' ? 'granddaughter' : 'grandson',
      maternal_grandfather: fromPersonGender === 'female' ? 'granddaughter' : 'grandson',
      maternal_grandmother: fromPersonGender === 'female' ? 'granddaughter' : 'grandson',
      stepfather: fromPersonGender === 'female' ? 'stepdaughter' : 'stepson',
      stepmother: fromPersonGender === 'female' ? 'stepdaughter' : 'stepson',
      elder_brother: 'younger_brother',
      younger_brother: 'elder_brother',
      elder_sister: 'younger_sister',
      younger_sister: 'elder_sister',
      // Keys used by the RelationshipsService
      fathers_brother: fromPersonGender === 'female' ? 'niece' : 'nephew',
      fathers_sister: fromPersonGender === 'female' ? 'niece' : 'nephew',
      mothers_brother: fromPersonGender === 'female' ? 'niece' : 'nephew',
      mothers_sister: fromPersonGender === 'female' ? 'niece' : 'nephew',
      husbands_father: 'sons_wife',
      husbands_mother: 'sons_wife',
      wives_father: 'daughters_husband',
      wives_mother: 'daughters_husband',
      sons_wife: 'husbands_father',
      daughters_husband: 'wives_father',
    };

    return EXTENDED_INVERSE[forwardKey] ?? forwardKey;
  }

  /**
   * Invert a direction (up ↔ down, sideways stays sideways).
   */
  private invertDirection(dir: 'up' | 'down' | 'sideways'): 'up' | 'down' | 'sideways' {
    if (dir === 'up') return 'down';
    if (dir === 'down') return 'up';
    return 'sideways';
  }

  /**
   * Normalize a gender value to one of the three keys used in the
   * KINSHIP_RULES lookup table: 'male', 'female', or 'neutral'.
   */
  private normalizeGenderKey(gender: string | null | undefined): 'male' | 'female' | 'neutral' {
    if (gender === 'male') return 'male';
    if (gender === 'female') return 'female';
    return 'neutral';
  }

  /**
   * Try progressive composition — match the longest prefix of the path
   * against known rules, then attempt to compose the remaining steps.
   *
   * For example, if the path is [father, father, brother, son, daughter]
   * and we know "father→father→brother→son" = second_cousin,
   * then "second_cousin + daughter" might be "second_cousin_once_removed".
   */
  private tryProgressiveComposition(
    path: RelationshipStep[],
    targetGender: string | null,
  ): KinshipResult | null {
    // Try matching progressively shorter prefixes
    for (let prefixLen = path.length - 1; prefixLen >= 2; prefixLen--) {
      const prefixKey = path
        .slice(0, prefixLen)
        .map((s) => s.relationshipType)
        .join('→');

      const prefixRule =
        GraphEngineService.KINSHIP_RULES[prefixKey] ??
        GraphEngineService.EXTENDED_INLAW_RULES[prefixKey];

      if (!prefixRule) continue;

      const genderKey = this.normalizeGenderKey(targetGender);
      const prefixEntry = prefixRule[genderKey];
      const remainingSteps = path.slice(prefixLen);

      // Compose: prefix_term + remaining steps
      const remainingKey = remainingSteps.map((s) => s.relationshipType).join('→');

      // Check if the composed path exists
      const composedKey = `${prefixEntry.term}→${remainingKey}`;
      const composedRule =
        GraphEngineService.KINSHIP_RULES[composedKey] ??
        GraphEngineService.EXTENDED_INLAW_RULES[composedKey];

      if (composedRule) {
        const entry = composedRule[genderKey];
        return {
          term: entry.term,
          termHindi: entry.termHindi,
          confidence: Math.min(entry.confidence, prefixEntry.confidence) * 0.9,
          path,
          genderSpecific: entry.genderSpecific || prefixEntry.genderSpecific,
        };
      }

      // If no composed rule exists, use the prefix term with a
      // reduced confidence and append the remaining steps descriptively
      const suffix = remainingSteps
        .map((s) => s.relationshipType)
        .join("'s ")
        .replace(/_/g, ' ');

      return {
        term: `${prefixEntry.term}'s ${suffix}`,
        termHindi: `${prefixEntry.termHindi} का/की ${suffix}`,
        confidence: prefixEntry.confidence * 0.7,
        path,
        genderSpecific: prefixEntry.genderSpecific,
      };
    }

    return null;
  }

  /**
   * Compose a descriptive kinship term when no lookup rule matches.
   *
   * This handles deeply nested or uncommon relationship paths by
   * generating a human-readable description like
   * "father's brother's son's daughter" and computing an
   * appropriate confidence score based on path length.
   */
  private composeDescriptiveTerm(
    path: RelationshipStep[],
    targetGender: string | null,
  ): KinshipResult {
    // Generate human-readable path description
    const parts = path.map((step) => step.relationshipType.replace(/_/g, ' '));
    const descriptiveTerm = parts.join("'s ");

    // Generate Hindi descriptive term
    const hindiParts = path.map((step) => {
      const hindiMap: Record<string, string> = {
        father: 'पिता',
        mother: 'माता',
        son: 'बेटा',
        daughter: 'बेटी',
        brother: 'भाई',
        sister: 'बहन',
        husband: 'पति',
        wife: 'पत्नी',
      };
      return hindiMap[step.relationshipType] ?? step.relationshipType;
    });
    const descriptiveTermHindi = hindiParts.join(' के/की ');

    // Confidence decreases with path length
    const confidence = Math.max(0.3, 1.0 - path.length * 0.1);

    // Determine if the final step is gender-specific
    const lastStep = path[path.length - 1];
    const genderSpecific =
      lastStep.relationshipType === 'son' ||
      lastStep.relationshipType === 'daughter' ||
      lastStep.relationshipType === 'brother' ||
      lastStep.relationshipType === 'sister' ||
      lastStep.relationshipType === 'husband' ||
      lastStep.relationshipType === 'wife' ||
      lastStep.relationshipType === 'father' ||
      lastStep.relationshipType === 'mother';

    return {
      term: descriptiveTerm,
      termHindi: descriptiveTermHindi,
      confidence,
      path,
      genderSpecific,
    };
  }

  /**
   * Get a person record from the database.
   */
  private async getPersonRecord(
    familyId: string,
    personId: string,
  ): Promise<PersonRecord | null> {
    // Check cache first
    const cached = this.graphCache.get(familyId);
    if (cached?.personMap.has(personId)) {
      return cached.personMap.get(personId)!;
    }

    // Fallback to DB
    const person = await this.prisma.person.findFirst({
      where: { id: personId, familyId, deletedAt: null },
      select: { id: true, name: true, gender: true },
    });

    if (!person) return null;

    return { id: person.id, name: person.name, gender: person.gender };
  }
}
