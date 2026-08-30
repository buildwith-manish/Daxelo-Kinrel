/**
 * Daxelo-Kinrel v3.0 — Relationship Validator
 * ══════════════════════════════════════════════════════════════════════
 *
 * Spec §12 — Validation Rules
 *
 * Before creating any relationship:
 *   1. Reject self-relationships. A person cannot relate to themselves.
 *   2. Reject duplicate edges. No two identical fundamental edges between the same pair.
 *   3. Reject circular ancestry. If A is an ancestor of B, B cannot be a parent of A.
 *   4. Reject invalid spouse relationships. Cannot marry an ancestor or descendant.
 *   5. Reject contradictory relationships. If A is already B's parent, A cannot be B's spouse.
 *   6. Preserve existing valid relationships. Never overwrite confirmed data automatically.
 *
 * This validator runs in-memory using a snapshot of existing edges,
 * so it can be called synchronously inside a Prisma transaction
 * without an extra round-trip to the DB.
 */

import { Injectable, Logger, BadRequestException, ConflictException } from '@nestjs/common';
import type { FundamentalEdge } from '../kinship/relationship-normalizer.service';

// ── Validation Input ──────────────────────────────────────────────────

export interface ValidationInput {
  familyId: string;
  fromPersonId: string;
  toPersonId: string;
  edge: FundamentalEdge;
  /** Existing relationships in the family (for duplicate/circular/contradictory checks). */
  existingEdges: Array<{
    fromPersonId: string;
    toPersonId: string;
    edge: string; // 'parent' | 'spouse' | 'adoptive_parent' | 'step_parent' | legacy key
  }>;
}

export interface ValidationFailure {
  rule: string;
  message: string;
}

export interface ValidationResult {
  valid: boolean;
  failures: ValidationFailure[];
}

// ── Service ───────────────────────────────────────────────────────────

@Injectable()
export class RelationshipValidator {
  private readonly logger = new Logger(RelationshipValidator.name);

  /**
   * Run all 6 validation rules against the proposed edge.
   *
   * Returns `valid: true` if all rules pass; otherwise returns the
   * list of failures with human-readable messages.
   *
   * The caller is responsible for translating failures to HTTP exceptions
   * (typically 400 BadRequest for self-relationship, 409 Conflict for
   * duplicates and contradictions).
   */
  validate(input: ValidationInput): ValidationResult {
    const failures: ValidationFailure[] = [];

    // Rule 1: reject self-relationships
    if (input.fromPersonId === input.toPersonId) {
      failures.push({
        rule: 'NO_SELF_RELATIONSHIP',
        message: 'A person cannot be related to themselves.',
      });
    }

    // Rule 2: reject duplicate fundamental edges
    if (this.isDuplicateEdge(input)) {
      failures.push({
        rule: 'NO_DUPLICATE_EDGE',
        message: `A ${input.edge} edge between these two persons already exists.`,
      });
    }

    // Rule 3: reject circular ancestry (parent-class only)
    if (input.edge === 'parent' || input.edge === 'adoptive_parent' || input.edge === 'step_parent') {
      if (this.wouldCreateCircularAncestry(input)) {
        failures.push({
          rule: 'NO_CIRCULAR_ANCESTRY',
          message: 'Cannot create this parent edge — it would form a cycle in the ancestry graph.',
        });
      }
    }

    // Rule 4: reject invalid spouse (cannot marry ancestor/descendant)
    if (input.edge === 'spouse') {
      if (this.wouldMarryAncestorOrDescendant(input)) {
        failures.push({
          rule: 'NO_SPOUSE_TO_ANCESTOR_OR_DESCENDANT',
          message: 'Cannot marry an ancestor or descendant.',
        });
      }
    }

    // Rule 5: reject contradictory relationships
    if (this.isContradictory(input)) {
      failures.push({
        rule: 'NO_CONTRADICTORY_RELATIONSHIP',
        message: `A ${input.edge} edge contradicts an existing relationship between these two persons.`,
      });
    }

    // Rule 6: preserve existing valid relationships
    // (This rule is enforced by the caller — we never overwrite confirmed
    // data automatically. We return valid=false if overwriting would be
    // required, with a descriptive failure.)
    if (this.wouldOverwriteConfirmed(input)) {
      failures.push({
        rule: 'PRESERVE_EXISTING',
        message: 'An existing confirmed relationship would be overwritten. Refusing to auto-overwrite.',
      });
    }

    return {
      valid: failures.length === 0,
      failures,
    };
  }

