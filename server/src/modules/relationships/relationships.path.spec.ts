import { Test, TestingModule } from '@nestjs/testing';
import { RelationshipsService } from './relationships.service';
import { PrismaService } from '../../prisma/prisma.service';
import { KinrelGateway } from '../gateway/kinrel.gateway';
import { GraphService } from '../graph/graph.service';
import { GraphEngineService } from '../graph/graph-engine.service';
import {
  ForbiddenException,
  BadRequestException,
} from '@nestjs/common';

// ── Mocks ───────────────────────────────────────────────────────────────

const mockPrismaService = {
  relationship: {
    findFirst: jest.fn(),
    findMany: jest.fn(),
    count: jest.fn(),
    create: jest.fn(),
    delete: jest.fn(),
  },
  person: {
    findFirst: jest.fn(),
    findUnique: jest.fn(),
  },
  family: { update: jest.fn() },
  familyMember: { findUnique: jest.fn() },
  relationshipPathCache: {
    findUnique: jest.fn(),
    upsert: jest.fn(),
  },
  $transaction: jest.fn((fn: any) =>
    typeof fn === 'function' ? fn(mockPrismaService) : Promise.resolve([]),
  ),
};

const mockGateway = {
  emitToFamily: jest.fn(),
};

const mockGraphService = {
  invalidateFlatGraphCache: jest.fn(),
};

const mockGraphEngineService = {
  findPath: jest.fn(),
};

// ── Fixtures ────────────────────────────────────────────────────────────

const FAMILY_ID = 'family-1';
const USER_ID = 'user-1';
const FROM_ID = 'p1';
const TO_ID = 'p2';

