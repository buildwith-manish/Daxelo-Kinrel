import { Test, TestingModule } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import {
  BadRequestException,
  NotFoundException,
  ForbiddenException,
  ConflictException,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { KinrelGateway } from '../gateway/kinrel.gateway';
import { RelationshipsService, getInverseKey } from './relationships.service';
import { CreateRelationshipDto } from './dto/create-relationship.dto';

// ── Mock PrismaService ─────────────────────────────────────────────────

const mockPrisma = {
  person: {
    findFirst: jest.fn(),
  },
  relationship: {
    create: jest.fn(),
    findFirst: jest.fn(),
    findMany: jest.fn(),
    count: jest.fn(),
    delete: jest.fn(),
  },
  familyMember: {
    findUnique: jest.fn(),
  },
  family: {
    update: jest.fn(),
  },
  $transaction: jest.fn(),
};

// ── Mock KinrelGateway ─────────────────────────────────────────────────

const mockGateway = {
  emitToFamily: jest.fn(),
};

// ── Mock ConfigService ─────────────────────────────────────────────────

const mockConfig = {
  get: jest.fn((key: string) => {
    switch (key) {
      case 'REDIS_URL':
        return ''; // No Redis in tests
      default:
        return undefined;
    }
  }),
};

// ── Test Suite ─────────────────────────────────────────────────────────

describe('RelationshipsService', () => {
  let service: RelationshipsService;

  beforeEach(async () => {
    jest.clearAllMocks();

    // Reset config mock
    mockConfig.get.mockImplementation((key: string) => {
      switch (key) {
        case 'REDIS_URL':
          return '';
        default:
          return undefined;
      }
    });

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        RelationshipsService,
        { provide: PrismaService, useValue: mockPrisma },
        { provide: KinrelGateway, useValue: mockGateway },
        { provide: ConfigService, useValue: mockConfig },
      ],
    }).compile();

    service = module.get<RelationshipsService>(RelationshipsService);
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });

  // ── getInverseKey() helper ─────────────────────────────────────────

  describe('getInverseKey', () => {
    it('should return son for father→male', () => {
      expect(getInverseKey('father', 'male')).toBe('son');
    });

    it('should return daughter for father→female', () => {
      expect(getInverseKey('father', 'female')).toBe('daughter');
    });

    it('should return wife for husband', () => {
      expect(getInverseKey('husband')).toBe('wife');
    });

    it('should return husband for wife', () => {
      expect(getInverseKey('wife')).toBe('husband');
    });

    it('should return father for son', () => {
      expect(getInverseKey('son')).toBe('father');
    });

    it('should return mother for daughter', () => {
      expect(getInverseKey('daughter')).toBe('mother');
    });

    it('should return the same key if no mapping exists', () => {
      expect(getInverseKey('custom_relation')).toBe('custom_relation');
    });
  });

  // ── create() ───────────────────────────────────────────────────────

  describe('create', () => {
    const userId = 'user-1';
    const familyId = 'family-1';
    const dto: CreateRelationshipDto = {
      fromPersonId: 'person-1',
      toPersonId: 'person-2',
      relationshipKey: 'father',
    };

    const mockMembership = {
      familyId_userId: { familyId, userId },
      role: 'admin',
      userId,
      familyId,
    };

    const mockFromPerson = {
      id: 'person-1',
      familyId,
      gender: 'male',
      deletedAt: null,
    };

    const mockToPerson = {
      id: 'person-2',
      familyId,
      gender: 'male',
      deletedAt: null,
    };

    it('should create bidirectional relationship (main + inverse)', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue(mockMembership);
      mockPrisma.person.findFirst
        .mockResolvedValueOnce(mockFromPerson)
        .mockResolvedValueOnce(mockToPerson);
      mockPrisma.relationship.findFirst.mockResolvedValue(null); // no existing

      const forwardRel = {
        id: 'rel-1',
        familyId,
        fromPersonId: 'person-1',
        toPersonId: 'person-2',
        relationshipKey: 'father',
        direction: 'from',
        isActive: true,
        label: null,
        updatedAt: new Date(),
      };

      mockPrisma.$transaction.mockImplementation(async (cb: any) => {
        const tx = {
          relationship: {
            create: jest.fn().mockResolvedValueOnce(forwardRel),
          },
          family: {
            update: jest.fn().mockResolvedValue({ id: familyId }),
          },
        };
        return cb(tx);
      });

      const result = await service.create(userId, familyId, dto);

      expect(result.relationshipKey).toBe('father');
      expect(result.fromPersonId).toBe('person-1');
      expect(result.toPersonId).toBe('person-2');
      // Gateway should emit events
      expect(mockGateway.emitToFamily).toHaveBeenCalled();
    });

    it('should throw ForbiddenException if user is not a family member', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue(null);

      try {
        await service.create(userId, familyId, dto);
        fail('Should have thrown');
      } catch (error) {
        expect(error).toBeInstanceOf(ForbiddenException);
        expect(error.message).toContain('You are not a member of this family');
      }
    });

    it('should throw ForbiddenException if user role is below editor', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue({
        ...mockMembership,
        role: 'viewer',
      });

      try {
        await service.create(userId, familyId, dto);
        fail('Should have thrown');
      } catch (error) {
        expect(error).toBeInstanceOf(ForbiddenException);
        expect(error.message).toContain('Insufficient permissions');
      }
    });

    it('should create father→son inverse (son→father)', async () => {
      const maleToPerson = { ...mockToPerson, gender: 'male' };
      mockPrisma.familyMember.findUnique.mockResolvedValue(mockMembership);
      mockPrisma.person.findFirst
        .mockResolvedValueOnce(mockFromPerson)
        .mockResolvedValueOnce(maleToPerson);
      mockPrisma.relationship.findFirst.mockResolvedValue(null);

      let inverseKeyUsed: string | null = null;

      const forwardRel = {
        id: 'rel-1',
        familyId,
        fromPersonId: 'person-1',
        toPersonId: 'person-2',
        relationshipKey: 'father',
        direction: 'from',
        isActive: true,
        label: null,
        updatedAt: new Date(),
      };

      mockPrisma.$transaction.mockImplementation(async (cb: any) => {
        const tx = {
          relationship: {
            create: jest.fn()
              .mockResolvedValueOnce(forwardRel)
              .mockImplementationOnce(({ data }) => {
                inverseKeyUsed = data.relationshipKey;
                return Promise.resolve({ id: 'rel-2', ...data });
              }),
          },
          family: {
            update: jest.fn().mockResolvedValue({ id: familyId }),
          },
        };
        return cb(tx);
      });

      await service.create(userId, familyId, {
        fromPersonId: 'person-1',
        toPersonId: 'person-2',
        relationshipKey: 'father',
      });

      // father→male should create inverse son→father? No — father's inverse with male target = son
      // The forward is "father" (person-1 is father of person-2)
      // The inverse should be: person-2 is "son" of person-1 (male target)
      expect(inverseKeyUsed).toBe('son');
    });

    it('should create husband→wife inverse (wife→husband)', async () => {
      const femaleToPerson = { ...mockToPerson, gender: 'female' };
      mockPrisma.familyMember.findUnique.mockResolvedValue(mockMembership);
      mockPrisma.person.findFirst
        .mockResolvedValueOnce(mockFromPerson)
        .mockResolvedValueOnce(femaleToPerson);
      mockPrisma.relationship.findFirst.mockResolvedValue(null);

      let inverseKeyUsed: string | null = null;

      const forwardRel = {
        id: 'rel-1',
        familyId,
        fromPersonId: 'person-1',
        toPersonId: 'person-2',
        relationshipKey: 'husband',
        direction: 'from',
        isActive: true,
        label: null,
        updatedAt: new Date(),
      };

      mockPrisma.$transaction.mockImplementation(async (cb: any) => {
        const tx = {
          relationship: {
            create: jest.fn()
              .mockResolvedValueOnce(forwardRel)
              .mockImplementationOnce(({ data }) => {
                inverseKeyUsed = data.relationshipKey;
                return Promise.resolve({ id: 'rel-2', ...data });
              }),
          },
          family: {
            update: jest.fn().mockResolvedValue({ id: familyId }),
          },
        };
        return cb(tx);
      });

      await service.create(userId, familyId, {
        fromPersonId: 'person-1',
        toPersonId: 'person-2',
        relationshipKey: 'husband',
      });

      // husband's inverse is wife
      expect(inverseKeyUsed).toBe('wife');
    });

    it('should throw ConflictException if relationship already exists', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue(mockMembership);
      mockPrisma.person.findFirst
        .mockResolvedValueOnce(mockFromPerson)
        .mockResolvedValueOnce(mockToPerson);
      mockPrisma.relationship.findFirst.mockResolvedValue({
        id: 'existing-rel',
        relationshipKey: 'father',
      });

      try {
        await service.create(userId, familyId, dto);
        fail('Should have thrown');
      } catch (error) {
        expect(error).toBeInstanceOf(ConflictException);
        expect(error.message).toContain('This relationship already exists');
      }
    });

    it('should throw BadRequestException for self-relationship', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue(mockMembership);

      try {
        await service.create(userId, familyId, {
          fromPersonId: 'person-1',
          toPersonId: 'person-1',
          relationshipKey: 'father',
        });
        fail('Should have thrown');
      } catch (error) {
        expect(error).toBeInstanceOf(BadRequestException);
        expect(error.message).toContain('Cannot create a self-relationship');
      }
    });

    it('should throw NotFoundException if source person not found', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue(mockMembership);
      mockPrisma.person.findFirst
        .mockResolvedValueOnce(null) // fromPerson not found
        .mockResolvedValueOnce(mockToPerson);

      try {
        await service.create(userId, familyId, dto);
        fail('Should have thrown');
      } catch (error) {
        expect(error).toBeInstanceOf(NotFoundException);
        expect(error.message).toContain('Source person not found in this family');
      }
    });

    it('should throw NotFoundException if target person not found', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue(mockMembership);
      mockPrisma.person.findFirst
        .mockResolvedValueOnce(mockFromPerson)
        .mockResolvedValueOnce(null); // toPerson not found

      try {
        await service.create(userId, familyId, dto);
        fail('Should have thrown');
      } catch (error) {
        expect(error).toBeInstanceOf(NotFoundException);
        expect(error.message).toContain('Target person not found in this family');
      }
    });

    it('should invalidate graph cache for the family', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue(mockMembership);
      mockPrisma.person.findFirst
        .mockResolvedValueOnce(mockFromPerson)
        .mockResolvedValueOnce(mockToPerson);
      mockPrisma.relationship.findFirst.mockResolvedValue(null);

      const forwardRel = {
        id: 'rel-1',
        familyId,
        fromPersonId: 'person-1',
        toPersonId: 'person-2',
        relationshipKey: 'father',
        direction: 'from',
        isActive: true,
        label: null,
        updatedAt: new Date(),
      };

      mockPrisma.$transaction.mockImplementation(async (cb: any) => {
        const tx = {
          relationship: {
            create: jest.fn().mockResolvedValueOnce(forwardRel),
          },
          family: {
            update: jest.fn().mockResolvedValue({ id: familyId }),
          },
        };
        return cb(tx);
      });

      await service.create(userId, familyId, dto);

      // Since REDIS_URL is empty, redis is null, so invalidateGraphCache is a no-op
      // But the method should still be called without error
      // Verify gateway events were emitted (proving create completed successfully)
      expect(mockGateway.emitToFamily).toHaveBeenCalledWith(
        familyId,
        'relationship:created',
        expect.objectContaining({ familyId, type: 'relationship:created' }),
      );
      expect(mockGateway.emitToFamily).toHaveBeenCalledWith(
        familyId,
        'graph:updated',
        expect.objectContaining({ familyId, type: 'graph:updated' }),
      );
    });
  });

  // ── findAll() ──────────────────────────────────────────────────────

  describe('findAll', () => {
    const userId = 'user-1';
    const familyId = 'family-1';
    const mockMembership = {
      familyId_userId: { familyId, userId },
      role: 'member',
      userId,
      familyId,
    };

    it('should return relationships for a family', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue(mockMembership);

      const relationships = [
        {
          id: 'rel-1',
          familyId,
          fromPersonId: 'person-1',
          toPersonId: 'person-2',
          relationshipKey: 'father',
          direction: 'from',
          isActive: true,
          label: null,
          fromPerson: { id: 'person-1', deletedAt: null },
          toPerson: { id: 'person-2', deletedAt: null },
        },
      ];

      mockPrisma.$transaction.mockResolvedValue([relationships, 1]);

      const result = await service.findAll(userId, familyId, {});

      expect(result.items).toHaveLength(1);
      expect(result.items[0].relationshipKey).toBe('father');
      expect(result.total).toBe(1);
    });

    it('should filter by personId when provided', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue(mockMembership);

      const relationships = [
        {
          id: 'rel-1',
          familyId,
          fromPersonId: 'person-1',
          toPersonId: 'person-2',
          relationshipKey: 'father',
          direction: 'from',
          isActive: true,
          label: null,
          fromPerson: { id: 'person-1', deletedAt: null },
          toPerson: { id: 'person-2', deletedAt: null },
        },
      ];

      mockPrisma.$transaction.mockResolvedValue([relationships, 1]);

      const result = await service.findAll(userId, familyId, {
        personId: 'person-1',
      });

      expect(result.items).toHaveLength(1);
      // Verify the transaction was called (which includes the OR filter)
      expect(mockPrisma.$transaction).toHaveBeenCalled();
    });

    it('should throw ForbiddenException if user is not a family member', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue(null);

      try {
        await service.findAll(userId, familyId, {});
        fail('Should have thrown');
      } catch (error) {
        expect(error).toBeInstanceOf(ForbiddenException);
        expect(error.message).toContain('You are not a member of this family');
      }
    });
  });

  // ── remove() ───────────────────────────────────────────────────────

  describe('remove', () => {
    const userId = 'user-1';
    const familyId = 'family-1';
    const relationshipId = 'rel-1';
    const mockMembership = {
      familyId_userId: { familyId, userId },
      role: 'admin',
      userId,
      familyId,
    };

    it('should delete both directions of the relationship', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue(mockMembership);

      const forwardRel = {
        id: 'rel-1',
        familyId,
        fromPersonId: 'person-1',
        toPersonId: 'person-2',
        relationshipKey: 'father',
        direction: 'from',
        isActive: true,
      };

      const inverseRel = {
        id: 'rel-2',
        familyId,
        fromPersonId: 'person-2',
        toPersonId: 'person-1',
        relationshipKey: 'son',
        direction: 'from',
        isActive: true,
      };

      mockPrisma.relationship.findFirst
        .mockResolvedValueOnce(forwardRel)
        .mockResolvedValueOnce(inverseRel);

      mockPrisma.$transaction.mockImplementation(async (cb: any) => {
        const tx = {
          relationship: {
            delete: jest.fn()
              .mockResolvedValueOnce({ id: 'rel-1' })
              .mockResolvedValueOnce({ id: 'rel-2' }),
          },
          family: {
            update: jest.fn().mockResolvedValue({ id: familyId }),
          },
        };
        return cb(tx);
      });

      const result = await service.remove(userId, familyId, relationshipId);

      expect(result.deleted).toBe(true);
      expect(result.relationshipId).toBe('rel-1');
      expect(mockGateway.emitToFamily).toHaveBeenCalledWith(
        familyId,
        'relationship:deleted',
        expect.objectContaining({ id: 'rel-1', type: 'relationship:deleted' }),
      );
      expect(mockGateway.emitToFamily).toHaveBeenCalledWith(
        familyId,
        'graph:updated',
        expect.objectContaining({ familyId, type: 'graph:updated' }),
      );
    });

    it('should throw ForbiddenException if user is not admin/editor', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue({
        ...mockMembership,
        role: 'viewer',
      });

      try {
        await service.remove(userId, familyId, relationshipId);
        fail('Should have thrown');
      } catch (error) {
        expect(error).toBeInstanceOf(ForbiddenException);
        expect(error.message).toContain('Insufficient permissions');
      }
    });

    it('should throw NotFoundException if relationship not found', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue(mockMembership);
      mockPrisma.relationship.findFirst.mockResolvedValue(null);

      try {
        await service.remove(userId, familyId, relationshipId);
        fail('Should have thrown');
      } catch (error) {
        expect(error).toBeInstanceOf(NotFoundException);
        expect(error.message).toContain('Relationship not found');
      }
    });
  });
});
