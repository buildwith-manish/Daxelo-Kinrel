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
        hi: { native: '\u092a\u093f\u0924\u093e', latin: 'Pita' },
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
        hi: { native: '\u092e\u093e\u0924\u093e', latin: 'Mata' },
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
        hi: { native: '\u092d\u093e\u0908', latin: 'Bhai' },
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
        hi: { native: '\u092c\u0939\u0928', latin: 'Behan' },
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
        hi: { native: '\u091a\u093e\u091a\u093e', latin: 'Chacha' },
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
        hi: { native: '\u092e\u093e\u092e\u093e', latin: 'Mama' },
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
      findMany: jest.fn().mockResolvedValue([]),
      count: jest.fn().mockResolvedValue(0),
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
    mockPrisma.userContribution.findMany.mockResolvedValue([]);
    mockPrisma.userContribution.count.mockResolvedValue(0);
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
    it('should throw NotFoundException if session not found', async () => {
      await expect(
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
    it('should return paginated leaderboard from database', async () => {
      mockPrisma.userContribution.findMany.mockResolvedValue([
        { userId: 'user-A', totalPoints: 500, user: { id: 'user-A', name: 'User A', email: 'a@test.com' } },
        { userId: 'user-B', totalPoints: 300, user: { id: 'user-B', name: 'User B', email: 'b@test.com' } },
      ]);
      mockPrisma.userContribution.count.mockResolvedValue(2);

      const result = await service.getLeaderboard();

      expect(result.entries).toBeDefined();
      expect(result.entries.length).toBeLessThanOrEqual(2);
      expect(result.total).toBe(2);
      // Should be sorted by score descending
      for (let i = 1; i < result.entries.length; i++) {
        expect(result.entries[i - 1].score).toBeGreaterThanOrEqual(
          result.entries[i].score,
        );
      }
      // Ranks should be assigned
      result.entries.forEach((entry, index) => {
        expect(entry.rank).toBe(index + 1);
      });
    });

    it('should return empty leaderboard when no contributions', async () => {
      mockPrisma.userContribution.findMany.mockResolvedValue([]);
      mockPrisma.userContribution.count.mockResolvedValue(0);

      const result = await service.getLeaderboard();
      expect(result.entries).toEqual([]);
      expect(result.total).toBe(0);
    });
  });

  // ─── checkIn ───────────────────────────────────────────────────────
  describe('checkIn', () => {
    it('should create initial streak on first check-in', async () => {
      const result = await service.checkIn('user-1', 'family-1');
      expect(result.checkedIn).toBe(true);
      expect(result.currentStreak).toBe(1);
      expect(result.pointsEarned).toBeGreaterThanOrEqual(10);
    });

    it('should return checkedIn=true on same-day repeat without streak change', async () => {
      // First check-in
      const result1 = await service.checkIn('user-1', 'family-1');
      expect(result1.checkedIn).toBe(true);

      // Same-day check-in
      const result2 = await service.checkIn('user-1', 'family-1');
      expect(result2.checkedIn).toBe(true);
      expect(result2.pointsEarned).toBe(0);
    });

    it('should track separate state per family', async () => {
      // Check in to family-1
      await service.checkIn('user-1', 'family-1');
      // Check in to family-2 — starts fresh
      const result = await service.checkIn('user-1', 'family-2');
      expect(result.checkedIn).toBe(true);
      expect(result.currentStreak).toBe(1);
    });
  });

  // ─── getDailyChallenge ─────────────────────────────────────────────
  describe('getDailyChallenge', () => {
    it('should return a challenge for today', () => {
      const challenge = service.getDailyChallenge();

      expect(challenge).toBeDefined();
      expect(challenge.date).toBe(new Date().toISOString().split('T')[0]);
      expect(challenge.question).toBeDefined();
      expect(challenge.streakBonus).toBeGreaterThanOrEqual(0);
    });
  });
});
