import {
  Controller,
  Get,
  Post,
  Param,
  Body,
  Query,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { GamificationService } from './gamification.service';
import { CreateQuizDto, SubmitQuizDto } from './dto/quiz.dto';

@Controller('v1/gamification')
@UseGuards(JwtAuthGuard)
export class GamificationController {
  constructor(private readonly gamificationService: GamificationService) {}

  // ── Start New Quiz ──────────────────────────────────────────────────
  @Post('quiz')
  @HttpCode(HttpStatus.CREATED)
  async createQuiz(@Body() dto: CreateQuizDto) {
    return this.gamificationService.createQuiz(dto);
  }

  // ── Submit Quiz Answers ─────────────────────────────────────────────
  @Post('quiz/:quizId/submit')
  @HttpCode(HttpStatus.OK)
  async submitQuiz(
    @CurrentUser('id') userId: string,
    @CurrentUser() user: any,
    @Param('quizId') quizId: string,
    @Body() dto: SubmitQuizDto,
  ) {
    const userName = user?.name || user?.email || 'Anonymous';
    return this.gamificationService.submitQuiz(quizId, dto.answers, userId, userName);
  }

  // ── Get Leaderboard ─────────────────────────────────────────────────
  @Get('leaderboard')
  async getLeaderboard() {
    return this.gamificationService.getLeaderboard();
  }

  // ── Get Daily Challenge ─────────────────────────────────────────────
  @Get('daily-challenge')
  async getDailyChallenge() {
    return this.gamificationService.getDailyChallenge();
  }
}
