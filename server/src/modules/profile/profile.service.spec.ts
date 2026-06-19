import { ProfileService } from './profile.service';
import { PrismaService } from '../../prisma/prisma.service';
import { GraphEngineService } from '../graph/graph-engine.service';
import { KinshipService } from '../kinship/kinship.service';

// ── Mock Services ────────────────────────────────────────────────────

const mockPrismaService = {
  familyMember: {
    findUnique: jest.fn(),
  },
  person: {
    findFirst: jest.fn(),
  },
  user: {
    findUnique: jest.fn(),
  },
  family: {
    findUnique: jest.fn(),
  },
  personPrivacySetting: {
    findUnique: jest.fn(),
    create: jest.fn(),
    update: jest.fn(),
  },
  dataAccessLog: {
    create: jest.fn(),
  },
};

const mockGraphEngineService = {
  getAllRelationships: jest.fn(),
  buildGraph: jest.fn(),
  findPath: jest.fn(),
};

const mockKinshipService = {
  getByKey: jest.fn(),
  lookup: jest.fn(),
  findByNativeTerm: jest.fn(),
};

// ── Shared Test Data ─────────────────────────────────────────────────

const userId = 'user-1';
const familyId = 'family-1';
const personId = 'person-1';

const mockPerson = {
  id: personId,
  familyId,
  name: 'Rahul Sharma',
  gender: 'male',
  dateOfBirth: new Date('1990-01-01'),
  city: 'Delhi',
  gotra: 'Bharadwaj',
  isDeceased: false,
  deletedAt: null,
  birthYear: 1990,
  occupation: 'Engineer',
  privacyLevel: 'family',
  notes: 'Some notes',
  sideOfFamily: 'paternal',
  generationIndex: 2,
  isAnchor: false,
  photoUrl: 'https://example.com/photo.jpg',
  photoThumb: 'https://example.com/thumb.jpg',
  username: 'rahul_s',
  bloodGroup: 'O+',
  education: 'B.Tech',
  biography: 'A software engineer',
  email: 'rahul@example.com',
  phone: '+91-9876543210',
  address: '{"city":"Delhi"}',
  anniversaryDate: null,
};

const mockPrivacy = {
  id: 'privacy-1',
  personId,
  visibility: 'family',
  searchable: true,
  matrimonialEligible: true,
  communityFeatures: true,
  minorFlag: false,
  photoConsent: true,
  healthConsent: false,
  gotraVisibility: 'family',
  showPhone: false,
  showEmail: false,
  showAddress: false,
  showDob: true,
  showAge: true,
  showOccupation: true,
  showEducation: true,
  showBloodGroup: false,
  showAnniversary: false,
  profileVisibleTo: 'family',
};

const mockComputedRelationships = [
  {
    personId: 'person-2',
    personName: 'Suresh Sharma',
    relationshipKey: 'father',
    computedTerm: 'father',
    computedTermHindi: 'पिता',
    distance: 1,
    path: [
      { personId: 'person-2', personName: 'Suresh Sharma', relationshipType: 'father', direction: 'up' },
    ],
  },
  {
    personId: 'person-3',
    personName: 'Anita Sharma',
    relationshipKey: 'mother',
    computedTerm: 'mother',
    computedTermHindi: 'माता',
    distance: 1,
    path: [
      { personId: 'person-3', personName: 'Anita Sharma', relationshipType: 'mother', direction: 'up' },
    ],
  },
  {
    personId: 'person-4',
    personName: 'Priya Sharma',
    relationshipKey: 'wife',
    computedTerm: 'wife',
    computedTermHindi: 'पत्नी',
    distance: 1,
    path: [
      { personId: 'person-4', personName: 'Priya Sharma', relationshipType: 'wife', direction: 'sideways' },
    ],
  },
];

/**
 * Helper to set up the "self viewer" mock chain.
 * The service calls person.findFirst multiple times:
 *   1st call: loadPerson(familyId, personId)
 *   2nd call: own person lookup (by username)
 * We use mockImplementation to handle both based on the where clause.
 */
