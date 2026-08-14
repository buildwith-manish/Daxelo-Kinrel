/**
 * Daxelo-Kinrel — Path Canonicalizer (spec §3.2)
 * ================================================
 * Before signature generation:
 *   1. Remove cycles.
 *   2. Remove backtracking (UP_PARENT followed by DOWN_CHILD on same node).
 *   3. Normalize equivalent paths to one canonical form.
 *   4. Produce the shortest valid path.
 *
 * Deterministic path selection (spec §3.3) when multiple shortest paths
 * of equal length exist:
 *   blood  >  adoptive  >  step  >  inLaw
 */

import { Primitive, Consanguinity } from "../kinship/kinship-signature";

export interface TraversalStep {
  primitive: Primitive;
  nodeId: string;        // person being traversed FROM at this step
  targetNodeId: string;  // person being traversed TO at this step
  edgeType: string;      // PARENT | SPOUSE | ADOPTIVE_PARENT | STEP_PARENT | ...
  consanguinity: Consanguinity;
}

export class PathCanonicalizer {
  /**
   * Remove backtracking per spec §3.2.2.
   * A backtracking pair is UP_PARENT immediately followed by DOWN_CHILD
   * on the same node (or vice versa) — they cancel out.
   */
  removeBacktracking(steps: TraversalStep[]): TraversalStep[] {
    const result: TraversalStep[] = [];
    let i = 0;
    while (i < steps.length) {
      if (i + 1 < steps.length) {
        const a = steps[i];
        const b = steps[i + 1];
        const isBacktrack =
          (a.primitive === "UP_PARENT" && b.primitive === "DOWN_CHILD" &&
            a.targetNodeId === b.nodeId) ||
          (a.primitive === "DOWN_CHILD" && b.primitive === "UP_PARENT" &&
            a.targetNodeId === b.nodeId) ||
          (a.primitive === "UP_ADOPTIVE_PARENT" && b.primitive === "DOWN_ADOPTIVE_CHILD" &&
            a.targetNodeId === b.nodeId) ||
          (a.primitive === "UP_STEP_PARENT" && b.primitive === "DOWN_STEP_CHILD" &&
            a.targetNodeId === b.nodeId);
        if (isBacktrack) {
          i += 2; // skip both
          continue;
        }
      }
      result.push(steps[i]);
      i += 1;
    }
    return result;
  }

  /**
   * Remove cycles per spec §3.2.1.
   * If the same node appears twice in the path, drop the segment between
   * the two occurrences.
   */
  removeCycles(steps: TraversalStep[]): TraversalStep[] {
    const visited = new Map<string, number>(); // nodeId → step index
    const result: TraversalStep[] = [];
    for (const step of steps) {
      if (visited.has(step.targetNodeId)) {
        // Cycle detected — trim everything after the first occurrence
        const cutAt = visited.get(step.targetNodeId)!;
        result.length = cutAt;
        visited.clear();
        result.forEach((s, idx) => visited.set(s.targetNodeId, idx));
      } else {
        visited.set(step.targetNodeId, result.length);
        result.push(step);
      }
    }
    return result;
  }

  /**
   * Canonicalize: cycles → backtracking → final form.
   * Order matters per spec §3.2.
   */
  canonicalize(steps: TraversalStep[]): TraversalStep[] {
    let s = this.removeCycles(steps);
    // Run backtracking removal iteratively until stable (one pass may expose new pairs).
    let prevLen: number;
    do {
      prevLen = s.length;
      s = this.removeBacktracking(s);
    } while (s.length > 0 && s.length < prevLen);
    return s;
  }

  /**
   * Deterministic path selection (spec §3.3).
   * When multiple shortest paths of equal length exist, pick by consanguinity rank:
   *   blood (0) > adoptive (1) > step (2) > inLaw (3) > foster (4) > spiritual (5)
   *
   * Returns the winning path.
   */
  selectDeterministic(candidates: TraversalStep[][]): TraversalStep[] {
    if (candidates.length === 0) return [];
    if (candidates.length === 1) return candidates[0];

    const rank: Record<string, number> = {
      blood: 0, adoptive: 1, step: 2, inLaw: 3, foster: 4, spiritual: 5,
    };
    const minLen = Math.min(...candidates.map((c) => c.length));
    const shortest = candidates.filter((c) => c.length === minLen);

    // Sort by (max consanguinity rank in path, then lexicographic path) — stable
    shortest.sort((a, b) => {
      const aMax = Math.max(...a.map((s) => rank[s.consanguinity] ?? 99));
      const bMax = Math.max(...b.map((s) => rank[s.consanguinity] ?? 99));
      if (aMax !== bMax) return aMax - bMax;
      // Tiebreak: lexicographic comparison of path patterns
      const aPat = a.map((s) => s.primitive).join("_");
      const bPat = b.map((s) => s.primitive).join("_");
      return aPat.localeCompare(bPat);
    });
    return shortest[0];
  }
}
