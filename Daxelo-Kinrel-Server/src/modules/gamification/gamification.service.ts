import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { KinshipService } from '../kinship/kinship.service';
import {
  KINSHIP_TERMS,
  LANGUAGE_MAP,
  type KinshipTerm,
  type KinshipTranslation,
} from '../kinship/data/kinship-terms';
import { kinshipData } from '@/lib/kinship';

// ── Types ──────────────────────────────────────────────────────────────

interface QuizQuestion {
  id: string;
  type: 'term_to_language' | 'native_to_relationship' | 'native_to_english';
  question: string;
  options: string[];
  correctIndex: number;
  explanation: string;
  kinshipData: {
    relationshipKey: string;
    englishTerm: string;
    category: string;
    gender: string;
  };
}

interface QuizSession {
  quizId: string;
  questions: QuizQuestion[];
  category: string;
  difficulty: string;
  language: string;
  createdAt: Date;
  submitted: boolean;
}

interface QuizResult {
  quizId: string;
  score: number;
  totalQuestions: number;
  correctAnswers: number;
  percentage: number;
  streak: number;
  results: {
    questionIndex: number;
    correct: boolean;
    yourAnswer: number;
    correctAnswer: number;
  }[];
}

interface LeaderboardEntry {
  rank: number;
  name: string;
  score: number;
  streak: number;
  avatar: string;
}

interface DailyChallenge {
  date: string;
  questions: QuizQuestion[];
  totalParticipants: number;
  averageScore: number;
}

// ── Language name map for question generation ──────────────────────────

const LANGUAGE_DISPLAY_NAMES: Record<string, string> = {
  hi: 'Hindi',
  bn: 'Bengali',
  te: 'Telugu',
  mr: 'Marathi',
  ta: 'Tamil',
  gu: 'Gujarati',
  kn: 'Kannada',
  ml: 'Malayalam',
  or: 'Odia',
  pa: 'Punjabi',
  as: 'Assamese',
  ur: 'Urdu',
  sa: 'Sanskrit',
  sd: 'Sindhi',
  en: 'English',
};

// ── Mock leaderboard data ─────────────────────────────────────────────

const MOCK_LEADERBOARD: LeaderboardEntry[] = [
  { rank: 1, name: 'Priya Sharma', score: 980, streak: 15, avatar: '👩' },
  { rank: 2, name: 'Rahul Verma', score: 940, streak: 12, avatar: '👨' },
  { rank: 3, name: 'Ananya Iyer', score: 920, streak: 10, avatar: '👩' },
  { rank: 4, name: 'Vikram Patel', score: 890, streak: 8, avatar: '👨' },
  { rank: 5, name: 'Deepika Reddy', score: 860, streak: 7, avatar: '👩' },
  { rank: 6, name: 'Arjun Nair', score: 830, streak: 6, avatar: '👨' },
  { rank: 7, name: 'Meera Joshi', score: 800, streak: 5, avatar: '👩' },
  { rank: 8, name: 'Karan Singh', score: 770, streak: 4, avatar: '👨' },
  { rank: 9, name: 'Sneha Das', score: 740, streak: 3, avatar: '👩' },
  { rank: 10, name: 'Rohan Kumar', score: 710, streak: 2, avatar: '👨' },
];

@Injectable()
export class GamificationService {
  private readonly logger = new Logger(GamificationService.name);

  /** In-memory storage for quiz sessions */
  private readonly quizSessions = new Map<string, QuizSession>();

  /** In-memory storage for user scores (userId → scores[]) */
  private readonly userScores = new Map<string, number[]>();

  /** In-memory storage for user streaks (userId → current streak) */
  private readonly userStreaks = new Map<string, number>();

  /** Cached daily challenge by date string (YYYY-MM-DD) */
  private readonly dailyChallengeCache = new Map<string, DailyChallenge>();

  constructor(private readonly kinshipService: KinshipService) {}

  // ── Generate Quiz ──────────────────────────────────────────────────

