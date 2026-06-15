import {
  Injectable,
  Logger,
  NotFoundException,
  OnModuleInit,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { KinshipService, KinshipTerm } from '../kinship/kinship.service';

// ── Types ────────────────────────────────────────────────────────────

export interface QuizQuestion {
  id: string;
  type: string;
  question: string;
  options: string[];
  correctIndex: number;
  explanation: string;
  kinshipData: Record<string, any>;
}

export interface QuizSession {
  quizId: string;
  questions: QuizQuestion[];
  totalQuestions: number;
  category: string;
  difficulty: string;
  language: string;
  createdAt: Date;
}

export interface LeaderboardEntry {
  userId: string;
  name: string;
  score: number;
  quizzesCompleted: number;
  rank: number;
}

export interface DailyChallenge {
  date: string;
  type: string;
  question: QuizQuestion;
  hint: string;
  streakBonus: number;
}

/** In-memory check-in state per user+family */
interface CheckInState {
  currentStreak: number;
  longestStreak: number;
  lastCheckInAt: Date | null;
  totalCheckIns: number;
}

/** In-memory quiz stats per user+family */
interface QuizStats {
  quizzesCompleted: number;
  totalQuizScore: number;
}

// ── Point Values ─────────────────────────────────────────────────────

const POINT_VALUES: Record<string, number> = {
  personsAdded: 5,
  relationshipsAdded: 10,
  storiesShared: 3,
  photosAdded: 3,
  eventsCreated: 5,
  commentsWritten: 2,
  invitationsSent: 5,
  personsEdited: 1,
};

// ── Standard Badge Definitions ───────────────────────────────────────

const STANDARD_BADGES = [
  {
    slug: 'first_person',
    name: 'First Person',
    nameHi: 'पहला व्यक्ति',
    description: 'Added your first family member',
    icon: '🌱',
    category: 'tree_builder',
    tier: 'bronze',
    threshold: 1,
    isSecret: false,
  },
  {
    slug: 'centurion',
    name: 'Centurion',
    nameHi: 'शताब्दी',
    description: 'Added 100 family members',
    icon: '💯',
    category: 'tree_builder',
    tier: 'gold',
    threshold: 100,
    isSecret: false,
  },
  {
    slug: 'bond_maker',
    name: 'Bond Maker',
    nameHi: 'रिश्ता बनाने वाला',
    description: 'Created 10 relationships',
    icon: '🔗',
    category: 'connector',
    tier: 'bronze',
    threshold: 10,
    isSecret: false,
  },
  {
    slug: 'super_connector',
    name: 'Super Connector',
    nameHi: 'सुपर कनेक्टर',
    description: 'Created 50 relationships',
    icon: '🤝',
    category: 'connector',
    tier: 'silver',
    threshold: 50,
    isSecret: false,
  },
  {
    slug: 'storyteller',
    name: 'Storyteller',
    nameHi: 'कहानीकार',
    description: 'Shared 5 family stories',
    icon: '📖',
    category: 'historian',
    tier: 'bronze',
    threshold: 5,
    isSecret: false,
  },
  {
    slug: 'memory_keeper',
    name: 'Memory Keeper',
    nameHi: 'याद रखने वाला',
    description: 'Shared 25 family stories',
    icon: '🏛️',
    category: 'historian',
    tier: 'silver',
    threshold: 25,
    isSecret: false,
  },
  {
    slug: 'photographer',
    name: 'Photographer',
    nameHi: 'फोटोग्राफर',
    description: 'Added 10 photos',
    icon: '📷',
    category: 'historian',
    tier: 'bronze',
    threshold: 10,
    isSecret: false,
  },
  {
    slug: 'social_butterfly',
    name: 'Social Butterfly',
    nameHi: 'सामाजिक तितली',
    description: 'Sent 10 invitations',
    icon: '🦋',
    category: 'social',
    tier: 'bronze',
    threshold: 10,
    isSecret: false,
  },
  {
    slug: 'family_organizer',
    name: 'Family Organizer',
    nameHi: 'पारिवारिक आयोजक',
    description: 'Created 5 family events',
    icon: '🎉',
    category: 'social',
    tier: 'bronze',
    threshold: 5,
    isSecret: false,
  },
];

// ── Service ──────────────────────────────────────────────────────────

@Injectable()
export class GamificationService implements OnModuleInit {
  private readonly logger = new Logger(GamificationService.name);

  /** Quiz sessions — kept in-memory (temporary by nature) */
  private readonly quizSessions: Map<string, QuizSession> = new Map();

  /** Check-in state per user+family — in-memory */
  private readonly checkInStates: Map<string, CheckInState> = new Map();

  /** Quiz stats per user+family — in-memory */
  private readonly quizStatsMap: Map<string, QuizStats> = new Map();

  /** Daily challenge submissions per user per day */
  private readonly dailyChallengeSubmissions: Map<string, Set<string>> = new Map();

  constructor(
    private readonly prisma: PrismaService,
    private readonly kinshipService: KinshipService,
  ) {}

  async onModuleInit() {
    await this.seedBadges();
  }

  // ── Badge Seeding ──────────────────────────────────────────────────

  private async seedBadges() {
    try {
      const existingCount = await this.prisma.badge.count();
      if (existingCount > 0) {
        this.logger.log(`🏅 ${existingCount} badges already exist — skipping seed`);
        return;
      }

      await this.prisma.badge.createMany({
        data: STANDARD_BADGES,
      });

      this.logger.log(`🏅 Seeded ${STANDARD_BADGES.length} badges`);
    } catch (error) {
      this.logger.warn(`Failed to seed badges: ${(error as Error).message}`);
    }
  }

  // ── Quiz ───────────────────────────────────────────────────────────

  /**
   * Start a new quiz session with generated questions.
   */
  async createQuiz(dto: {
    category?: string;
    language: string;
    count: number;
    difficulty?: string;
  }): Promise<QuizSession> {
    const {
      category = 'kinship_basic',
      language,
      count,
      difficulty = 'medium',
    } = dto;

    const quizId = `quiz_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
    const questions = this.generateQuestions(
      category,
      language,
      count,
      difficulty,
    );

    const session: QuizSession = {
      quizId,
      questions,
      totalQuestions: questions.length,
      category,
      difficulty,
      language,
      createdAt: new Date(),
    };

    this.quizSessions.set(quizId, session);
    return session;
  }

  /**
   * Submit answers for a quiz and calculate score.
   * Persists the score to UserContribution when familyId is provided.
   */
  async submitQuiz(
    quizId: string,
    answers: number[],
    userId: string,
    userName: string,
    familyId?: string,
  ): Promise<{
    score: number;
    totalQuestions: number;
    correctAnswers: number;
    details: Array<{
      questionId: string;
      correct: boolean;
      correctIndex: number;
      userAnswer: number;
    }>;
    pointsEarned: number;
    newBadges: string[];
  }> {
    const session = this.quizSessions.get(quizId);
    if (!session) {
      throw new NotFoundException(`Quiz session ${quizId} not found`);
    }

    let correctAnswers = 0;
    const details = session.questions.map((q, i) => {
      const userAnswer = answers[i] ?? -1;
      const correct = userAnswer === q.correctIndex;
      if (correct) correctAnswers++;
      return {
        questionId: q.id,
        correct,
        correctIndex: q.correctIndex,
        userAnswer,
      };
    });

    const score = Math.round(
      (correctAnswers / session.totalQuestions) * 100,
    );

    // Track quiz stats in-memory
    if (familyId) {
      const statsKey = `${userId}:${familyId}`;
      const stats = this.quizStatsMap.get(statsKey) || {
        quizzesCompleted: 0,
        totalQuizScore: 0,
      };
      stats.quizzesCompleted += 1;
      stats.totalQuizScore += score;
      this.quizStatsMap.set(statsKey, stats);

      // Award quiz points (1 point per score point)
      const pointsEarned = score;
      await this.updateContribution(userId, familyId, 'commentsWritten', 0, pointsEarned);

      // Check for new badges
      const newBadges = await this.checkAndAwardBadges(userId, familyId);

      // Clean up session
      this.quizSessions.delete(quizId);

      return {
        score,
        totalQuestions: session.totalQuestions,
        correctAnswers,
        details,
        pointsEarned,
        newBadges: newBadges.map((b) => b.slug),
      };
    }

    // Clean up session
    this.quizSessions.delete(quizId);

    return {
      score,
      totalQuestions: session.totalQuestions,
      correctAnswers,
      details,
      pointsEarned: 0,
      newBadges: [],
    };
  }

  // ── Leaderboard ────────────────────────────────────────────────────

  /**
   * Get leaderboard from DB, ordered by totalPoints desc.
   * Supports optional familyId filter and timeframe.
   */
  async getLeaderboard(query?: {
    familyId?: string;
    timeframe?: 'weekly' | 'monthly' | 'all';
    page?: number;
    limit?: number;
  }): Promise<{
    entries: LeaderboardEntry[];
    total: number;
    page: number;
    limit: number;
  }> {
    const {
      familyId,
      timeframe = 'all',
      page = 1,
      limit = 20,
    } = query || {};

    const where: any = {};

    if (familyId) {
      where.familyId = familyId;
    }

    // Apply timeframe filter based on updatedAt
    if (timeframe !== 'all') {
      const now = new Date();
      let since: Date;
      if (timeframe === 'weekly') {
        since = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
      } else {
        since = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
      }
      where.updatedAt = { gte: since };
    }

    const [contributions, total] = await Promise.all([
      this.prisma.userContribution.findMany({
        where,
        orderBy: { totalPoints: 'desc' },
        skip: (page - 1) * limit,
        take: limit,
        include: {
          user: {
            select: {
              id: true,
              name: true,
              email: true,
            },
          },
        },
      }),
      this.prisma.userContribution.count({ where }),
    ]);

    const entries: LeaderboardEntry[] = contributions.map((c, index) => ({
      userId: c.userId,
      name: c.user?.name || c.user?.email || 'Anonymous',
      score: c.totalPoints,
      quizzesCompleted: 0,
      rank: (page - 1) * limit + index + 1,
    }));

    return { entries, total, page, limit };
  }

  // ── Badges ─────────────────────────────────────────────────────────

  /**
   * List all available badges from DB.
   */
  async getBadges() {
    return this.prisma.badge.findMany({
      orderBy: [{ category: 'asc' }, { threshold: 'asc' }],
    });
  }

  /**
   * List earned badges for a user, optionally filtered by familyId.
   */
  async getUserBadges(userId: string, familyId?: string) {
    const where: any = { userId };
    if (familyId) {
      where.familyId = familyId;
    }

    return this.prisma.userBadge.findMany({
      where,
      include: {
        badge: true,
      },
      orderBy: { earnedAt: 'desc' },
    });
  }

  /**
   * Check contribution thresholds against badge thresholds and award new badges.
   */
  async checkAndAwardBadges(
    userId: string,
    familyId: string,
  ): Promise<{ slug: string; name: string }[]> {
    const contribution = await this.prisma.userContribution.findUnique({
      where: { userId_familyId: { userId, familyId } },
    });

    if (!contribution) return [];

    // Get all badges the user hasn't earned yet for this family
    const earnedBadgeIds = (
      await this.prisma.userBadge.findMany({
        where: { userId, familyId },
        select: { badgeId: true },
      })
    ).map((ub) => ub.badgeId);

    const unearnedBadges = await this.prisma.badge.findMany({
      where: {
        id: { notIn: earnedBadgeIds },
      },
    });

    const newBadges: { slug: string; name: string }[] = [];

    for (const badge of unearnedBadges) {
      const qualifies = this.checkBadgeQualification(
        badge.slug,
        badge.category,
        badge.threshold,
        contribution,
      );

      if (qualifies) {
        try {
          await this.prisma.userBadge.create({
            data: {
              userId,
              badgeId: badge.id,
              familyId,
            },
          });
          newBadges.push({ slug: badge.slug, name: badge.name });
          this.logger.log(
            `🏅 User ${userId} earned badge "${badge.name}" (${badge.slug})`,
          );
        } catch {
          // Unique constraint violation — badge already awarded, skip silently
        }
      }
    }

    return newBadges;
  }

  /**
   * Determine if a user qualifies for a badge based on their contributions.
   */
  private checkBadgeQualification(
    slug: string,
    category: string,
    threshold: number,
    contribution: Record<string, any>,
  ): boolean {
    switch (slug) {
      // Tree builder badges
      case 'first_person':
        return (contribution.personsAdded ?? 0) >= threshold;
      case 'centurion':
        return (contribution.personsAdded ?? 0) >= threshold;

      // Connector badges
      case 'bond_maker':
        return (contribution.relationshipsAdded ?? 0) >= threshold;
      case 'super_connector':
        return (contribution.relationshipsAdded ?? 0) >= threshold;

      // Historian badges
      case 'storyteller':
        return (contribution.storiesShared ?? 0) >= threshold;
      case 'memory_keeper':
        return (contribution.storiesShared ?? 0) >= threshold;
      case 'photographer':
        return (contribution.photosAdded ?? 0) >= threshold;

      // Social badges
      case 'social_butterfly':
        return (contribution.invitationsSent ?? 0) >= threshold;
      case 'family_organizer':
        return (contribution.eventsCreated ?? 0) >= threshold;

      default:
        // Generic category-based check using totalPoints
        return (contribution.totalPoints ?? 0) >= threshold;
    }
  }

  // ── Contributions ──────────────────────────────────────────────────

  /**
   * Update a contribution field and recalculate totalPoints and level.
   */
  async updateContribution(
    userId: string,
    familyId: string,
    field: string,
    increment: number = 1,
    extraPoints: number = 0,
  ): Promise<Record<string, any>> {
    const validFields = [
      'personsAdded',
      'relationshipsAdded',
      'photosAdded',
      'eventsCreated',
      'storiesShared',
      'commentsWritten',
      'invitationsSent',
      'personsEdited',
    ];

    // Upsert the contribution record
    const existing = await this.prisma.userContribution.findUnique({
      where: { userId_familyId: { userId, familyId } },
    });

    const updateData: Record<string, any> = {};

    if (validFields.includes(field) && increment > 0) {
      const currentValue = existing ? (existing as any)[field] ?? 0 : 0;
      updateData[field] = currentValue + increment;
    }

    // Recalculate total points from all fields
    const base = existing
      ? { ...existing }
      : {
          personsAdded: 0,
          relationshipsAdded: 0,
          photosAdded: 0,
          eventsCreated: 0,
          storiesShared: 0,
          commentsWritten: 0,
          invitationsSent: 0,
          personsEdited: 0,
        };

    // Apply the field increment on top of base
    if (validFields.includes(field) && increment > 0) {
      (base as any)[field] = updateData[field];
    }

    let totalPoints = 0;
    for (const f of validFields) {
      totalPoints += ((base as any)[f] ?? 0) * (POINT_VALUES[f] ?? 0);
    }
    totalPoints += extraPoints;

    updateData.totalPoints = totalPoints;
    updateData.level = Math.floor(totalPoints / 100) + 1;

    const result = await this.prisma.userContribution.upsert({
      where: { userId_familyId: { userId, familyId } },
      create: {
        userId,
        familyId,
        ...updateData,
      },
      update: updateData,
    });

    return result;
  }

  /**
   * Get contribution summary for a user in a family.
   */
  async getContribution(userId: string, familyId: string) {
    const contribution = await this.prisma.userContribution.findUnique({
      where: { userId_familyId: { userId, familyId } },
    });

    if (!contribution) {
      return {
        userId,
        familyId,
        personsAdded: 0,
        relationshipsAdded: 0,
        photosAdded: 0,
        eventsCreated: 0,
        storiesShared: 0,
        commentsWritten: 0,
        invitationsSent: 0,
        personsEdited: 0,
        totalPoints: 0,
        level: 1,
        checkIns: 0,
        currentStreak: 0,
        longestStreak: 0,
        quizzesCompleted: 0,
      };
    }

    // Merge in-memory stats
    const key = `${userId}:${familyId}`;
    const checkInState = this.checkInStates.get(key);
    const quizStats = this.quizStatsMap.get(key);

    return {
      ...contribution,
      checkIns: checkInState?.totalCheckIns ?? 0,
      currentStreak: checkInState?.currentStreak ?? 0,
      longestStreak: checkInState?.longestStreak ?? 0,
      quizzesCompleted: quizStats?.quizzesCompleted ?? 0,
    };
  }

  // ── Check-In System ────────────────────────────────────────────────

  /**
   * Record a daily check-in for a user.
   * Updates streak logic and awards points.
   */
  async checkIn(
    userId: string,
    familyId: string,
  ): Promise<{
    checkedIn: boolean;
    currentStreak: number;
    pointsEarned: number;
    newBadges: string[];
  }> {
    const key = `${userId}:${familyId}`;
    const now = new Date();
    const state = this.checkInStates.get(key) || {
      currentStreak: 0,
      longestStreak: 0,
      lastCheckInAt: null as Date | null,
      totalCheckIns: 0,
    };

    // Streak logic
    if (state.lastCheckInAt) {
      const lastDate = new Date(state.lastCheckInAt);
      const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
      const lastDateStart = new Date(lastDate.getFullYear(), lastDate.getMonth(), lastDate.getDate());
      const diffDays = Math.floor(
        (todayStart.getTime() - lastDateStart.getTime()) / (24 * 60 * 60 * 1000),
      );

      if (diffDays === 0) {
        // Already checked in today — no change
        return {
          checkedIn: true,
          currentStreak: state.currentStreak,
          pointsEarned: 0,
          newBadges: [],
        };
      } else if (diffDays === 1) {
        // Checked in yesterday — increment streak
        state.currentStreak += 1;
      } else {
        // Streak broken — reset to 1
        state.currentStreak = 1;
      }
    } else {
      // First check-in
      state.currentStreak = 1;
    }

    // Update longest streak
    if (state.currentStreak > state.longestStreak) {
      state.longestStreak = state.currentStreak;
    }

    state.lastCheckInAt = now;
    state.totalCheckIns += 1;

    this.checkInStates.set(key, state);

    // Award check-in points (10 base, +5 bonus for 7+ day streak)
    const streakBonus = state.currentStreak >= 7 ? 15 : 10;
    const pointsEarned = streakBonus;

    await this.updateContribution(userId, familyId, 'commentsWritten', 0, pointsEarned);

    // Check for new badges
    const newBadges = await this.checkAndAwardBadges(userId, familyId);

    return {
      checkedIn: true,
      currentStreak: state.currentStreak,
      pointsEarned,
      newBadges: newBadges.map((b) => b.slug),
    };
  }

  // ── Daily Challenge ────────────────────────────────────────────────

  /**
   * Get daily challenge based on today's date.
   */
  getDailyChallenge(): DailyChallenge {
    const today = new Date().toISOString().split('T')[0];
    const seed = this.dateSeed(today);

    // Generate a daily question from the kinship database
    const allTerms = this.kinshipService.getAllTerms();
    const termIndex = seed % allTerms.length;
    const term = allTerms[termIndex];

    const question = this.generateQuestionFromTerm(term, 'en', 'medium');

    return {
      date: today,
      type: 'kinship_translation',
      question,
      hint: `This term is in the "${term.relationshipCategory}" category`,
      streakBonus: seed % 3 === 0 ? 10 : 5,
    };
  }

  /**
   * Submit answer for the daily challenge.
   * Awards points if correct, tracks completion.
   */
  async submitDailyChallenge(
    userId: string,
    familyId: string,
    answer: number,
  ): Promise<{
    correct: boolean;
    pointsEarned: number;
    alreadySubmitted: boolean;
    correctIndex: number;
    newBadges: string[];
  }> {
    const today = new Date().toISOString().split('T')[0];

    // Check if already submitted today
    if (!this.dailyChallengeSubmissions.has(today)) {
      this.dailyChallengeSubmissions.set(today, new Set());
    }
    const todaySubmissions = this.dailyChallengeSubmissions.get(today)!;

    if (todaySubmissions.has(userId)) {
      return {
        correct: false,
        pointsEarned: 0,
        alreadySubmitted: true,
        correctIndex: -1,
        newBadges: [],
      };
    }

    // Mark as submitted
    todaySubmissions.add(userId);

    // Get today's challenge
    const challenge = this.getDailyChallenge();
    const correct = answer === challenge.question.correctIndex;

    let pointsEarned = 0;
    if (correct) {
      pointsEarned = challenge.streakBonus + 20; // base 20 + streak bonus
      await this.updateContribution(
        userId,
        familyId,
        'commentsWritten',
        0,
        pointsEarned,
      );
    }

    // Check for new badges
    const newBadges = correct
      ? (await this.checkAndAwardBadges(userId, familyId)).map((b) => b.slug)
      : [];

    return {
      correct,
      pointsEarned,
      alreadySubmitted: false,
      correctIndex: challenge.question.correctIndex,
      newBadges,
    };
  }

  // ── Private Helpers ────────────────────────────────────────────────

  private generateQuestions(
    category: string,
    language: string,
    count: number,
    difficulty: string,
  ): QuizQuestion[] {
    switch (category) {
      case 'kinship_basic':
        return this.generateKinshipBasicQuestions(language, count, difficulty);
      case 'kinship_advanced':
        return this.generateKinshipAdvancedQuestions(language, count, difficulty);
      case 'family_traditions':
        return this.generateFamilyTraditionsQuestions(language, count, difficulty);
      case 'languages':
        return this.generateLanguageQuestions(language, count, difficulty);
      default:
        return this.generateKinshipBasicQuestions(language, count, difficulty);
    }
  }

  private generateKinshipBasicQuestions(
    language: string,
    count: number,
    difficulty: string,
  ): QuizQuestion[] {
    const terms = this.kinshipService.getRandomTerms(count * 3, 'immediate_family');
    const questions: QuizQuestion[] = [];

    for (let i = 0; i < count && i < terms.length; i++) {
      const term = terms[i];
      questions.push(this.generateQuestionFromTerm(term, language, difficulty));
    }

    return questions;
  }

  private generateKinshipAdvancedQuestions(
    language: string,
    count: number,
    difficulty: string,
  ): QuizQuestion[] {
    const terms = this.kinshipService.getRandomTerms(
      count * 3,
      'extended_paternal',
    );
    const maternalTerms = this.kinshipService.getRandomTerms(
      count * 3,
      'extended_maternal',
    );
    const allTerms = [...terms, ...maternalTerms].sort(
      () => Math.random() - 0.5,
    );
    const questions: QuizQuestion[] = [];

    for (let i = 0; i < count && i < allTerms.length; i++) {
      questions.push(
        this.generateQuestionFromTerm(allTerms[i], language, difficulty),
      );
    }

    return questions;
  }

  private generateFamilyTraditionsQuestions(
    language: string,
    count: number,
    difficulty: string,
  ): QuizQuestion[] {
    const traditionQuestions: QuizQuestion[] = [
      {
        id: 'ft_1',
        type: 'multiple_choice',
        question:
          'During Raksha Bandhan, which relationship is primarily celebrated?',
        options: [
          'Brother-Sister',
          'Father-Daughter',
          'Husband-Wife',
          'Mother-Son',
        ],
        correctIndex: 0,
        explanation:
          'Raksha Bandhan celebrates the bond between brothers and sisters. The sister ties a rakhi (sacred thread) on her brother\'s wrist.',
        kinshipData: {
          relationships: ['brother', 'sister'],
        },
      },
      {
        id: 'ft_2',
        type: 'multiple_choice',
        question:
          'In Indian tradition, "Kanyadaan" refers to the father giving away his daughter at wedding. What does "Kanya" mean?',
        options: ['Daughter', 'Bride', 'Girl', 'All of the above'],
        correctIndex: 3,
        explanation:
          '"Kanya" means girl/daughter/bride. Kanyadaan is considered one of the most sacred duties of a father in Hindu tradition.',
        kinshipData: {
          relationships: ['father', 'daughter'],
        },
      },
      {
        id: 'ft_3',
        type: 'multiple_choice',
        question:
          'What is "Grihapravesh" in Indian family tradition?',
        options: [
          'First entry into a new home',
          'Naming ceremony',
          'Sacred thread ceremony',
          'First harvest celebration',
        ],
        correctIndex: 0,
        explanation:
          'Grihapravesh is the traditional Hindu ceremony performed when entering a new home for the first time.',
        kinshipData: {},
      },
      {
        id: 'ft_4',
        type: 'multiple_choice',
        question:
          'In the "Pag Phera" tradition, the newly married couple visits which relative\'s home?',
        options: [
          "Bride's parents' home",
          "Groom's parents' home",
          'Grandparents\' home',
          'Uncle\'s home',
        ],
        correctIndex: 0,
        explanation:
          'Pag Phera is the tradition where the newly married couple visits the bride\'s parents\' home after the wedding.',
        kinshipData: {
          relationships: ['daughter_in_law', 'son_in_law'],
        },
      },
      {
        id: 'ft_5',
        type: 'multiple_choice',
        question:
          'What is the significance of "Karva Chauth" in Indian tradition?',
        options: [
          'Wives fast for their husbands\' well-being',
          'Sisters pray for their brothers',
          'Mothers bless their children',
          'Fathers honor their ancestors',
        ],
        correctIndex: 0,
        explanation:
          'Karva Chauth is a festival where married women fast from sunrise to moonrise for the safety and longevity of their husbands.',
        kinshipData: {
          relationships: ['husband', 'wife'],
        },
      },
      {
        id: 'ft_6',
        type: 'multiple_choice',
        question:
          'During "Bhai Dooj", which family relationship is celebrated?',
        options: [
          'Brother-Sister',
          'Father-Son',
          'Mother-Daughter',
          'Husband-Wife',
        ],
        correctIndex: 0,
        explanation:
          'Bhai Dooj celebrates the bond between brothers and sisters, similar to Raksha Bandhan but observed during Diwali.',
        kinshipData: {
          relationships: ['brother', 'sister'],
        },
      },
      {
        id: 'ft_7',
        type: 'multiple_choice',
        question:
          'In the "Naamkaran" ceremony, what is determined?',
        options: [
          'The name of a newborn child',
          'The marriage date',
          'The family gotra',
          'The ancestral property division',
        ],
        correctIndex: 0,
        explanation:
          'Naamkaran is the Hindu naming ceremony for a newborn, typically performed on the 12th day after birth.',
        kinshipData: {
          relationships: ['son', 'daughter', 'father', 'mother'],
        },
      },
      {
        id: 'ft_8',
        type: 'multiple_choice',
        question:
          '"Mundan" ceremony in Indian tradition involves:',
        options: [
          'First haircut of a child',
          'Sacred thread ceremony',
          'Engagement ceremony',
          'House warming',
        ],
        correctIndex: 0,
        explanation:
          'Mundan is the Hindu tonsure ceremony where a child\'s head is shaved for the first time, believed to cleanse the soul.',
        kinshipData: {},
      },
    ];

    const shuffled = traditionQuestions.sort(() => Math.random() - 0.5);
    return shuffled.slice(0, Math.min(count, shuffled.length));
  }

  private generateLanguageQuestions(
    language: string,
    count: number,
    difficulty: string,
  ): QuizQuestion[] {
    const terms = this.kinshipService.getRandomTerms(count * 3);
    const questions: QuizQuestion[] = [];

    const targetLang = language !== 'en' ? language : 'hi';

    for (let i = 0; i < count && i < terms.length; i++) {
      const term = terms[i];
      const translation = term.translations[targetLang];

      if (!translation) continue;

      // Generate wrong options from other terms
      const otherTerms = this.kinshipService
        .getRandomTerms(4)
        .filter((t) => t.relationshipKey !== term.relationshipKey);
      const wrongOptions = otherTerms
        .slice(0, 3)
        .map((t) => t.translations[targetLang]?.latin || t.englishTerm);

      const correctOption = translation.latin;
      const allOptions = [...wrongOptions, correctOption].sort(
        () => Math.random() - 0.5,
      );
      const correctIndex = allOptions.indexOf(correctOption);

      questions.push({
        id: `lang_${Date.now()}_${i}`,
        type: 'translation',
        question: `What is the ${targetLang.toUpperCase()} term for "${term.englishTerm}"?`,
        options: allOptions,
        correctIndex,
        explanation: `"${term.englishTerm}" is called "${translation.native}" (${translation.latin}) in ${targetLang.toUpperCase()}.`,
        kinshipData: {
          relationshipKey: term.relationshipKey,
          englishTerm: term.englishTerm,
          translations: { [targetLang]: translation },
        },
      });
    }

    return questions;
  }

  private generateQuestionFromTerm(
    term: KinshipTerm,
    language: string,
    difficulty: string,
  ): QuizQuestion {
    const targetLang = language !== 'en' ? language : 'hi';
    const translation = term.translations[targetLang];

    // Get distractors
    const otherTerms = this.kinshipService
      .getRandomTerms(5)
      .filter((t) => t.relationshipKey !== term.relationshipKey);

    if (difficulty === 'easy' || !translation) {
      // English-only question
      const correctOption = term.englishTerm;
      const wrongOptions = otherTerms.slice(0, 3).map((t) => t.englishTerm);
      const allOptions = [...wrongOptions, correctOption].sort(
        () => Math.random() - 0.5,
      );
      const correctIndex = allOptions.indexOf(correctOption);

      return {
        id: `q_${Date.now()}_${Math.random().toString(36).substring(2, 6)}`,
        type: 'kinship_term',
        question: `What is the English term for "${term.relationshipKey.replace(/_/g, ' ')}"?`,
        options: allOptions,
        correctIndex,
        explanation: `"${term.relationshipKey.replace(/_/g, ' ')}" means "${term.englishTerm}" in English.`,
        kinshipData: {
          relationshipKey: term.relationshipKey,
          englishTerm: term.englishTerm,
          gender: term.gender,
          lineage: term.lineage,
        },
      };
    }

    // Medium/Hard: Ask about translation
    const correctOption = translation.latin;
    const wrongOptions = otherTerms
      .slice(0, 3)
      .map(
        (t) =>
          t.translations[targetLang]?.latin || t.englishTerm,
      );
    const allOptions = [...wrongOptions, correctOption].sort(
      () => Math.random() - 0.5,
    );
    const correctIndex = allOptions.indexOf(correctOption);

    const questionText =
      difficulty === 'hard'
        ? `In ${targetLang.toUpperCase()}, what is "${term.englishTerm}" called?`
        : `What is the ${targetLang.toUpperCase()} word for "${term.englishTerm}"?`;

    return {
      id: `q_${Date.now()}_${Math.random().toString(36).substring(2, 6)}`,
      type: 'kinship_translation',
      question: questionText,
      options: allOptions,
      correctIndex,
      explanation: `"${term.englishTerm}" is called "${translation.native}" (${translation.latin}) in ${targetLang.toUpperCase()}. Category: ${term.relationshipCategory.replace(/_/g, ' ')}.`,
      kinshipData: {
        relationshipKey: term.relationshipKey,
        englishTerm: term.englishTerm,
        gender: term.gender,
        lineage: term.lineage,
        translations: { [targetLang]: translation },
      },
    };
  }

  private dateSeed(dateString: string): number {
    let hash = 0;
    for (let i = 0; i < dateString.length; i++) {
      const char = dateString.charCodeAt(i);
      hash = (hash << 5) - hash + char;
      hash = hash & hash; // Convert to 32-bit integer
    }
    return Math.abs(hash);
  }
}
