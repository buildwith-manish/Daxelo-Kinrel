import {
  Controller,
  Post,
  Get,
  Body,
  Param,
  Query,
} from '@nestjs/common';
import { GamificationService } from './gamification.service';
import { GenerateQuizDto } from './dto/generate-quiz.dto';

/**
 * GamificationController — /api/v1/gamification
 *
 * Handles:
 * - POST /api/v1/gamification/quiz              — Generate a new quiz
 * - POST /api/v1/gamification/quiz/:quizId/submit — Submit quiz answers
 * - GET  /api/v1/gamification/leaderboard         — Get leaderboard
 * - GET  /api/v1/gamification/daily-challenge      — Get today's challenge
 */
@Controller('v1/gamification')
export class GamificationController {
  constructor(private readonly gamificationService: GamificationService) {}

  @Post('quiz')
  async generateQuiz(@Body() dto: GenerateQuizDto) {
    return this.gamificationService.generateQuiz({
      category: dto.category,
      language: dto.language,
      count: dto.count,
      difficulty: dto.difficulty,
    });
  }

  @Post('quiz/:quizId/submit')
  async submitQuiz(
    @Param('quizId') quizId: string,
    @Body() body: { answers: Record<number, number> },
  ) {
    return this.gamificationService.submitQuiz(quizId, body.answers);
  }

  @Get('leaderboard')
  async getLeaderboard(
    @Query('period') period?: string,
    @Query('limit') limit?: number,
  ) {
    return this.gamificationService.getLeaderboard({
      period: period ?? 'weekly',
      limit: limit ?? 10,
    });
  }

  @Get('daily-challenge')
  async getDailyChallenge() {
    return this.gamificationService.getDailyChallenge();
  }
}
