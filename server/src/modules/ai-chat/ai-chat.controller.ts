import {
  Controller,
  Get,
  Post,
  Delete,
  Param,
  Body,
  Query,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { AiChatService } from './ai-chat.service';
import { AiChatMessageDto } from './dto/ai-chat-message.dto';

@Controller('v1/ai-chat')
@UseGuards(JwtAuthGuard)
export class AiChatController {
  constructor(private readonly aiChatService: AiChatService) {}

  // ── Get Chat Suggestions ────────────────────────────────────────────
  @Get('suggestions')
  async getSuggestions() {
    return this.aiChatService.getSuggestions();
  }

  // ── Get Relationship Explanation ─────────────────────────────────────
  // GET /api/v1/ai-chat/relationship-explanation?familyId=x&from=x&to=x
  @Get('relationship-explanation')
  async getRelationshipExplanation(
    @CurrentUser('id') _userId: string,
    @Query('familyId') familyId: string,
    @Query('from') fromPersonId: string,
    @Query('to') toPersonId: string,
  ) {
    return this.aiChatService.getRelationshipExplanation(
      fromPersonId,
      toPersonId,
      familyId,
    );
  }

  // ── Get Family Summary ──────────────────────────────────────────────
  // GET /api/v1/ai-chat/family-summary/:familyId
  @Get('family-summary/:familyId')
  async getFamilySummary(
    @CurrentUser('id') _userId: string,
    @Param('familyId') familyId: string,
  ) {
    return this.aiChatService.getFamilySummary(familyId);
  }

  // ── Get Smart Search Suggestions ─────────────────────────────────────
  // GET /api/v1/ai-chat/search-suggestions?q=query
  @Get('search-suggestions')
  async getSmartSearchSuggestions(
    @CurrentUser('id') userId: string,
    @Query('q') query: string,
  ) {
    return this.aiChatService.getSmartSearchSuggestions(query, userId);
  }

  // ── Send Message & Get AI Response ──────────────────────────────────
  @Post()
  @HttpCode(HttpStatus.OK)
  async chat(
    @CurrentUser('id') userId: string,
    @Body() dto: AiChatMessageDto,
  ) {
    return this.aiChatService.chat(userId, dto);
  }

  // ── Delete Chat Session ─────────────────────────────────────────────
  @Delete(':sessionId')
  @HttpCode(HttpStatus.OK)
  async deleteSession(
    @CurrentUser('id') userId: string,
    @Param('sessionId') sessionId: string,
  ) {
    return this.aiChatService.deleteSession(sessionId, userId);
  }
}
