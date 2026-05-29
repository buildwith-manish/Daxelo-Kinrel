import { KinshipService } from '../kinship/kinship.service';
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
export declare class GamificationService {
    private readonly kinshipService;
    private readonly logger;
    private readonly quizSessions;
    private readonly leaderboard;
    constructor(kinshipService: KinshipService);
    createQuiz(dto: {
        category?: string;
        language: string;
        count: number;
        difficulty?: string;
    }): Promise<QuizSession>;
    submitQuiz(quizId: string, answers: number[], userId: string, userName: string): {
        score: number;
        totalQuestions: number;
        correctAnswers: number;
        details: Array<{
            questionId: string;
            correct: boolean;
            correctIndex: number;
            userAnswer: number;
        }>;
    };
    getLeaderboard(): LeaderboardEntry[];
    getDailyChallenge(): DailyChallenge;
    private generateQuestions;
    private generateKinshipBasicQuestions;
    private generateKinshipAdvancedQuestions;
    private generateFamilyTraditionsQuestions;
    private generateLanguageQuestions;
    private generateQuestionFromTerm;
    private updateLeaderboard;
    private dateSeed;
}