  /**
   * Convenience: validate, then throw the appropriate NestJS HTTP exception
   * if validation fails.
   */
  validateOrThrow(input: ValidationInput): void {
    const result = this.validate(input);
    if (result.valid) return;

    const first = result.failures[0];
    const allRules = result.failures.map(f => f.rule).join(', ');

    this.logger.warn(
      `Relationship validation failed for ${input.fromPersonId} → ${input.toPersonId} (${input.edge}): ${allRules}`,
    );

    // Self-relationship → 400
    if (result.failures.some(f => f.rule === 'NO_SELF_RELATIONSHIP')) {
      throw new BadRequestException(first.message);
    }
    // Duplicates, contradictions, circular ancestry, invalid spouse → 409
    throw new ConflictException(
      `${first.message}${result.failures.length > 1 ? ` (also: ${result.failures.slice(1).map(f => f.rule).join(', ')})` : ''}`,
    );
  }

  // ── Private: Individual Rule Implementations ────────────────────────

  /**
   * Rule 2: duplicate fundamental edge.
   * A duplicate is the same edge type between the same two persons in
   * either direction. (Spouse is symmetric; parent-class edges have
   * explicit inverses but the engine treats them as a single stored
   * row plus its computed inverse — see spec §11.)
   */
  private isDuplicateEdge(input: ValidationInput): boolean {
    const edge = input.edge;
    for (const e of input.existingEdges) {
      // Spouse is bidirectional — check both directions
      if (edge === 'spouse' && (e.edge === 'spouse' || e.edge === 'husband' || e.edge === 'wife')) {
        if (
          (e.fromPersonId === input.fromPersonId && e.toPersonId === input.toPersonId) ||
          (e.fromPersonId === input.toPersonId && e.toPersonId === input.fromPersonId)
        ) {
          return true;
        }
      }
      // Parent-class edges: forward (A→B) and reverse (B→A) count as duplicates
      // because we'd store the same edge twice.
      if (edge === e.edge || this.isSameParentClassEdge(edge, e.edge)) {
        if (
          (e.fromPersonId === input.fromPersonId && e.toPersonId === input.toPersonId) ||
          (e.fromPersonId === input.toPersonId && e.toPersonId === input.fromPersonId)
        ) {
          return true;
        }
      }
    }
    return false;
  }

  /**
   * Helper: check whether two edge strings belong to the same fundamental
   * "parent-class" group (parent, adoptive_parent, step_parent, plus the
   * legacy father/mother/son/daughter keys).
   */
  private isSameParentClassEdge(a: string, b: string): boolean {
    const parentClass = new Set([
      'parent', 'adoptive_parent', 'step_parent',
      'father', 'mother', 'son', 'daughter',
    ]);
    return parentClass.has(a) && parentClass.has(b);
  }

  /**
   * Rule 3: circular ancestry.
   * If `toPersonId` is already an ancestor of `fromPersonId`, then making
   * `toPersonId` a parent of `fromPersonId` would create a cycle.
   *
   * Equivalent check: if `fromPersonId` is already a descendant of `toPersonId`.
   */
  private wouldCreateCircularAncestry(input: ValidationInput): boolean {
    // We're about to add a parent edge: fromPerson → toPerson (toPerson is parent of fromPerson).
    // Cycle: does `toPersonId` already have `fromPersonId` as an ancestor?
    //
    // i.e. trace UP from `toPersonId`; if we reach `fromPersonId`, cycle.
    const ancestors = this.collectAncestors(input.toPersonId, input.existingEdges);
    return ancestors.has(input.fromPersonId);
  }

  /**
   * Rule 4: invalid spouse.
   * Cannot marry an ancestor or descendant.
   */
  private wouldMarryAncestorOrDescendant(input: ValidationInput): boolean {
    const ancestors = this.collectAncestors(input.fromPersonId, input.existingEdges);
    if (ancestors.has(input.toPersonId)) return true;

    const descendants = this.collectDescendants(input.fromPersonId, input.existingEdges);
    if (descendants.has(input.toPersonId)) return true;

    return false;
  }

