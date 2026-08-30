/**
 * Daxelo-Kinrel v3.0 — Relationship Normalizer
 * ══════════════════════════════════════════════════════════════════════
 *
 * Spec §8 — Bridge between user-facing kinship terms and fundamental
 * storage. Accepts a detected term, normalizes it to a Canonical ID,
 * then maps that Canonical ID to the fundamental edge that should be
 * stored in the database.
 *
 * Critical rule (spec §8.2):
 *   If the auto-detection engine returns a derived term (e.g. "uncle"),
 *   the normalizer must trace back to the missing fundamental edge that
 *   would complete the graph, ask the user to confirm that edge, and
 *   store ONLY the fundamental edge.
 *
 * Flow:
 *   Detected Term (e.g. "wife")
 *     ↓
 *   Canonical ID (e.g. "SPOUSE")
 *     ↓
 *   Relationship Normalizer
 *     ↓
 *   Fundamental Edge (e.g. "spouse")
 *     ↓
 *   Store in Database
 */

import { Injectable, Logger } from '@nestjs/common';
import {
  CanonicalIdService,
  CanonicalResolution,
} from './canonical-id.service';

// ── Fundamental edge strings (matches Prisma EdgeType enum) ────────────

export type FundamentalEdge =
  | 'parent'
  | 'spouse'
  | 'adoptive_parent'
  | 'step_parent';

// ── Result Types ──────────────────────────────────────────────────────

export interface NormalizationResult {
  /** The fundamental edge to store, or null if the input was derived. */
  fundamentalEdge: FundamentalEdge | null;
  /** Direction of the parent-class edge: 'forward' = from→to is parent, 'reverse' = to→from is parent. */
  direction: 'forward' | 'reverse' | 'bidirectional';
  /** True if the input was a derived term (grandfather, uncle, cousin). */
  isDerived: boolean;
  /** True if the input could not be normalized. */
  isUnknown: boolean;
  /** Echoed canonical resolution for UI display. */
  canonical: CanonicalResolution;
  /**
   * For derived inputs: the missing fundamental edge(s) the user must add
   * to complete the graph. Empty for fundamental inputs.
   */
  missingEdges: Array<{
    edge: FundamentalEdge;
    note: string;
  }>;
  /** English label for UI display. */
  englishLabel: string;
}

// ── Service ───────────────────────────────────────────────────────────

@Injectable()
export class RelationshipNormalizerService {
  private readonly logger = new Logger(RelationshipNormalizerService.name);

  // Canonical ID → Fundamental Edge mapping (spec §8.1)
  private static readonly CANONICAL_TO_EDGE: Record<string, FundamentalEdge> = {
    PARENT: 'parent',
    SPOUSE: 'spouse',
    ADOPTIVE_PARENT: 'adoptive_parent',
    STEP_PARENT: 'step_parent',
  };

  constructor(private readonly canonicalIdService: CanonicalIdService) {}

  /**
   * Normalize a user-input kinship term into the fundamental edge
   * that should be stored in the database.
   *
   * Returns:
   *   • For fundamental terms (father, mother, son, daughter, husband, wife,
   *     adoptive father/mother, step father/mother): the fundamental edge
   *     to store + the direction of the parent-class edge.
   *   • For derived terms (grandfather, uncle, cousin, in-laws, sibling):
   *     fundamentalEdge=null, isDerived=true, missingEdges describes the
   *     fundamental edge(s) the user must add instead.
   *   • For unrecognized input: isUnknown=true, asks user for clarification.
   */
  normalize(input: string, locale: string = 'en'): NormalizationResult {
    const canonical = this.canonicalIdService.normalizeToCanonical(input, locale);

    if (canonical.canonicalId === 'UNKNOWN') {
      return {
        fundamentalEdge: null,
        direction: 'forward',
        isDerived: false,
        isUnknown: true,
        canonical,
        missingEdges: [],
        englishLabel: canonical.englishLabel,
      };
    }

    if (canonical.canonicalId === 'DERIVED') {
      return {
        fundamentalEdge: null,
        direction: canonical.direction ?? 'forward',
        isDerived: true,
        isUnknown: false,
        canonical,
        missingEdges: canonical.missingEdges ?? [],
        englishLabel: canonical.englishLabel,
      };
    }

    // Fundamental canonical ID — map to fundamental edge
    const edge = RelationshipNormalizerService.CANONICAL_TO_EDGE[canonical.canonicalId];
    const direction: 'forward' | 'reverse' | 'bidirectional' =
      canonical.canonicalId === 'SPOUSE'
        ? 'bidirectional'
        : canonical.direction === 'reverse'
          ? 'reverse'
          : 'forward';

    return {
      fundamentalEdge: edge,
      direction,
      isDerived: false,
      isUnknown: false,
      canonical,
      missingEdges: [],
      englishLabel: canonical.englishLabel,
    };
  }

  /**
   * Resolve the inverse of a fundamental edge.
   *
   * Spec §11 — Every stored fundamental edge has a logical inverse for
   * traversal purposes. These inverses are computed in memory, NOT
   * stored as duplicate database rows.
   *
   *   parent (A→B)            → parent (B→A, but traversed as child)
   *   spouse (A→B)            → spouse (B→A, bidirectional)
   *   adoptive_parent (A→B)   → adoptive_parent (B→A, traversed as child)
   *   step_parent (A→B)       → step_parent (B→A, traversed as child)
   */
  static inverseEdge(edge: FundamentalEdge): FundamentalEdge {
    // All four fundamental edges are symmetric in their inverse:
    // a parent edge from A→B implies the same parent edge in the
    // reverse direction when traversed B→A. The gender-specific term
    // ("father"/"mother"/"son"/"daughter") is resolved at vocabulary
    // mapping time using the target person's gender (spec §11).
    return edge;
  }

  /**
   * Whether a given relationship key (legacy or canonical) is one of
   * the four fundamental edges.
   */
  isFundamentalEdge(key: string): boolean {
    const k = key.toLowerCase();
    return (
      k === 'parent' ||
      k === 'spouse' ||
      k === 'adoptive_parent' ||
      k === 'step_parent'
    );
  }

  /**
   * Returns the list of fundamental edges (for the manual picker UI
   * when auto-detection fails — spec §10).
   */
  listFundamentalEdges(): FundamentalEdge[] {
    return ['parent', 'spouse', 'adoptive_parent', 'step_parent'];
  }
}
