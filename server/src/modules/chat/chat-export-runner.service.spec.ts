// server/src/modules/chat/chat-export-runner.service.spec.ts
//
// Unit tests for ChatExportRunnerService — Tier 5 Feature 5.4 follow-up.

import { Test, TestingModule } from '@nestjs/testing';
import { ChatExportRunnerService } from './chat-export-runner.service';
import { PrismaService } from '../../prisma/prisma.service';

describe('ChatExportRunnerService', () => {
  let service: ChatExportRunnerService;

  const mockPrisma = {
    chatExportJob: {
      findMany: jest.fn(),
      findUnique: jest.fn(),
      update: jest.fn(),
    },
    familyMember: { findUnique: jest.fn() },
    chatMessage: { findMany: jest.fn() },
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        ChatExportRunnerService,
        { provide: PrismaService, useValue: mockPrisma },
      ],
    }).compile();
    service = module.get<ChatExportRunnerService>(ChatExportRunnerService);
    jest.clearAllMocks();
  });

  describe('processPendingJobs', () => {
    it('no-ops when there are no pending jobs', async () => {
      mockPrisma.chatExportJob.findMany.mockResolvedValue([]);
      await service.processPendingJobs();
      expect(mockPrisma.chatExportJob.findMany).toHaveBeenCalled();
      expect(mockPrisma.chatExportJob.update).not.toHaveBeenCalled();
    });

    it('processes each pending job', async () => {
      const jobs = [{ id: 'cej_1', status: 'pending' }, { id: 'cej_2', status: 'pending' }];
      mockPrisma.chatExportJob.findMany.mockResolvedValue(jobs);
      mockPrisma.chatExportJob.findUnique.mockImplementation(({ where }: any) =>
        Promise.resolve(jobs.find((j) => j.id === where.id)),
      );
      mockPrisma.familyMember.findUnique.mockResolvedValue({ id: 'fm-1' });
      mockPrisma.chatMessage.findMany.mockResolvedValue([]);
      mockPrisma.chatExportJob.update.mockResolvedValue({});

      await service.processPendingJobs();
      // Two jobs × two updates each (running + completed) = 4 total.
      expect(mockPrisma.chatExportJob.update).toHaveBeenCalledTimes(4);
    });
  });

  describe('processJob — validation', () => {
    it('no-ops when the job does not exist', async () => {
      mockPrisma.chatExportJob.findUnique.mockResolvedValue(null);
      await service.processJob('cej_missing');
      expect(mockPrisma.chatExportJob.update).not.toHaveBeenCalled();
    });

    it('no-ops when the job is not pending (already running/completed)', async () => {
      mockPrisma.chatExportJob.findUnique.mockResolvedValue({ id: 'cej_1', status: 'running' });
      await service.processJob('cej_1');
      expect(mockPrisma.chatExportJob.update).not.toHaveBeenCalled();
    });

    it('marks the job as failed when the requester is no longer a member', async () => {
      mockPrisma.chatExportJob.findUnique.mockResolvedValue({
        id: 'cej_1', status: 'pending', familyId: 'fam-1', requesterId: 'user-1', scope: 'text',
      });
      mockPrisma.familyMember.findUnique.mockResolvedValue(null);

      await service.processJob('cej_1');

      // Two updates: running + failed.
      expect(mockPrisma.chatExportJob.update).toHaveBeenCalledTimes(2);
      const failedCall = mockPrisma.chatExportJob.update.mock.calls[1][0];
      expect(failedCall.data.status).toBe('failed');
      expect(failedCall.data.failureReason).toBe('requester_no_longer_member');
    });

    it('completes a text-scope job with a transcript', async () => {
      mockPrisma.chatExportJob.findUnique.mockResolvedValue({
        id: 'cej_1', status: 'pending', familyId: 'fam-1', requesterId: 'user-1', scope: 'text',
      });
      mockPrisma.familyMember.findUnique.mockResolvedValue({ id: 'fm-1' });
      const messages = [
        { id: 'cm_1', senderName: 'Manish', content: 'Hello', messageType: 'text',
          createdAt: new Date('2026-01-01T10:00:00Z'), mediaUrl: null, caption: null, isEdited: false },
        { id: 'cm_2', senderName: 'Priya', content: 'Hi!', messageType: 'text',
          createdAt: new Date('2026-01-01T10:00:05Z'), mediaUrl: null, caption: null, isEdited: false },
      ];
      mockPrisma.chatMessage.findMany.mockResolvedValue(messages);

      await service.processJob('cej_1');

      const completedCall = mockPrisma.chatExportJob.update.mock.calls[1][0];
      expect(completedCall.data.status).toBe('completed');
      expect(completedCall.data.resultFormat).toBe('txt');
      expect(completedCall.data.messageCount).toBe(2);
      expect(completedCall.data.resultUrl).toMatch(/^data:text\/plain;base64,/);
      expect(completedCall.data.resultSizeBytes).toEqual(expect.any(BigInt));
      expect(completedCall.data.expiresAt).toEqual(expect.any(Date));
    });

    it('handles "full" scope by falling back to text with a TODO note', async () => {
      mockPrisma.chatExportJob.findUnique.mockResolvedValue({
        id: 'cej_2', status: 'pending', familyId: 'fam-1', requesterId: 'user-1', scope: 'full',
      });
      mockPrisma.familyMember.findUnique.mockResolvedValue({ id: 'fm-1' });
      mockPrisma.chatMessage.findMany.mockResolvedValue([
        { id: 'cm_1', senderName: 'Manish', content: 'A photo', messageType: 'photo',
          createdAt: new Date('2026-01-01T10:00:00Z'), mediaUrl: 'https://example.com/p.jpg',
          caption: 'Sunset', isEdited: false },
      ]);

      await service.processJob('cej_2');

      const completedCall = mockPrisma.chatExportJob.update.mock.calls[1][0];
      expect(completedCall.data.status).toBe('completed');
      expect(completedCall.data.resultFormat).toBe('txt'); // TODO: switch to 'zip' when adm-zip is wired
    });
  });
});
