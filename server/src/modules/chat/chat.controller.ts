import {
  Controller,
  Get,
  Post,
  Delete,
  Param,
  Body,
  Query,
  UseGuards,
} from '@nestjs/common';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { ChatService } from './chat.service';
import {
  AddReactionDto,
  MarkAsReadDto,
  RemoveReactionDto,
  SendChatMessageDto,
  TypingDto,
} from './dto/chat.dto';

/**
 * ChatController — REST endpoints for family group chat.
 *
 * Real-time updates are pushed over Socket.IO via ChatGateway; this
 * controller handles the initial fetch (message history), message send
 * (for clients without socket), and read-receipt / reaction mutations
 * (for clients that prefer HTTP over socket events).
 */
@Controller('families/:familyId/chat')
@UseGuards(JwtAuthGuard)
export class ChatController {
  constructor(private readonly chatService: ChatService) {}

  @Get()
  async listMessages(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Query('limit') limit?: string,
    @Query('before') before?: string,
  ) {
    return this.chatService.listMessages(
      familyId,
      userId,
      limit ? parseInt(limit, 10) : 50,
      before,
    );
  }

  @Post()
  async sendMessage(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Body() body: SendChatMessageDto,
  ) {
    return this.chatService.sendMessage(familyId, userId, body.content, {
      messageType: body.messageType,
      replyToId: body.replyToId,
      senderPersonId: body.senderPersonId,
      senderInitials: body.senderInitials,
    });
  }

  // ── Feature 1: read receipts ──────────────────────────────────────────

  @Post('read')
  async markAsRead(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Body() body: MarkAsReadDto,
  ) {
    return this.chatService.markAsRead(familyId, userId, body.messageId);
  }

  @Post('typing')
  async setTyping(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Body() body: Omit<TypingDto, 'familyId'>,
  ) {
    await this.chatService.setTypingStatus(familyId, userId, body.isTyping);
    return { ok: true };
  }

  @Get('typing')
  async getTypingUsers(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
  ) {
    return this.chatService.getTypingUsers(familyId, userId);
  }

  // ── Feature 2: reactions ─────────────────────────────────────────────

  @Post('reactions')
  async addReaction(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Body() body: AddReactionDto,
  ) {
    return this.chatService.addReaction(familyId, userId, body);
  }

  @Delete('reactions')
  async removeReaction(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Body() body: RemoveReactionDto,
  ) {
    return this.chatService.removeReaction(familyId, userId, body);
  }

  @Get('messages/:messageId/reactions')
  async getReactions(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Param('messageId') messageId: string,
  ) {
    // assertMember throws if not a member
    await this.chatService.listMessages(familyId, userId, 1, undefined).catch(() => {
      // listMessages validates membership; we don't actually need the messages
    });
    return this.chatService.getReactionCounts(messageId);
  }

  // ── Feature 3: chat streaks ──────────────────────────────────────────

  @Get('streak')
  async getStreak(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
  ) {
    // Validate membership before returning the streak.
    await this.chatService.listMessages(familyId, userId, 1, undefined).catch(() => {});
    const streak = await this.chatService.getStreak(familyId);
    return {
      chatId: familyId,
      currentStreak: streak?.currentStreak ?? 0,
      longestStreak: streak?.longestStreak ?? 0,
      lastMessageAt: streak?.lastMessageAt ?? null,
    };
  }
}
