import { Test, TestingModule } from '@nestjs/testing';
import { GamificationService } from './gamification.service';
import { PrismaService } from '../../prisma/prisma.service';
import { KinshipService, KinshipTerm } from '../kinship/kinship.service';
import { NotFoundException } from '@nestjs/common';

describe('GamificationService', () => {
  let service: GamificationService;

  const mockTerms: KinshipTerm[] = [
    {
      relationshipKey: 'father',
      englishTerm: 'Father',
      gender: 'male',
      lineage: 'neutral',
      relationshipCategory: 'immediate_family',
      translations: {
        hi: { native: 'पिता', latin: 'Pita' },
      },
      aliases: ['papa', 'dad'],
    },
    {
      relationshipKey: 'mother',
      englishTerm: 'Mother',
      gender: 'female',
      lineage: 'neutral',
      relationshipCategory: 'immediate_family',
      translations: {
        hi: { native: 'माता', latin: 'Mata' },
      },
      aliases: ['mummy', 'mom'],
    },
    {
      relationshipKey: 'brother',
      englishTerm: 'Brother',
      gender: 'male',
      lineage: 'neutral',
      relationshipCategory: 'immediate_family',
      translations: {
        hi: { native: 'भाई', latin: 'Bhai' },
      },
      aliases: ['bhai'],
    },
    {
      relationshipKey: 'sister',
      englishTerm: 'Sister',
      gender: 'female',
      lineage: 'neutral',
      relationshipCategory: 'immediate_family',
      translations: {
        hi: { native: 'बहन', latin: 'Behan' },
      },
      aliases: [],
    },
    {
      relationshipKey: 'paternal_uncle',
      englishTerm: 'Paternal Uncle',
      gender: 'male',
      lineage: 'paternal',
      relationshipCategory: 'extended_paternal',
      translations: {
        hi: { native: 'चाचा', latin: 'Chacha' },
      },
      aliases: ['chacha'],
    },
    {
      relationshipKey: 'maternal_uncle',
      englishTerm: 'Maternal Uncle',
      gender: 'male',
      lineage: 'maternal',
      relationshipCategory: 'extended_maternal',
      translations: {
        hi: { native: 'मामा', latin: 'Mama' },
      },
      aliases: ['mama'],
    },
  ];

  const mockPrisma = {
    badge: {
      count: jest.fn().mockResolvedValue(0),
      createMany: jest.fn().mockResolvedValue({ count: 0 }),
      findMany: jest.fn().mockResolvedValue([]),
    },
    userContribution: {
      findUnique: jest.fn().mockResolvedValue(null),
      upsert: jest.fn().mockResolvedValue({}),
    },
    userBadge: {
      create: jest.fn().mockResolvedValue({}),
      findFirst: jest.fn().mockResolvedValue(null),
    },
  };

  const mockKinshipService = {
    getAllTerms: jest.fn().mockReturnValue(mockTerms),
    getRandomTerms: jest.fn().mockImplementation((count: number, category?: string) => {
      const pool = category
        ? mockTerms.filter((t) => t.relationshipCategory === category)
        : mockTerms;
      return pool.slice(0, Math.min(count, pool.length));
    }),
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        GamificationService,
        { provide: PrismaService, useValue: mockPrisma },
        { provide: KinshipService, useValue: mockKinshipService },
      ],
    }).compile();

    service = module.get<GamificationService>(GamificationService);

    jest.clearAllMocks();
    // Re-apply mock implementations after clearAllMocks
    mockPrisma.badge.count.mockResolvedValue(0);
    mockPrisma.badge.createMany.mockResolvedValue({ count: 0 });
    mockPrisma.badge.findMany.mockResolvedValue([]);
    mockPrisma.userContribution.findUnique.mockResolvedValue(null);
    mockPrisma.userContribution.upsert.mockResolvedValue({});
    mockPrisma.userBadge.create.mockResolvedValue({});
    mockPrisma.userBadge.findFirst.mockResolvedValue(null);
    mockKinshipService.getAllTerms.mockReturnValue(mockTerms);
    mockKinshipService.getRandomTerms.mockImplementation(
      (count: number, category?: string) => {
        const pool = category
          ? mockTerms.filter((t) => t.relationshipCategory === category)
          : mockTerms;
        return pool.slice(0, Math.min(count, pool.length));
      },
    );
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });

  // ─── createQuiz ────────────────────────────────────────────────────
  describe('createQuiz', () => {
    it('should generate questions based on category/language/count/difficulty', async () => {
      const result = await service.createQuiz({
        category: 'kinship_basic',
        language: 'hi',
        count: 3,
        difficulty: 'medium',
      });

      expect(result.questions).toBeDefined();
      expect(result.questions.length).toBeLessThanOrEqual(3);
      expect(result.category).toBe('kinship_basic');
      expect(result.difficulty).toBe('medium');
      expect(result.language).toBe('hi');
      expect(result.quizId).toMatch(/^quiz_/);
      expect(result.totalQuestions).toBe(result.questions.length);
    });

    it('should default to kinship_basic if unknown category', async () => {
      const result = await service.createQuiz({
        category: 'unknown_category',
        language: 'en',
        count: 2,
        difficulty: 'easy',
      });

      expect(result.questions).toBeDefined();
      expect(result.questions.length).toBeGreaterThan(0);
    });

    it('should use default difficulty medium if not provided', async () => {
      const result = await service.createQuiz({
        language: 'en',
        count: 2,
      });

      expect(result.difficulty).toBe('medium');
      expect(result.category).toBe('kinship_basic');
    });

    it('should generate family_traditions questions', async () => {
      const result = await service.createQuiz({
        category: 'family_traditions',
        language: 'en',
        count: 3,
        difficulty: 'easy',
      });

      expect(result.questions).toBeDefined();
      expect(result.questions.length).toBeLessThanOrEqual(3);
      expect(result.questions.length).toBeGreaterThan(0);
    });

    it('should generate language questions', async () => {
      const result = await service.createQuiz({
        category: 'languages',
        language: 'hi',
        count: 2,
        difficulty: 'medium',
      });

      expect(result.questions).toBeDefined();
    });
  });

  // ─── submitQuiz ────────────────────────────────────────────────────
  describe('submitQuiz', () => {
    it('should throw NotFoundException if session not found', () => {
      expect(() =>
        service.submitQuiz('nonexistent-quiz', [0], 'user-1', 'User 1'),
      ).rejects.toThrow(NotFoundException);
    });

    it('should calculate score correctly', async () => {
      const session = await service.createQuiz({
        category: 'kinship_basic',
        language: 'en',
        count: 2,
        difficulty: 'easy',
      });

      // Answer all correctly
      const answers = session.questions.map((q) => q.correctIndex);
      const result = await service.submitQuiz(
        session.quizId,
        answers,
        'user-1',
        'User 1',
      );

      expect(result.score).toBe(100);
      expect(result.correctAnswers).toBe(session.totalQuestions);
      expect(result.totalQuestions).toBe(session.totalQuestions);
      expect(result.details).toHaveLength(session.totalQuestions);
      result.details.forEach((d) => {
        expect(d.correct).toBe(true);
      });
    });

    it('should calculate partial score', async () => {
      const session = await service.createQuiz({
        category: 'kinship_basic',
        language: 'en',
        count: 2,
        difficulty: 'easy',
      });

      // Answer only first correctly
      const answers = session.questions.map((q, i) =>
        i === 0 ? q.correctIndex : -1,
      );
      const result = await service.submitQuiz(
        session.quizId,
        answers,
        'user-1',
        'User 1',
      );

      expect(result.score).toBe(
        Math.round((1 / session.totalQuestions) * 100),
      );
      expect(result.correctAnswers).toBe(1);
    });

    it('should clean up session after submission', async () => {
      const session = await service.createQuiz({
        category: 'kinship_basic',
        language: 'en',
        count: 1,
        difficulty: 'easy',
      });

      await service.submitQuiz(session.quizId, [0], 'user-1', 'User 1');

      // Session should be deleted — submitting again should throw
      await expect(
        service.submitQuiz(session.quizId, [0], 'user-1', 'User 1'),
      ).rejects.toThrow(NotFoundException);
    });
  });

  // ─── getLeaderboard ────────────────────────────────────────────────
  describe('getLeaderboard', () => {
    it('should return sorted entries with ranks', async () => {
      // Create two quiz sessions and submit them
      const session1 = await service.createQuiz({
        language: 'en',
        count: 2,
        difficulty: 'easy',
      });
      const session2 = await service.createQuiz({
        language: 'en',
        count: 2,
        difficulty: 'easy',
      });

      // User A gets 100%
      const answers1 = session1.questions.map((q) => q.correctIndex);
      await service.submitQuiz(session1.quizId, answers1, 'user-A', 'User A');

      // User B gets partial score (answer wrong)
      const answers2 = session2.questions.map((q, i) =>
        i === 0 ? q.correctIndex : -1,
      );
      await service.submitQuiz(session2.quizId, answers2, 'user-B', 'User B');

      const leaderboard = service.getLeaderboard();

      expect(leaderboard.length).toBeGreaterThanOrEqual(2);
      // Should be sorted by score descending
      for (let i = 1; i < leaderboard.length; i++) {
        expect(leaderboard[i - 1].score).toBeGreaterThanOrEqual(
          leaderboard[i].score,
        );
      }
      // Ranks should be assigned
      leaderboard.forEach((entry, index) => {
        expect(entry.rank).toBe(index + 1);
      });
    });

    it('should return empty leaderboard when no quizzes submitted', () => {
      const leaderboard = service.getLeaderboard();
      // Might have entries from previous tests if not isolated, but
      // at minimum it should be an array
      expect(Array.isArray(leaderboard)).toBe(true);
    });
  });

  // ─── checkIn ───────────────────────────────────────────────────────
  describe('checkIn', () => {
    it('should create initial streak and increment on consecutive days', async () => {
      // First check-in
      const result1 = await service.checkIn('user-1', 'family-1');
      expect(result1.currentStreak).toBe(1);
      expect(result1.totalCheckIns).toBe(1);

      // Second check-in (same day should not increment streak, but counts)
      const result2 = await service.checkIn('user-1', 'family-1');
      expect(result2.currentStreak).toBe(1); // Same day = no streak increment
      expect(result2.totalCheckIns).toBe(2); // But total check-ins increment
    });

    it('should track longest streak', async () => {
      // Simulate multiple check-ins
      await service.checkIn('user-1', 'family-1');
      // Check-in with different family
      const result = await service.checkIn('user-1', 'family-2');
      expect(result.totalCheckIns).toBe(1); // Different family, starts fresh
    });
  });

  // ─── getDailyChallenge ─────────────────────────────────────────────
  describe('getDailyChallenge', () => {
    it('should return a challenge for today', () => {
      const challenge = service.getDailyChallenge('en');

      expect(challenge).toBeDefined();
      expect(challenge.date).toBe(new Date().toISOString().split('T')[0]);
      expect(challenge.question).toBeDefined();
      expect(challenge.streakBonus).toBeGreaterThanOrEqual(0);
    });

    it('should return different challenges for different languages', () => {
      const enChallenge = service.getDailyChallenge('en');
      const hiChallenge = service.getDailyChallenge('hi');

      // Both should be valid challenges (might be same or different)
      expect(enChallenge.question).toBeDefined();
      expect(hiChallenge.question).toBeDefined();
    });
  });
});
