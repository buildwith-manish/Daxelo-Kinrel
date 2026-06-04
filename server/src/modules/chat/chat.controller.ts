import { Controller, Get, Post, Param, Body, Query, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { ChatService } from './chat.service';

@Controller('families/:familyId/chat')
@UseGuards(JwtAuthGuard)
export class ChatController {
  constructor(private readonly chatService: ChatService) {}

  @Get()
  async listMessages(
    @Param('familyId') familyId: string,
    @Query('limit') limit?: string,
    @Query('before') before?: string,
  ) {
    return this.chatService.listMessages(familyId, limit ? parseInt(limit, 10) : 50, before);
  }

  @Post()
  async sendMessage(
    @Param('familyId') familyId: string,
    @Body() body: { authorId: string; content: string },
  ) {
    return this.chatService.sendMessage(familyId, body.authorId, body.content);
  }
}
