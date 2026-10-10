// server/src/modules/chat/cloud-backups.service.spec.ts
//
// Unit tests for CloudBackupsService — Tier 5 Feature 5.5.

import { Test, TestingModule } from '@nestjs/testing';
import { CloudBackupsService } from './cloud-backups.service';
import { PrismaService } from '../../prisma/prisma.service';
import { BadRequestException } from '@nestjs/common';

describe('CloudBackupsService', () => {
  let service: CloudBackupsService;

  const mockPrisma = {
    cloudBackupRecord: {
      create: jest.fn(),
      findMany: jest.fn(),
      findFirst: jest.fn(),
      findUnique: jest.fn(),
      delete: jest.fn(),
    },
    user: { update: jest.fn() },
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        CloudBackupsService,
        { provide: PrismaService, useValue: mockPrisma },
      ],
    }).compile();
    service = module.get<CloudBackupsService>(CloudBackupsService);
    jest.clearAllMocks();
  });

  describe('recordBackup — validation', () => {
    it('throws BadRequestException for an invalid provider', async () => {
      await expect(
        service.recordBackup('user-1', {
          provider: 'dropbox' as any, backupKey: 'k', sizeBytes: 100,
        }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('throws BadRequestException when backupKey is empty', async () => {
      await expect(
        service.recordBackup('user-1', {
          provider: 'google_drive', backupKey: '', sizeBytes: 100,
        }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('throws BadRequestException when sizeBytes is negative', async () => {
      await expect(
        service.recordBackup('user-1', {
          provider: 'icloud', backupKey: 'k', sizeBytes: -1,
        }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('creates the backup record + updates the User.lastCloudBackupAt cache', async () => {
      const created = { id: 'cbr_new', provider: 'google_drive' };
      mockPrisma.cloudBackupRecord.create.mockResolvedValue(created);
      const result = await service.recordBackup('user-1', {
        provider: 'google_drive', backupKey: 'k', sizeBytes: 1024,
        messageCount: 50, mediaCount: 10, deviceLabel: 'iPhone 15',
      });
      expect(result).toBe(created);
      expect(mockPrisma.cloudBackupRecord.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            userId: 'user-1',
            provider: 'google_drive',
            sizeBytes: BigInt(1024),
            messageCount: 50,
            mediaCount: 10,
            deviceLabel: 'iPhone 15',
          }),
        }),
      );
      expect(mockPrisma.user.update).toHaveBeenCalledWith({
        where: { id: 'user-1' },
        data: expect.objectContaining({ lastCloudBackupAt: expect.any(Date) }),
      });
    });
  });

  describe('listMyBackups', () => {
    it('queries the caller\'s backups ordered by createdAt desc', async () => {
      const rows = [{ id: 'cbr_1' }, { id: 'cbr_2' }];
      mockPrisma.cloudBackupRecord.findMany.mockResolvedValue(rows);
      const result = await service.listMyBackups('user-1', 10);
      expect(result).toBe(rows);
      expect(mockPrisma.cloudBackupRecord.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { userId: 'user-1' },
          orderBy: { createdAt: 'desc' },
          take: 10,
        }),
      );
    });
  });

  describe('getLatestBackup', () => {
    it('returns the most recent backup', async () => {
      const latest = { id: 'cbr_1', provider: 'google_drive' };
      mockPrisma.cloudBackupRecord.findFirst.mockResolvedValue(latest);
      const result = await service.getLatestBackup('user-1');
      expect(result).toBe(latest);
    });
  });

  describe('deleteBackup', () => {
    it('returns not_found when the backup does not exist', async () => {
      mockPrisma.cloudBackupRecord.findUnique.mockResolvedValue(null);
      const result = await service.deleteBackup('user-1', 'cbr_x');
      expect(result).toEqual({ success: false, error: 'not_found' });
    });

    it('returns not_owner when the caller is not the owner', async () => {
      mockPrisma.cloudBackupRecord.findUnique.mockResolvedValue({
        id: 'cbr_x', userId: 'user-OTHER',
      });
      const result = await service.deleteBackup('user-1', 'cbr_x');
      expect(result).toEqual({ success: false, error: 'not_owner' });
    });

    it('deletes the backup when owned by the caller', async () => {
      mockPrisma.cloudBackupRecord.findUnique.mockResolvedValue({
        id: 'cbr_x', userId: 'user-1',
      });
      mockPrisma.cloudBackupRecord.delete.mockResolvedValue({});
      const result = await service.deleteBackup('user-1', 'cbr_x');
      expect(result).toEqual({ success: true, deleted: 'cbr_x' });
    });
  });
});
