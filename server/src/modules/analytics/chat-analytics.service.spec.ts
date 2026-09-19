import { Test, TestingModule } from '@nestjs/testing';
import { ChatAnalyticsService } from './chat-analytics.service';
import { PrismaService } from '../../prisma/prisma.service';

/**
 * ChatAnalyticsService unit tests.
 *
 * Verifies:
 *   • track() writes an Event row + returns true
 *   • track() catches + swallows DB errors (returns false, never throws)
 *   • Convenience methods (trackMessageSent, trackReactionAdded, etc.)
 *     call track() with the right eventName + metadata
 *   • getDailyCounts aggregates events by date + eventName
 *   • getEventCount returns the count for a specific event (+ optional userId filter)
 */
describe('ChatAnalyticsService', () => {
  let service: ChatAnalyticsService;

  const mockPrisma = {
    event: {
      create: jest.fn(),
      findMany: jest.fn(),
      count: jest.fn(),
    },
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        ChatAnalyticsService,
        { provide: PrismaService, useValue: mockPrisma },
      ],
    }).compile();
    service = module.get<ChatAnalyticsService>(ChatAnalyticsService);
    jest.clearAllMocks();
  });

  describe('track', () => {
    it('creates an Event row + returns true on success', async () => {
      mockPrisma.event.create.mockResolvedValue({});
      const result = await service.track(
        'message_sent',
        'user-1',
        { messageId: 'msg-1' },
        'fam-1',
      );
      expect(result).toBe(true);
      const args = mockPrisma.event.create.mock.calls[0][0];
      expect(args.data.eventName).toBe('message_sent');
      expect(args.data.userId).toBe('user-1');
      expect(args.data.chatId).toBe('fam-1');
      expect(args.data.metadata).toEqual({ messageId: 'msg-1' });
    });

    it('returns false (never throws) when the DB write fails', async () => {
      mockPrisma.event.create.mockRejectedValue(new Error('DB down'));
      const result = await service.track('message_sent', 'user-1');
      expect(result).toBe(false);
    });

    it('handles null chatId for global events', async () => {
      mockPrisma.event.create.mockResolvedValue({});
      await service.track('notification_tapped', 'user-1', { type: 'push' }, null);
      const args = mockPrisma.event.create.mock.calls[0][0];
      expect(args.data.chatId).toBeNull();
    });
  });

  describe('convenience methods', () => {
    it('trackMessageSent includes messageId + messageType in metadata', async () => {
      mockPrisma.event.create.mockResolvedValue({});
      await service.trackMessageSent('user-1', 'fam-1', 'msg-1', {
        messageType: 'text',
      });
      const args = mockPrisma.event.create.mock.calls[0][0];
      expect(args.data.eventName).toBe('message_sent');
      expect(args.data.metadata.messageId).toBe('msg-1');
      expect(args.data.metadata.messageType).toBe('text');
    });

    it('trackReactionAdded includes emoji in metadata', async () => {
      mockPrisma.event.create.mockResolvedValue({});
      await service.trackReactionAdded('user-1', 'fam-1', 'msg-1', '❤️');
      const args = mockPrisma.event.create.mock.calls[0][0];
      expect(args.data.eventName).toBe('reaction_added');
      expect(args.data.metadata.emoji).toBe('❤️');
    });

    it('trackVoiceNoteSent includes durationSeconds', async () => {
      mockPrisma.event.create.mockResolvedValue({});
      await service.trackVoiceNoteSent('user-1', 'fam-1', 'msg-1', 30);
      const args = mockPrisma.event.create.mock.calls[0][0];
      expect(args.data.eventName).toBe('voice_note_sent');
      expect(args.data.metadata.durationSeconds).toBe(30);
    });

    it('trackSearchUsed includes query + resultCount', async () => {
      mockPrisma.event.create.mockResolvedValue({});
      await service.trackSearchUsed('user-1', 'fam-1', 'hello', 5);
      const args = mockPrisma.event.create.mock.calls[0][0];
      expect(args.data.eventName).toBe('search_used');
      expect(args.data.metadata.query).toBe('hello');
      expect(args.data.metadata.resultCount).toBe(5);
    });

    it('trackFirstMessageInChat uses the right event name', async () => {
      mockPrisma.event.create.mockResolvedValue({});
      await service.trackFirstMessageInChat('user-1', 'fam-1', 'msg-1');
      const args = mockPrisma.event.create.mock.calls[0][0];
      expect(args.data.eventName).toBe('first_message_in_chat');
    });

    it('trackNotificationTapped includes notificationType', async () => {
      mockPrisma.event.create.mockResolvedValue({});
      await service.trackNotificationTapped('user-1', 'fam-1', 'chat_message_batch');
      const args = mockPrisma.event.create.mock.calls[0][0];
      expect(args.data.eventName).toBe('notification_tapped');
      expect(args.data.metadata.notificationType).toBe('chat_message_batch');
    });

    it('trackStreakEvent uses continued/broken event names', async () => {
      mockPrisma.event.create.mockResolvedValue({});
      await service.trackStreakEvent('fam-1', 5, 'continued');
      expect(mockPrisma.event.create.mock.calls[0][0].data.eventName).toBe('streak_continued');

      await service.trackStreakEvent('fam-1', 3, 'broken');
      expect(mockPrisma.event.create.mock.calls[1][0].data.eventName).toBe('streak_broken');
    });
  });

  describe('getDailyCounts', () => {
    it('aggregates events by date + eventName', async () => {
      // 3 message_sent events on 2026-09-19, 2 on 2026-09-18
      const events = [
        { eventName: 'message_sent', createdAt: new Date('2026-09-19T10:00:00Z') },
        { eventName: 'message_sent', createdAt: new Date('2026-09-19T11:00:00Z') },
        { eventName: 'message_sent', createdAt: new Date('2026-09-19T12:00:00Z') },
        { eventName: 'message_sent', createdAt: new Date('2026-09-18T10:00:00Z') },
        { eventName: 'message_sent', createdAt: new Date('2026-09-18T11:00:00Z') },
        { eventName: 'reaction_added', createdAt: new Date('2026-09-19T10:00:00Z') },
      ];
      mockPrisma.event.findMany.mockResolvedValue(events);

      const result = await service.getDailyCounts({});

      // Should return 3 rows: 2026-09-18 message_sent (2), 2026-09-19 message_sent (3), 2026-09-19 reaction_added (1)
      expect(result.length).toBe(3);
      const msgSent19 = result.find(r => r.date === '2026-09-19' && r.eventName === 'message_sent');
      expect(msgSent19).toBeDefined();
      expect(Number(msgSent19!.count)).toBe(3);
      const msgSent18 = result.find(r => r.date === '2026-09-18' && r.eventName === 'message_sent');
      expect(Number(msgSent18!.count)).toBe(2);
      const reactionAdded = result.find(r => r.date === '2026-09-19' && r.eventName === 'reaction_added');
      expect(Number(reactionAdded!.count)).toBe(1);
    });

    it('filters by eventName', async () => {
      mockPrisma.event.findMany.mockResolvedValue([]);
      await service.getDailyCounts({ eventName: 'message_sent' });
      const args = mockPrisma.event.findMany.mock.calls[0][0];
      expect(args.where.eventName).toBe('message_sent');
    });

    it('filters by date range', async () => {
      mockPrisma.event.findMany.mockResolvedValue([]);
      const from = new Date('2026-09-01');
      const to = new Date('2026-09-30');
      await service.getDailyCounts({ from, to });
      const args = mockPrisma.event.findMany.mock.calls[0][0];
      expect(args.where.createdAt.gte).toBe(from);
      expect(args.where.createdAt.lt).toBe(to);
    });
  });

  describe('getEventCount', () => {
    it('returns the count for a specific event', async () => {
      mockPrisma.event.count.mockResolvedValue(42);
      const result = await service.getEventCount('message_sent');
      expect(result).toBe(42);
      const args = mockPrisma.event.count.mock.calls[0][0];
      expect(args.where.eventName).toBe('message_sent');
    });

    it('filters by userId when provided', async () => {
      mockPrisma.event.count.mockResolvedValue(5);
      await service.getEventCount('message_sent', 'user-1');
      const args = mockPrisma.event.count.mock.calls[0][0];
      expect(args.where.userId).toBe('user-1');
    });
  });
});