  generateQuiz(options: {
    category?: string;
    language?: string;
    count?: number;
    difficulty?: string;
  }) {
    const {
      category,
      language = 'hi',
      count = 5,
      difficulty = 'medium',
    } = options;

    // 1. Get kinship terms from KinshipService
    let terms: KinshipTerm[];

    if (category) {
      const categoryResult = this.kinshipService.getByCategory(category);
      const categoryKeys = categoryResult.results.map(
        (r: { relationshipKey: string }) => r.relationshipKey,
      );
      terms = KINSHIP_TERMS.filter((t) =>
        categoryKeys.includes(t.relationshipKey),
      );
    } else {
      terms = [...KINSHIP_TERMS];
    }

    // Filter out 'self' and terms without translations for the requested language
    const langName = LANGUAGE_MAP[language] ?? 'hindi';
    const eligibleTerms = terms.filter((t) => {
      if (t.relationshipKey === 'self') return false;
      const translation = t.translations[langName];
      return translation && translation.native && translation.latin;
    });

    if (eligibleTerms.length < 4) {
      throw new NotFoundException(
        `Not enough terms with translations for language '${language}' in category '${category ?? 'all'}'`,
      );
    }

    // 2. Select random terms for questions
    const questionCount = Math.min(count, eligibleTerms.length);
    const selectedTerms = this.shuffleArray([...eligibleTerms]).slice(
      0,
      questionCount,
    );

    // 3. Generate quiz questions
    const questions: QuizQuestion[] = selectedTerms.map((term, index) => {
      const questionType = this.pickQuestionType(difficulty);
      return this.buildQuestion(term, questionType, language, eligibleTerms, index);
    });

    // 4. Create quiz session
    const quizId = `quiz_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`;
    const session: QuizSession = {
      quizId,
      questions,
      category: category ?? 'mixed',
      difficulty,
      language,
      createdAt: new Date(),
      submitted: false,
    };

    this.quizSessions.set(quizId, session);

    return {
      quizId,
      questions,
      totalQuestions: questions.length,
      category: session.category,
      difficulty,
      language,
    };
  }

  // ── Submit Quiz ────────────────────────────────────────────────────

  submitQuiz(quizId: string, answers: Record<number, number>) {
    const session = this.quizSessions.get(quizId);

    if (!session) {
      throw new NotFoundException(`Quiz session '${quizId}' not found`);
    }

    if (session.submitted) {
      throw new NotFoundException(`Quiz session '${quizId}' already submitted`);
    }

    // Calculate score
    let correctCount = 0;
    const results = session.questions.map((q, index) => {
      const yourAnswer = answers[index] ?? -1;
      const correct = yourAnswer === q.correctIndex;
      if (correct) correctCount++;

      return {
        questionIndex: index,
        correct,
        yourAnswer,
        correctAnswer: q.correctIndex,
      };
    });

    // Mark session as submitted
    session.submitted = true;

    const percentage = Math.round((correctCount / session.questions.length) * 100);

    // Update streak (simplified: consecutive correct answers from start)
    let streak = 0;
    for (const r of results) {
      if (r.correct) {
        streak++;
      } else {
        break;
      }
    }

    return {
      quizId,
      score: correctCount,
      totalQuestions: session.questions.length,
      correctAnswers: correctCount,
      percentage,
      streak,
      results,
    } as QuizResult;
  }

  // ── Get Leaderboard ────────────────────────────────────────────────

  getLeaderboard(options: { period?: string; limit?: number }) {
    const { period = 'weekly', limit = 10 } = options;

    const leaderboard = MOCK_LEADERBOARD.slice(0, limit).map(
      (entry: LeaderboardEntry, index: number) => ({
        ...entry,
        rank: index + 1,
      }),
    );

    return {
      leaderboard,
      period,
    };
  }

  // ── Get Daily Challenge ────────────────────────────────────────────

