import {
  Controller,
  Post,
  Body,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { AiVoiceService } from './ai-voice.service';
import { TranscribeDto, VoiceLookupDto } from './dto/voice.dto';

@Controller('v1/ai-voice')
@UseGuards(JwtAuthGuard)
export class AiVoiceController {
  constructor(private readonly aiVoiceService: AiVoiceService) {}

  // ── Transcribe Audio ────────────────────────────────────────────────
  @Post('transcribe')
  @HttpCode(HttpStatus.OK)
  async transcribe(@Body() dto: TranscribeDto) {
    return this.aiVoiceService.transcribe(dto.audio, dto.language);
  }

  // ── Lookup Kinship Term from Audio ──────────────────────────────────
  @Post('lookup')
  @HttpCode(HttpStatus.OK)
  async lookup(@Body() dto: VoiceLookupDto) {
    return this.aiVoiceService.lookup(dto.audio, dto.language);
  }
}
