import { Test, TestingModule } from '@nestjs/testing';
import { StreakService } from './streak.service';
import { ChatAnalyticsService } from '../analytics/chat-analytics.service';
import { PrismaService } from '../../prisma/prisma.service';

/**
 * StreakService unit tests.
 *
 * Verifies the three streak paths:
 *   1. First-ever message in a chat → create row with streak=1
 *   2. Message within 24h window + different calendar day → increment
 *   3. Message within 24h window + same calendar day → no increment
 *      (avoids double-counting rapid-fire messages)
 *   4. Message outside 24h window → reset to 1
 *   5. longestStreak is preserved on reset
 *
 * Uses a fake timer so the 24h window math is deterministic.
 */
describe('StreakService', () => {
  let service: StreakService;

  const mockPrisma = {
    chatStreak: {
      create: jest.fn(),
      findUnique: jest.fn(),
      update: jest.fn(),
    },
    $transaction: jest.fn((cb) => cb(mockPrisma)),
  };

  const mockAnalyticsService = {
    trackStreakEvent: jest.fn().mockResolvedValue(true),
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        StreakService,
        { provide: PrismaService, useValue: mockPrisma },
        { provide: ChatAnalyticsService, useValue: mockAnalyticsService },
      ],
    }).compile();
    service = module.get<StreakService>(StreakService);
    jest.clearAllMocks();
    // Use a fixed "now" so the 24h window + same-calendar-day math is
    // deterministic regardless of when the test suite runs.
    // Now = 2026-06-15T10:00:00Z (a Monday morning).
    jest.useFakeTimers();
    jest.setSystemTime(new Date('2026-06-15T10:00:00Z'));
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  describe('recordMessage — first message (no existing streak)', () => {
    it('creates a streak row with currentStreak=1, longestStreak=1', async () => {
      mockPrisma.chatStreak.create.mockResolvedValue({});
      const result = await service.recordMessage('fam-1');
      expect(result.currentStreak).toBe(1);
      expect(result.longestStreak).toBe(1);
      expect(result.streakJustIncreased).toBe(false);
      expect(result.streakReset).toBe(false);
      expect(mockPrisma.chatStreak.create).toHaveBeenCalledTimes(1);
      const createArgs = mockPrisma.chatStreak.create.mock.calls[0][0];
      expect(createArgs.data.chatId).toBe('fam-1');
      expect(createArgs.data.currentStreak).toBe(1);
    });
  });

  describe('recordMessage — existing streak, within window, different day', () => {
    it('increments currentStreak and updates longestStreak', async () => {
      // Now = 2026-06-15T10:00:00Z. Last message at 2026-06-14T22:00:00Z
      // (12 hours ago, different calendar day, within 24h window).
      const conflictErr = Object.assign(new Error('dup'), { code: 'P2002' });
      mockPrisma.chatStreak.create.mockRejectedValue(conflictErr);
      const lastMessageAt = new Date('2026-06-14T22:00:00Z');
      mockPrisma.chatStreak.findUnique.mockResolvedValue({
        chatId: 'fam-1',
        currentStreak: 3,
        longestStreak: 5,
        lastMessageAt,
      });
      mockPrisma.chatStreak.update.mockResolvedValue({});

      const result = await service.recordMessage('fam-1');

      expect(result.currentStreak).toBe(4);
      expect(result.longestStreak).toBe(5); // existing longest stays at 5
      expect(result.streakJustIncreased).toBe(true);
      expect(result.streakReset).toBe(false);
    });

    it('updates longestStreak when currentStreak exceeds it', async () => {
      const conflictErr = Object.assign(new Error('dup'), { code: 'P2002' });
      mockPrisma.chatStreak.create.mockRejectedValue(conflictErr);
      const lastMessageAt = new Date('2026-06-14T22:00:00Z');
      mockPrisma.chatStreak.findUnique.mockResolvedValue({
        chatId: 'fam-1',
        currentStreak: 5,
        longestStreak: 5,
        lastMessageAt,
      });
      mockPrisma.chatStreak.update.mockResolvedValue({});

      const result = await service.recordMessage('fam-1');
      expect(result.currentStreak).toBe(6);
      expect(result.longestStreak).toBe(6); // bumped
    });
  });

  describe('recordMessage — existing streak, same calendar day', () => {
    it('does not increment (avoids double-counting rapid-fire messages)', async () => {
      // Same calendar day: now = 10:00, last = 09:50 (10 min ago, same day).
      const conflictErr = Object.assign(new Error('dup'), { code: 'P2002' });
      mockPrisma.chatStreak.create.mockRejectedValue(conflictErr);
      const lastMessageAt = new Date('2026-06-15T09:50:00Z');
      mockPrisma.chatStreak.findUnique.mockResolvedValue({
        chatId: 'fam-1',
        currentStreak: 3,
        longestStreak: 5,
        lastMessageAt,
      });
      mockPrisma.chatStreak.update.mockResolvedValue({});

      const result = await service.recordMessage('fam-1');
      expect(result.currentStreak).toBe(3); // unchanged
      expect(result.longestStreak).toBe(5);
      expect(result.streakJustIncreased).toBe(false);
      expect(result.streakReset).toBe(false);
    });
  });

  describe('recordMessage — existing streak, outside 24h window', () => {
    it('resets currentStreak to 1, preserves longestStreak', async () => {
      // Now = 2026-06-15T10:00:00Z. Last message 3 days ago (outside 24h).
      const conflictErr = Object.assign(new Error('dup'), { code: 'P2002' });
      mockPrisma.chatStreak.create.mockRejectedValue(conflictErr);
      const lastMessageAt = new Date('2026-06-12T10:00:00Z');
      mockPrisma.chatStreak.findUnique.mockResolvedValue({
        chatId: 'fam-1',
        currentStreak: 10,
        longestStreak: 12,
        lastMessageAt,
      });
      mockPrisma.chatStreak.update.mockResolvedValue({});

      const result = await service.recordMessage('fam-1');
      expect(result.currentStreak).toBe(1);
      expect(result.longestStreak).toBe(12); // preserved
      expect(result.streakJustIncreased).toBe(false);
      expect(result.streakReset).toBe(true);
    });
  });

  describe('getStreak', () => {
    it('returns the streak row for a chat', async () => {
      mockPrisma.chatStreak.findUnique.mockResolvedValue({
        chatId: 'fam-1',
        currentStreak: 7,
        longestStreak: 10,
        lastMessageAt: new Date(),
      });
      const result = await service.getStreak('fam-1');
      expect(result?.currentStreak).toBe(7);
      expect(mockPrisma.chatStreak.findUnique).toHaveBeenCalledWith({
        where: { chatId: 'fam-1' },
      });
    });

    it('returns null when no streak row exists', async () => {
      mockPrisma.chatStreak.findUnique.mockResolvedValue(null);
      const result = await service.getStreak('fam-new');
      expect(result).toBeNull();
    });
  });
});
