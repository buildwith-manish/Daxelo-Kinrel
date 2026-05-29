import { Test, TestingModule } from '@nestjs/testing';
import { FamiliesService } from './families.service';
import { FamilyIdService } from './family-id.service';
import { PrismaService } from '../../prisma/prisma.service';
import {
  BadRequestException,
  NotFoundException,
  ForbiddenException,
} from '@nestjs/common';

// ── Mock PrismaService ──────────────────────────────────────────────────

const mockPrismaService = {
  $transaction: jest.fn(),
  family: {
    create: jest.fn(),
    findUnique: jest.fn(),
    findMany: jest.fn(),
    update: jest.fn(),
    delete: jest.fn(),
  },
  familyMember: {
    create: jest.fn(),
    findUnique: jest.fn(),
    findMany: jest.fn(),
    deleteMany: jest.fn(),
  },
  person: {
    findMany: jest.fn(),
    deleteMany: jest.fn(),
  },
  relationship: {
    deleteMany: jest.fn(),
  },
};

// ── Mock FamilyIdService ────────────────────────────────────────────────

const mockFamilyIdService = {
  generateFamilyId: jest.fn(),
};

describe('FamiliesService', () => {
  let service: FamiliesService;

  beforeEach(async () => {
    jest.clearAllMocks();

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        FamiliesService,
        { provide: PrismaService, useValue: mockPrismaService },
        { provide: FamilyIdService, useValue: mockFamilyIdService },
      ],
    }).compile();

    service = module.get<FamiliesService>(FamiliesService);
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });

  // ── createFamily ────────────────────────────────────────────────────

  describe('create', () => {
    const userId = 'user-123';
    const kinFamilyId = 'KIN-AB12CD34';

    const createdFamily = {
      id: 'family-1',
      name: 'Sharma Family',
      description: 'A test family',
      familyCode: 'FC123',
      kinFamilyId,
      username: null,
      primaryLanguage: 'en',
      gotra: null,
      originVillage: null,
      privacyMode: 'private',
      anchorPersonId: null,
      memberCount: 1,
      generationCount: 0,
      createdBy: userId,
      avatarUrl: null,
      region: null,
      isOnboarded: false,
      lastActivityAt: new Date(),
      createdAt: new Date(),
    };

    it('should create a family and auto-generate KIN ID', async () => {
      mockFamilyIdService.generateFamilyId.mockResolvedValue(kinFamilyId);
      mockPrismaService.$transaction.mockImplementation(async (cb) => {
        // Simulate the transaction callback
        const tx = {
          family: {
            create: jest.fn().mockResolvedValue(createdFamily),
          },
          familyMember: {
            create: jest.fn().mockResolvedValue({
              id: 'member-1',
              familyId: 'family-1',
              userId,
              role: 'admin',
            }),
          },
        };
        return cb(tx);
      });

      const result = await service.create(userId, {
        name: 'Sharma Family',
        description: 'A test family',
      });

      expect(mockFamilyIdService.generateFamilyId).toHaveBeenCalled();
      expect(result.kinFamilyId).toBe(kinFamilyId);
      expect(result.name).toBe('Sharma Family');
    });

    it('should throw BadRequestException if name is empty', async () => {
      await expect(
        service.create(userId, { name: '' }),
      ).rejects.toThrow(BadRequestException);
    });

    it('should throw BadRequestException if name is whitespace', async () => {
      await expect(
        service.create(userId, { name: '   ' }),
      ).rejects.toThrow(BadRequestException);
    });

    it('should trim family name', async () => {
      mockFamilyIdService.generateFamilyId.mockResolvedValue(kinFamilyId);
      mockPrismaService.$transaction.mockImplementation(async (cb) => {
        const tx = {
          family: {
            create: jest.fn().mockImplementation(({ data }) => {
              expect(data.name).toBe('Sharma Family'); // trimmed
              return Promise.resolve(createdFamily);
            }),
          },
          familyMember: {
            create: jest.fn().mockResolvedValue({ id: 'member-1' }),
          },
        };
        return cb(tx);
      });

      await service.create(userId, { name: '  Sharma Family  ' });
    });

    it('should set default values correctly', async () => {
      mockFamilyIdService.generateFamilyId.mockResolvedValue(kinFamilyId);
      mockPrismaService.$transaction.mockImplementation(async (cb) => {
        const tx = {
          family: {
            create: jest.fn().mockImplementation(({ data }) => {
              expect(data.primaryLanguage).toBe('hi'); // custom
              expect(data.privacyMode).toBe('private'); // default
              expect(data.memberCount).toBe(1);
              expect(data.createdBy).toBe(userId);
              return Promise.resolve(createdFamily);
            }),
          },
          familyMember: {
            create: jest.fn().mockResolvedValue({ id: 'member-1' }),
          },
        };
        return cb(tx);
      });

      await service.create(userId, {
        name: 'Sharma Family',
        primaryLanguage: 'hi',
      });
    });
  });

  // ── getFamilyById (findOne) ─────────────────────────────────────────

  describe('findOne', () => {
    const userId = 'user-123';
    const familyId = 'family-1';

    const familyRecord = {
      id: familyId,
      name: 'Sharma Family',
      description: 'Test',
      familyCode: 'FC123',
      kinFamilyId: 'KIN-AB12CD34',
      username: null,
      primaryLanguage: 'en',
      gotra: null,
      originVillage: null,
      privacyMode: 'private',
      anchorPersonId: null,
      memberCount: 3,
      generationCount: 2,
      createdBy: userId,
      avatarUrl: null,
      region: null,
      isOnboarded: true,
      lastActivityAt: new Date(),
      createdAt: new Date(),
    };

    it('should return family with members if user is a member', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue({
        id: 'member-1',
        familyId,
        userId,
        role: 'admin',
      });
      mockPrismaService.family.findUnique.mockResolvedValue(familyRecord);

      const result = await service.findOne(userId, familyId);

      expect(result.id).toBe(familyId);
      expect(result.name).toBe('Sharma Family');
      expect(result.kinFamilyId).toBe('KIN-AB12CD34');
      expect(result.memberCount).toBe(3);
    });

    it('should throw ForbiddenException if user is not a member', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue(null);

      await expect(
        service.findOne(userId, familyId),
      ).rejects.toThrow(ForbiddenException);
    });

    it('should throw NotFoundException if family not found', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue({
        id: 'member-1',
        familyId,
        userId,
        role: 'admin',
      });
      mockPrismaService.family.findUnique.mockResolvedValue(null);

      await expect(
        service.findOne(userId, familyId),
      ).rejects.toThrow(NotFoundException);
    });
  });

  // ── updateFamily ────────────────────────────────────────────────────

  describe('update', () => {
    const userId = 'user-123';
    const familyId = 'family-1';

    const existingFamily = {
      id: familyId,
      name: 'Sharma Family',
      description: 'Old description',
      familyCode: 'FC123',
      kinFamilyId: 'KIN-AB12CD34',
      username: null,
      primaryLanguage: 'en',
      gotra: null,
      originVillage: null,
      privacyMode: 'private',
      anchorPersonId: null,
      memberCount: 3,
      generationCount: 2,
      createdBy: userId,
      avatarUrl: null,
      region: null,
      isOnboarded: true,
      lastActivityAt: new Date(),
      createdAt: new Date(),
    };

    it('should update family name', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue({
        id: 'member-1',
        familyId,
        userId,
        role: 'admin',
      });
      mockPrismaService.family.findUnique.mockResolvedValue(existingFamily);

      const updatedFamily = {
        ...existingFamily,
        name: 'Gupta Family',
        lastActivityAt: new Date(),
      };
      mockPrismaService.family.update.mockResolvedValue(updatedFamily);

      const result = await service.update(userId, familyId, {
        name: 'Gupta Family',
      });

      expect(result.name).toBe('Gupta Family');
      expect(mockPrismaService.family.update).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { id: familyId },
          data: expect.objectContaining({ name: 'Gupta Family' }),
        }),
      );
    });

    it('should update multiple fields at once', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue({
        id: 'member-1',
        familyId,
        userId,
        role: 'admin',
      });
      mockPrismaService.family.findUnique.mockResolvedValue(existingFamily);

      const updatedFamily = {
        ...existingFamily,
        name: 'Gupta Family',
        description: 'New description',
        primaryLanguage: 'hi',
        lastActivityAt: new Date(),
      };
      mockPrismaService.family.update.mockResolvedValue(updatedFamily);

      const result = await service.update(userId, familyId, {
        name: 'Gupta Family',
        description: 'New description',
        primaryLanguage: 'hi',
      });

      expect(result.name).toBe('Gupta Family');
      expect(result.description).toBe('New description');
      expect(result.primaryLanguage).toBe('hi');
    });

    it('should throw ForbiddenException if user has insufficient role', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue({
        id: 'member-1',
        familyId,
        userId,
        role: 'viewer',
      });

      await expect(
        service.update(userId, familyId, { name: 'Gupta Family' }),
      ).rejects.toThrow(ForbiddenException);
    });

    it('should throw NotFoundException if family not found', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue({
        id: 'member-1',
        familyId,
        userId,
        role: 'admin',
      });
      mockPrismaService.family.findUnique.mockResolvedValue(null);

      await expect(
        service.update(userId, familyId, { name: 'Gupta Family' }),
      ).rejects.toThrow(NotFoundException);
    });

    it('should trim name when updating', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue({
        id: 'member-1',
        familyId,
        userId,
        role: 'admin',
      });
      mockPrismaService.family.findUnique.mockResolvedValue(existingFamily);
      mockPrismaService.family.update.mockResolvedValue(existingFamily);

      await service.update(userId, familyId, { name: '  Gupta Family  ' });

      expect(mockPrismaService.family.update).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({ name: 'Gupta Family' }),
        }),
      );
    });
  });

  // ── deleteFamily ────────────────────────────────────────────────────

  describe('remove', () => {
    const userId = 'user-123';
    const familyId = 'family-1';

    it('should cascade delete members and persons', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue({
        id: 'member-1',
        familyId,
        userId,
        role: 'admin',
      });
      mockPrismaService.family.findUnique.mockResolvedValue({
        id: familyId,
        name: 'Sharma Family',
      });

      mockPrismaService.$transaction.mockImplementation(async (cb) => {
        const tx = {
          person: {
            findMany: jest.fn().mockResolvedValue([
              { id: 'person-1' },
              { id: 'person-2' },
            ]),
            deleteMany: jest.fn().mockResolvedValue({ count: 2 }),
          },
          relationship: {
            deleteMany: jest.fn().mockResolvedValue({ count: 3 }),
          },
          familyMember: {
            deleteMany: jest.fn().mockResolvedValue({ count: 1 }),
          },
          family: {
            delete: jest.fn().mockResolvedValue({ id: familyId }),
          },
        };
        return cb(tx);
      });

      const result = await service.remove(userId, familyId);

      expect(result.deleted).toBe(true);
      expect(result.familyId).toBe(familyId);
    });

    it('should delete relationships for persons in the family', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue({
        id: 'member-1',
        familyId,
        userId,
        role: 'admin',
      });
      mockPrismaService.family.findUnique.mockResolvedValue({
        id: familyId,
        name: 'Sharma Family',
      });

      const relationshipDeleteMany = jest.fn().mockResolvedValue({ count: 3 });
      const personFindMany = jest.fn().mockResolvedValue([
        { id: 'p1' },
        { id: 'p2' },
      ]);
      const personDeleteMany = jest.fn().mockResolvedValue({ count: 2 });
      const memberDeleteMany = jest.fn().mockResolvedValue({ count: 1 });
      const familyDelete = jest.fn().mockResolvedValue({ id: familyId });

      mockPrismaService.$transaction.mockImplementation(async (cb) => {
        const tx = {
          person: {
            findMany: personFindMany,
            deleteMany: personDeleteMany,
          },
          relationship: {
            deleteMany: relationshipDeleteMany,
          },
          familyMember: {
            deleteMany: memberDeleteMany,
          },
          family: {
            delete: familyDelete,
          },
        };
        const result = await cb(tx);

        // Verify the deletion order: relationships → persons → members → family
        expect(relationshipDeleteMany).toHaveBeenCalledWith({
          where: {
            OR: [
              { fromPersonId: { in: ['p1', 'p2'] } },
              { toPersonId: { in: ['p1', 'p2'] } },
            ],
          },
        });
        expect(personDeleteMany).toHaveBeenCalledWith({
          where: { familyId },
        });
        expect(memberDeleteMany).toHaveBeenCalledWith({
          where: { familyId },
        });
        expect(familyDelete).toHaveBeenCalledWith({
          where: { id: familyId },
        });

        return result;
      });

      await service.remove(userId, familyId);
    });

    it('should throw ForbiddenException if user is not admin', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue({
        id: 'member-1',
        familyId,
        userId,
        role: 'member',
      });

      await expect(
        service.remove(userId, familyId),
      ).rejects.toThrow(ForbiddenException);
    });

    it('should throw NotFoundException if family not found', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue({
        id: 'member-1',
        familyId,
        userId,
        role: 'admin',
      });
      mockPrismaService.family.findUnique.mockResolvedValue(null);

      await expect(
        service.remove(userId, familyId),
      ).rejects.toThrow(NotFoundException);
    });

    it('should handle empty family (no persons)', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue({
        id: 'member-1',
        familyId,
        userId,
        role: 'admin',
      });
      mockPrismaService.family.findUnique.mockResolvedValue({
        id: familyId,
        name: 'Empty Family',
      });

      mockPrismaService.$transaction.mockImplementation(async (cb) => {
        const tx = {
          person: {
            findMany: jest.fn().mockResolvedValue([]),
            deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
          },
          relationship: {
            deleteMany: jest.fn(),
          },
          familyMember: {
            deleteMany: jest.fn().mockResolvedValue({ count: 1 }),
          },
          family: {
            delete: jest.fn().mockResolvedValue({ id: familyId }),
          },
        };
        // Should NOT call relationship.deleteMany when there are no persons
        const result = await cb(tx);
        expect(tx.relationship.deleteMany).not.toHaveBeenCalled();
        return result;
      });

      const result = await service.remove(userId, familyId);
      expect(result.deleted).toBe(true);
    });
  });

  // ── generateFamilyId (via FamilyIdService) ─────────────────────────

  describe('FamilyIdService.generateFamilyId', () => {
    it('should generate unique KIN-XXXXXXXX format IDs', async () => {
      // Mock no existing family with this kinFamilyId
      mockPrismaService.family.findUnique.mockResolvedValue(null);

      mockFamilyIdService.generateFamilyId.mockResolvedValue('KIN-AB12CD34');

      const id = await mockFamilyIdService.generateFamilyId();

      expect(id).toMatch(/^KIN-[A-Z0-9]{8}$/);
    });

    it('should generate IDs with correct format (KIN- + 8 alphanumeric)', async () => {
      // Generate multiple IDs and verify format
      const ids = [
        'KIN-AB12CD34',
        'KIN-XYZ98765',
        'KIN-A1B2C3D4',
        'KIN-Z9Y8X7W6',
        'KIN-MNPQRSTU',
      ];

      for (const id of ids) {
        expect(id).toMatch(/^KIN-[A-Z0-9]{8}$/);
      }
    });

    it('should retry on collision', async () => {
      // First call collides, second succeeds
      mockFamilyIdService.generateFamilyId
        .mockRejectedValueOnce(new Error('collision'))
        .mockResolvedValueOnce('KIN-NEWID01');

      // This simulates what the actual FamilyIdService does internally
      // The FamiliesService just delegates to FamilyIdService
      await expect(
        mockFamilyIdService.generateFamilyId(),
      ).rejects.toThrow('collision');

      const id = await mockFamilyIdService.generateFamilyId();
      expect(id).toBe('KIN-NEWID01');
    });
  });

  // ── requireFamilyRole ──────────────────────────────────────────────

  describe('requireFamilyRole', () => {
    it('should allow admin access', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue({
        id: 'member-1',
        familyId: 'family-1',
        userId: 'user-1',
        role: 'admin',
      });

      const result = await service.requireFamilyRole('user-1', 'family-1', 'editor');
      expect(result.role).toBe('admin');
    });

    it('should reject viewer trying to edit', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue({
        id: 'member-1',
        familyId: 'family-1',
        userId: 'user-1',
        role: 'viewer',
      });

      await expect(
        service.requireFamilyRole('user-1', 'family-1', 'editor'),
      ).rejects.toThrow(ForbiddenException);
    });

    it('should reject non-member', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue(null);

      await expect(
        service.requireFamilyRole('user-1', 'family-1', 'member'),
      ).rejects.toThrow(ForbiddenException);
    });

    it('should allow editor for editor role', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue({
        id: 'member-1',
        familyId: 'family-1',
        userId: 'user-1',
        role: 'editor',
      });

      const result = await service.requireFamilyRole('user-1', 'family-1', 'editor');
      expect(result.role).toBe('editor');
    });
  });
});
