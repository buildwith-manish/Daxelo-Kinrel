import { Controller, Get, Post, Param, Body, Query, UseGuards } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { ApiTags, ApiBearerAuth } from '@nestjs/swagger';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { ChatService } from './chat.service';

@ApiTags('Chat')
@ApiBearerAuth()
@Controller('families/:familyId/chat')
@UseGuards(JwtAuthGuard)
export class ChatController {
  constructor(private readonly chatService: ChatService) {}

  @Get()
  async listMessages(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Query('limit') limit?: string,
    @Query('before') before?: string,
  ) {
    return this.chatService.listMessages(familyId, userId, limit ? parseInt(limit, 10) : 50, before);
  }

  @Post()
  @Throttle({ default: { limit: 30, ttl: 60000 } })
  async sendMessage(
    @CurrentUser('id') userId: string,
    @Param('familyId') familyId: string,
    @Body() body: { content: string },
  ) {
    return this.chatService.sendMessage(familyId, userId, body.content);
  }
}
