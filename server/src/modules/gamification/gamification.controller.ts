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
import {
  ApiTags,
  ApiOperation,
  ApiBearerAuth,
  ApiResponse,
} from '@nestjs/swagger';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { GamificationService } from './gamification.service';
import {
  CreateQuizDto,
  SubmitQuizDto,
} from './dto/quiz.dto';
import {
  LeaderboardQueryDto,
  CheckInDto,
  SubmitDailyChallengeDto,
  ContributionQueryDto,
} from './dto/gamification.dto';

@ApiTags('Gamification')
@Controller('v1/gamification')
@UseGuards(JwtAuthGuard)
@ApiBearerAuth()
export class GamificationController {
  constructor(private readonly gamificationService: GamificationService) {}

  // ── Start New Quiz ──────────────────────────────────────────────────
  @Post('quiz')
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Start a new quiz session' })
  @ApiResponse({ status: 201, description: 'Quiz session created' })
  async createQuiz(@Body() dto: CreateQuizDto) {
    return this.gamificationService.createQuiz(dto);
  }

  // ── Submit Quiz Answers ─────────────────────────────────────────────
  @Post('quiz/:quizId/submit')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Submit answers for a quiz' })
  @ApiResponse({ status: 200, description: 'Quiz submitted successfully' })
  @ApiResponse({ status: 404, description: 'Quiz session not found' })
  async submitQuiz(
    @CurrentUser('id') userId: string,
    @CurrentUser() user: any,
    @Param('quizId') quizId: string,
    @Body() dto: SubmitQuizDto,
  ) {
    const userName = user?.name || user?.email || 'Anonymous';
    const familyId = user?.familyId as string | undefined;
    return this.gamificationService.submitQuiz(
      quizId,
      dto.answers,
      userId,
      userName,
      familyId,
    );
  }

  // ── Get Leaderboard ─────────────────────────────────────────────────
  @Get('leaderboard')
  @ApiOperation({ summary: 'Get leaderboard with optional filters' })
  @ApiResponse({ status: 200, description: 'Leaderboard retrieved' })
  async getLeaderboard(@Query() query: LeaderboardQueryDto) {
    return this.gamificationService.getLeaderboard(query);
  }

  // ── Get Daily Challenge ─────────────────────────────────────────────
  @Get('daily-challenge')
  @ApiOperation({ summary: 'Get today\'s daily challenge' })
  @ApiResponse({ status: 200, description: 'Daily challenge retrieved' })
  async getDailyChallenge() {
    return this.gamificationService.getDailyChallenge();
  }

  // ── Submit Daily Challenge ──────────────────────────────────────────
  @Post('daily-challenge/submit')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Submit an answer for the daily challenge' })
  @ApiResponse({ status: 200, description: 'Daily challenge answer submitted' })
  async submitDailyChallenge(
    @CurrentUser('id') userId: string,
    @Body() dto: SubmitDailyChallengeDto,
    @Query() query: ContributionQueryDto,
  ) {
    return this.gamificationService.submitDailyChallenge(
      userId,
      query.familyId,
      dto.answer,
    );
  }

  // ── List All Badges ─────────────────────────────────────────────────
  @Get('badges')
  @ApiOperation({ summary: 'List all available badges' })
  @ApiResponse({ status: 200, description: 'Badges listed' })
  async getBadges() {
    return this.gamificationService.getBadges();
  }

  // ── Get Current User's Badges ───────────────────────────────────────
  @Get('badges/mine')
  @ApiOperation({ summary: 'Get current user\'s earned badges' })
  @ApiResponse({ status: 200, description: 'User badges retrieved' })
  async getUserBadges(
    @CurrentUser('id') userId: string,
    @Query() query: ContributionQueryDto,
  ) {
    return this.gamificationService.getUserBadges(userId, query.familyId);
  }

  // ── Get Contribution Summary ────────────────────────────────────────
  @Get('contributions')
  @ApiOperation({ summary: 'Get current user\'s contribution summary' })
  @ApiResponse({ status: 200, description: 'Contribution summary retrieved' })
  async getContributions(
    @CurrentUser('id') userId: string,
    @Query() query: ContributionQueryDto,
  ) {
    return this.gamificationService.getContribution(userId, query.familyId);
  }

  // ── Daily Check-In ──────────────────────────────────────────────────
  @Post('checkin')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Record a daily check-in' })
  @ApiResponse({ status: 200, description: 'Check-in recorded' })
  async checkIn(
    @CurrentUser('id') userId: string,
    @Body() dto: CheckInDto,
  ) {
    return this.gamificationService.checkIn(userId, dto.familyId);
  }
}
