/**
 * GraphEngineService v4.0 spec
 * ══════════════════════════════════════════════════════════════════════
 *
 * Rewritten for the v4.0 deterministic kinship engine (commit 763e4d24 /
 * e4f3f0dc). The old spec targeted the removed v3 surface:
 *
 *   OLD (v3)                          → NEW (v4.0)
 *   ────────────────────────────────────────────────────────────────────
 *   GraphEngineService.CORE_TYPES     → FUNDAMENTAL_EDGES module const
 *                                       (parent/spouse/adoptive_parent/
 *                                       step_parent — graph-engine.service.ts:123-128);
 *                                       legacy gendered keys (father, mother,
 *                                       son, daughter, husband, wife) are
 *                                       normalized in buildAdjacency (:555-587)
 *   GraphEngineService.INVERSE_MAP    → adjacency is built bidirectionally:
 *                                       every edge registers both a forward
 *                                       and a reverse primitive (:593-597)
 *   service.buildGraph(familyId, opts) → private buildAdjacency + 60s TTL
 *                                       adjacencyCache (:131, :164-170, :514-520);
 *                                       forced refresh is invalidateCache() (:468-473)
 *   service.findPath(fam, from, to)   → same name/args, new PathResult shape
 *                                       {found, path, distance, signature, result}
 *                                       — kinshipTerm/kinshipTermHindi are
 *                                       legacy fields left to callers (:78-79);
 *                                       distance for "not found" is now 0
 *                                       (was -1) and self returns found=false
 *                                       (:227-237)
 *   service.resolveKinship(steps,     → resolveKinship(familyId, fromPersonId,
 *     targetGender)                     toPersonId) — loads the family graph
 *                                       from prisma, BFS shortest path,
 *                                       canonicalization, KinshipSignature;
 *                                       returns null for self / no path
 *                                       (:190-216). Hindi/localized terms and
 *                                       confidence scores were removed by
 *                                       design (header :7-13); the 5,396-term
 *                                       vocabulary is served by
 *                                       /kinship/resolve (kinship.controller.ts:72-101)
 *
 * The दादा/नाना (paternal/maternal) distinctions the old termHindi assertions
 * encoded are preserved via signature.side + the side-suffixed English terms.
 *
 * QA fix 2026-09-19: canonicalizePath (graph-engine.service.ts) previously
 * cancelled consecutive UP_PARENT/DOWN_CHILD primitive PAIRS without
 * checking node identity — BFS paths never revisit a node, so any
 * up-then-down pair always landed on a *different* node (a sibling,
 * uncle, cousin, nephew...), yet the pair was cancelled (uncle [UP,UP,DOWN]
 * collapsed to "Father", cousin to null, nephew to "Son"). Fixed with a
 * node-identity check (genuine backtracks only), plus resolveTerm gained
 * the DOWN_CHILD_SPOUSE and UP_PARENT_DOWN_CHILD_SPOUSE in-law patterns
 * (the old SPOUSE_DOWN_CHILD entry had the legs swapped and could never
 * match a child-in-law path; it now maps stepchildren). The collateral-kin
 * tests below are live (un-pinned) and green.
 */
import { GraphEngineService } from './graph-engine.service';
import { PrismaService } from '../../prisma/prisma.service';

// ── Mock PrismaService ──────────────────────────────────────────────────

const mockPrismaService = {
  person: {
    findMany: jest.fn(),
    findFirst: jest.fn(),
  },
  relationship: {
    findMany: jest.fn(),
  },
};

// v4.0 loads the family graph as two flat arrays (graph-engine.service.ts:495-504):
// persons (id/name/gender) and relationships (from/to/relationshipKey).
// Convention: for parent-type keys the toId is the parent (child → parent).
const P = (id: string, gender: 'male' | 'female' = 'male') => ({
  id,
  name: `Name-${id}`,
  gender,
});
const R = (from: string, to: string, relationshipKey: string) => ({
  fromPersonId: from,
  toPersonId: to,
  relationshipKey,
});