function setupSelfViewerMocks() {
  mockPrismaService.familyMember.findUnique.mockResolvedValue({
    id: 'member-1', familyId, userId, role: 'admin',
  });
  mockPrismaService.user.findUnique.mockResolvedValue({
    id: userId, username: 'rahul_s',
  });
  // person.findFirst is called twice: loadPerson + ownPerson lookup
  // Use mockImplementation to differentiate by the where clause
  mockPrismaService.person.findFirst.mockImplementation((args: any) => {
    if (args?.where?.id === personId && args?.where?.familyId === familyId) {
      return Promise.resolve(mockPerson); // loadPerson
    }
    if (args?.where?.username === 'rahul_s') {
      return Promise.resolve({ id: personId }); // own person → matches target → self
    }
    return Promise.resolve(null);
  });
  mockPrismaService.personPrivacySetting.findUnique.mockResolvedValue(mockPrivacy);
  mockPrismaService.dataAccessLog.create.mockResolvedValue({});
  mockGraphEngineService.getAllRelationships.mockResolvedValue(mockComputedRelationships);
  mockKinshipService.getByKey.mockReturnValue(null);
}

function setupMemberViewerMocks() {
  mockPrismaService.familyMember.findUnique.mockResolvedValue({
    id: 'member-2', familyId, userId: 'user-2', role: 'member',
  });
  mockPrismaService.user.findUnique.mockResolvedValue({
    id: 'user-2', username: 'other_user',
  });
  mockPrismaService.person.findFirst.mockImplementation((args: any) => {
    if (args?.where?.id === personId && args?.where?.familyId === familyId) {
      return Promise.resolve(mockPerson); // loadPerson
    }
    if (args?.where?.username === 'other_user') {
      return Promise.resolve({ id: 'different-person-id' }); // own person ≠ target → member
    }
    return Promise.resolve(null);
  });
  mockPrismaService.personPrivacySetting.findUnique.mockResolvedValue(mockPrivacy);
  mockPrismaService.dataAccessLog.create.mockResolvedValue({});
  mockGraphEngineService.getAllRelationships.mockResolvedValue(mockComputedRelationships);
  mockKinshipService.getByKey.mockReturnValue(null);
}

