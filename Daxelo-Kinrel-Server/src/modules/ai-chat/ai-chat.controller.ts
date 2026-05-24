import {
  Controller,
  Post,
  Delete,
  Get,
  Body,
  Param,
  Query,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { AiChatService } from './ai-chat.service';
import { ChatMessageDto } from './dto/chat-message.dto';

@Controller('v1/ai-chat')
export class AiChatController {
  constructor(private readonly aiChatService: AiChatService) {}

  @Post()
  @HttpCode(HttpStatus.OK)
  async chat(@Body() dto: ChatMessageDto) {
    return this.aiChatService.chat(dto.sessionId, dto.message, dto.language);
  }

  @Delete(':sessionId')
  @HttpCode(HttpStatus.OK)
  clearSession(@Param('sessionId') sessionId: string) {
    this.aiChatService.clearSession(sessionId);
    return { message: 'Session cleared', sessionId };
  }

  @Get('suggestions')
  getSuggestions(@Query('language') language?: string) {
    return {
      suggestions: this.aiChatService.getSuggestions(language),
    };
  }
}