describe('RelationshipsService — getRelationshipPath (v2.2)', () => {
  let service: RelationshipsService;

  beforeEach(async () => {
    jest.clearAllMocks();

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        RelationshipsService,
        { provide: PrismaService, useValue: mockPrismaService },
        { provide: KinrelGateway, useValue: mockGateway },
        { provide: GraphService, useValue: mockGraphService },
        { provide: GraphEngineService, useValue: mockGraphEngineService },
      ],
    }).compile();

    service = module.get<RelationshipsService>(RelationshipsService);
  });

  it('returns "self" when from === to', async () => {
    mockPrismaService.familyMember.findUnique.mockResolvedValue({
      id: 'fm-1',
      familyId: FAMILY_ID,
      userId: USER_ID,
      role: 'member',
    });

    const result = await service.getRelationshipPath(
      USER_ID,
      FAMILY_ID,
      FROM_ID,
      FROM_ID,
    );

    expect(result.found).toBe(true);
    expect(result.distance).toBe(0);
    expect(result.kinshipTerm).toBe('self');
    expect(result.path).toEqual([]);
    expect(result.cached).toBe(false);
    expect(mockGraphEngineService.findPath).not.toHaveBeenCalled();
  });

  it('returns cached path when cache hit is fresh', async () => {
    mockPrismaService.familyMember.findUnique.mockResolvedValue({
      id: 'fm-1',
      familyId: FAMILY_ID,
      userId: USER_ID,
      role: 'member',
    });
    const futureDate = new Date(Date.now() + 60 * 1000);
    const pathArr = [
      {
        personId: 'p2',
        personName: 'Father',
        relationshipType: 'father',
        direction: 'up',
      },
    ];
    mockPrismaService.relationshipPathCache.findUnique.mockResolvedValue({
      id: 'cache-1',
      familyId: FAMILY_ID,
      fromPersonId: FROM_ID,
      toPersonId: TO_ID,
      path: JSON.stringify(pathArr),
      kinshipTerm: 'father',
      kinshipTermHi: 'पिता',
      distance: 1,
      expiresAt: futureDate,
    });

    const result = await service.getRelationshipPath(
      USER_ID,
      FAMILY_ID,
      FROM_ID,
      TO_ID,
    );

    expect(result.cached).toBe(true);
    expect(result.found).toBe(true);
    expect(result.distance).toBe(1);
    expect(result.kinshipTerm).toBe('father');
    expect(result.kinshipTermHindi).toBe('पिता');
    expect(result.path).toEqual(pathArr);
    expect(mockGraphEngineService.findPath).not.toHaveBeenCalled();
    expect(mockPrismaService.relationshipPathCache.upsert).not.toHaveBeenCalled();
  });

  it('computes fresh path on cache miss and persists it', async () => {
    mockPrismaService.familyMember.findUnique.mockResolvedValue({
      id: 'fm-1',
      familyId: FAMILY_ID,
      userId: USER_ID,
      role: 'member',
    });
    mockPrismaService.relationshipPathCache.findUnique.mockResolvedValue(null);
    const path = [
      {
        personId: 'p2',
        personName: 'Father',
        relationshipType: 'father',
        direction: 'up',
      },
    ];
    mockGraphEngineService.findPath.mockResolvedValue({
      found: true,
      path,
      distance: 1,
      kinshipTerm: 'father',
      kinshipTermHindi: 'पिता',
    });
    mockPrismaService.relationshipPathCache.upsert.mockResolvedValue({});

    const result = await service.getRelationshipPath(
      USER_ID,
      FAMILY_ID,
      FROM_ID,
      TO_ID,
    );

    expect(result.cached).toBe(false);
    expect(result.found).toBe(true);
    expect(result.distance).toBe(1);
    expect(result.kinshipTerm).toBe('father');
    expect(mockGraphEngineService.findPath).toHaveBeenCalledWith(
      FAMILY_ID,
      FROM_ID,
      TO_ID,
    );
    expect(mockPrismaService.relationshipPathCache.upsert).toHaveBeenCalled();
    const upsertArg = mockPrismaService.relationshipPathCache.upsert.mock.calls[0][0];
    expect(upsertArg.where.familyId_fromPersonId_toPersonId).toEqual({
      familyId: FAMILY_ID,
      fromPersonId: FROM_ID,
      toPersonId: TO_ID,
    });
    expect(upsertArg.create.kinshipTerm).toBe('father');
    expect(upsertArg.create.distance).toBe(1);
  });

  it('recomputes when cache hit is expired', async () => {
    mockPrismaService.familyMember.findUnique.mockResolvedValue({
      id: 'fm-1',
      familyId: FAMILY_ID,
      userId: USER_ID,
      role: 'member',
    });
    const pastDate = new Date(Date.now() - 60 * 1000);
    mockPrismaService.relationshipPathCache.findUnique.mockResolvedValue({
      id: 'cache-1',
      familyId: FAMILY_ID,
      fromPersonId: FROM_ID,
      toPersonId: TO_ID,
      path: '[]',
      kinshipTerm: null,
      kinshipTermHi: null,
      distance: -1,
      expiresAt: pastDate,
    });
    mockGraphEngineService.findPath.mockResolvedValue({
      found: true,
      path: [
        {
          personId: 'p2',
          personName: 'Mother',
          relationshipType: 'mother',
          direction: 'up',
        },
      ],
      distance: 1,
      kinshipTerm: 'mother',
      kinshipTermHindi: 'माता',
    });
    mockPrismaService.relationshipPathCache.upsert.mockResolvedValue({});

    const result = await service.getRelationshipPath(
      USER_ID,
      FAMILY_ID,
      FROM_ID,
      TO_ID,
    );

    expect(result.cached).toBe(false);
    expect(result.kinshipTerm).toBe('mother');
    expect(mockGraphEngineService.findPath).toHaveBeenCalled();
  });

  it('returns found=false when no path exists', async () => {
    mockPrismaService.familyMember.findUnique.mockResolvedValue({
      id: 'fm-1',
      familyId: FAMILY_ID,
      userId: USER_ID,
      role: 'member',
    });
    mockPrismaService.relationshipPathCache.findUnique.mockResolvedValue(null);
    mockGraphEngineService.findPath.mockResolvedValue({
      found: false,
      path: [],
      distance: -1,
    });
    mockPrismaService.relationshipPathCache.upsert.mockResolvedValue({});

    const result = await service.getRelationshipPath(
      USER_ID,
      FAMILY_ID,
      FROM_ID,
      TO_ID,
    );

    expect(result.found).toBe(false);
    expect(result.distance).toBe(-1);
    expect(result.path).toEqual([]);
  });

  it('throws ForbiddenException when user is not a family member', async () => {
    mockPrismaService.familyMember.findUnique.mockResolvedValue(null);

    await expect(
      service.getRelationshipPath(USER_ID, FAMILY_ID, FROM_ID, TO_ID),
    ).rejects.toThrow(ForbiddenException);
    expect(mockGraphEngineService.findPath).not.toHaveBeenCalled();
  });

  it('continues even if cache write fails (non-fatal)', async () => {
    mockPrismaService.familyMember.findUnique.mockResolvedValue({
      id: 'fm-1',
      familyId: FAMILY_ID,
      userId: USER_ID,
      role: 'member',
    });
    mockPrismaService.relationshipPathCache.findUnique.mockResolvedValue(null);
    mockGraphEngineService.findPath.mockResolvedValue({
      found: true,
      path: [],
      distance: 0,
      kinshipTerm: 'self',
      kinshipTermHindi: 'स्वयं',
    });
    mockPrismaService.relationshipPathCache.upsert.mockRejectedValue(
      new Error('DB write failed'),
    );

    const result = await service.getRelationshipPath(
      USER_ID,
      FAMILY_ID,
      FROM_ID,
      TO_ID,
    );

    expect(result.found).toBe(true);
    expect(result.kinshipTerm).toBe('self');
  });
});
