import { Test, TestingModule } from '@nestjs/testing';
import { ViewerService } from './viewer.service';
import { PrismaService } from '../../prisma/prisma.service';
import {
  ForbiddenException,
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';

// ── Mock PrismaService ──────────────────────────────────────────────────

const mockPrismaService = {
  person: {
    findFirst: jest.fn(),
    findMany: jest.fn(),
    update: jest.fn(),
  },
  familyMember: {
    findUnique: jest.fn(),
  },
  personLinkInvitation: {
    findFirst: jest.fn(),
    create: jest.fn(),
    update: jest.fn(),
  },
  $transaction: jest.fn((fn: any) =>
    typeof fn === 'function' ? fn(mockPrismaService) : Promise.resolve(),
  ),
};

// ── Test fixtures ───────────────────────────────────────────────────────

const FAMILY_ID = 'family-1';
const USER_ID = 'user-1';
const PERSON_ID = 'person-1';
const OTHER_USER_ID = 'user-2';

const familyMemberShip = (role = 'member') => ({
  id: 'fm-1',
  familyId: FAMILY_ID,
  userId: USER_ID,
  role,
});

const personFixture = (overrides: Partial<any> = {}) => ({
  id: PERSON_ID,
  familyId: FAMILY_ID,
  name: 'Test Person',
  linkedUserId: null,
  linkedAt: null,
  deletedAt: null,
  ...overrides,
});

describe('ViewerService', () => {
  let service: ViewerService;

  beforeEach(async () => {
    jest.clearAllMocks();

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        ViewerService,
        { provide: PrismaService, useValue: mockPrismaService },
      ],
    }).compile();

    service = module.get<ViewerService>(ViewerService);
  });

  // ── resolveViewer ──────────────────────────────────────────────────────

  describe('resolveViewer', () => {
    it('returns the linked Person when linkedUserId matches', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue(familyMemberShip());
      mockPrismaService.person.findFirst.mockResolvedValueOnce({
        id: PERSON_ID,
        linkedAt: new Date(),
      });

      const result = await service.resolveViewer(USER_ID, FAMILY_ID);

      expect(result).toEqual({
        familyId: FAMILY_ID,
        viewerPersonId: PERSON_ID,
        resolution: 'linked',
        isLinked: true,
      });
    });

    it('falls back to isAnchor when no link exists', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue(familyMemberShip());
      // First findFirst (linked lookup) → null
      mockPrismaService.person.findFirst.mockResolvedValueOnce(null);
      // Second findFirst (anchor lookup) → returns anchor
      mockPrismaService.person.findFirst.mockResolvedValueOnce({ id: 'anchor-1' });

      const result = await service.resolveViewer(USER_ID, FAMILY_ID);

      expect(result).toEqual({
        familyId: FAMILY_ID,
        viewerPersonId: 'anchor-1',
        resolution: 'anchor',
        isLinked: false,
      });
    });

    it('returns null resolution when neither link nor anchor exists', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue(familyMemberShip());
      mockPrismaService.person.findFirst.mockResolvedValue(null);

      const result = await service.resolveViewer(USER_ID, FAMILY_ID);

      expect(result).toEqual({
        familyId: FAMILY_ID,
        viewerPersonId: null,
        resolution: 'none',
        isLinked: false,
      });
    });

    it('throws ForbiddenException when user is not a family member', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue(null);

      await expect(service.resolveViewer(USER_ID, FAMILY_ID)).rejects.toThrow(
        ForbiddenException,
      );
      expect(mockPrismaService.person.findFirst).not.toHaveBeenCalled();
    });
  });

  // ── claimPerson ────────────────────────────────────────────────────────

  describe('claimPerson', () => {
    it('links the user to an unclaimed Person (happy path)', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue(familyMemberShip());
      mockPrismaService.person.findFirst
        .mockResolvedValueOnce(personFixture({ linkedUserId: null })) // initial lookup
        .mockResolvedValueOnce(null); // duplicate-prevention lookup
      const linkedAt = new Date();
      mockPrismaService.person.update.mockResolvedValue({
        id: PERSON_ID,
        linkedUserId: USER_ID,
        linkedAt,
      });

      const result = await service.claimPerson(USER_ID, FAMILY_ID, PERSON_ID);

      expect(result).toEqual({
        personId: PERSON_ID,
        linkedUserId: USER_ID,
        linkedAt,
      });
      expect(mockPrismaService.person.update).toHaveBeenCalledWith({
        where: { id: PERSON_ID },
        data: { linkedUserId: USER_ID, linkedAt: expect.any(Date) },
        select: { id: true, linkedUserId: true, linkedAt: true },
      });
    });

    it('throws NotFoundException when Person does not exist', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue(familyMemberShip());
      mockPrismaService.person.findFirst.mockResolvedValue(null);

      await expect(
        service.claimPerson(USER_ID, FAMILY_ID, PERSON_ID),
      ).rejects.toThrow(NotFoundException);
    });

    it('throws ForbiddenException when Person is already claimed by another user (impersonation prevention)', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue(familyMemberShip());
      mockPrismaService.person.findFirst.mockResolvedValue(
        personFixture({ linkedUserId: OTHER_USER_ID }),
      );

      await expect(
        service.claimPerson(USER_ID, FAMILY_ID, PERSON_ID),
      ).rejects.toThrow(ForbiddenException);
    });

    it('throws ForbiddenException when user is already linked to a different Person (duplicate prevention)', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue(familyMemberShip());
      mockPrismaService.person.findFirst
        .mockResolvedValueOnce(personFixture({ linkedUserId: null })) // target Person
        .mockResolvedValueOnce({
          id: 'person-other',
          name: 'Other Person',
        }); // existing link

      await expect(
        service.claimPerson(USER_ID, FAMILY_ID, PERSON_ID),
      ).rejects.toThrow(ForbiddenException);
    });

    it('throws ForbiddenException when user is not a family member', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue(null);

      await expect(
        service.claimPerson(USER_ID, FAMILY_ID, PERSON_ID),
      ).rejects.toThrow(ForbiddenException);
    });
  });

  // ── unlinkPerson ───────────────────────────────────────────────────────

  describe('unlinkPerson', () => {
    it('unlinks when the user owns the link', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue(familyMemberShip());
      mockPrismaService.person.findFirst.mockResolvedValue(
        personFixture({ linkedUserId: USER_ID }),
      );
      mockPrismaService.person.update.mockResolvedValue({});

      const result = await service.unlinkPerson(USER_ID, FAMILY_ID, PERSON_ID);

      expect(result).toEqual({ personId: PERSON_ID, unlinked: true });
      expect(mockPrismaService.person.update).toHaveBeenCalledWith({
        where: { id: PERSON_ID },
        data: { linkedUserId: null, linkedAt: null },
      });
    });

    it('unlinks when the user is a family admin (not the owner)', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue(
        familyMemberShip('admin'),
      );
      mockPrismaService.person.findFirst.mockResolvedValue(
        personFixture({ linkedUserId: OTHER_USER_ID }),
      );

      const result = await service.unlinkPerson(USER_ID, FAMILY_ID, PERSON_ID);

      expect(result).toEqual({ personId: PERSON_ID, unlinked: true });
    });

    it('throws ForbiddenException when a non-owner, non-admin tries to unlink', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue(
        familyMemberShip('member'),
      );
      mockPrismaService.person.findFirst.mockResolvedValue(
        personFixture({ linkedUserId: OTHER_USER_ID }),
      );

      await expect(
        service.unlinkPerson(USER_ID, FAMILY_ID, PERSON_ID),
      ).rejects.toThrow(ForbiddenException);
    });

    it('is idempotent when Person is already unlinked', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue(
        familyMemberShip('admin'),
      );
      mockPrismaService.person.findFirst.mockResolvedValue(
        personFixture({ linkedUserId: null }),
      );

      const result = await service.unlinkPerson(USER_ID, FAMILY_ID, PERSON_ID);

      expect(result).toEqual({ personId: PERSON_ID, unlinked: true });
      expect(mockPrismaService.person.update).not.toHaveBeenCalled();
    });

    it('throws NotFoundException when Person does not exist', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue(familyMemberShip());
      mockPrismaService.person.findFirst.mockResolvedValue(null);

      await expect(
        service.unlinkPerson(USER_ID, FAMILY_ID, PERSON_ID),
      ).rejects.toThrow(NotFoundException);
    });
  });

  // ── invitePerson ───────────────────────────────────────────────────────

  describe('invitePerson', () => {
    it('creates an invitation when editor+ invites (happy path)', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue(
        familyMemberShip('editor'),
      );
      mockPrismaService.person.findFirst.mockResolvedValue(
        personFixture({ linkedUserId: null, name: 'Aarav' }),
      );
      const inviteRow = {
        code: 'abcd1234',
        recipientEmail: 'aarav@example.com',
        recipientPhone: null,
        expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
        createdAt: new Date(),
      };
      mockPrismaService.personLinkInvitation.create.mockResolvedValue(inviteRow);

      const result = await service.invitePerson(USER_ID, FAMILY_ID, PERSON_ID, {
        recipientEmail: 'aarav@example.com',
        recipientName: 'Aarav',
      });

      expect(result.personId).toBe(PERSON_ID);
      expect(result.invitationCode).toBe('abcd1234');
      expect(result.recipientEmail).toBe('aarav@example.com');
      expect(mockPrismaService.personLinkInvitation.create).toHaveBeenCalled();
    });

    it('throws BadRequestException when neither email nor phone is provided', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue(
        familyMemberShip('editor'),
      );

      await expect(
        service.invitePerson(USER_ID, FAMILY_ID, PERSON_ID, {}),
      ).rejects.toThrow(BadRequestException);
    });

    it('throws ForbiddenException when a viewer-role member tries to invite', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue(
        familyMemberShip('viewer'),
      );

      await expect(
        service.invitePerson(USER_ID, FAMILY_ID, PERSON_ID, {
          recipientEmail: 'x@example.com',
        }),
      ).rejects.toThrow(ForbiddenException);
    });

    it('throws ForbiddenException when Person is already claimed', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue(
        familyMemberShip('editor'),
      );
      mockPrismaService.person.findFirst.mockResolvedValue(
        personFixture({ linkedUserId: OTHER_USER_ID }),
      );

      await expect(
        service.invitePerson(USER_ID, FAMILY_ID, PERSON_ID, {
          recipientEmail: 'x@example.com',
        }),
      ).rejects.toThrow(ForbiddenException);
    });

    it('throws NotFoundException when Person does not exist', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue(
        familyMemberShip('editor'),
      );
      mockPrismaService.person.findFirst.mockResolvedValue(null);

      await expect(
        service.invitePerson(USER_ID, FAMILY_ID, PERSON_ID, {
          recipientEmail: 'x@example.com',
        }),
      ).rejects.toThrow(NotFoundException);
    });
  });

  // ── acceptInvitation ───────────────────────────────────────────────────

  describe('acceptInvitation', () => {
    const validInvite = {
      id: 'inv-1',
      familyId: FAMILY_ID,
      personId: PERSON_ID,
      code: 'abcd1234',
      inviterUserId: 'inviter-1',
      status: 'pending',
      expiresAt: new Date(Date.now() + 60 * 60 * 1000),
    };

    it('accepts a pending invitation and links the user (happy path)', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue(familyMemberShip());
      mockPrismaService.personLinkInvitation.findFirst.mockResolvedValue(validInvite);
      mockPrismaService.person.findFirst
        .mockResolvedValueOnce(personFixture({ linkedUserId: null })) // target Person
        .mockResolvedValueOnce(null); // duplicate-prevention check
      mockPrismaService.person.update.mockResolvedValue({});
      mockPrismaService.personLinkInvitation.update.mockResolvedValue({});

      const result = await service.acceptInvitation(
        USER_ID,
        FAMILY_ID,
        'abcd1234',
      );

      expect(result.personId).toBe(PERSON_ID);
      expect(result.linkedUserId).toBe(USER_ID);
      expect(result.invitationCode).toBe('abcd1234');
      expect(mockPrismaService.$transaction).toHaveBeenCalled();
    });

    it('throws NotFoundException when invitation does not exist', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue(familyMemberShip());
      mockPrismaService.personLinkInvitation.findFirst.mockResolvedValue(null);

      await expect(
        service.acceptInvitation(USER_ID, FAMILY_ID, 'bad-code'),
      ).rejects.toThrow(NotFoundException);
    });

    it('throws ForbiddenException when invitation has expired', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue(familyMemberShip());
      mockPrismaService.personLinkInvitation.findFirst.mockResolvedValue({
        ...validInvite,
        expiresAt: new Date(Date.now() - 1000), // expired
      });

      await expect(
        service.acceptInvitation(USER_ID, FAMILY_ID, 'abcd1234'),
      ).rejects.toThrow(ForbiddenException);
    });

    it('throws ForbiddenException when target Person is already claimed', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue(familyMemberShip());
      mockPrismaService.personLinkInvitation.findFirst.mockResolvedValue(validInvite);
      mockPrismaService.person.findFirst.mockResolvedValueOnce(
        personFixture({ linkedUserId: OTHER_USER_ID }),
      );

      await expect(
        service.acceptInvitation(USER_ID, FAMILY_ID, 'abcd1234'),
      ).rejects.toThrow(ForbiddenException);
    });

    it('throws ForbiddenException when user is already linked to a different Person', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue(familyMemberShip());
      mockPrismaService.personLinkInvitation.findFirst.mockResolvedValue(validInvite);
      mockPrismaService.person.findFirst
        .mockResolvedValueOnce(personFixture({ linkedUserId: null })) // target
        .mockResolvedValueOnce({ id: 'person-other', name: 'Other' }); // existing link

      await expect(
        service.acceptInvitation(USER_ID, FAMILY_ID, 'abcd1234'),
      ).rejects.toThrow(ForbiddenException);
    });

    it('throws ForbiddenException when user is not a family member', async () => {
      mockPrismaService.familyMember.findUnique.mockResolvedValue(null);

      await expect(
        service.acceptInvitation(USER_ID, FAMILY_ID, 'abcd1234'),
      ).rejects.toThrow(ForbiddenException);
    });
  });
});
