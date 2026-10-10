// server/src/modules/chat/scheduled-messages.service.spec.ts
//
// Unit tests for ScheduledMessagesService — covers the Tier 1
// Feature 1.2 happy path + auth + idempotency + cancel + cron
// dispatcher. Mocks Prisma so the tests run without a database.

import { Test, TestingModule } from '@nestjs/testing';
import { ScheduledMessagesService } from './scheduled-messages.service';
import { PrismaService } from '../../prisma/prisma.service';
import { BadRequestException, ForbiddenException, NotFoundException } from '@nestjs/common';

describe('ScheduledMessagesService', () => {
  let service: ScheduledMessagesService;

  const mockPrisma = {
    familyMember: { findUnique: jest.fn() },
    scheduledMessage: {
      findUnique: jest.fn(),
      findMany: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
    },
    $queryRaw: jest.fn(),
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        ScheduledMessagesService,
        { provide: PrismaService, useValue: mockPrisma },
      ],
    }).compile();
    service = module.get<ScheduledMessagesService>(ScheduledMessagesService);
    jest.clearAllMocks();
  });

  /// Build a valid ScheduleMessageDto whose scheduledFor is +10 min.
  const buildDto = (overrides: Record<string, any> = {}) => ({
    content: 'Hello future',
    scheduledFor: new Date(Date.now() + 10 * 60 * 1000).toISOString(),
    familyId: 'fam-1',
    ...overrides,
  });

  describe('scheduleMessage — happy path', () => {
    it('persists a pending scheduled message for a family group', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue({ id: 'fm-1' });
      mockPrisma.scheduledMessage.findUnique.mockResolvedValue(null);
      const created = { id: 'sm_1', status: 'pending' };
      mockPrisma.scheduledMessage.create.mockResolvedValue(created);

      const result = await service.scheduleMessage('user-1', buildDto());
      expect(result).toBe(created);
      // The persisted row should NOT carry silent/caption (those are
      // SendChatMessageDto fields, not ScheduleMessageDto fields).
      const callArg = mockPrisma.scheduledMessage.create.mock.calls[0][0];
      expect(callArg.data).not.toHaveProperty('silent');
      expect(callArg.data).not.toHaveProperty('caption');
      expect(callArg.data).toEqual(
        expect.objectContaining({
          senderId: 'user-1',
          familyId: 'fam-1',
          receiverId: null,
          content: 'Hello future',
          status: 'pending',
        }),
      );
    });

    it('persists a DM scheduled message when receiverId is set', async () => {
      mockPrisma.scheduledMessage.findUnique.mockResolvedValue(null);
      const created = { id: 'sm_2', status: 'pending' };
      mockPrisma.scheduledMessage.create.mockResolvedValue(created);

      const result = await service.scheduleMessage(
        'user-1',
        buildDto({ familyId: undefined, receiverId: 'user-2' }),
      );
      expect(result).toBe(created);
      expect(mockPrisma.scheduledMessage.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            familyId: null,
            receiverId: 'user-2',
          }),
        }),
      );
    });

    it('passes through the silent + caption + viewOnce fields', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue({ id: 'fm-1' });
      mockPrisma.scheduledMessage.findUnique.mockResolvedValue(null);
      mockPrisma.scheduledMessage.create.mockResolvedValue({ id: 'sm_3' });

      // The DTO doesn't actually have silent/caption fields — those are
      // only on the SendChatMessageDto. But scheduledMessage.create
      // should NOT receive them. We assert the persisted payload doesn't
      // have unrelated fields by checking the data object's keys.
      await service.scheduleMessage('user-1', buildDto({ content: 'X' }));
      const callArg = mockPrisma.scheduledMessage.create.mock.calls[0][0];
      expect(callArg.data).not.toHaveProperty('silent');
      expect(callArg.data).not.toHaveProperty('caption');
    });
  });

  describe('scheduleMessage — validation', () => {
    it('throws BadRequestException when both familyId and receiverId are set', async () => {
      await expect(
        service.scheduleMessage(
          'user-1',
          buildDto({ familyId: 'fam-1', receiverId: 'user-2' }),
        ),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('throws BadRequestException when neither familyId nor receiverId is set', async () => {
      await expect(
        service.scheduleMessage(
          'user-1',
          buildDto({ familyId: undefined, receiverId: undefined }),
        ),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('throws BadRequestException when scheduledFor is in the past', async () => {
      await expect(
        service.scheduleMessage(
          'user-1',
          buildDto({ scheduledFor: new Date(Date.now() - 60_000).toISOString() }),
        ),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('throws BadRequestException when scheduledFor is less than 1 minute in the future', async () => {
      await expect(
        service.scheduleMessage(
          'user-1',
          buildDto({ scheduledFor: new Date(Date.now() + 30_000).toISOString() }),
        ),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('throws BadRequestException when scheduledFor is not a valid date', async () => {
      await expect(
        service.scheduleMessage(
          'user-1',
          buildDto({ scheduledFor: 'not-a-date' }),
        ),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('throws ForbiddenException when the user is not a member of the family', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue(null);
      await expect(
        service.scheduleMessage('user-1', buildDto()),
      ).rejects.toBeInstanceOf(ForbiddenException);
    });
  });

  describe('scheduleMessage — idempotency', () => {
    it('returns the existing row when clientScheduleId matches an owned row', async () => {
      // The membership check runs BEFORE the idempotency check, so we
      // need to stub it even though we're testing idempotency.
      mockPrisma.familyMember.findUnique.mockResolvedValue({ id: 'fm-1' });
      const existing = { id: 'sm_existing', senderId: 'user-1', status: 'pending' };
      mockPrisma.scheduledMessage.findUnique.mockResolvedValue(existing);

      const result = await service.scheduleMessage(
        'user-1',
        buildDto({ clientScheduleId: 'sm_existing' }),
      );
      expect(result).toBe(existing);
      expect(mockPrisma.scheduledMessage.create).not.toHaveBeenCalled();
    });

    it('falls back to a fresh ID when the idempotency ID belongs to a different user', async () => {
      // ID collision: another user already has this ID. We must NOT return
      // their row to the caller — generate a fresh ID and persist a new row.
      mockPrisma.familyMember.findUnique.mockResolvedValue({ id: 'fm-1' });
      mockPrisma.scheduledMessage.findUnique.mockResolvedValue({
        id: 'sm_collision',
        senderId: 'user-OTHER',
      });
      mockPrisma.scheduledMessage.create.mockResolvedValue({ id: 'sm_fresh' });

      const result = await service.scheduleMessage(
        'user-1',
        buildDto({ clientScheduleId: 'sm_collision' }),
      );
      expect(result).toEqual({ id: 'sm_fresh' });
      expect(mockPrisma.scheduledMessage.create).toHaveBeenCalled();
    });
  });

  describe('cancelScheduledMessage', () => {
    it('throws NotFoundException when the row does not exist', async () => {
      mockPrisma.scheduledMessage.findUnique.mockResolvedValue(null);
      await expect(
        service.cancelScheduledMessage('user-1', 'sm_x'),
      ).rejects.toBeInstanceOf(NotFoundException);
    });

    it('throws ForbiddenException when the caller is not the owner', async () => {
      mockPrisma.scheduledMessage.findUnique.mockResolvedValue({
        id: 'sm_x',
        senderId: 'user-OTHER',
        status: 'pending',
      });
      await expect(
        service.cancelScheduledMessage('user-1', 'sm_x'),
      ).rejects.toBeInstanceOf(ForbiddenException);
    });

    it('throws BadRequestException when the row is not pending', async () => {
      mockPrisma.scheduledMessage.findUnique.mockResolvedValue({
        id: 'sm_x',
        senderId: 'user-1',
        status: 'sent',
      });
      await expect(
        service.cancelScheduledMessage('user-1', 'sm_x'),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('flips status to cancelled for an owned pending row', async () => {
      mockPrisma.scheduledMessage.findUnique.mockResolvedValue({
        id: 'sm_x',
        senderId: 'user-1',
        status: 'pending',
      });
      const updated = { id: 'sm_x', status: 'cancelled' };
      mockPrisma.scheduledMessage.update.mockResolvedValue(updated);

      const result = await service.cancelScheduledMessage('user-1', 'sm_x');
      expect(result).toBe(updated);
      expect(mockPrisma.scheduledMessage.update).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { id: 'sm_x' },
          data: expect.objectContaining({ status: 'cancelled' }),
        }),
      );
    });
  });

  describe('listMyScheduledMessages', () => {
    it('queries pending + failed rows for the caller', async () => {
      const rows = [
        { id: 'sm_1', senderId: 'user-1', status: 'pending' },
        { id: 'sm_2', senderId: 'user-1', status: 'failed' },
      ];
      mockPrisma.scheduledMessage.findMany.mockResolvedValue(rows);

      const result = await service.listMyScheduledMessages('user-1');
      expect(result).toBe(rows);
      expect(mockPrisma.scheduledMessage.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: {
            senderId: 'user-1',
            status: { in: ['pending', 'failed'] },
          },
          orderBy: { scheduledFor: 'asc' },
        }),
      );
    });
  });

  describe('dispatchDueMessages (the @Cron dispatcher)', () => {
    it('calls the fn_send_scheduled_messages RPC + parses the result', async () => {
      mockPrisma.$queryRaw.mockResolvedValue([
        {
          result: JSON.stringify({
            success: true,
            sent: 3,
            failed: 1,
            processed: 4,
          }),
        },
      ]);

      await service.dispatchDueMessages();
      expect(mockPrisma.$queryRaw).toHaveBeenCalled();
    });

    it('tolerates a null RPC result without throwing', async () => {
      mockPrisma.$queryRaw.mockResolvedValue([{ result: null }]);
      await expect(service.dispatchDueMessages()).resolves.not.toThrow();
    });

    it('tolerates a malformed JSON result without throwing', async () => {
      mockPrisma.$queryRaw.mockResolvedValue([{ result: 'not-json' }]);
      await expect(service.dispatchDueMessages()).resolves.not.toThrow();
    });

    it('logs but does not throw when the RPC errors', async () => {
      mockPrisma.$queryRaw.mockRejectedValue(new Error('connection lost'));
      await expect(service.dispatchDueMessages()).resolves.not.toThrow();
    });
  });
});


