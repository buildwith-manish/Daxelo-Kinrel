import { GamificationService } from './gamification.service';
import { CreateQuizDto, SubmitQuizDto } from './dto/quiz.dto';
export declare class GamificationController {
    private readonly gamificationService;
    constructor(gamificationService: GamificationService);
    createQuiz(dto: CreateQuizDto): Promise<import("./gamification.service").QuizSession>;
    submitQuiz(userId: string, user: any, quizId: string, dto: SubmitQuizDto): Promise<{
        score: number;
        totalQuestions: number;
        correctAnswers: number;
        details: Array<{
            questionId: string;
            correct: boolean;
            correctIndex: number;
            userAnswer: number;
        }>;
    }>;
    getLeaderboard(): Promise<import("./gamification.service").LeaderboardEntry[]>;
    getDailyChallenge(): Promise<import("./gamification.service").DailyChallenge>;
}
