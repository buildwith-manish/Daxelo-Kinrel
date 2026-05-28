import {
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
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

// ── Service ──────────────────────────────────────────────────────────

@Injectable()
export class GamificationService {
  private readonly logger = new Logger(GamificationService.name);
  private readonly quizSessions: Map<string, QuizSession> = new Map();
  private readonly leaderboard: Map<string, LeaderboardEntry> = new Map();

  constructor(private readonly kinshipService: KinshipService) {}

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
   */
  submitQuiz(
    quizId: string,
    answers: number[],
    userId: string,
    userName: string,
  ): {
    score: number;
    totalQuestions: number;
    correctAnswers: number;
    details: Array<{ questionId: string; correct: boolean; correctIndex: number; userAnswer: number }>;
  } {
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

    const score = Math.round((correctAnswers / session.totalQuestions) * 100);

    // Update leaderboard
    this.updateLeaderboard(userId, userName, score);

    // Clean up session
    this.quizSessions.delete(quizId);

    return {
      score,
      totalQuestions: session.totalQuestions,
      correctAnswers,
      details,
    };
  }

  /**
   * Get leaderboard sorted by score.
   */
  getLeaderboard(): LeaderboardEntry[] {
    const entries = [...this.leaderboard.values()].sort(
      (a, b) => b.score - a.score,
    );

    // Assign ranks
    return entries.map((entry, index) => ({
      ...entry,
      rank: index + 1,
    }));
  }

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

  // ── Private Helpers ────────────────────────────────────────────────

  private generateQuestions(
    category: string,
    language: string,
    count: number,
    difficulty: string,
  ): QuizQuestion[] {
    const questions: QuizQuestion[] = [];

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

  private updateLeaderboard(
    userId: string,
    name: string,
    score: number,
  ): void {
    const existing = this.leaderboard.get(userId);
    if (existing) {
      existing.score = Math.max(existing.score, score);
      existing.quizzesCompleted += 1;
    } else {
      this.leaderboard.set(userId, {
        userId,
        name,
        score,
        quizzesCompleted: 1,
        rank: 0,
      });
    }
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
