// server/src/modules/chat/chat-folders.service.spec.ts
//
// Unit tests for ChatFoldersService — Tier 3 Feature 3.1.

import { Test, TestingModule } from '@nestjs/testing';
import { ChatFoldersService } from './chat-folders.service';
import { PrismaService } from '../../prisma/prisma.service';
import { BadRequestException, ForbiddenException, NotFoundException } from '@nestjs/common';

describe('ChatFoldersService', () => {
  let service: ChatFoldersService;

  const mockPrisma = {
    chatFolder: {
      findMany: jest.fn(),
      findUnique: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
      delete: jest.fn(),
    },
    $transaction: jest.fn(),
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        ChatFoldersService,
        { provide: PrismaService, useValue: mockPrisma },
      ],
    }).compile();
    service = module.get<ChatFoldersService>(ChatFoldersService);
    jest.clearAllMocks();
  });

  describe('createFolder — happy path', () => {
    it('creates a folder with ruleType=all + includeUnread=false', async () => {
      const created = { id: 'cf_1', userId: 'user-1', name: 'All', ruleType: 'all' };
      mockPrisma.chatFolder.create.mockResolvedValue(created);
      const result = await service.createFolder('user-1', { name: 'All' });
      expect(result).toBe(created);
      expect(mockPrisma.chatFolder.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            userId: 'user-1',
            name: 'All',
            ruleType: 'all',
          }),
        }),
      );
    });

    it('creates a folder with ruleType=by-name and a ruleValue', async () => {
      mockPrisma.chatFolder.create.mockResolvedValue({ id: 'cf_2' });
      await service.createFolder('user-1', {
        name: 'Sharma chats',
        ruleType: 'by-name',
        ruleValue: 'Sharma',
      });
      expect(mockPrisma.chatFolder.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            ruleType: 'by-name',
            ruleValue: 'Sharma',
          }),
        }),
      );
    });
  });

  describe('createFolder — validation', () => {
    it('throws BadRequestException when the name is empty', async () => {
      await expect(
        service.createFolder('user-1', { name: '   ' }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('throws BadRequestException when the name exceeds 50 chars', async () => {
      await expect(
        service.createFolder('user-1', { name: 'X'.repeat(60) }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('throws BadRequestException for an invalid ruleType', async () => {
      await expect(
        service.createFolder('user-1', { name: 'X', ruleType: 'invalid' as any }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('throws BadRequestException when by-name ruleType lacks a ruleValue', async () => {
      await expect(
        service.createFolder('user-1', { name: 'X', ruleType: 'by-name', ruleValue: null }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('rethrows a P2002 unique violation as a BadRequestException', async () => {
      mockPrisma.chatFolder.create.mockRejectedValue({ code: 'P2002' });
      await expect(
        service.createFolder('user-1', { name: 'Existing' }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });
  });

  describe('updateFolder', () => {
    it('throws NotFoundException when the folder does not exist', async () => {
      mockPrisma.chatFolder.findUnique.mockResolvedValue(null);
      await expect(
        service.updateFolder('user-1', 'cf_x', { name: 'New' }),
      ).rejects.toBeInstanceOf(NotFoundException);
    });

    it('throws ForbiddenException when the caller is not the owner', async () => {
      mockPrisma.chatFolder.findUnique.mockResolvedValue({
        id: 'cf_x',
        userId: 'user-OTHER',
        name: 'Old',
      });
      await expect(
        service.updateFolder('user-1', 'cf_x', { name: 'New' }),
      ).rejects.toBeInstanceOf(ForbiddenException);
    });

    it('updates the folder when owned by the caller', async () => {
      mockPrisma.chatFolder.findUnique.mockResolvedValue({
        id: 'cf_x',
        userId: 'user-1',
        name: 'Old',
      });
      const updated = { id: 'cf_x', name: 'New' };
      mockPrisma.chatFolder.update.mockResolvedValue(updated);
      const result = await service.updateFolder('user-1', 'cf_x', { name: 'New' });
      expect(result).toBe(updated);
    });
  });

  describe('deleteFolder', () => {
    it('throws NotFoundException when the folder does not exist', async () => {
      mockPrisma.chatFolder.findUnique.mockResolvedValue(null);
      await expect(
        service.deleteFolder('user-1', 'cf_x'),
      ).rejects.toBeInstanceOf(NotFoundException);
    });

    it('throws ForbiddenException when the caller is not the owner', async () => {
      mockPrisma.chatFolder.findUnique.mockResolvedValue({ id: 'cf_x', userId: 'user-OTHER' });
      await expect(
        service.deleteFolder('user-1', 'cf_x'),
      ).rejects.toBeInstanceOf(ForbiddenException);
    });

    it('deletes the folder when owned by the caller', async () => {
      mockPrisma.chatFolder.findUnique.mockResolvedValue({ id: 'cf_x', userId: 'user-1' });
      mockPrisma.chatFolder.delete.mockResolvedValue({});
      const result = await service.deleteFolder('user-1', 'cf_x');
      expect(result).toEqual({ success: true, deleted: 'cf_x' });
    });
  });

  describe('reorderFolders', () => {
    it('throws ForbiddenException when a folder is not owned by the caller', async () => {
      mockPrisma.chatFolder.findMany.mockResolvedValue([{ id: 'cf_1' }]);
      await expect(
        service.reorderFolders('user-1', ['cf_1', 'cf_missing']),
      ).rejects.toBeInstanceOf(ForbiddenException);
    });

    it('updates orderIndex for each folder in a transaction', async () => {
      mockPrisma.chatFolder.findMany.mockResolvedValue([{ id: 'cf_1' }, { id: 'cf_2' }]);
      mockPrisma.$transaction.mockResolvedValue([{ id: 'cf_1' }, { id: 'cf_2' }]);
      const result = await service.reorderFolders('user-1', ['cf_1', 'cf_2']);
      expect(result).toEqual({ success: true, reordered: 2 });
      expect(mockPrisma.$transaction).toHaveBeenCalled();
    });
  });
});