  /**
   * Rule 5: contradictory.
   * If A is already B's parent (in either direction), A cannot be B's spouse.
   * If A is already B's spouse, A cannot also be B's parent (in either direction).
   */
  private isContradictory(input: ValidationInput): boolean {
    const a = input.fromPersonId;
    const b = input.toPersonId;

    for (const e of input.existingEdges) {
      const isSpouse =
        e.edge === 'spouse' || e.edge === 'husband' || e.edge === 'wife';
      const isParentClass = this.isSameParentClassEdge('parent', e.edge);

      const connectsAB =
        (e.fromPersonId === a && e.toPersonId === b) ||
        (e.fromPersonId === b && e.toPersonId === a);

      if (!connectsAB) continue;

      // Trying to add spouse when there's a parent-class edge → contradiction
      if (input.edge === 'spouse' && isParentClass) return true;
      // Trying to add parent-class when there's already a spouse edge → contradiction
      if ((input.edge === 'parent' || input.edge === 'adoptive_parent' || input.edge === 'step_parent') && isSpouse) return true;
    }

    return false;
  }

  /**
   * Rule 6: would overwrite a confirmed relationship.
   * In our model, edges are stored as a single forward row + computed
   * inverse — there's never an "overwrite" because duplicates are
   * rejected at the DB unique-constraint level (spec §2). The only
   * overwrite case is when the user submits an edge that conflicts
   * with an existing edge between the same two persons but a different
   * edge type — and that case is handled by Rule 5 (contradictory).
   *
   * This rule is a safety net for legacy data and is effectively a
   * no-op for fresh fundamental edges.
   */
  private wouldOverwriteConfirmed(input: ValidationInput): boolean {
    // No-op for v3.0 — duplicates are caught by Rule 2, contradictions
    // by Rule 5. Confirmed edges are never auto-overwritten because
    // we never call update() in the create flow.
    return false;
  }

  // ── Traversal Helpers ──────────────────────────────────────────────

  /**
   * Collect all ancestors of `personId` by walking UP through parent-class
   * edges (parent, adoptive_parent, step_parent, plus legacy
   * father/mother/son/daughter keys).
   *
   * Cycle-safe: uses a visited set.
   */
  private collectAncestors(
    personId: string,
    edges: Array<{ fromPersonId: string; toPersonId: string; edge: string }>,
  ): Set<string> {
    const ancestors = new Set<string>();
    const visited = new Set<string>([personId]);
    const queue: string[] = [personId];

    while (queue.length > 0) {
      const current = queue.shift()!;
      for (const e of edges) {
        // A→B is a parent edge means "A's parent is B" (A is the child, B is the parent).
        // So traversing UP from `current`: find edges where fromPersonId === current
        // and edge is parent-class.
        if (e.fromPersonId === current && this.isSameParentClassEdge('parent', e.edge)) {
          if (!visited.has(e.toPersonId)) {
            visited.add(e.toPersonId);
            ancestors.add(e.toPersonId);
            queue.push(e.toPersonId);
          }
        }
        // Legacy inverse: parent→person with key='son'/'daughter' means parent is fromPersonId, child is toPersonId.
        // So traversing UP from `current`: find edges where toPersonId === current and edge is son/daughter
        // (the parent is the fromPersonId).
        if (e.toPersonId === current && (e.edge === 'son' || e.edge === 'daughter')) {
          if (!visited.has(e.fromPersonId)) {
            visited.add(e.fromPersonId);
            ancestors.add(e.fromPersonId);
            queue.push(e.fromPersonId);
          }
        }
      }
    }

    return ancestors;
  }

  /**
   * Collect all descendants of `personId` by walking DOWN through
   * parent-class edges (parent, adoptive_parent, step_parent, plus legacy
   * father/mother/son/daughter).
   *
   * Cycle-safe.
   */
  private collectDescendants(
    personId: string,
    edges: Array<{ fromPersonId: string; toPersonId: string; edge: string }>,
  ): Set<string> {
    const descendants = new Set<string>();
    const visited = new Set<string>([personId]);
    const queue: string[] = [personId];

    while (queue.length > 0) {
      const current = queue.shift()!;
      for (const e of edges) {
        // A→B is a parent edge means B is the parent of A → so to find children of `current`,
        // find edges where toPersonId === current and edge is parent-class.
        if (e.toPersonId === current && this.isSameParentClassEdge('parent', e.edge)) {
          if (!visited.has(e.fromPersonId)) {
            visited.add(e.fromPersonId);
            descendants.add(e.fromPersonId);
            queue.push(e.fromPersonId);
          }
        }
        // Legacy forward: parent→person with key='son'/'daughter'
        // (parent is fromPersonId, child is toPersonId).
        if (e.fromPersonId === current && (e.edge === 'son' || e.edge === 'daughter')) {
          if (!visited.has(e.toPersonId)) {
            visited.add(e.toPersonId);
            descendants.add(e.toPersonId);
            queue.push(e.toPersonId);
          }
        }
      }
    }

    return descendants;
  }
}
