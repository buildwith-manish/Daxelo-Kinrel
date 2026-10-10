// server/src/modules/chat/drafts.service.spec.ts
//
// Unit tests for DraftsService — Tier 1 Feature 1.3.
// Verifies the upsert (create + update), the "empty text = clear"
// behavior, family membership enforcement, and the load path.

import { Test, TestingModule } from '@nestjs/testing';
import { DraftsService } from './drafts.service';
import { PrismaService } from '../../prisma/prisma.service';
import { BadRequestException, ForbiddenException } from '@nestjs/common';

describe('DraftsService', () => {
  let service: DraftsService;

  const mockPrisma = {
    familyMember: { findUnique: jest.fn() },
    chatDraft: {
      findFirst: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
      deleteMany: jest.fn(),
      findMany: jest.fn(),
    },
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        DraftsService,
        { provide: PrismaService, useValue: mockPrisma },
      ],
    }).compile();
    service = module.get<DraftsService>(DraftsService);
    jest.clearAllMocks();
  });

  describe('saveDraft — happy path', () => {
    it('creates a new draft when none exists', async () => {
      mockPrisma.chatDraft.findFirst.mockResolvedValue(null);
      const created = { id: 'cd_1', draftText: 'hello' };
      mockPrisma.chatDraft.create.mockResolvedValue(created);

      const result = await service.saveDraft('user-1', {
        receiverId: 'user-2',
        draftText: 'hello',
      });
      expect(result).toEqual({ action: 'created', draftId: 'cd_1' });
      expect(mockPrisma.chatDraft.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            userId: 'user-1',
            receiverId: 'user-2',
            familyId: null,
            draftText: 'hello',
          }),
        }),
      );
    });

    it('updates the existing draft when one already exists', async () => {
      mockPrisma.chatDraft.findFirst.mockResolvedValue({
        id: 'cd_1',
        userId: 'user-1',
        receiverId: 'user-2',
      });
      const updated = { id: 'cd_1', draftText: 'hello world' };
      mockPrisma.chatDraft.update.mockResolvedValue(updated);

      const result = await service.saveDraft('user-1', {
        receiverId: 'user-2',
        draftText: 'hello world',
      });
      expect(result).toEqual({ action: 'updated', draftId: 'cd_1' });
      expect(mockPrisma.chatDraft.update).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { id: 'cd_1' },
          data: expect.objectContaining({ draftText: 'hello world' }),
        }),
      );
      expect(mockPrisma.chatDraft.create).not.toHaveBeenCalled();
    });
  });

  describe('saveDraft — clear (empty text)', () => {
    it('deletes the draft when the text is empty (WhatsApp send-clears-draft)', async () => {
      mockPrisma.chatDraft.deleteMany.mockResolvedValue({ count: 1 });
      const result = await service.saveDraft('user-1', {
        receiverId: 'user-2',
        draftText: '   ',
      });
      expect(result).toEqual({ action: 'cleared' });
      expect(mockPrisma.chatDraft.deleteMany).toHaveBeenCalled();
      expect(mockPrisma.chatDraft.create).not.toHaveBeenCalled();
    });

    it('deletes the draft when the text is null', async () => {
      mockPrisma.chatDraft.deleteMany.mockResolvedValue({ count: 0 });
      const result = await service.saveDraft('user-1', {
        receiverId: 'user-2',
        draftText: '',
      });
      expect(result).toEqual({ action: 'cleared' });
    });
  });

  describe('saveDraft — validation', () => {
    it('throws BadRequestException when both familyId and receiverId are null', async () => {
      await expect(
        service.saveDraft('user-1', { draftText: 'x' }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('throws BadRequestException when both familyId and receiverId are set', async () => {
      await expect(
        service.saveDraft('user-1', {
          familyId: 'fam-1',
          receiverId: 'user-2',
          draftText: 'x',
        }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('throws ForbiddenException when the user is not a member of the family', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue(null);
      await expect(
        service.saveDraft('user-1', {
          familyId: 'fam-1',
          draftText: 'x',
        }),
      ).rejects.toBeInstanceOf(ForbiddenException);
    });
  });

  describe('getDraft', () => {
    it('returns hasDraft=false when no row exists', async () => {
      mockPrisma.chatDraft.findFirst.mockResolvedValue(null);
      const result = await service.getDraft('user-1', { receiverId: 'user-2' });
      expect(result).toEqual({
        hasDraft: false,
        draftText: null,
        replyToId: null,
      });
    });

    it('returns the draft text + replyToId when a row exists', async () => {
      mockPrisma.chatDraft.findFirst.mockResolvedValue({
        id: 'cd_1',
        draftText: 'hello',
        replyToId: 'cm_parent',
        updatedAt: new Date('2026-01-01T00:00:00Z'),
      });
      const result = await service.getDraft('user-1', { receiverId: 'user-2' });
      expect(result).toEqual({
        hasDraft: true,
        draftText: 'hello',
        replyToId: 'cm_parent',
        updatedAt: new Date('2026-01-01T00:00:00Z'),
      });
    });
  });

  describe('listDrafts', () => {
    it('returns all drafts for the caller ordered by updatedAt desc', async () => {
      const rows = [
        { id: 'cd_2', userId: 'user-1' },
        { id: 'cd_1', userId: 'user-1' },
      ];
      mockPrisma.chatDraft.findMany.mockResolvedValue(rows);
      const result = await service.listDrafts('user-1');
      expect(result).toBe(rows);
      expect(mockPrisma.chatDraft.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { userId: 'user-1' },
          orderBy: { updatedAt: 'desc' },
        }),
      );
    });
  });
});