describe('ProfileService', () => {
  let service: ProfileService;

  beforeEach(async () => {
    jest.clearAllMocks();
    service = new ProfileService(
      mockPrismaService as any,
      mockGraphEngineService as any,
      mockKinshipService as any,
    );
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });

  // ══════════════════════════════════════════════════════════════════
  // getProfileWithKinship
  // ══════════════════════════════════════════════════════════════════

  describe('getProfileWithKinship', () => {
    it('should return profile with kinship information for self', async () => {
      setupSelfViewerMocks();

      const result = await service.getProfileWithKinship(userId, familyId, personId);

      expect(result).toBeDefined();
      expect(result.person).toBeDefined();
      expect(result.person.name).toBe('Rahul Sharma');
      expect(result.kinshipSummary).toBeDefined();
      expect(result.kinshipGraph).toBeDefined();
      expect(result.viewerRole).toBe('self');
      expect(result.readOnly).toBe(false);
    });

    it('should include privacy settings for self or admin', async () => {
      setupSelfViewerMocks();

      const result = await service.getProfileWithKinship(userId, familyId, personId);

      expect(result.privacy).toBeDefined();
      expect(result.privacy!.visibility).toBe('family');
      expect(result.privacy!.showDob).toBe(true);
    });

    it('should compute kinship coefficients for relationships', async () => {
      setupSelfViewerMocks();

      const result = await service.getProfileWithKinship(userId, familyId, personId);

      const fatherRel = result.kinshipGraph.find((r: any) => r.computedTerm === 'father');
      expect(fatherRel).toBeDefined();
      expect(fatherRel.kinshipCoefficient).toBe(0.5);

      const wifeRel = result.kinshipGraph.find((r: any) => r.computedTerm === 'wife');
      expect(wifeRel).toBeDefined();
      expect(wifeRel.kinshipCoefficient).toBe(0);
    });

    it('should classify relationships as blood, marital, or affinal', async () => {
      setupSelfViewerMocks();

      const result = await service.getProfileWithKinship(userId, familyId, personId);

      const fatherRel = result.kinshipGraph.find((r: any) => r.computedTerm === 'father');
      expect(fatherRel.relationType).toBe('blood');

      const wifeRel = result.kinshipGraph.find((r: any) => r.computedTerm === 'wife');
      expect(wifeRel.relationType).toBe('marital');
    });

    it('should compute kinship summary statistics', async () => {
      setupSelfViewerMocks();

      const result = await service.getProfileWithKinship(userId, familyId, personId);

      expect(result.kinshipSummary.totalRelationships).toBe(3);
      expect(result.kinshipSummary.bloodRelations).toBe(2); // father + mother
      expect(result.kinshipSummary.maritalRelations).toBe(1); // wife
      expect(result.kinshipSummary.maxKinshipCoefficient).toBe(0.5);
    });

    it('should determine lineage for relationships', async () => {
      setupSelfViewerMocks();

      const result = await service.getProfileWithKinship(userId, familyId, personId);

      const fatherRel = result.kinshipGraph.find((r: any) => r.computedTerm === 'father');
      expect(fatherRel.lineage).toBe('paternal');

      const motherRel = result.kinshipGraph.find((r: any) => r.computedTerm === 'mother');
      expect(motherRel.lineage).toBe('maternal');
    });

    it('should apply privacy filtering for non-self viewers', async () => {
      setupMemberViewerMocks();

      const result = await service.getProfileWithKinship('user-2', familyId, personId);

      // Non-self viewer should not see privacy settings
      expect(result.privacy).toBeNull();
      // Non-self viewer should not see phone, email based on privacy settings
      expect(result.person.phone).toBeNull();
      expect(result.person.email).toBeNull();
    });

    it('should throw NotFoundException for missing person', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue({
        id: 'member-1', familyId, userId, role: 'admin',
      });
      mockPrismaService.person.findFirst.mockResolvedValue(null);

      await expect(
        service.getProfileWithKinship(userId, familyId, 'nonexistent'),
      ).rejects.toThrow('Person not found');
    });

    it('should throw ForbiddenException for non-member on private family', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue(null);
      mockPrismaService.family.findUnique.mockResolvedValue({ isPublic: false });

      await expect(
        service.getProfileWithKinship('unknown-user', familyId, personId),
      ).rejects.toThrow('You are not a member of this family');
    });

    it('should continue with empty kinship if graph computation fails', async () => {
      setupSelfViewerMocks();
      mockGraphEngineService.getAllRelationships.mockRejectedValue(
        new Error('Graph computation failed'),
      );

      const result = await service.getProfileWithKinship(userId, familyId, personId);

      expect(result).toBeDefined();
      expect(result.kinshipGraph).toEqual([]);
      expect(result.kinshipSummary.totalRelationships).toBe(0);
    });

    it('should include multilingual translations when requested', async () => {
      setupSelfViewerMocks();
      mockKinshipService.getByKey.mockReturnValue({
        relationshipKey: 'father',
        englishTerm: 'Father',
        gender: 'male',
        lineage: 'paternal',
        relationshipCategory: 'immediate_family',
        translations: {
          hi: { native: 'पिता', latin: 'pita' },
          mr: { native: 'वडील', latin: 'vadil' },
          ta: { native: 'தந்தை', latin: 'thanthai' },
        },
        aliases: [],
      });

      const result = await service.getProfileWithKinship(
        userId,
        familyId,
        personId,
        { includeTranslations: true },
      );

      const fatherRel = result.kinshipGraph.find((r: any) => r.computedTerm === 'father');
      expect(fatherRel).toBeDefined();
      expect(fatherRel.translations).toBeDefined();
      expect(fatherRel.translations.hi.native).toBe('पिता');
    });

    it('should create default privacy settings if none exist', async () => {
      setupSelfViewerMocks();
      mockPrismaService.personPrivacySetting.findUnique.mockResolvedValue(null);
      mockPrismaService.personPrivacySetting.create.mockResolvedValue(mockPrivacy);

      const result = await service.getProfileWithKinship(userId, familyId, personId);

      expect(mockPrismaService.personPrivacySetting.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({ personId }),
        }),
      );
      expect(result).toBeDefined();
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // getKinshipGraph
  // ══════════════════════════════════════════════════════════════════

  describe('getKinshipGraph', () => {
    beforeEach(() => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue({
        id: 'member-1', familyId, userId, role: 'admin',
      });
      mockPrismaService.person.findFirst.mockImplementation((args: any) => {
        if (args?.where?.id === personId) return Promise.resolve({ id: personId, familyId, name: 'Rahul', gender: 'male' });
        if (args?.where?.username) return Promise.resolve({ id: personId });
        return Promise.resolve(null);
      });
      mockPrismaService.user.findUnique.mockResolvedValue({ id: userId, username: 'rahul_s' });
      mockPrismaService.dataAccessLog.create.mockResolvedValue({});

      mockGraphEngineService.getAllRelationships.mockResolvedValue([
        {
          personId: 'p2',
          personName: 'Uncle',
          relationshipKey: 'father→brother',
          computedTerm: 'uncle',
          computedTermHindi: 'चाचा',
          distance: 2,
          path: [
            { personId: 'p-f', personName: 'Father', relationshipType: 'father', direction: 'up' },
            { personId: 'p2', personName: 'Uncle', relationshipType: 'brother', direction: 'sideways' },
          ],
        },
        {
          personId: 'p3',
          personName: 'Wife',
          relationshipKey: 'wife',
          computedTerm: 'wife',
          computedTermHindi: 'पत्नी',
          distance: 1,
          path: [
            { personId: 'p3', personName: 'Wife', relationshipType: 'wife', direction: 'sideways' },
          ],
        },
      ]);

      mockKinshipService.getByKey.mockReturnValue(null);
    });

    it('should return filtered kinship graph', async () => {
      const result = await service.getKinshipGraph(userId, familyId, personId, {
        relationType: 'blood',
      });

      expect(result.items).toBeDefined();
      expect(result.items.every((r: any) => r.relationType === 'blood')).toBe(true);
    });

    it('should filter by minimum coefficient', async () => {
      const result = await service.getKinshipGraph(userId, familyId, personId, {
        minCoefficient: '0.1',
      });

      // Only uncle (0.25) passes, wife (0) is filtered out
      expect(result.items.length).toBe(1);
      expect(result.items[0].computedTerm).toBe('uncle');
    });

    it('should filter by maximum distance', async () => {
      const result = await service.getKinshipGraph(userId, familyId, personId, {
        maxDistance: '1',
      });

      // Only wife (distance 1) passes, uncle (distance 2) is filtered out
      expect(result.items.length).toBe(1);
      expect(result.items[0].computedTerm).toBe('wife');
    });

    it('should return summary with the graph', async () => {
      const result = await service.getKinshipGraph(userId, familyId, personId);

      expect(result.summary).toBeDefined();
      expect(result.total).toBe(2);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // updatePrivacySettings
  // ══════════════════════════════════════════════════════════════════

  describe('updatePrivacySettings', () => {
    beforeEach(() => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue({
        id: 'member-1', familyId, userId, role: 'admin',
      });
      mockPrismaService.person.findFirst.mockImplementation((args: any) => {
        if (args?.where?.id === personId) return Promise.resolve({ id: personId, familyId, name: 'Rahul' });
        if (args?.where?.username) return Promise.resolve({ id: personId }); // self
        return Promise.resolve(null);
      });
      mockPrismaService.user.findUnique.mockResolvedValue({ id: userId, username: 'rahul_s' });

      mockPrismaService.personPrivacySetting.findUnique.mockResolvedValue({
        id: 'privacy-1', personId, visibility: 'family', searchable: true,
        showPhone: false, showEmail: false, profileVisibleTo: 'family',
        matrimonialEligible: true, communityFeatures: true, minorFlag: false,
        photoConsent: true, healthConsent: false, gotraVisibility: 'family',
        showAddress: false, showDob: true, showAge: true, showOccupation: true,
        showEducation: true, showBloodGroup: false, showAnniversary: false,
      });

      mockPrismaService.personPrivacySetting.update.mockResolvedValue({
        id: 'privacy-1', personId, visibility: 'extended', searchable: true,
        showPhone: true, showEmail: true, profileVisibleTo: 'extended',
        matrimonialEligible: true, communityFeatures: true, minorFlag: false,
        photoConsent: true, healthConsent: false, gotraVisibility: 'family',
        showAddress: false, showDob: true, showAge: true, showOccupation: true,
        showEducation: true, showBloodGroup: false, showAnniversary: false,
      });

      mockPrismaService.dataAccessLog.create.mockResolvedValue({});
    });

    it('should update privacy settings for self', async () => {
      const result = await service.updatePrivacySettings(userId, familyId, personId, {
        visibility: 'extended',
        showPhone: true,
        showEmail: true,
        profileVisibleTo: 'extended',
      });

      expect(mockPrismaService.personPrivacySetting.update).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { personId },
          data: expect.objectContaining({
            visibility: 'extended',
            showPhone: true,
            showEmail: true,
            profileVisibleTo: 'extended',
          }),
        }),
      );
    });

    it('should throw ForbiddenException for non-admin non-self viewer', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue({
        id: 'member-2', familyId, userId: 'user-2', role: 'member',
      });
      mockPrismaService.user.findUnique.mockResolvedValue({ id: 'user-2', username: 'other' });
      mockPrismaService.person.findFirst.mockImplementation((args: any) => {
        if (args?.where?.id === personId) return Promise.resolve({ id: personId, familyId, name: 'Rahul' });
        if (args?.where?.username === 'other') return Promise.resolve({ id: 'different-person' });
        return Promise.resolve(null);
      });

      await expect(
        service.updatePrivacySettings('user-2', familyId, personId, { showPhone: true }),
      ).rejects.toThrow('Only the person themselves or a family admin can update privacy settings');
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // getKinshipSummary
  // ══════════════════════════════════════════════════════════════════

  describe('getKinshipSummary', () => {
    beforeEach(() => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue({
        id: 'member-1', familyId, userId, role: 'admin',
      });
      mockPrismaService.person.findFirst.mockImplementation((args: any) => {
        if (args?.where?.id === personId) return Promise.resolve({ id: personId, familyId, name: 'Rahul' });
        if (args?.where?.username) return Promise.resolve({ id: personId });
        return Promise.resolve(null);
      });
      mockPrismaService.user.findUnique.mockResolvedValue({ id: userId, username: 'rahul_s' });
      mockPrismaService.dataAccessLog.create.mockResolvedValue({});

      mockGraphEngineService.getAllRelationships.mockResolvedValue([
        {
          personId: 'p2',
          personName: 'Father',
          relationshipKey: 'father',
          computedTerm: 'father',
          computedTermHindi: 'पिता',
          distance: 1,
          path: [{ personId: 'p2', personName: 'Father', relationshipType: 'father', direction: 'up' }],
        },
      ]);

      mockKinshipService.getByKey.mockReturnValue(null);
    });

    it('should return kinship summary without full graph', async () => {
      const result = await service.getKinshipSummary(userId, familyId, personId);

      expect(result).toBeDefined();
      expect(result.totalRelationships).toBe(1);
      expect(result.bloodRelations).toBe(1);
      expect(result.maxKinshipCoefficient).toBe(0.5);
    });
  });
});
