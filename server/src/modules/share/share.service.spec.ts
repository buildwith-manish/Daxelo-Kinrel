import { Test, TestingModule } from '@nestjs/testing';
import { ShareService } from './share.service';
import { PrismaService } from '../../prisma/prisma.service';
import {
  BadRequestException,
  NotFoundException,
} from '@nestjs/common';

describe('ShareService', () => {
  let service: ShareService;
  let prisma: PrismaService;

  const mockPrisma = {
    shareableLink: {
      findUnique: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
    },
    family: {
      findUnique: jest.fn(),
    },
    person: {
      findUnique: jest.fn(),
    },
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        ShareService,
        { provide: PrismaService, useValue: mockPrisma },
      ],
    }).compile();

    service = module.get<ShareService>(ShareService);
    prisma = module.get<PrismaService>(PrismaService);

    jest.clearAllMocks();
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });

  // ─── createShareableLink ───────────────────────────────────────────
  describe('createShareableLink', () => {
    const userId = 'user-1';

    it('should throw BadRequestException for invalid card type', async () => {
      await expect(
        service.createShareableLink(userId, {
          cardType: 'invalid_type',
          title: 'Test',
        }),
      ).rejects.toThrow(BadRequestException);
      await expect(
        service.createShareableLink(userId, {
          cardType: 'invalid_type',
          title: 'Test',
        }),
      ).rejects.toThrow('Invalid card type');
    });

    it('should throw BadRequestException for empty title', async () => {
      await expect(
        service.createShareableLink(userId, {
          cardType: 'family_tree',
          title: '',
        }),
      ).rejects.toThrow(BadRequestException);
      await expect(
        service.createShareableLink(userId, {
          cardType: 'family_tree',
          title: '',
        }),
      ).rejects.toThrow('Title is required');
    });

    it('should throw BadRequestException for whitespace-only title', async () => {
      await expect(
        service.createShareableLink(userId, {
          cardType: 'family_tree',
          title: '   ',
        }),
      ).rejects.toThrow(BadRequestException);
    });

    it('should generate token and deep link', async () => {
      mockPrisma.shareableLink.create.mockImplementation(({ data }) =>
        Promise.resolve({
          id: 'link-1',
          ...data,
          viewCount: 0,
          shareCount: 0,
          createdAt: new Date(),
        }),
      );

      const result = await service.createShareableLink(userId, {
        cardType: 'family_tree',
        title: 'My Family',
      });

      expect(result.token).toBeDefined();
      expect(result.token.length).toBe(32); // randomBytes(16).toString('hex')
      expect(result.deepLinkUrl).toContain('kinrel://share/family_tree/');
      expect(result.cardType).toBe('family_tree');
    });

    it('should use provided deepLinkUrl if given', async () => {
      mockPrisma.shareableLink.create.mockImplementation(({ data }) =>
        Promise.resolve({
          id: 'link-1',
          ...data,
          viewCount: 0,
          shareCount: 0,
          createdAt: new Date(),
        }),
      );

      const result = await service.createShareableLink(userId, {
        cardType: 'birthday',
        title: 'Birthday Card',
        deepLinkUrl: 'https://example.com/share/abc',
      });

      expect(result.deepLinkUrl).toBe('https://example.com/share/abc');
    });

    it('should set expiry when expiresInDays provided', async () => {
      mockPrisma.shareableLink.create.mockImplementation(({ data }) =>
        Promise.resolve({
          id: 'link-1',
          ...data,
          viewCount: 0,
          shareCount: 0,
          createdAt: new Date(),
        }),
      );

      const result = await service.createShareableLink(userId, {
        cardType: 'milestone',
        title: 'Milestone',
        expiresInDays: 7,
      });

      expect(result.expiresAt).toBeDefined();
      const expiresAt = new Date(result.expiresAt as string | number | Date);
      const now = new Date();
      const diffDays = Math.ceil(
        (expiresAt.getTime() - now.getTime()) / (1000 * 60 * 60 * 24),
      );
      expect(diffDays).toBeGreaterThanOrEqual(6);
      expect(diffDays).toBeLessThanOrEqual(8);
    });

    it('should not set expiry when expiresInDays is not provided', async () => {
      mockPrisma.shareableLink.create.mockImplementation(({ data }) =>
        Promise.resolve({
          id: 'link-1',
          ...data,
          viewCount: 0,
          shareCount: 0,
          createdAt: new Date(),
        }),
      );

      const result = await service.createShareableLink(userId, {
        cardType: 'milestone',
        title: 'Milestone',
      });

      expect(result.expiresAt).toBeNull();
    });

    it('should accept all valid card types', async () => {
      const validTypes = [
        'family_tree',
        'birthday',
        'anniversary',
        'memorial',
        'milestone',
        'relationship_discovery',
        'festival_greeting',
      ];

      mockPrisma.shareableLink.create.mockImplementation(({ data }) =>
        Promise.resolve({
          id: 'link-1',
          ...data,
          viewCount: 0,
          shareCount: 0,
          createdAt: new Date(),
        }),
      );

      for (const cardType of validTypes) {
        const result = await service.createShareableLink(userId, {
          cardType,
          title: `Test ${cardType}`,
        });
        expect(result.cardType).toBe(cardType);
      }
    });
  });

  // ─── getShareStats ─────────────────────────────────────────────────
  describe('getShareStats', () => {
    it('should throw NotFoundException if not found', async () => {
      mockPrisma.shareableLink.findUnique.mockResolvedValue(null);

      await expect(service.getShareStats('nonexistent-token')).rejects.toThrow(
        NotFoundException,
      );
      await expect(service.getShareStats('nonexistent-token')).rejects.toThrow(
        'Shareable link not found',
      );
    });

    it('should return share stats for valid token', async () => {
      const linkData = {
        id: 'link-1',
        token: 'abc123',
        cardType: 'family_tree',
        title: 'My Family',
        viewCount: 10,
        shareCount: 3,
        expiresAt: null,
        createdAt: new Date(),
      };
      mockPrisma.shareableLink.findUnique.mockResolvedValue(linkData);

      const result = await service.getShareStats('abc123');

      expect(result.token).toBe('abc123');
      expect(result.viewCount).toBe(10);
      expect(result.shareCount).toBe(3);
      expect(result.cardType).toBe('family_tree');
    });
  });

  // ─── getSharedCard ─────────────────────────────────────────────────
  describe('getSharedCard', () => {
    it('should throw NotFoundException if not found', async () => {
      mockPrisma.shareableLink.findUnique.mockResolvedValue(null);

      await expect(service.getSharedCard('nonexistent')).rejects.toThrow(
        NotFoundException,
      );
      await expect(service.getSharedCard('nonexistent')).rejects.toThrow(
        'Shared card not found or has expired',
      );
    });

    it('should throw NotFoundException if expired', async () => {
      const expiredLink = {
        id: 'link-1',
        token: 'expired-token',
        cardType: 'family_tree',
        title: 'My Family',
        description: '',
        deepLinkUrl: 'kinrel://share/family_tree/expired-token',
        familyId: null,
        personId: null,
        viewCount: 5,
        shareCount: 1,
        expiresAt: new Date(Date.now() - 86400000), // yesterday
        createdAt: new Date(),
      };
      mockPrisma.shareableLink.findUnique.mockResolvedValue(expiredLink);

      await expect(service.getSharedCard('expired-token')).rejects.toThrow(
        NotFoundException,
      );
      await expect(service.getSharedCard('expired-token')).rejects.toThrow(
        'Shared card has expired',
      );
    });

    it('should increment viewCount', async () => {
      const linkData = {
        id: 'link-1',
        token: 'valid-token',
        cardType: 'family_tree',
        title: 'My Family',
        description: 'A great family',
        deepLinkUrl: 'kinrel://share/family_tree/valid-token',
        familyId: null,
        personId: null,
        viewCount: 5,
        shareCount: 1,
        expiresAt: null,
        createdAt: new Date(),
      };
      mockPrisma.shareableLink.findUnique.mockResolvedValue(linkData);
      mockPrisma.shareableLink.update.mockResolvedValue({
        ...linkData,
        viewCount: 6,
      });

      const result = await service.getSharedCard('valid-token');

      expect(mockPrisma.shareableLink.update).toHaveBeenCalledWith({
        where: { token: 'valid-token' },
        data: { viewCount: { increment: 1 } },
      });
      expect(result.viewCount).toBe(6); // 5 + 1
    });

    it('should fetch family data if familyId present', async () => {
      const linkData = {
        id: 'link-1',
        token: 'family-token',
        cardType: 'family_tree',
        title: 'My Family',
        description: '',
        deepLinkUrl: 'kinrel://share/family_tree/family-token',
        familyId: 'fam-1',
        personId: null,
        viewCount: 3,
        shareCount: 0,
        expiresAt: null,
        createdAt: new Date(),
      };
      const familyData = {
        id: 'fam-1',
        name: 'The Smiths',
        description: 'A great family',
        avatarUrl: 'https://example.com/avatar.jpg',
        memberCount: 20,
        gotra: 'Bharadwaj',
        originVillage: 'Rampur',
        region: 'Uttar Pradesh',
      };

      mockPrisma.shareableLink.findUnique.mockResolvedValue(linkData);
      mockPrisma.shareableLink.update.mockResolvedValue({
        ...linkData,
        viewCount: 4,
      });
      mockPrisma.family.findUnique.mockResolvedValue(familyData);

      const result = await service.getSharedCard('family-token');

      expect(result.family).toEqual(familyData);
      expect(mockPrisma.family.findUnique).toHaveBeenCalledWith({
        where: { id: 'fam-1' },
        select: expect.objectContaining({
          id: true,
          name: true,
          description: true,
          avatarUrl: true,
          memberCount: true,
        }),
      });
    });

    it('should fetch person data if personId present', async () => {
      const linkData = {
        id: 'link-1',
        token: 'person-token',
        cardType: 'birthday',
        title: 'Birthday Card',
        description: '',
        deepLinkUrl: 'kinrel://share/birthday/person-token',
        familyId: null,
        personId: 'person-1',
        viewCount: 2,
        shareCount: 1,
        expiresAt: null,
        createdAt: new Date(),
      };
      const personData = {
        id: 'person-1',
        name: 'John Doe',
        dateOfBirth: '1990-01-01',
        birthYear: 1990,
        photoUrl: 'https://example.com/photo.jpg',
        gender: 'male',
        gotra: 'Bharadwaj',
        occupation: 'Engineer',
        city: 'New Delhi',
      };

      mockPrisma.shareableLink.findUnique.mockResolvedValue(linkData);
      mockPrisma.shareableLink.update.mockResolvedValue({
        ...linkData,
        viewCount: 3,
      });
      mockPrisma.person.findUnique.mockResolvedValue(personData);

      const result = await service.getSharedCard('person-token');

      expect(result.person).toEqual(personData);
      expect(mockPrisma.person.findUnique).toHaveBeenCalledWith({
        where: { id: 'person-1' },
        select: expect.objectContaining({
          id: true,
          name: true,
          photoUrl: true,
          gender: true,
        }),
      });
    });

    it('should handle non-expired link with future expiresAt', async () => {
      const linkData = {
        id: 'link-1',
        token: 'future-token',
        cardType: 'milestone',
        title: 'Milestone',
        description: '',
        deepLinkUrl: 'kinrel://share/milestone/future-token',
        familyId: null,
        personId: null,
        viewCount: 1,
        shareCount: 0,
        expiresAt: new Date(Date.now() + 86400000), // tomorrow
        createdAt: new Date(),
      };

      mockPrisma.shareableLink.findUnique.mockResolvedValue(linkData);
      mockPrisma.shareableLink.update.mockResolvedValue({
        ...linkData,
        viewCount: 2,
      });

      const result = await service.getSharedCard('future-token');

      expect(result.token).toBe('future-token');
      expect(result.viewCount).toBe(2);
    });
  });
});
