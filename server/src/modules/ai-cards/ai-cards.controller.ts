import {
  Controller,
  Get,
  Post,
  Body,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { AiCardsService } from './ai-cards.service';
import { FestivalCardDto, KinshipCardDto } from './dto/card.dto';

@Controller('v1/ai-cards')
@UseGuards(JwtAuthGuard)
export class AiCardsController {
  constructor(private readonly aiCardsService: AiCardsService) {}

  // ── Get Festival Templates ──────────────────────────────────────────
  @Get('templates')
  async getTemplates() {
    return this.aiCardsService.getTemplates();
  }

  // ── Generate Festival Card ──────────────────────────────────────────
  @Post('festival')
  @HttpCode(HttpStatus.OK)
  async generateFestivalCard(@Body() dto: FestivalCardDto) {
    return this.aiCardsService.generateFestivalCard(dto);
  }

  // ── Generate Kinship Card ───────────────────────────────────────────
  @Post('kinship')
  @HttpCode(HttpStatus.OK)
  async generateKinshipCard(@Body() dto: KinshipCardDto) {
    return this.aiCardsService.generateKinshipCard(dto);
  }
}
