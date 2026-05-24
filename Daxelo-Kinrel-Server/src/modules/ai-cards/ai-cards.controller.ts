import {
  Controller,
  Post,
  Get,
  Body,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { AiCardsService } from './ai-cards.service';
import { GenerateFestivalCardDto, GenerateKinshipCardDto } from './dto/generate-card.dto';

@Controller('v1/ai-cards')
export class AiCardsController {
  constructor(private readonly aiCardsService: AiCardsService) {}

  /**
   * POST /v1/ai-cards/festival
   * Generate a festival greeting card.
   */
  @Post('festival')
  @HttpCode(HttpStatus.OK)
  async generateFestivalCard(@Body() dto: GenerateFestivalCardDto) {
    return this.aiCardsService.generateFestivalCard({
      festival: dto.festival,
      kinshipTerm: dto.kinshipTerm,
      language: dto.language ?? 'en',
      style: dto.style ?? 'traditional',
    });
  }

  /**
   * POST /v1/ai-cards/kinship
   * Generate a kinship relationship card.
   */
  @Post('kinship')
  @HttpCode(HttpStatus.OK)
  async generateKinshipCard(@Body() dto: GenerateKinshipCardDto) {
    return this.aiCardsService.generateKinshipCard({
      relationshipKey: dto.relationshipKey,
      language: dto.language ?? 'en',
      style: dto.style ?? 'traditional',
    });
  }

  /**
   * GET /v1/ai-cards/templates
   * Return the list of festival templates.
   */
  @Get('templates')
  async getTemplates() {
    return this.aiCardsService.getFestivalTemplates();
  }
}