  getDailyChallenge() {
    const today = new Date().toISOString().split('T')[0]; // YYYY-MM-DD

    // Return cached challenge if available
    const cached = this.dailyChallengeCache.get(today);
    if (cached) {
      return { challenge: cached };
    }

    // Generate a special quiz with 5 questions across random categories
    const allCategories = [
      'paternal',
      'maternal',
      'sibling',
      'spouse',
      'in_law',
      'cousin',
      'grandparent',
      'offspring',
      'extended',
    ];

    const selectedCategories = this.shuffleArray([...allCategories]).slice(0, 5);

    const questions: QuizQuestion[] = [];
    const usedKeys = new Set<string>();

    for (const cat of selectedCategories) {
      const categoryResult = this.kinshipService.getByCategory(cat);
      const categoryKeys = categoryResult.results.map(
        (r: { relationshipKey: string }) => r.relationshipKey,
      );
      const catTerms = KINSHIP_TERMS.filter(
        (t) =>
          categoryKeys.includes(t.relationshipKey) &&
          t.relationshipKey !== 'self' &&
          t.translations['hindi'] &&
          !usedKeys.has(t.relationshipKey),
      );

      if (catTerms.length < 4) continue;

      const term = catTerms[Math.floor(Math.random() * catTerms.length)];
      usedKeys.add(term.relationshipKey);

      const questionType = this.pickQuestionType('medium');
      const eligibleTerms = KINSHIP_TERMS.filter((t) => {
        if (t.relationshipKey === 'self') return false;
        return t.translations['hindi'] && t.translations['hindi'].native;
      });

      questions.push(
        this.buildQuestion(term, questionType, 'hi', eligibleTerms, questions.length),
      );
    }

    const challenge: DailyChallenge = {
      date: today,
      questions,
      totalParticipants: Math.floor(Math.random() * 500) + 100,
      averageScore: Math.round(Math.random() * 30 + 60), // 60-90%
    };

    // Cache the challenge for today
    this.dailyChallengeCache.set(today, challenge);

    return { challenge };
  }

  // ── Private Helpers ────────────────────────────────────────────────

  private pickQuestionType(
    difficulty: string,
  ): 'term_to_language' | 'native_to_relationship' | 'native_to_english' {
    const types: Array<
      'term_to_language' | 'native_to_relationship' | 'native_to_english'
    > = ['term_to_language', 'native_to_relationship', 'native_to_english'];

    if (difficulty === 'easy') {
      // Easy: mostly term_to_language (e.g., "What do you call your father in Hindi?")
      return Math.random() < 0.7
        ? 'term_to_language'
        : types[Math.floor(Math.random() * types.length)];
    }

    if (difficulty === 'hard') {
      // Hard: mostly native_to_relationship and native_to_english
      return Math.random() < 0.7
        ? types[Math.floor(Math.random() * 2) + 1]
        : 'term_to_language';
    }

    // Medium: equal distribution
    return types[Math.floor(Math.random() * types.length)];
  }

