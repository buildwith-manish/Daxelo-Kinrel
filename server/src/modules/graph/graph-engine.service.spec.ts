import { GraphEngineService } from './graph-engine.service';
import { PrismaService } from '../../prisma/prisma.service';
import { NotFoundException } from '@nestjs/common';
import { RelationshipStep } from './graph-engine.service';

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

describe('GraphEngineService', () => {
  let service: GraphEngineService;

  // Helper to create a step (shared across describe blocks)
  const makeStep = (
    relType: string,
    direction: 'up' | 'down' | 'sideways' = 'up',
  ): RelationshipStep => ({
    personId: `person-${relType}`,
    personName: `Name-${relType}`,
    relationshipType: relType,
    direction,
  });

  beforeEach(async () => {
    jest.clearAllMocks();

    // Create service with mocked PrismaService
    service = new GraphEngineService(mockPrismaService as any);
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });

  // ── Static Properties ──────────────────────────────────────────────

  describe('CORE_TYPES', () => {
    it('should define exactly 8 core relationship types', () => {
      expect(GraphEngineService.CORE_TYPES).toHaveLength(8);
      expect(GraphEngineService.CORE_TYPES).toEqual(
        expect.arrayContaining([
          'father', 'mother', 'son', 'daughter',
          'brother', 'sister', 'husband', 'wife',
        ]),
      );
    });
  });

  describe('INVERSE_MAP', () => {
    it('should map father → child', () => {
      expect(GraphEngineService.INVERSE_MAP.father).toBe('child');
    });
    it('should map mother → child', () => {
      expect(GraphEngineService.INVERSE_MAP.mother).toBe('child');
    });
    it('should map son → parent', () => {
      expect(GraphEngineService.INVERSE_MAP.son).toBe('parent');
    });
    it('should map daughter → parent', () => {
      expect(GraphEngineService.INVERSE_MAP.daughter).toBe('parent');
    });
    it('should map brother → sibling', () => {
      expect(GraphEngineService.INVERSE_MAP.brother).toBe('sibling');
    });
    it('should map sister → sibling', () => {
      expect(GraphEngineService.INVERSE_MAP.sister).toBe('sibling');
    });
    it('should map husband → wife', () => {
      expect(GraphEngineService.INVERSE_MAP.husband).toBe('wife');
    });
    it('should map wife → husband', () => {
      expect(GraphEngineService.INVERSE_MAP.wife).toBe('husband');
    });
  });

  // ── buildGraph ─────────────────────────────────────────────────────

  describe('buildGraph', () => {
    const familyId = 'family-1';

    it('should build adjacency list from relationships', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([
        { id: 'p1', name: 'Rahul', gender: 'male' },
        { id: 'p2', name: 'Suresh', gender: 'male' },
        { id: 'p3', name: 'Anita', gender: 'female' },
      ]);

      mockPrismaService.relationship.findMany.mockResolvedValue([
        { fromPersonId: 'p1', toPersonId: 'p2', relationshipKey: 'father' },
        { fromPersonId: 'p1', toPersonId: 'p3', relationshipKey: 'mother' },
      ]);

      const adjacency = await service.buildGraph(familyId);

      // Forward edge: p1 --[father]--> p2
      const p1Neighbors = adjacency.get('p1');
      expect(p1Neighbors).toBeDefined();
      expect(p1Neighbors!.length).toBeGreaterThanOrEqual(2);

      const fatherEdge = p1Neighbors!.find((e) => e.neighborId === 'p2');
      expect(fatherEdge).toBeDefined();
      expect(fatherEdge!.relationshipKey).toBe('father');
      expect(fatherEdge!.direction).toBe('up');

      // Inverse edge: p2 --[son/daughter]--> p1
      // Since p1 (Rahul) has gender 'male', the inverse of 'father' (from p1) is 'son' (to p1)
      const p2Neighbors = adjacency.get('p2');
      expect(p2Neighbors).toBeDefined();
      const childEdge = p2Neighbors!.find((e) => e.neighborId === 'p1');
      expect(childEdge).toBeDefined();
      // 'child' gets gender-normalized based on the source person's gender
      expect(['child', 'son']).toContain(childEdge!.relationshipKey);
    });

    it('should skip inactive persons from relationships', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([
        { id: 'p1', name: 'Rahul', gender: 'male' },
      ]);

      mockPrismaService.relationship.findMany.mockResolvedValue([]);

      const adjacency = await service.buildGraph(familyId);

      expect(adjacency.size).toBe(0); // No relationships, so no edges
    });

    it('should skip self-loops', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([
        { id: 'p1', name: 'Rahul', gender: 'male' },
      ]);

      // Self-referencing relationship
      mockPrismaService.relationship.findMany.mockResolvedValue([
        { fromPersonId: 'p1', toPersonId: 'p1', relationshipKey: 'father' },
      ]);

      const adjacency = await service.buildGraph(familyId);

      const p1Neighbors = adjacency.get('p1');
      expect(p1Neighbors).toBeUndefined(); // Self-loop should be skipped
    });

    it('should cache the built graph', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([
        { id: 'p1', name: 'Rahul', gender: 'male' },
      ]);
      mockPrismaService.relationship.findMany.mockResolvedValue([]);

      // First call builds the graph
      await service.buildGraph(familyId);
      expect(mockPrismaService.person.findMany).toHaveBeenCalledTimes(1);

      // Second call should use cache
      await service.buildGraph(familyId);
      expect(mockPrismaService.person.findMany).toHaveBeenCalledTimes(1); // Still 1
    });

    it('should force refresh when option is set', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([
        { id: 'p1', name: 'Rahul', gender: 'male' },
      ]);
      mockPrismaService.relationship.findMany.mockResolvedValue([]);

      await service.buildGraph(familyId);
      expect(mockPrismaService.person.findMany).toHaveBeenCalledTimes(1);

      await service.buildGraph(familyId, { forceRefresh: true });
      expect(mockPrismaService.person.findMany).toHaveBeenCalledTimes(2);
    });
  });

  // ── findPath ───────────────────────────────────────────────────────

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
        { fromPersonId: 'p1', toPersonId: 'p2', relationshipKey: 'father' },
        { fromPersonId: 'p2', toPersonId: 'p3', relationshipKey: 'father' },
      ]);

      const result = await service.findPath(familyId, 'p1', 'p3');

      expect(result.found).toBe(true);
      expect(result.distance).toBe(2);
      expect(result.kinshipTerm).toBe('grandfather');
      expect(result.kinshipTermHindi).toBe('दादा');
    });

    it('should return self for same person', async () => {
      mockPrismaService.person.findFirst.mockResolvedValue({
        id: 'p1', name: 'Rahul', gender: 'male',
      });
      mockPrismaService.person.findMany.mockResolvedValue([
        { id: 'p1', name: 'Rahul', gender: 'male' },
      ]);
      mockPrismaService.relationship.findMany.mockResolvedValue([]);

      const result = await service.findPath(familyId, 'p1', 'p1');

      expect(result.found).toBe(true);
      expect(result.distance).toBe(0);
      expect(result.kinshipTerm).toBe('self');
    });

    it('should return not found when no path exists', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([
        { id: 'p1', name: 'Rahul', gender: 'male' },
        { id: 'p2', name: 'Unrelated', gender: 'male' },
      ]);
      mockPrismaService.relationship.findMany.mockResolvedValue([]);

      const result = await service.findPath(familyId, 'p1', 'p2');

      expect(result.found).toBe(false);
      expect(result.distance).toBe(-1);
    });

    it('should throw NotFoundException for unknown fromPersonId', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([
        { id: 'p1', name: 'Rahul', gender: 'male' },
      ]);
      mockPrismaService.relationship.findMany.mockResolvedValue([]);

      await expect(
        service.findPath(familyId, 'unknown', 'p1'),
      ).rejects.toThrow(NotFoundException);
    });
  });

  // ── resolveKinship ─────────────────────────────────────────────────

  describe('resolveKinship', () => {
    it('should resolve father→father = grandfather (दादा)', () => {
      const result = service.resolveKinship([
        makeStep('father', 'up'),
        makeStep('father', 'up'),
      ]);

      expect(result.term).toBe('grandfather');
      expect(result.termHindi).toBe('दादा');
      expect(result.confidence).toBe(1.0);
    });

    it('should resolve father→brother = uncle (चाचा)', () => {
      const result = service.resolveKinship([
        makeStep('father', 'up'),
        makeStep('brother', 'sideways'),
      ]);

      expect(result.term).toBe('uncle');
      expect(result.termHindi).toBe('चाचा');
      expect(result.confidence).toBe(1.0);
    });

    it('should resolve mother→brother→son = cousin (ममेरा भाई)', () => {
      const result = service.resolveKinship([
        makeStep('mother', 'up'),
        makeStep('brother', 'sideways'),
        makeStep('son', 'down'),
      ]);

      expect(result.term).toBe('cousin');
      expect(result.termHindi).toBe('ममेरा भाई');
      expect(result.confidence).toBe(1.0);
    });

    it('should resolve brother→son = nephew (भतीजा)', () => {
      const result = service.resolveKinship([
        makeStep('brother', 'sideways'),
        makeStep('son', 'down'),
      ]);

      expect(result.term).toBe('nephew');
      expect(result.termHindi).toBe('भतीजा');
      expect(result.confidence).toBe(1.0);
    });

    it('should resolve sister→daughter = niece (भांजी)', () => {
      const result = service.resolveKinship([
        makeStep('sister', 'sideways'),
        makeStep('daughter', 'down'),
      ]);

      expect(result.term).toBe('niece');
      expect(result.termHindi).toBe('भांजी');
      expect(result.confidence).toBe(1.0);
    });

    // Additional kinship resolutions

    it('should resolve father→mother = grandmother (दादी)', () => {
      const result = service.resolveKinship([
        makeStep('father', 'up'),
        makeStep('mother', 'up'),
      ]);

      expect(result.term).toBe('grandmother');
      expect(result.termHindi).toBe('दादी');
    });

    it('should resolve mother→father = grandfather (नाना)', () => {
      const result = service.resolveKinship([
        makeStep('mother', 'up'),
        makeStep('father', 'up'),
      ]);

      expect(result.term).toBe('grandfather');
      expect(result.termHindi).toBe('नाना');
    });

    it('should resolve mother→mother = grandmother (नानी)', () => {
      const result = service.resolveKinship([
        makeStep('mother', 'up'),
        makeStep('mother', 'up'),
      ]);

      expect(result.term).toBe('grandmother');
      expect(result.termHindi).toBe('नानी');
    });

    it('should resolve mother→sister = aunt (मौसी)', () => {
      const result = service.resolveKinship([
        makeStep('mother', 'up'),
        makeStep('sister', 'sideways'),
      ]);

      expect(result.term).toBe('aunt');
      expect(result.termHindi).toBe('मौसी');
    });

    it('should resolve father→sister = aunt (बुआ)', () => {
      const result = service.resolveKinship([
        makeStep('father', 'up'),
        makeStep('sister', 'sideways'),
      ]);

      expect(result.term).toBe('aunt');
      expect(result.termHindi).toBe('बुआ');
    });

    it('should resolve husband→father = father_in_law (ससुर)', () => {
      const result = service.resolveKinship([
        makeStep('husband', 'sideways'),
        makeStep('father', 'up'),
      ]);

      expect(result.term).toBe('father_in_law');
      expect(result.termHindi).toBe('ससुर');
    });

    it('should resolve brother→daughter = niece (भतीजी)', () => {
      const result = service.resolveKinship([
        makeStep('brother', 'sideways'),
        makeStep('daughter', 'down'),
      ]);

      expect(result.term).toBe('niece');
      expect(result.termHindi).toBe('भतीजी');
    });

    it('should resolve sister→son = nephew (भांजा)', () => {
      const result = service.resolveKinship([
        makeStep('sister', 'sideways'),
        makeStep('son', 'down'),
      ]);

      expect(result.term).toBe('nephew');
      expect(result.termHindi).toBe('भांजा');
    });

    it('should resolve father→brother→son = cousin (चचेरा भाई)', () => {
      const result = service.resolveKinship([
        makeStep('father', 'up'),
        makeStep('brother', 'sideways'),
        makeStep('son', 'down'),
      ]);

      expect(result.term).toBe('cousin');
      expect(result.termHindi).toBe('चचेरा भाई');
    });

    it('should return self for empty path', () => {
      const result = service.resolveKinship([]);

      expect(result.term).toBe('self');
      expect(result.termHindi).toBe('स्वयं');
      expect(result.confidence).toBe(1.0);
    });

    it('should handle gender-specific resolution with targetGender', () => {
      // father→brother→daughter = cousin (चचेरी बहन) - neutral by default
      const result = service.resolveKinship(
        [
          makeStep('father', 'up'),
          makeStep('brother', 'sideways'),
          makeStep('daughter', 'down'),
        ],
        'female',
      );

      expect(result.term).toBe('cousin');
      expect(result.termHindi).toBe('चचेरी बहन');
    });

    // Extended kinship - great grandparents

    it('should resolve father→father→father = great_grandfather (परदादा)', () => {
      const result = service.resolveKinship([
        makeStep('father', 'up'),
        makeStep('father', 'up'),
        makeStep('father', 'up'),
      ]);

      expect(result.term).toBe('great_grandfather');
      expect(result.termHindi).toBe('परदादा');
    });

    // In-law paths

    it('should resolve sister→husband = brother_in_law (जीजा)', () => {
      const result = service.resolveKinship([
        makeStep('sister', 'sideways'),
        makeStep('husband', 'sideways'),
      ]);

      expect(result.term).toBe('brother_in_law');
      expect(result.termHindi).toBe('जीजा');
    });

    it('should resolve son→wife = daughter_in_law (बहू)', () => {
      const result = service.resolveKinship([
        makeStep('son', 'down'),
        makeStep('wife', 'sideways'),
      ]);

      expect(result.term).toBe('daughter_in_law');
      expect(result.termHindi).toBe('बहू');
    });

    // Descriptive fallback for unknown paths

    it('should compose descriptive term for unknown path', () => {
      // A path not in KINSHIP_RULES - very long chain
      const result = service.resolveKinship([
        makeStep('father', 'up'),
        makeStep('father', 'up'),
        makeStep('father', 'up'),
        makeStep('father', 'up'),
        makeStep('father', 'up'),
      ]);

      // Should still return a result (not throw)
      expect(result).toBeDefined();
      expect(result.term).toBeDefined();
      expect(result.path.length).toBe(5);
    });
  });

  // ── Depth Limit Enforcement ──────────────────────────────────────────

  describe('Depth Limit Enforcement', () => {
    const familyId = 'family-depth';

    it('should respect default maxDepth=6 in getAllRelationships', async () => {
      // Create a 8-person chain: p0 → p1 → p2 → ... → p7 (7 hops)
      const persons = Array.from({ length: 8 }, (_, i) => ({
        id: `p${i}`,
        name: `Person ${i}`,
        gender: 'male',
      }));

      const relationships = [];
      for (let i = 0; i < 7; i++) {
        relationships.push({
          fromPersonId: `p${i}`,
          toPersonId: `p${i + 1}`,
          relationshipKey: 'father',
        });
      }

      mockPrismaService.person.findMany.mockResolvedValue(persons);
      mockPrismaService.relationship.findMany.mockResolvedValue(relationships);

      const result = await service.getAllRelationships(familyId, 'p0');

      // Default maxDepth=6, so p7 (distance 7) should NOT be in results
      const maxDistance = Math.max(...result.map((r) => r.distance));
      expect(maxDistance).toBeLessThanOrEqual(6);

      // p7 at distance 7 should not be present
      const p7Entry = result.find((r) => r.personId === 'p7');
      expect(p7Entry).toBeUndefined();

      // p6 at distance 6 SHOULD be present
      const p6Entry = result.find((r) => r.personId === 'p6');
      expect(p6Entry).toBeDefined();
      expect(p6Entry!.distance).toBe(6);
    });

    it('should respect custom maxDepth in getAllRelationships', async () => {
      const persons = Array.from({ length: 5 }, (_, i) => ({
        id: `p${i}`,
        name: `Person ${i}`,
        gender: 'male',
      }));

      const relationships = [];
      for (let i = 0; i < 4; i++) {
        relationships.push({
          fromPersonId: `p${i}`,
          toPersonId: `p${i + 1}`,
          relationshipKey: 'father',
        });
      }

      mockPrismaService.person.findMany.mockResolvedValue(persons);
      mockPrismaService.relationship.findMany.mockResolvedValue(relationships);

      const result = await service.getAllRelationships(familyId, 'p0', 2);

      // maxDepth=2, so only p1 (dist 1) and p2 (dist 2) should appear
      expect(result.length).toBe(2);
      const maxDistance = Math.max(...result.map((r) => r.distance));
      expect(maxDistance).toBeLessThanOrEqual(2);
    });

    it('should resolve kinship for paths at exactly the depth limit', () => {
      // 3-step path (father→father→father) is in KINSHIP_RULES as great_grandfather
      const result = service.resolveKinship([
        makeStep('father', 'up'),
        makeStep('father', 'up'),
        makeStep('father', 'up'),
      ]);

      expect(result.term).toBe('great_grandfather');
      expect(result.confidence).toBe(1.0);
    });

    it('should handle kinship resolution for paths exceeding depth limit gracefully', () => {
      // 7-step path — way beyond any explicit KINSHIP_RULES entry
      // Should still produce a result (descriptive fallback), not throw
      const longPath: RelationshipStep[] = Array.from({ length: 7 }, () => ({
        personId: 'x',
        personName: 'X',
        relationshipType: 'father',
        direction: 'up' as const,
      }));

      const result = service.resolveKinship(longPath);

      expect(result).toBeDefined();
      expect(result.term).toBeDefined();
      expect(result.path.length).toBe(7);
      // Confidence should be lower for such long paths
      expect(result.confidence).toBeLessThan(1.0);
    });
  });

  // ── Circular Relationship Prevention ─────────────────────────────────

  describe('Circular Relationship Prevention', () => {
    const familyId = 'family-circular';

    it('should not infinite loop on 2-node cycle (A→B→A) in findPath', async () => {
      // A is father of B, B is father of A (circular data)
      mockPrismaService.person.findMany.mockResolvedValue([
        { id: 'pA', name: 'Person A', gender: 'male' },
        { id: 'pB', name: 'Person B', gender: 'male' },
      ]);

      mockPrismaService.relationship.findMany.mockResolvedValue([
        { fromPersonId: 'pA', toPersonId: 'pB', relationshipKey: 'father' },
        { fromPersonId: 'pB', toPersonId: 'pA', relationshipKey: 'father' },
      ]);

      // Should terminate and return a result
      const result = await service.findPath(familyId, 'pA', 'pB');

      expect(result.found).toBe(true);
      expect(result.distance).toBe(1); // Shortest path
      // BFS should find the shortest path immediately
    });

    it('should not infinite loop on 3-node cycle (A→B→C→A) in findPath', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([
        { id: 'pA', name: 'Person A', gender: 'male' },
        { id: 'pB', name: 'Person B', gender: 'male' },
        { id: 'pC', name: 'Person C', gender: 'male' },
      ]);

      mockPrismaService.relationship.findMany.mockResolvedValue([
        { fromPersonId: 'pA', toPersonId: 'pB', relationshipKey: 'father' },
        { fromPersonId: 'pB', toPersonId: 'pC', relationshipKey: 'father' },
        { fromPersonId: 'pC', toPersonId: 'pA', relationshipKey: 'father' },
      ]);

      const result = await service.findPath(familyId, 'pA', 'pC');

      expect(result.found).toBe(true);
      // Bidirectional edges mean A→C is reachable in 1 hop via inverse of C→A
      expect(result.distance).toBeGreaterThanOrEqual(1);
      expect(result.distance).toBeLessThanOrEqual(2);
    });

    it('should not infinite loop on complex cycle (A→B→C→D→B) in findPath', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([
        { id: 'pA', name: 'Person A', gender: 'male' },
        { id: 'pB', name: 'Person B', gender: 'male' },
        { id: 'pC', name: 'Person C', gender: 'male' },
        { id: 'pD', name: 'Person D', gender: 'male' },
      ]);

      mockPrismaService.relationship.findMany.mockResolvedValue([
        { fromPersonId: 'pA', toPersonId: 'pB', relationshipKey: 'father' },
        { fromPersonId: 'pB', toPersonId: 'pC', relationshipKey: 'brother' },
        { fromPersonId: 'pC', toPersonId: 'pD', relationshipKey: 'father' },
        { fromPersonId: 'pD', toPersonId: 'pB', relationshipKey: 'father' }, // Cycle back to B
      ]);

      const result = await service.findPath(familyId, 'pA', 'pD');

      expect(result.found).toBe(true);
      // Bidirectional edges create shortcuts; distance can be 2 (A→B→D via inverse of D→B)
      expect(result.distance).toBeGreaterThanOrEqual(1);
      expect(result.distance).toBeLessThanOrEqual(3);
    });

    it('should build graph with circular relationships without crashing', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([
        { id: 'pA', name: 'Person A', gender: 'male' },
        { id: 'pB', name: 'Person B', gender: 'female' },
      ]);

      // Both A→B and B→A relationships
      mockPrismaService.relationship.findMany.mockResolvedValue([
        { fromPersonId: 'pA', toPersonId: 'pB', relationshipKey: 'husband' },
        { fromPersonId: 'pB', toPersonId: 'pA', relationshipKey: 'wife' },
      ]);

      const adjacency = await service.buildGraph(familyId);

      // Should not crash and should have entries
      expect(adjacency.size).toBeGreaterThan(0);
      // Both persons should have adjacency entries
      expect(adjacency.has('pA')).toBe(true);
      expect(adjacency.has('pB')).toBe(true);
    });
  });

  // ── Large Family Performance ─────────────────────────────────────────

  describe('Large Family Performance', () => {
    const familyId = 'family-large';

    it('should handle large family (1000 members) within reasonable time', async () => {
      // Generate 1000 persons
      const persons = Array.from({ length: 1000 }, (_, i) => ({
        id: `person-${i}`,
        name: `Person ${i}`,
        gender: i % 2 === 0 ? 'male' : 'female',
      }));

      // Generate ~2000 relationships (each person has ~2 relationships)
      const relationships = [];
      for (let i = 1; i < 1000; i++) {
        relationships.push({
          fromPersonId: `person-${Math.floor(i / 2)}`,
          toPersonId: `person-${i}`,
          relationshipKey: i % 2 === 0 ? 'father' : 'mother',
        });
      }

      mockPrismaService.person.findMany.mockResolvedValue(persons);
      mockPrismaService.relationship.findMany.mockResolvedValue(relationships);

      const start = performance.now();
      const adjacency = await service.buildGraph(familyId);
      const duration = performance.now() - start;

      expect(duration).toBeLessThan(5000); // 5 seconds max
      expect(adjacency.size).toBeGreaterThan(0);
    });

    it('should find path in large family within reasonable time', async () => {
      const persons = Array.from({ length: 1000 }, (_, i) => ({
        id: `person-${i}`,
        name: `Person ${i}`,
        gender: i % 2 === 0 ? 'male' : 'female',
      }));

      // Create a chain: person-0 → person-1 → person-2 → ... → person-999
      const relationships = [];
      for (let i = 0; i < 999; i++) {
        relationships.push({
          fromPersonId: `person-${i}`,
          toPersonId: `person-${i + 1}`,
          relationshipKey: 'father',
        });
      }

      mockPrismaService.person.findMany.mockResolvedValue(persons);
      mockPrismaService.relationship.findMany.mockResolvedValue(relationships);

      // First build the graph
      await service.buildGraph(familyId);

      // Then find a path from person-0 to person-5
      const start = performance.now();
      const result = await service.findPath(familyId, 'person-0', 'person-5');
      const duration = performance.now() - start;

      expect(duration).toBeLessThan(1000); // 1 second max
      expect(result.found).toBe(true);
      expect(result.distance).toBe(5);
    });

    it('should getAllRelationships in large family within reasonable time', async () => {
      const persons = Array.from({ length: 500 }, (_, i) => ({
        id: `person-${i}`,
        name: `Person ${i}`,
        gender: i % 2 === 0 ? 'male' : 'female',
      }));

      // Binary tree structure: person-i has children at 2i+1 and 2i+2
      const relationships = [];
      for (let i = 0; i < 250; i++) {
        if (2 * i + 1 < 500) {
          relationships.push({
            fromPersonId: `person-${i}`,
            toPersonId: `person-${2 * i + 1}`,
            relationshipKey: 'son',
          });
        }
        if (2 * i + 2 < 500) {
          relationships.push({
            fromPersonId: `person-${i}`,
            toPersonId: `person-${2 * i + 2}`,
            relationshipKey: 'daughter',
          });
        }
      }

      mockPrismaService.person.findMany.mockResolvedValue(persons);
      mockPrismaService.relationship.findMany.mockResolvedValue(relationships);

      await service.buildGraph(familyId);

      const start = performance.now();
      const result = await service.getAllRelationships(familyId, 'person-0');
      const duration = performance.now() - start;

      expect(duration).toBeLessThan(2000); // 2 seconds max
      expect(result.length).toBeGreaterThan(0);
    });
  });

  // ── findPath on Disconnected Persons ─────────────────────────────────

  describe('findPath on Disconnected Persons', () => {
    const familyId = 'family-disconnected';

    it('should return not found for persons in different family components', async () => {
      // Component 1: p1 → p2
      // Component 2: p3 → p4 (no connection to component 1)
      mockPrismaService.person.findMany.mockResolvedValue([
        { id: 'p1', name: 'Rahul', gender: 'male' },
        { id: 'p2', name: 'Suresh', gender: 'male' },
        { id: 'p3', name: 'Anita', gender: 'female' },
        { id: 'p4', name: 'Meera', gender: 'female' },
      ]);

      mockPrismaService.relationship.findMany.mockResolvedValue([
        { fromPersonId: 'p1', toPersonId: 'p2', relationshipKey: 'father' },
        { fromPersonId: 'p3', toPersonId: 'p4', relationshipKey: 'mother' },
      ]);

      const result = await service.findPath(familyId, 'p1', 'p3');

      expect(result.found).toBe(false);
      expect(result.distance).toBe(-1);
      expect(result.path).toEqual([]);
    });

    it('should return not found for person with no relationships to another', async () => {
      // p1 has no relationships, p2 has no relationships
      mockPrismaService.person.findMany.mockResolvedValue([
        { id: 'p1', name: 'Rahul', gender: 'male' },
        { id: 'p2', name: 'Suresh', gender: 'male' },
      ]);

      mockPrismaService.relationship.findMany.mockResolvedValue([]);

      const result = await service.findPath(familyId, 'p1', 'p2');

      expect(result.found).toBe(false);
      expect(result.distance).toBe(-1);
    });

    it('should return not found from isolated person to connected person', async () => {
      // p1 is isolated (no relationships), p2→p3 connected
      mockPrismaService.person.findMany.mockResolvedValue([
        { id: 'p1', name: 'Rahul', gender: 'male' },
        { id: 'p2', name: 'Suresh', gender: 'male' },
        { id: 'p3', name: 'Anita', gender: 'female' },
      ]);

      mockPrismaService.relationship.findMany.mockResolvedValue([
        { fromPersonId: 'p2', toPersonId: 'p3', relationshipKey: 'mother' },
      ]);

      const result = await service.findPath(familyId, 'p1', 'p2');

      expect(result.found).toBe(false);
      expect(result.distance).toBe(-1);
    });
  });

  // ── findPath on Unknown Person ───────────────────────────────────────

  describe('findPath on Unknown Person', () => {
    const familyId = 'family-unknown';

    it('should throw NotFoundException for unknown toPersonId', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([
        { id: 'p1', name: 'Rahul', gender: 'male' },
      ]);
      mockPrismaService.relationship.findMany.mockResolvedValue([]);

      await expect(
        service.findPath(familyId, 'p1', 'nonexistent'),
      ).rejects.toThrow(NotFoundException);
    });

    it('should throw NotFoundException for unknown fromPersonId', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([
        { id: 'p1', name: 'Rahul', gender: 'male' },
      ]);
      mockPrismaService.relationship.findMany.mockResolvedValue([]);

      await expect(
        service.findPath(familyId, 'nonexistent', 'p1'),
      ).rejects.toThrow(NotFoundException);
    });

    it('should throw NotFoundException when both persons are unknown', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([
        { id: 'p1', name: 'Rahul', gender: 'male' },
      ]);
      mockPrismaService.relationship.findMany.mockResolvedValue([]);

      await expect(
        service.findPath(familyId, 'unknown1', 'unknown2'),
      ).rejects.toThrow(NotFoundException);
    });
  });

  // ── Additional Edge Cases ────────────────────────────────────────────

  describe('Additional Edge Cases', () => {
    const familyId = 'family-edge';

    it('should handle empty family (0 persons) without crashing', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([]);
      mockPrismaService.relationship.findMany.mockResolvedValue([]);

      const adjacency = await service.buildGraph(familyId);

      expect(adjacency.size).toBe(0);
    });

    it('should handle family with 1 person and no relationships', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([
        { id: 'p1', name: 'Rahul', gender: 'male' },
      ]);
      mockPrismaService.relationship.findMany.mockResolvedValue([]);

      const adjacency = await service.buildGraph(familyId);

      // No relationships means no edges, so p1 might not appear in adjacency
      expect(adjacency.size).toBe(0);

      // findPath from p1 to p1 should still work (self-path)
      mockPrismaService.person.findFirst.mockResolvedValue({
        id: 'p1',
        name: 'Rahul',
        gender: 'male',
      });
      const result = await service.findPath(familyId, 'p1', 'p1');
      expect(result.found).toBe(true);
      expect(result.distance).toBe(0);
    });

    it('should handle person with multiple relationships to the same person (duplicates)', async () => {
      mockPrismaService.person.findMany.mockResolvedValue([
        { id: 'p1', name: 'Rahul', gender: 'male' },
        { id: 'p2', name: 'Suresh', gender: 'male' },
      ]);

      // Duplicate relationships: p1→p2 as both father and brother
      mockPrismaService.relationship.findMany.mockResolvedValue([
        { fromPersonId: 'p1', toPersonId: 'p2', relationshipKey: 'father' },
        { fromPersonId: 'p1', toPersonId: 'p2', relationshipKey: 'brother' },
      ]);

      const adjacency = await service.buildGraph(familyId);

      // Both edges should be present
      const p1Neighbors = adjacency.get('p1');
      expect(p1Neighbors).toBeDefined();
      const edgesToP2 = p1Neighbors!.filter((e) => e.neighborId === 'p2');
      expect(edgesToP2.length).toBe(2);

      // findPath should still work — BFS will find the shortest path (1 hop)
      const result = await service.findPath(familyId, 'p1', 'p2');
      expect(result.found).toBe(true);
      expect(result.distance).toBe(1);
    });

    it('should return found=true with empty path for self-path of non-existent person', async () => {
      // getPersonRecord returns null for non-existent person
      mockPrismaService.person.findFirst.mockResolvedValue(null);

      const result = await service.findPath(familyId, 'ghost', 'ghost');

      // Service returns found=true with empty path when person not found for self-path
      expect(result.found).toBe(true);
      expect(result.distance).toBe(0);
      expect(result.path).toEqual([]);
    });
  });
});
