import {
  Controller,
  Post,
  Body,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { AiVoiceService } from './ai-voice.service';
import { VoiceQueryDto } from './dto/voice-query.dto';

@Controller('v1/ai-voice')
export class AiVoiceController {
  constructor(private readonly aiVoiceService: AiVoiceService) {}

  /**
   * POST /v1/ai-voice/transcribe
   * Transcribe audio and search kinship terms.
   */
  @Post('transcribe')
  @HttpCode(HttpStatus.OK)
  async transcribe(@Body() dto: VoiceQueryDto) {
    return this.aiVoiceService.transcribeAndSearch(dto.audio, dto.language);
  }

  /**
   * POST /v1/ai-voice/lookup
   * Transcribe audio and perform an exact kinship lookup.
   */
  @Post('lookup')
  @HttpCode(HttpStatus.OK)
  async lookup(@Body() dto: VoiceQueryDto) {
    if (!dto.language) {
      return {
        error: 'Language is required for lookup',
        statusCode: 400,
      };
    }
    return this.aiVoiceService.quickLookup(dto.audio, dto.language);
  }
}
