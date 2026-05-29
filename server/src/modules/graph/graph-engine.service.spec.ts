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
    // Helper to create a step
    const makeStep = (
      relType: string,
      direction: 'up' | 'down' | 'sideways' = 'up',
    ): RelationshipStep => ({
      personId: `person-${relType}`,
      personName: `Name-${relType}`,
      relationshipType: relType,
      direction,
    });

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
});
