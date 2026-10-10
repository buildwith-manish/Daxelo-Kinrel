// server/src/modules/chat/chat-exports.service.spec.ts
//
// Unit tests for ChatExportsService — Tier 5 Feature 5.4.

import { Test, TestingModule } from '@nestjs/testing';
import { ChatExportsService } from './chat-exports.service';
import { PrismaService } from '../../prisma/prisma.service';
import { BadRequestException, ForbiddenException, NotFoundException } from '@nestjs/common';

describe('ChatExportsService', () => {
  let service: ChatExportsService;

  const mockPrisma = {
    familyMember: { findUnique: jest.fn() },
    chatExportJob: { findFirst: jest.fn(), findUnique: jest.fn(), findMany: jest.fn(), create: jest.fn(), update: jest.fn() },
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        ChatExportsService,
        { provide: PrismaService, useValue: mockPrisma },
      ],
    }).compile();
    service = module.get<ChatExportsService>(ChatExportsService);
    jest.clearAllMocks();
  });

  describe('createExportJob — validation', () => {
    it('throws BadRequestException for an invalid scope', async () => {
      await expect(
        service.createExportJob('user-1', { familyId: 'fam-1', scope: 'invalid' as any }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('throws ForbiddenException when the caller is not a member', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue(null);
      await expect(
        service.createExportJob('user-1', { familyId: 'fam-1', scope: 'text' }),
      ).rejects.toBeInstanceOf(ForbiddenException);
    });

    it('returns the existing pending job when one exists', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue({ id: 'fm-1' });
      const existing = { id: 'cej_1', status: 'pending' };
      mockPrisma.chatExportJob.findFirst.mockResolvedValue(existing);
      const result = await service.createExportJob('user-1', { familyId: 'fam-1', scope: 'text' });
      expect(result).toEqual(expect.objectContaining({ action: 'already_pending' }));
      expect(mockPrisma.chatExportJob.create).not.toHaveBeenCalled();
    });

    it('creates a new pending job', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue({ id: 'fm-1' });
      mockPrisma.chatExportJob.findFirst.mockResolvedValue(null);
      const created = { id: 'cej_new', status: 'pending' };
      mockPrisma.chatExportJob.create.mockResolvedValue(created);
      const result = await service.createExportJob('user-1', { familyId: 'fam-1', scope: 'full' });
      expect(result).toBe(created);
    });
  });

  describe('getJob', () => {
    it('throws NotFoundException when the job does not exist', async () => {
      mockPrisma.chatExportJob.findUnique.mockResolvedValue(null);
      await expect(
        service.getJob('user-1', 'cej_x'),
      ).rejects.toBeInstanceOf(NotFoundException);
    });

    it('throws ForbiddenException when the caller is not the owner', async () => {
      mockPrisma.chatExportJob.findUnique.mockResolvedValue({
        id: 'cej_x', requesterId: 'user-OTHER',
      });
      await expect(
        service.getJob('user-1', 'cej_x'),
      ).rejects.toBeInstanceOf(ForbiddenException);
    });
  });

  describe('cancelJob', () => {
    it('throws BadRequestException when the job is not pending', async () => {
      mockPrisma.chatExportJob.findUnique.mockResolvedValue({
        id: 'cej_x', requesterId: 'user-1', status: 'running',
      });
      await expect(
        service.cancelJob('user-1', 'cej_x'),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('cancels a pending job', async () => {
      mockPrisma.chatExportJob.findUnique.mockResolvedValue({
        id: 'cej_x', requesterId: 'user-1', status: 'pending',
      });
      const updated = { id: 'cej_x', status: 'failed' };
      mockPrisma.chatExportJob.update.mockResolvedValue(updated);
      const result = await service.cancelJob('user-1', 'cej_x');
      expect(result).toBe(updated);
    });
  });
});