  private buildQuestion(
    term: KinshipTerm,
    type: 'term_to_language' | 'native_to_relationship' | 'native_to_english',
    language: string,
    allTerms: KinshipTerm[],
    index: number,
  ): QuizQuestion {
    const langName = LANGUAGE_MAP[language] ?? 'hindi';
    const langDisplay = LANGUAGE_DISPLAY_NAMES[language] ?? langName;
    const translation = term.translations[langName];

    if (!translation) {
      // Fallback to English question type
      return this.buildQuestion(term, 'term_to_language', 'en', allTerms, index);
    }

    let question: string;
    let correctOption: string;
    let optionGenerator: () => string[];

    switch (type) {
      case 'term_to_language': {
        // "What do you call your [relationship] in [language]?"
        question = `What do you call your ${term.englishTerm.toLowerCase()} in ${langDisplay}?`;
        correctOption = translation.native;
        optionGenerator = () =>
          this.generateWrongOptions(
            term,
            allTerms,
            language,
            'native',
          );
        break;
      }
      case 'native_to_relationship': {
        // "Which relationship does [native term] refer to?"
        question = `Which relationship does "${translation.native}" (${translation.latin}) refer to?`;
        correctOption = term.englishTerm;
        optionGenerator = () =>
          this.generateWrongOptions(
            term,
            allTerms,
            language,
            'english',
          );
        break;
      }
      case 'native_to_english': {
        // "What is the English term for [native term]?"
        question = `What is the English term for "${translation.native}"?`;
        correctOption = term.englishTerm;
        optionGenerator = () =>
          this.generateWrongOptions(
            term,
            allTerms,
            language,
            'english',
          );
        break;
      }
    }

    // Build options with correct answer placed randomly
    const wrongOptions = optionGenerator();
    const correctIndex = Math.floor(Math.random() * 4);
    const options: string[] = [];
    let wrongIdx = 0;
    for (let i = 0; i < 4; i++) {
      if (i === correctIndex) {
        options.push(correctOption);
      } else {
        options.push(wrongOptions[wrongIdx++]);
      }
    }

    const explanation =
      type === 'term_to_language'
        ? `In ${langDisplay}, ${term.englishTerm.toLowerCase()} is called "${translation.native}" (${translation.latin}).`
        : `"${translation.native}" (${translation.latin}) means ${term.englishTerm.toLowerCase()} in ${langDisplay}.`;

    return {
      id: `q_${index}_${Date.now()}`,
      type,
      question,
      options,
      correctIndex,
      explanation,
      kinshipData: {
        relationshipKey: term.relationshipKey,
        englishTerm: term.englishTerm,
        category: term.category,
        gender: term.gender,
      },
    };
  }

  private generateWrongOptions(
    correctTerm: KinshipTerm,
    allTerms: KinshipTerm[],
    language: string,
    optionType: 'native' | 'english',
  ): string[] {
    const langName = LANGUAGE_MAP[language] ?? 'hindi';
    const correctValue =
      optionType === 'native'
        ? correctTerm.translations[langName]?.native ?? correctTerm.englishTerm
        : correctTerm.englishTerm;

    // Get candidate wrong answers
    const candidates = allTerms
      .filter((t) => {
        if (t.relationshipKey === correctTerm.relationshipKey) return false;
        if (optionType === 'native') {
          const trans = t.translations[langName];
          return trans && trans.native && trans.native !== correctValue;
        }
        return t.englishTerm !== correctValue;
      })
      .map((t) => {
        if (optionType === 'native') {
          return t.translations[langName]?.native ?? t.englishTerm;
        }
        return t.englishTerm;
      })
      .filter((v) => v !== correctValue);

    // Prefer wrong answers from same category for harder questions
    const sameCategoryCandidates = allTerms
      .filter((t) => {
        if (t.relationshipKey === correctTerm.relationshipKey) return false;
        if (t.category !== correctTerm.category) return false;
        if (optionType === 'native') {
          const trans = t.translations[langName];
          return trans && trans.native && trans.native !== correctValue;
        }
        return t.englishTerm !== correctValue;
      })
      .map((t) => {
        if (optionType === 'native') {
          return t.translations[langName]?.native ?? t.englishTerm;
        }
        return t.englishTerm;
      })
      .filter((v) => v !== correctValue);

    // Use same-category options first, then fill from general pool
    const pool = [
      ...this.shuffleArray(sameCategoryCandidates),
      ...this.shuffleArray(candidates),
    ];

    // Deduplicate while preserving order
    const seen = new Set<string>();
    const uniquePool: string[] = [];
    for (const p of pool) {
      if (!seen.has(p) && p !== correctValue) {
        seen.add(p);
        uniquePool.push(p);
      }
    }

    return uniquePool.slice(0, 3);
  }

  private shuffleArray<T>(array: T[]): T[] {
    const result = [...array];
    for (let i = result.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [result[i], result[j]] = [result[j], result[i]];
    }
    return result;
  }
}
