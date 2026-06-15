import { Test, TestingModule } from '@nestjs/testing';
import { ShareService } from './share.service';
import { PrismaService } from '../../prisma/prisma.service';
import { KinrelGateway } from '../gateway/kinrel.gateway';
import {
  BadRequestException,
  NotFoundException,
} from '@nestjs/common';

describe('ShareService', () => {
  let service: ShareService;
  let prisma: PrismaService;

  const mockGateway = {
    emitToUser: jest.fn(),
    emitToFamily: jest.fn(),
  };

  const mockPrisma = {
    shareableLink: {
      findUnique: jest.fn(),
      findMany: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
      delete: jest.fn(),
      count: jest.fn(),
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
        { provide: KinrelGateway, useValue: mockGateway },
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
    const baseDto = {
      cardType: 'family_tree',
      title: 'My Family Tree',
    };

    it('should create a shareable link with valid data', async () => {
      const mockLink = {
        id: 'link-1',
        token: 'abc123',
        cardType: 'family_tree',
        familyId: null,
        personId: null,
        title: 'My Family Tree',
        description: '',
        deepLinkUrl: 'kinrel://share/family_tree/abc123',
        viewCount: 0,
        shareCount: 0,
        expiresAt: null,
        createdAt: new Date(),
      };
      mockPrisma.shareableLink.create.mockResolvedValue(mockLink);

      const result = await service.createShareableLink(userId, baseDto as any);

      expect(result.token).toBe('abc123');
      expect(result.cardType).toBe('family_tree');
      expect(result.title).toBe('My Family Tree');
      expect(mockGateway.emitToUser).toHaveBeenCalledWith(
        userId,
        'share:link_created',
        expect.objectContaining({ token: 'abc123' }),
      );
    });

    it('should throw BadRequestException for invalid cardType', async () => {
      const invalidDto = { cardType: 'invalid_type', title: 'Test' };

      await expect(
        service.createShareableLink(userId, invalidDto as any),
      ).rejects.toThrow(BadRequestException);
    });

    it('should throw BadRequestException for empty title', async () => {
      const emptyTitleDto = { cardType: 'family_tree', title: '   ' };

      await expect(
        service.createShareableLink(userId, emptyTitleDto as any),
      ).rejects.toThrow(BadRequestException);
    });

    it('should set expiresAt when expiresInDays is provided', async () => {
      const dtoWithExpiry = { ...baseDto, expiresInDays: 7 };
      const mockLink = {
        id: 'link-1',
        token: 'abc123',
        cardType: 'family_tree',
        familyId: null,
        personId: null,
        title: 'My Family Tree',
        description: '',
        deepLinkUrl: 'kinrel://share/family_tree/abc123',
        viewCount: 0,
        shareCount: 0,
        expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
        createdAt: new Date(),
      };
      mockPrisma.shareableLink.create.mockResolvedValue(mockLink);

      const result = await service.createShareableLink(userId, dtoWithExpiry as any);

      expect(result.expiresAt).toBeTruthy();
      const createCall = mockPrisma.shareableLink.create.mock.calls[0][0];
      expect(createCall.data.expiresAt).toBeInstanceOf(Date);
    });

    it('should use custom deepLinkUrl when provided', async () => {
      const customUrlDto = { ...baseDto, deepLinkUrl: 'https://custom.url/abc' };
      mockPrisma.shareableLink.create.mockResolvedValue({
        id: 'link-1',
        token: 'abc123',
        deepLinkUrl: 'https://custom.url/abc',
        createdAt: new Date(),
      });

      await service.createShareableLink(userId, customUrlDto as any);

      const createCall = mockPrisma.shareableLink.create.mock.calls[0][0];
      expect(createCall.data.deepLinkUrl).toBe('https://custom.url/abc');
    });

    it('should auto-generate deepLinkUrl when not provided', async () => {
      mockPrisma.shareableLink.create.mockResolvedValue({
        id: 'link-1',
        token: 'abc123',
        deepLinkUrl: 'kinrel://share/family_tree/abc123',
        createdAt: new Date(),
      });

      await service.createShareableLink(userId, baseDto as any);

      const createCall = mockPrisma.shareableLink.create.mock.calls[0][0];
      expect(createCall.data.deepLinkUrl).toMatch(/^kinrel:\/\/share\//);
    });

    it('should create link with familyId and personId', async () => {
      const fullDto = { ...baseDto, familyId: 'fam-1', personId: 'p-1', description: 'Test desc' };
      mockPrisma.shareableLink.create.mockResolvedValue({
        id: 'link-1',
        token: 'abc123',
        familyId: 'fam-1',
        personId: 'p-1',
        description: 'Test desc',
        createdAt: new Date(),
      });

      const result = await service.createShareableLink(userId, fullDto as any);

      const createCall = mockPrisma.shareableLink.create.mock.calls[0][0];
      expect(createCall.data.familyId).toBe('fam-1');
      expect(createCall.data.personId).toBe('p-1');
      expect(createCall.data.description).toBe('Test desc');
    });
  });

  // ─── getShareStats ─────────────────────────────────────────────────
  describe('getShareStats', () => {
    it('should return share stats for a valid token', async () => {
      mockPrisma.shareableLink.findUnique.mockResolvedValue({
        id: 'link-1',
        token: 'abc123',
        cardType: 'family_tree',
        title: 'Test',
        viewCount: 10,
        shareCount: 5,
        expiresAt: null,
        createdAt: new Date(),
      });

      const result = await service.getShareStats('abc123');

      expect(result.viewCount).toBe(10);
      expect(result.shareCount).toBe(5);
      expect(result.token).toBe('abc123');
    });

    it('should throw NotFoundException for invalid token', async () => {
      mockPrisma.shareableLink.findUnique.mockResolvedValue(null);

      await expect(service.getShareStats('invalid')).rejects.toThrow(NotFoundException);
    });
  });

  // ─── getSharedCard ─────────────────────────────────────────────────
  describe('getSharedCard', () => {
    it('should return card data and increment viewCount', async () => {
      mockPrisma.shareableLink.findUnique.mockResolvedValue({
        id: 'link-1',
        token: 'abc123',
        cardType: 'family_tree',
        title: 'Test',
        description: '',
        deepLinkUrl: 'kinrel://share/family_tree/abc123',
        viewCount: 5,
        shareCount: 2,
        familyId: null,
        personId: null,
        expiresAt: null,
        createdAt: new Date(),
      });
      mockPrisma.shareableLink.update.mockResolvedValue({});

      const result = await service.getSharedCard('abc123');

      expect(result.viewCount).toBe(6); // 5 + 1
      expect(mockPrisma.shareableLink.update).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { token: 'abc123' },
          data: { viewCount: { increment: 1 } },
        }),
      );
    });

    it('should include family data when familyId is set', async () => {
      mockPrisma.shareableLink.findUnique.mockResolvedValue({
        id: 'link-1',
        token: 'abc123',
        cardType: 'family_tree',
        title: 'Test',
        description: '',
        deepLinkUrl: 'kinrel://share/family_tree/abc123',
        viewCount: 0,
        shareCount: 0,
        familyId: 'fam-1',
        personId: null,
        expiresAt: null,
        createdAt: new Date(),
      });
      mockPrisma.shareableLink.update.mockResolvedValue({});
      mockPrisma.family.findUnique.mockResolvedValue({
        id: 'fam-1',
        name: 'Test Family',
      });

      const result = await service.getSharedCard('abc123');

      expect(result.family).toEqual({ id: 'fam-1', name: 'Test Family' });
    });

    it('should include person data when personId is set', async () => {
      mockPrisma.shareableLink.findUnique.mockResolvedValue({
        id: 'link-1',
        token: 'abc123',
        cardType: 'birthday',
        title: 'Birthday',
        description: '',
        deepLinkUrl: 'kinrel://share/birthday/abc123',
        viewCount: 0,
        shareCount: 0,
        familyId: null,
        personId: 'p-1',
        expiresAt: null,
        createdAt: new Date(),
      });
      mockPrisma.shareableLink.update.mockResolvedValue({});
      mockPrisma.person.findUnique.mockResolvedValue({
        id: 'p-1',
        name: 'Test Person',
      });

      const result = await service.getSharedCard('abc123');

      expect(result.person).toEqual({ id: 'p-1', name: 'Test Person' });
    });

    it('should throw NotFoundException if link not found', async () => {
      mockPrisma.shareableLink.findUnique.mockResolvedValue(null);

      await expect(service.getSharedCard('invalid')).rejects.toThrow(NotFoundException);
    });

    it('should throw NotFoundException if link has expired', async () => {
      mockPrisma.shareableLink.findUnique.mockResolvedValue({
        id: 'link-1',
        token: 'abc123',
        expiresAt: new Date('2020-01-01'),
      });

      await expect(service.getSharedCard('abc123')).rejects.toThrow(NotFoundException);
    });
  });

  // ─── trackShare ────────────────────────────────────────────────────
  describe('trackShare', () => {
    it('should increment shareCount for a valid token', async () => {
      mockPrisma.shareableLink.findUnique.mockResolvedValue({
        id: 'link-1',
        token: 'abc123',
        shareCount: 5,
        expiresAt: null,
      });
      mockPrisma.shareableLink.update.mockResolvedValue({
        id: 'link-1',
        token: 'abc123',
        shareCount: 6,
      });

      const result = await service.trackShare({ token: 'abc123' });

      expect(result.shareCount).toBe(6);
      expect(mockPrisma.shareableLink.update).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { token: 'abc123' },
          data: { shareCount: { increment: 1 } },
        }),
      );
    });

    it('should throw NotFoundException for invalid token', async () => {
      mockPrisma.shareableLink.findUnique.mockResolvedValue(null);

      await expect(service.trackShare({ token: 'invalid' })).rejects.toThrow(
        NotFoundException,
      );
    });

    it('should throw NotFoundException for expired link', async () => {
      mockPrisma.shareableLink.findUnique.mockResolvedValue({
        id: 'link-1',
        token: 'abc123',
        expiresAt: new Date('2020-01-01'),
      });

      await expect(service.trackShare({ token: 'abc123' })).rejects.toThrow(
        NotFoundException,
      );
    });
  });

  // ─── revokeShareableLink ───────────────────────────────────────────
  describe('revokeShareableLink', () => {
    const userId = 'user-1';
    const linkId = 'link-1';

    it('should delete a shareable link and emit socket event', async () => {
      mockPrisma.shareableLink.findUnique.mockResolvedValue({
        id: linkId,
        token: 'abc123',
      });
      mockPrisma.shareableLink.delete.mockResolvedValue({ id: linkId });

      const result = await service.revokeShareableLink(userId, linkId);

      expect(result.deleted).toBe(true);
      expect(result.id).toBe(linkId);
      expect(mockPrisma.shareableLink.delete).toHaveBeenCalledWith({
        where: { id: linkId },
      });
      expect(mockGateway.emitToUser).toHaveBeenCalledWith(
        userId,
        'share:link_revoked',
        expect.objectContaining({ id: linkId }),
      );
    });

    it('should throw NotFoundException if link not found', async () => {
      mockPrisma.shareableLink.findUnique.mockResolvedValue(null);

      await expect(service.revokeShareableLink(userId, linkId)).rejects.toThrow(
        NotFoundException,
      );
    });
  });

  // ─── getMyShareableLinks ───────────────────────────────────────────
  describe('getMyShareableLinks', () => {
    const userId = 'user-1';

    it('should return paginated list of shareable links', async () => {
      const links = [
        {
          id: 'link-1',
          token: 'abc123',
          cardType: 'family_tree',
          familyId: null,
          personId: null,
          title: 'Family Tree',
          description: '',
          deepLinkUrl: 'kinrel://share/family_tree/abc123',
          viewCount: 10,
          shareCount: 3,
          expiresAt: null,
          createdAt: new Date(),
        },
        {
          id: 'link-2',
          token: 'def456',
          cardType: 'birthday',
          familyId: null,
          personId: null,
          title: 'Birthday Card',
          description: '',
          deepLinkUrl: 'kinrel://share/birthday/def456',
          viewCount: 5,
          shareCount: 1,
          expiresAt: null,
          createdAt: new Date(),
        },
      ];

      mockPrisma.shareableLink.findMany.mockResolvedValue(links);
      mockPrisma.shareableLink.count.mockResolvedValue(2);

      const result = await service.getMyShareableLinks(userId, 20, 1);

      expect(result.items).toHaveLength(2);
      expect(result.total).toBe(2);
      expect(result.page).toBe(1);
      expect(result.limit).toBe(20);
    });

    it('should support pagination with page and limit', async () => {
      mockPrisma.shareableLink.findMany.mockResolvedValue([]);
      mockPrisma.shareableLink.count.mockResolvedValue(25);

      const result = await service.getMyShareableLinks(userId, 10, 3);

      expect(result.page).toBe(3);
      expect(result.limit).toBe(10);
      expect(mockPrisma.shareableLink.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          skip: 20, // (3-1) * 10
          take: 10,
        }),
      );
    });

    it('should return empty list when no links exist', async () => {
      mockPrisma.shareableLink.findMany.mockResolvedValue([]);
      mockPrisma.shareableLink.count.mockResolvedValue(0);

      const result = await service.getMyShareableLinks(userId);

      expect(result.items).toHaveLength(0);
      expect(result.total).toBe(0);
    });
  });
});
