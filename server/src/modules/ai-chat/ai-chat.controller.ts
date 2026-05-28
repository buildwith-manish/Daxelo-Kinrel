import {
  Controller,
  Get,
  Post,
  Delete,
  Param,
  Body,
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
