import {
  Controller,
  Get,
  Post,
  Param,
  Body,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { AiFeaturesService } from './ai-features.service';
import { ExplainRelationshipDto } from './dto/explain-relationship.dto';
import { SmartSearchDto } from './dto/smart-search.dto';
import { AiChatMessageDto } from './dto/ai-features-chat.dto';

@Controller('v1/ai')
@UseGuards(JwtAuthGuard)
export class AiFeaturesController {
  constructor(private readonly aiFeaturesService: AiFeaturesService) {}

  // ── Explain a Relationship ──────────────────────────────────────────
  @Post('explain-relationship')
  @HttpCode(HttpStatus.OK)
  async explainRelationship(
    @CurrentUser('id') userId: string,
    @Body() dto: ExplainRelationshipDto,
  ) {
    return this.aiFeaturesService.explainRelationship(userId, dto);
  }

  // ── Generate Family Summary ─────────────────────────────────────────
  @Post('family-summary/:id')
  @HttpCode(HttpStatus.OK)
  async generateFamilySummary(
    @CurrentUser('id') userId: string,
    @Param('id') familyId: string,
  ) {
    return this.aiFeaturesService.generateFamilySummary(userId, familyId);
  }

  // ── Generate Family History Summary ─────────────────────────────────
  @Post('family-history/:id')
  @HttpCode(HttpStatus.OK)
  async generateHistorySummary(
    @CurrentUser('id') userId: string,
    @Param('id') familyId: string,
  ) {
    return this.aiFeaturesService.generateHistorySummary(userId, familyId);
  }

  // ── Smart Search ────────────────────────────────────────────────────
  @Post('smart-search')
  @HttpCode(HttpStatus.OK)
  async smartSearch(
    @CurrentUser('id') userId: string,
    @Body() dto: SmartSearchDto,
  ) {
    return this.aiFeaturesService.smartSearch(userId, dto);
  }

  // ── General AI Chat ─────────────────────────────────────────────────
  @Post('chat')
  @HttpCode(HttpStatus.OK)
  async chat(
    @CurrentUser('id') userId: string,
    @Body() dto: AiChatMessageDto,
  ) {
    return this.aiFeaturesService.chat(userId, dto.message, dto.context);
  }

  // ── Get Usage Stats ─────────────────────────────────────────────────
  @Get('usage')
  async getUsageStats(@CurrentUser('id') userId: string) {
    return this.aiFeaturesService.getUsageStats(userId);
  }
}
