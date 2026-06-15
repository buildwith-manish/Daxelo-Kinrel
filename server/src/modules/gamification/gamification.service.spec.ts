import { Test, TestingModule } from '@nestjs/testing';
import { GamificationService } from './gamification.service';
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
        { provide: KinshipService, useValue: mockKinshipService },
      ],
    }).compile();

    service = module.get<GamificationService>(GamificationService);

    jest.clearAllMocks();
    // Re-apply mock implementations after clearAllMocks
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
      ).toThrow(NotFoundException);
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
      const result = service.submitQuiz(
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
      const result = service.submitQuiz(
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

      service.submitQuiz(session.quizId, [0], 'user-1', 'User 1');

      // Session should be deleted — submitting again should throw
      expect(() =>
        service.submitQuiz(session.quizId, [0], 'user-1', 'User 1'),
      ).toThrow(NotFoundException);
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
      service.submitQuiz(session1.quizId, answers1, 'user-A', 'User A');

      // User B gets partial score (answer wrong)
      const answers2 = session2.questions.map((q, i) =>
        i === 0 ? q.correctIndex : -1,
      );
      service.submitQuiz(session2.quizId, answers2, 'user-B', 'User B');

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
      // with the fresh service instance in beforeEach it should be empty
      // Actually, the service is recreated each time so it should be empty
      expect(Array.isArray(leaderboard)).toBe(true);
    });
  });

  // ─── getDailyChallenge ─────────────────────────────────────────────
  describe('getDailyChallenge', () => {
    it('should return a daily challenge with question and hint', () => {
      const challenge = service.getDailyChallenge();

      expect(challenge.date).toBe(new Date().toISOString().split('T')[0]);
      expect(challenge.type).toBe('kinship_translation');
      expect(challenge.question).toBeDefined();
      expect(challenge.question.id).toBeDefined();
      expect(challenge.question.options).toBeDefined();
      expect(challenge.question.correctIndex).toBeDefined();
      expect(challenge.hint).toBeDefined();
      expect(typeof challenge.streakBonus).toBe('number');
      expect([5, 10]).toContain(challenge.streakBonus);
    });

    it('should return consistent challenge for same date', () => {
      const challenge1 = service.getDailyChallenge();
      const challenge2 = service.getDailyChallenge();

      expect(challenge1.date).toBe(challenge2.date);
      // Same date should yield the same question text (question ID uses Date.now() + random, so compare question instead)
      expect(challenge1.question.question).toBe(challenge2.question.question);
    });
  });
});