describe('GraphEngineService', () => {
  let service: GraphEngineService;

  beforeEach(async () => {
    jest.clearAllMocks();

    // Create service with mocked PrismaService — the v4.0 constructor takes
    // only prisma (no gateway/config).
    service = new GraphEngineService(mockPrismaService as any);
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });

  // ── Fundamental edges & legacy key normalization (replaces CORE_TYPES) ──

  describe('fundamental edge traversal (v4.0 CORE_TYPES replacement)', () => {
    it.each([
      // Legacy gendered keys accepted by buildAdjacency (:555-587)
      ['father', 'UP_PARENT'],
      ['mother', 'UP_PARENT'],
      ['parent', 'UP_PARENT'],
      ['son', 'DOWN_CHILD'],
      ['daughter', 'DOWN_CHILD'],
      ['child', 'DOWN_CHILD'],
      ['husband', 'SPOUSE'],
      ['wife', 'SPOUSE'],
      ['spouse', 'SPOUSE'],
    ])('should traverse a %s edge as %s', async (key, primitive) => {
      mockPrismaService.person.findMany.mockResolvedValue([P('p1'), P('p2')]);
      mockPrismaService.relationship.findMany.mockResolvedValue([R('p1', 'p2', key)]);

      const result = await service.findPath('family-1', 'p1', 'p2');

      expect(result.found).toBe(true);
      expect(result.distance).toBe(1);
      expect(result.path[0].primitive).toBe(primitive);
    });

    it('should ignore non-fundamental relationship keys (sibling/uncle/cousin are derived, never stored)', async () => {
      // v4.0 stores only parent/spouse/adoptive_parent/step_parent
      // (FUNDAMENTAL_EDGES, :123-128). A bare 'brother' edge is skipped by
      // buildAdjacency's default branch (:588-590) — no traversal.
      mockPrismaService.person.findMany.mockResolvedValue([P('p1'), P('p2')]);
      mockPrismaService.relationship.findMany.mockResolvedValue([R('p1', 'p2', 'brother')]);

      const result = await service.findPath('family-1', 'p1', 'p2');

      expect(result.found).toBe(false);
      expect(result.path).toEqual([]);
    });

    it('should traverse adoptive_parent and step_parent keys upwards', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([P('p1'), P('ap1'), P('sp1')]);
      mockPrismaService.relationship.findMany.mockResolvedValue([
        R('p1', 'ap1', 'adoptive_parent'),
        R('p1', 'sp1', 'step_father'),
      ]);

      const adoptive = await service.findPath('family-1', 'p1', 'ap1');
      expect(adoptive.found).toBe(true);
      expect(adoptive.result?.term).toBe('Adoptive Father');

      const step = await service.findPath('family-1', 'p1', 'sp1');
      expect(step.found).toBe(true);
      expect(step.result?.term).toBe('Step Father');
    });
  });

  // ── Bidirectional adjacency (replaces INVERSE_MAP) ──────────────────────

  describe('bidirectional adjacency (v4.0 INVERSE_MAP replacement)', () => {
    it('should register the inverse of a father edge as a child edge (father → son)', async () => {
      // p1 is p0's father; from p1 the inverse traversal reaches p0 downwards.
      mockPrismaService.person.findMany.mockResolvedValue([P('p0'), P('p1')]);
      mockPrismaService.relationship.findMany.mockResolvedValue([R('p0', 'p1', 'father')]);

      const result = await service.resolveKinship('family-1', 'p1', 'p0');

      expect(result?.term).toBe('Son'); // inverse of father = child, gender of p0
    });

    it('should register the inverse of a mother edge as a child edge (mother → daughter)', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([
        P('p0', 'female'),
        P('m1', 'female'),
      ]);
      mockPrismaService.relationship.findMany.mockResolvedValue([R('p0', 'm1', 'mother')]);

      const result = await service.resolveKinship('family-1', 'm1', 'p0');

      expect(result?.term).toBe('Daughter');
    });

    it('should register the inverse of a son edge as a parent edge (son → father)', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([P('p0'), P('s1')]);
      mockPrismaService.relationship.findMany.mockResolvedValue([R('p0', 's1', 'son')]);

      const result = await service.resolveKinship('family-1', 's1', 'p0');

      expect(result?.term).toBe('Father');
    });

    it('should register the inverse of a daughter edge as a parent edge (daughter → mother)', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([
        P('p0', 'female'),
        P('d1', 'female'),
      ]);
      mockPrismaService.relationship.findMany.mockResolvedValue([R('p0', 'd1', 'daughter')]);

      const result = await service.resolveKinship('family-1', 'd1', 'p0');

      expect(result?.term).toBe('Mother');
    });

    it('should treat husband ↔ wife as symmetric spouse edges', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([P('h1'), P('w1', 'female')]);
      mockPrismaService.relationship.findMany.mockResolvedValue([R('h1', 'w1', 'wife')]);

      const asHusbandView = await service.resolveKinship('family-1', 'h1', 'w1');
      expect(asHusbandView?.term).toBe('Wife');

      const asWifeView = await service.resolveKinship('family-1', 'w1', 'h1');
      expect(asWifeView?.term).toBe('Husband');
    });

    it('should register both directions of a single parent edge in one adjacency pass', async () => {
      // One relationship row must produce both the UP (child→parent) and the
      // DOWN (parent→child) adjacency entries (:593-597).
      mockPrismaService.person.findMany.mockResolvedValue([P('p0'), P('p1')]);
      mockPrismaService.relationship.findMany.mockResolvedValue([R('p0', 'p1', 'parent')]);

      const up = await service.findPath('family-1', 'p0', 'p1');
      expect(up.path[0].primitive).toBe('UP_PARENT');

      const down = await service.findPath('family-1', 'p1', 'p0');
      expect(down.path[0].primitive).toBe('DOWN_CHILD');
    });
  });

  // ── Graph loading & adjacency cache (replaces buildGraph) ───────────────

  describe('graph loading & adjacency cache (v4.0 buildGraph replacement)', () => {
    const familyId = 'family-1';

    it('should load only non-deleted persons and active relationships', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([P('p1'), P('p2')]);
      mockPrismaService.relationship.findMany.mockResolvedValue([R('p1', 'p2', 'father')]);

      await service.findPath(familyId, 'p1', 'p2');

      // Inactive relationships / soft-deleted persons are excluded at the
      // query level (loadFamilyGraph, :496-503).
      expect(mockPrismaService.person.findMany).toHaveBeenCalledWith(
        expect.objectContaining({ where: { familyId, deletedAt: null } }),
      );
      expect(mockPrismaService.relationship.findMany).toHaveBeenCalledWith(
        expect.objectContaining({ where: { familyId, isActive: true } }),
      );
    });

    it('should skip self-loop relationships without creating phantom kinship', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([P('p1'), P('p2')]);
      mockPrismaService.relationship.findMany.mockResolvedValue([
        R('p1', 'p1', 'father'), // self-referencing relationship
      ]);

      // Must terminate (no infinite loop) and find no path p1 → p2.
      const result = await service.findPath(familyId, 'p1', 'p2');
      expect(result.found).toBe(false);

      const kinship = await service.resolveKinship(familyId, 'p1', 'p2');
      expect(kinship).toBeNull();
    });

    it('should cache the built adjacency for 60s (single load per family)', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([P('p1'), P('p2')]);
      mockPrismaService.relationship.findMany.mockResolvedValue([R('p1', 'p2', 'father')]);

      // First call builds and caches the graph (ADJACENCY_CACHE_TTL_MS = 60s)
      await service.findPath(familyId, 'p1', 'p2');
      expect(mockPrismaService.person.findMany).toHaveBeenCalledTimes(1);

      // Second call uses the cache
      await service.findPath(familyId, 'p1', 'p2');
      expect(mockPrismaService.person.findMany).toHaveBeenCalledTimes(1); // still 1
    });

    it('should re-load the graph after invalidateCache() (v4.1 force refresh)', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([P('p1'), P('p2')]);
      mockPrismaService.relationship.findMany.mockResolvedValue([R('p1', 'p2', 'father')]);

      await service.findPath(familyId, 'p1', 'p2');
      await service.findPath(familyId, 'p1', 'p2');
      expect(mockPrismaService.person.findMany).toHaveBeenCalledTimes(1);

      // v4.1: invalidateCache() is the refresh mechanism (used by
      // RelationshipsService on every mutation — graph.service.ts:730)
      service.invalidateCache(familyId);
      await service.findPath(familyId, 'p1', 'p2');
      expect(mockPrismaService.person.findMany).toHaveBeenCalledTimes(2);
    });
  });

  // ── findPath ───────────────────────────────────────────────────────────

  describe('findPath', () => {
    const familyId = 'family-1';

    it('should find shortest path between two persons', async () => {
      // Setup: p1 (self) → p2 (father) → p3 (grandfather)
      mockPrismaService.person.findMany.mockResolvedValue([
        { id: 'p1', name: 'Rahul', gender: 'male' },
        { id: 'p2', name: 'Suresh', gender: 'male' },
        { id: 'p3', name: 'Ramesh', gender: 'male' },
      ]);
      mockPrismaService.relationship.findMany.mockResolvedValue([
        R('p1', 'p2', 'father'),
        R('p2', 'p3', 'father'),
      ]);

      const result = await service.findPath(familyId, 'p1', 'p3');

      expect(result.found).toBe(true);
      expect(result.distance).toBe(2);
      expect(result.path).toHaveLength(2);
      expect(result.path[0]).toMatchObject({
        personId: 'p2',
        personName: 'Suresh',
        primitive: 'UP_PARENT',
      });
      expect(result.path[1]).toMatchObject({ personId: 'p3', personName: 'Ramesh' });

      // v4.0: the resolved KinshipResult rides on PathResult.result; the
      // Hindi term (दादा) is served by the vocabulary layer. The paternal/
      // maternal distinction is carried by the side-suffixed term + signature.
      expect(result.result?.term).toBe('Grandfather (Paternal)'); // दादा
      expect(result.signature?.side).toBe('paternal');
    });

    it('should return not-found for the same person (v4.0: self is not a path)', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([
        { id: 'p1', name: 'Rahul', gender: 'male' },
      ]);
      mockPrismaService.relationship.findMany.mockResolvedValue([]);

      const result = await service.findPath(familyId, 'p1', 'p1');

      // v4.0 changed self from a "found" path with term 'self' to an early
      // not-found return (graph-engine.service.ts:227-229); resolveKinship
      // returns null for self (:195).
      expect(result.found).toBe(false);
      expect(result.distance).toBe(0);
      expect(result.path).toEqual([]);
      await expect(service.resolveKinship(familyId, 'p1', 'p1')).resolves.toBeNull();
    });

    it('should return not found when no path exists', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([
        { id: 'p1', name: 'Rahul', gender: 'male' },
        { id: 'p2', name: 'Unrelated', gender: 'male' },
      ]);
      mockPrismaService.relationship.findMany.mockResolvedValue([]);

      const result = await service.findPath(familyId, 'p1', 'p2');

      // v4.0 reports distance 0 (was -1 in v3) for not-found (:235-237)
      expect(result.found).toBe(false);
      expect(result.distance).toBe(0);
      expect(result.path).toEqual([]);
    });

    it('should return not found (not throw) for unknown fromPersonId', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([
        { id: 'p1', name: 'Rahul', gender: 'male' },
      ]);
      mockPrismaService.relationship.findMany.mockResolvedValue([]);

      // v4.0 removed the person-existence check / NotFoundException — unknown
      // persons simply have no path. The kinship controller maps the null
      // result to { found: false } (kinship.controller.ts:85-87).
      const result = await service.findPath(familyId, 'unknown', 'p1');

      expect(result.found).toBe(false);
      expect(result.distance).toBe(0);
    });
  });

  // ── resolveKinship — direct-line terms (working v4.0 surface) ───────────

  describe('resolveKinship — direct-line terms', () => {
    const familyId = 'family-1';

    it('should resolve father (पिता)', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([P('p0'), P('p1')]);
      mockPrismaService.relationship.findMany.mockResolvedValue([R('p0', 'p1', 'father')]);

      const result = await service.resolveKinship(familyId, 'p0', 'p1');

      expect(result?.term).toBe('Father');
      expect(result?.fundamentalEdge).toBe('parent');
      expect(result?.isDerived).toBe(false);
      expect(result?.signature.resolutionStatus).toBe('confirmed');
    });

    it('should resolve mother (माता)', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([P('p0'), P('m1', 'female')]);
      mockPrismaService.relationship.findMany.mockResolvedValue([R('p0', 'm1', 'mother')]);

      const result = await service.resolveKinship(familyId, 'p0', 'm1');

      expect(result?.term).toBe('Mother');
      expect(result?.signature.side).toBe('maternal');
    });

    it('should resolve son (बेटा) and daughter (बेटी) by target gender', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([P('p0'), P('s1'), P('d1', 'female')]);
      mockPrismaService.relationship.findMany.mockResolvedValue([
        R('p0', 's1', 'son'),
        R('p0', 'd1', 'daughter'),
      ]);

      const son = await service.resolveKinship(familyId, 'p0', 's1');
      expect(son?.term).toBe('Son');

      const daughter = await service.resolveKinship(familyId, 'p0', 'd1');
      expect(daughter?.term).toBe('Daughter');
    });

    it('should resolve wife (पत्नी) and husband (पति)', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([P('h1'), P('w1', 'female')]);
      mockPrismaService.relationship.findMany.mockResolvedValue([R('h1', 'w1', 'spouse')]);

      const wife = await service.resolveKinship(familyId, 'h1', 'w1');
      expect(wife?.term).toBe('Wife');
      expect(wife?.fundamentalEdge).toBe('spouse');
      expect(wife?.signature.consanguinity).toBe('affine');

      const husband = await service.resolveKinship(familyId, 'w1', 'h1');
      expect(husband?.term).toBe('Husband');
    });

    it('should resolve father→father = grandfather (दादा — paternal)', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([P('p0'), P('p1'), P('g1')]);
      mockPrismaService.relationship.findMany.mockResolvedValue([
        R('p0', 'p1', 'father'),
        R('p1', 'g1', 'father'),
      ]);

      const result = await service.resolveKinship(familyId, 'p0', 'g1');

      expect(result?.term).toBe('Grandfather (Paternal)');
      expect(result?.signature.side).toBe('paternal');
      expect(result?.isDerived).toBe(true);
    });

    it('should resolve father→mother = grandmother (दादी — paternal)', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([
        P('p0'),
        P('p1'),
        P('gm1', 'female'),
      ]);
      mockPrismaService.relationship.findMany.mockResolvedValue([
        R('p0', 'p1', 'father'),
        R('p1', 'gm1', 'mother'),
      ]);

      const result = await service.resolveKinship(familyId, 'p0', 'gm1');

      expect(result?.term).toBe('Grandmother (Paternal)');
      expect(result?.signature.side).toBe('paternal');
    });

    it('should resolve mother→father = grandfather (नाना — maternal)', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([
        P('p0'),
        P('m1', 'female'),
        P('f1'),
      ]);
      mockPrismaService.relationship.findMany.mockResolvedValue([
        R('p0', 'm1', 'mother'),
        R('m1', 'f1', 'father'),
      ]);

      const result = await service.resolveKinship(familyId, 'p0', 'f1');

      expect(result?.term).toBe('Grandfather (Maternal)');
      expect(result?.signature.side).toBe('maternal');
    });

    it('should resolve mother→mother = grandmother (नानी — maternal)', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([
        P('p0'),
        P('m1', 'female'),
        P('gm1', 'female'),
      ]);
      mockPrismaService.relationship.findMany.mockResolvedValue([
        R('p0', 'm1', 'mother'),
        R('m1', 'gm1', 'mother'),
      ]);

      const result = await service.resolveKinship(familyId, 'p0', 'gm1');

      expect(result?.term).toBe('Grandmother (Maternal)');
      expect(result?.signature.side).toBe('maternal');
    });

    it('should resolve father→father→father = great grandfather (परदादा)', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([P('p0'), P('p1'), P('g1'), P('gg1')]);
      mockPrismaService.relationship.findMany.mockResolvedValue([
        R('p0', 'p1', 'father'),
        R('p1', 'g1', 'father'),
        R('g1', 'gg1', 'father'),
      ]);

      const result = await service.resolveKinship(familyId, 'p0', 'gg1');

      expect(result?.term).toBe('Great Grandfather');
      expect(result?.signature.generationDelta).toBe(-3);
    });

    it('should resolve husband→father = father-in-law (ससुर)', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([
        P('p0'),
        P('w1', 'female'),
        P('f1'),
      ]);
      mockPrismaService.relationship.findMany.mockResolvedValue([
        R('p0', 'w1', 'spouse'),
        R('w1', 'f1', 'father'),
      ]);

      const result = await service.resolveKinship(familyId, 'p0', 'f1');

      expect(result?.term).toBe('Father-in-Law');
      expect(result?.signature.consanguinity).toBe('inLaw');
    });

    it('should return null for self (v4.0 removed the "self" term)', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([P('p0')]);
      mockPrismaService.relationship.findMany.mockResolvedValue([]);

      await expect(service.resolveKinship(familyId, 'p0', 'p0')).resolves.toBeNull();
    });

    it('should compose a descriptive term for unknown deep paths', async () => {
      // 5×father chain — beyond the enumerated term table, so the fallback
      // composer runs (resolveTerm :1200-1214).
      const persons = [P('p0'), P('a'), P('b'), P('c'), P('d'), P('e')];
      mockPrismaService.person.findMany.mockResolvedValue(persons);
      mockPrismaService.relationship.findMany.mockResolvedValue([
        R('p0', 'a', 'father'),
        R('a', 'b', 'father'),
        R('b', 'c', 'father'),
        R('c', 'd', 'father'),
        R('d', 'e', 'father'),
      ]);

      const result = await service.resolveKinship(familyId, 'p0', 'e');
      expect(result).toBeDefined();
      expect(result?.term).toBe('Great Father');
      expect(result?.isDerived).toBe(true);
      expect(result?.signature.resolutionStatus).toBe('derived');
      expect(result?.signature.generationDelta).toBe(-5);

      // The full 5-step path is reported by findPath (KinshipResult.path is
      // always [] by design — buildResult :1063).
      const path = await service.findPath(familyId, 'p0', 'e');
      expect(path.distance).toBe(5);
      expect(path.path).toHaveLength(5);
    });
  });

  // ── resolveKinship — collateral kin ───────────────────────────────
  //
  // Fixtures model collateral kin the v4.0 way — through shared parents,
  // since sibling/aunt/uncle edges are no longer stored as fundamental
  // relationships. Expected terms per the service's resolveTerm mapper:
  //   sibling   UP_PARENT_DOWN_CHILD                       → Brother/Sister
  //   uncle     UP_PARENT_UP_PARENT_DOWN_CHILD             → Uncle (side)
  //   nephew    UP_PARENT_DOWN_CHILD_DOWN_CHILD            → Nephew/Niece
  //   cousin    UP_PARENT_UP_PARENT_DOWN_CHILD_DOWN_CHILD  → Cousin
  //   in-laws   SPOUSE_UP_PARENT_DOWN_CHILD                → Brother-in-Law
  //   in-laws   child's spouse (DOWN_CHILD+SPOUSE)         → Daughter-in-Law
  //   in-laws   sibling's spouse (UP+DOWN+SPOUSE)          → Brother-in-Law
  //
  // QA fix 2026-09-19: these were pinned it.failing while canonicalizePath
  // over-collapsed collateral paths; the engine fix (node-identity-aware
  // cancellation + corrected in-law patterns) makes them live and green.

  describe('resolveKinship — collateral kin terms', () => {
    const familyId = 'family-1';

    it('should resolve father→brother = uncle (चाचा — paternal)', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([P('p0'), P('p1'), P('g1'), P('u1')]);
      mockPrismaService.relationship.findMany.mockResolvedValue([
        R('p0', 'p1', 'father'),
        R('p1', 'g1', 'father'),
        R('u1', 'g1', 'father'), // uncle is also a child of the grandfather
      ]);

      const result = await service.resolveKinship(familyId, 'p0', 'u1');

      expect(result?.term).toBe('Uncle (Paternal)');
      expect(result?.signature.side).toBe('paternal');
    });

    it('should resolve mother→brother = uncle (मामा — maternal)', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([
        P('p0'),
        P('m1', 'female'),
        P('gm1', 'female'),
        P('u1'),
      ]);
      mockPrismaService.relationship.findMany.mockResolvedValue([
        R('p0', 'm1', 'mother'),
        R('m1', 'gm1', 'mother'),
        R('u1', 'gm1', 'mother'),
      ]);

      const result = await service.resolveKinship(familyId, 'p0', 'u1');

      expect(result?.term).toBe('Uncle (Maternal)');
      expect(result?.signature.side).toBe('maternal');
    });

    it('should resolve father→sister = aunt (बुआ — paternal)', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([
        P('p0'),
        P('p1'),
        P('g1'),
        P('a1', 'female'),
      ]);
      mockPrismaService.relationship.findMany.mockResolvedValue([
        R('p0', 'p1', 'father'),
        R('p1', 'g1', 'father'),
        R('a1', 'g1', 'father'),
      ]);

      const result = await service.resolveKinship(familyId, 'p0', 'a1');

      expect(result?.term).toBe('Aunt (Paternal)');
      expect(result?.signature.side).toBe('paternal');
    });

    it('should resolve mother→sister = aunt (मौसी — maternal)', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([
        P('p0'),
        P('m1', 'female'),
        P('gm1', 'female'),
        P('a1', 'female'),
      ]);
      mockPrismaService.relationship.findMany.mockResolvedValue([
        R('p0', 'm1', 'mother'),
        R('m1', 'gm1', 'mother'),
        R('a1', 'gm1', 'mother'),
      ]);

      const result = await service.resolveKinship(familyId, 'p0', 'a1');

      expect(result?.term).toBe('Aunt (Maternal)');
      expect(result?.signature.side).toBe('maternal');
    });

    it('should resolve father→brother→son = cousin (चचेरा भाई — paternal)', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([
        P('p0'),
        P('p1'),
        P('g1'),
        P('u1'),
        P('c1'),
      ]);
      mockPrismaService.relationship.findMany.mockResolvedValue([
        R('p0', 'p1', 'father'),
        R('p1', 'g1', 'father'),
        R('u1', 'g1', 'father'),
        R('c1', 'u1', 'father'),
      ]);

      const result = await service.resolveKinship(familyId, 'p0', 'c1');

      // v4.0 cousin term is gender-neutral (resolveTerm :1145-1148); the
      // चचेरा भाई / चचेरी बहन distinction lives in the vocabulary layer.
      expect(result?.term).toBe('Cousin');
      expect(result?.signature.side).toBe('paternal');
    });

    it('should resolve mother→brother→son = cousin (ममेरा भाई — maternal)', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([
        P('p0'),
        P('m1', 'female'),
        P('gm1', 'female'),
        P('u1'),
        P('c1'),
      ]);
      mockPrismaService.relationship.findMany.mockResolvedValue([
        R('p0', 'm1', 'mother'),
        R('m1', 'gm1', 'mother'),
        R('u1', 'gm1', 'mother'),
        R('c1', 'u1', 'father'),
      ]);

      const result = await service.resolveKinship(familyId, 'p0', 'c1');

      expect(result?.term).toBe('Cousin');
      expect(result?.signature.side).toBe('maternal');
    });

    it('should resolve father→brother→daughter = cousin (चचेरी बहन — female target)', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([
        P('p0'),
        P('p1'),
        P('g1'),
        P('u1'),
        P('c1', 'female'),
      ]);
      mockPrismaService.relationship.findMany.mockResolvedValue([
        R('p0', 'p1', 'father'),
        R('p1', 'g1', 'father'),
        R('u1', 'g1', 'father'),
        R('c1', 'u1', 'father'),
      ]);

      const result = await service.resolveKinship(familyId, 'p0', 'c1');

      expect(result?.term).toBe('Cousin');
    });

    it('should resolve brother→son = nephew (भतीजा)', async () => {
      // Brother modeled through both shared parents (v4.0 has no sibling edge)
      mockPrismaService.person.findMany.mockResolvedValue([
        P('p0'),
        P('g1'),
        P('gm1', 'female'),
        P('b1'),
        P('n1'),
      ]);
      mockPrismaService.relationship.findMany.mockResolvedValue([
        R('p0', 'g1', 'father'),
        R('p0', 'gm1', 'mother'),
        R('b1', 'g1', 'father'),
        R('b1', 'gm1', 'mother'),
        R('n1', 'b1', 'father'),
      ]);

      const result = await service.resolveKinship(familyId, 'p0', 'n1');

      expect(result?.term).toBe('Nephew');
    });

    it('should resolve brother→daughter = niece (भतीजी)', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([
        P('p0'),
        P('g1'),
        P('gm1', 'female'),
        P('b1'),
        P('n1', 'female'),
      ]);
      mockPrismaService.relationship.findMany.mockResolvedValue([
        R('p0', 'g1', 'father'),
        R('p0', 'gm1', 'mother'),
        R('b1', 'g1', 'father'),
        R('b1', 'gm1', 'mother'),
        R('n1', 'b1', 'father'),
      ]);

      const result = await service.resolveKinship(familyId, 'p0', 'n1');

      expect(result?.term).toBe('Niece');
    });

    it('should resolve sister→son = nephew (भांजा)', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([
        P('p0'),
        P('g1'),
        P('gm1', 'female'),
        P('s1', 'female'),
        P('n1'),
      ]);
      mockPrismaService.relationship.findMany.mockResolvedValue([
        R('p0', 'g1', 'father'),
        R('p0', 'gm1', 'mother'),
        R('s1', 'g1', 'father'),
        R('s1', 'gm1', 'mother'),
        R('n1', 's1', 'mother'),
      ]);

      const result = await service.resolveKinship(familyId, 'p0', 'n1');

      expect(result?.term).toBe('Nephew');
    });

    it('should resolve sister→daughter = niece (भांजी)', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([
        P('p0'),
        P('g1'),
        P('gm1', 'female'),
        P('s1', 'female'),
        P('n1', 'female'),
      ]);
      mockPrismaService.relationship.findMany.mockResolvedValue([
        R('p0', 'g1', 'father'),
        R('p0', 'gm1', 'mother'),
        R('s1', 'g1', 'father'),
        R('s1', 'gm1', 'mother'),
        R('n1', 's1', 'mother'),
      ]);

      const result = await service.resolveKinship(familyId, 'p0', 'n1');

      expect(result?.term).toBe('Niece');
    });

    it('should resolve a sibling through shared parents (भाई)', async () => {
      // Both parents shared → consanguinity 'blood' → Brother (not Half Brother)
      mockPrismaService.person.findMany.mockResolvedValue([
        P('p0'),
        P('g1'),
        P('gm1', 'female'),
        P('b1'),
      ]);
      mockPrismaService.relationship.findMany.mockResolvedValue([
        R('p0', 'g1', 'father'),
        R('p0', 'gm1', 'mother'),
        R('b1', 'g1', 'father'),
        R('b1', 'gm1', 'mother'),
      ]);

      const result = await service.resolveKinship(familyId, 'p0', 'b1');

      expect(result?.term).toBe('Brother');
      expect(result?.signature.consanguinity).toBe('blood');
    });

    it('should resolve sister→husband = brother-in-law (जीजा)', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([
        P('p0'),
        P('g1'),
        P('gm1', 'female'),
        P('s1', 'female'),
        P('h1'),
      ]);
      mockPrismaService.relationship.findMany.mockResolvedValue([
        R('p0', 'g1', 'father'),
        R('p0', 'gm1', 'mother'),
        R('s1', 'g1', 'father'),
        R('s1', 'gm1', 'mother'),
        R('s1', 'h1', 'spouse'),
      ]);

      const result = await service.resolveKinship(familyId, 'p0', 'h1');

      expect(result?.term).toBe('Brother-in-Law');
    });

    it('should resolve son→wife = daughter-in-law (बहू)', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([
        P('p0'),
        P('s1'),
        P('d1', 'female'),
      ]);
      mockPrismaService.relationship.findMany.mockResolvedValue([
        R('p0', 's1', 'son'),
        R('s1', 'd1', 'spouse'),
      ]);

      const result = await service.resolveKinship(familyId, 'p0', 'd1');

      expect(result?.term).toBe('Daughter-in-Law');
    });
  });

  // ── v4.0 extras: spouse inference & ancestor/descendant walks ───────────

  describe('suggestSpouseIfSharedChildren (v4.0 spouse inference)', () => {
    it('should suggest a spouse when two persons share a child', async () => {
      // Canonical 'parent' keys (v4.0 storage; the normalizer maps legacy
      // father/mother to 'parent' on write).
      mockPrismaService.person.findMany.mockResolvedValue([
        P('a'),
        P('b', 'female'),
        P('c'),
      ]);
      mockPrismaService.relationship.findMany.mockResolvedValue([
        R('c', 'a', 'parent'),
        R('c', 'b', 'parent'),
      ]);

      const suggestion = await service.suggestSpouseIfSharedChildren('family-1', 'a', 'b');

      expect(suggestion).not.toBeNull();
      expect(suggestion?.isSuggested).toBe(true);
      expect(suggestion?.term).toBe('Wife');
      expect(suggestion?.fundamentalEdge).toBe('spouse');
      expect(suggestion?.signature.resolutionStatus).toBe('inferred');
    });

    it('should not suggest when the persons are already spouses', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([
        P('a'),
        P('b', 'female'),
        P('c'),
      ]);
      mockPrismaService.relationship.findMany.mockResolvedValue([
        R('c', 'a', 'parent'),
        R('c', 'b', 'parent'),
        R('a', 'b', 'spouse'),
      ]);

      await expect(
        service.suggestSpouseIfSharedChildren('family-1', 'a', 'b'),
      ).resolves.toBeNull();
    });

    it('should not suggest when there is no shared child', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([P('a'), P('b', 'female')]);
      mockPrismaService.relationship.findMany.mockResolvedValue([]);

      await expect(
        service.suggestSpouseIfSharedChildren('family-1', 'a', 'b'),
      ).resolves.toBeNull();
    });
  });

  describe('getAncestors / getDescendants', () => {
    it('should walk ancestors upwards and descendants downwards', async () => {
      // p0 → p1 → g1 (upwards); s1 → gs1 downwards from p0
      mockPrismaService.person.findMany.mockResolvedValue([
        P('p0'),
        P('p1'),
        P('g1'),
        P('s1'),
        P('gs1', 'female'),
      ]);
      mockPrismaService.relationship.findMany.mockResolvedValue([
        R('p0', 'p1', 'father'),
        R('p1', 'g1', 'father'),
        R('s1', 'p0', 'father'),
        R('gs1', 's1', 'father'),
      ]);

      const ancestors = await service.getAncestors('family-1', 'p0');
      expect(ancestors.map((a) => a.id)).toEqual(['p1', 'g1']);

      const descendants = await service.getDescendants('family-1', 'p0');
      expect(descendants.map((d) => d.id)).toEqual(['s1', 'gs1']);
    });
  });
});
