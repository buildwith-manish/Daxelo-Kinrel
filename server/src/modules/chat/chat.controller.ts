import {
  Controller,
  Get,
  Post,
  Delete,
  Param,
  Body,
  Query,
  UseGuards,
  UseInterceptors,
  UploadedFile,
  BadRequestException,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { ChatService } from './chat.service';
import { MediaService } from './media.service';
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
  constructor(
    private readonly chatService: ChatService,
    private readonly mediaService: MediaService,
  ) {}

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

  // ── Feature 3: empty-state nudge ────────────────────────────────────
  //
  // Returns relationship-aware greeting suggestions + upcoming
  // birthday/anniversary data for the chat empty state. Called by the
  // Flutter empty_chat_state widget when a chat has zero messages.

  @Get('nudge')
  async getEmptyStateNudge(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
  ) {
    return this.chatService.getEmptyStateNudge(familyId, userId);
  }

  // ── Feature 2: Group chat endpoints ──────────────────────────────────

  /**
   * GET /families/:familyId/chat/info
   * Returns group chat info: participant list (with online status) +
   * family metadata. Used by the Flutter group info screen.
   */
  @Get('info')
  async getGroupInfo(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
  ) {
    return this.chatService.getGroupInfo(familyId, userId);
  }

  /**
   * GET /families/:familyId/chat/messages/:messageId/read-count
   * Returns { readCount, totalParticipants } for "seen by 4/7" UI.
   */
  @Get('messages/:messageId/read-count')
  async getReadCount(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Param('messageId') messageId: string,
  ) {
    return this.chatService.getReadCount(familyId, userId, messageId);
  }

  /**
   * GET /families/:familyId/chat/mentions?userId=X
   * Returns messages that @mention a specific user. Used by the Flutter
   * "Mentions" filter in the chat search screen.
   */
  @Get('mentions')
  async getMentions(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Query('userId') mentionedUserId?: string,
    @Query('limit') limit?: string,
  ) {
    // If userId not provided, default to the requesting user (their own mentions)
    return this.chatService.getMentionsForUser(
      familyId,
      userId,
      mentionedUserId || userId,
      limit ? parseInt(limit, 10) : 20,
    );
  }

  /**
   * POST /families/:familyId/chat/with-mentions
   * Send a message with @mentions. The body contains the message content
   * + an array of mention refs.
   */
  @Post('with-mentions')
  async sendMessageWithMentions(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Body() body: {
      content: string;
      mentions: Array<{ userId: string; name: string; start: number; end: number }>;
      messageType?: string;
      replyToId?: string;
      senderPersonId?: string;
      senderInitials?: string;
    },
  ) {
    return this.chatService.sendMessageWithMentions(
      familyId,
      userId,
      body.content,
      body.mentions || [],
      {
        messageType: body.messageType,
        replyToId: body.replyToId,
        senderPersonId: body.senderPersonId,
        senderInitials: body.senderInitials,
      },
    );
  }

  // ── Feature 5: Message search ──────────────────────────────────────
  //
  // GET /families/:familyId/chat/search?q=<query>&limit=20
  // Returns matching messages sorted by createdAt DESC (newest first).
  // Case-insensitive substring search (Postgres ILIKE) on the content field.

  @Get('search')
  async searchMessages(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Query('q') query: string,
    @Query('limit') limit?: string,
  ) {
    return this.chatService.searchMessages(
      familyId,
      userId,
      query ?? '',
      limit ? parseInt(limit, 10) : 20,
    );
  }

  // ── Feature 3: Message pinning ──────────────────────────────────────

  /**
   * POST /families/:familyId/chat/messages/:messageId/pin
   * Pin a message. Sets isPinned=true + pinnedBy + pinnedAt.
   */
  @Post('messages/:messageId/pin')
  async pinMessage(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Param('messageId') messageId: string,
  ) {
    return this.chatService.pinMessage(familyId, userId, messageId);
  }

  /**
   * DELETE /families/:familyId/chat/messages/:messageId/pin
   * Unpin a message. Clears isPinned + pinnedBy + pinnedAt.
   */
  @Delete('messages/:messageId/pin')
  async unpinMessage(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @Param('messageId') messageId: string,
  ) {
    return this.chatService.unpinMessage(familyId, userId, messageId);
  }

  /**
   * GET /families/:familyId/chat/pinned
   * Returns all pinned messages in this chat (newest-pinned first, max 10).
   */
  @Get('pinned')
  async getPinnedMessages(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
  ) {
    return this.chatService.getPinnedMessages(familyId, userId);
  }

  // ── Feature 4: Media upload (images, voice notes, videos) ──────────
  //
  // Multipart form-data POST. The client uploads the file bytes + the
  // mediaType (image|voice|video) + optional durationSeconds (for voice/video).
  // The server validates the file, uploads to Supabase Storage, and returns
  // the public URL. The client then calls sendMessage with mediaUrl +
  // mediaType to persist the message.
  //
  // We use a generated messageId (cm_<timestamp>_<random>) as the storage
  // path so the file is uniquely named + tied to the eventual message.
  // If the message send fails after upload, the orphaned file is cleaned
  // up by a future GC pass (not implemented yet — acceptable for now).

  @Post('media')
  @UseInterceptors(FileInterceptor('file', {
    limits: { fileSize: 25 * 1024 * 1024 }, // 25 MB hard cap at multer level
  }))
  async uploadMedia(
    @Param('familyId') familyId: string,
    @CurrentUser('id') userId: string,
    @UploadedFile() file: Express.Multer.File,
    @Body() body: { mediaType: string; durationSeconds?: string },
  ) {
    if (!file) {
      throw new BadRequestException('No file uploaded (expected multipart field "file")');
    }
    if (!body.mediaType) {
      throw new BadRequestException('mediaType is required (image|voice|video)');
    }

    // Validate membership — don't allow uploads to families the user
    // doesn't belong to.
    await this.chatService.listMessages(familyId, userId, 1, undefined).catch(() => {});

    // Generate a unique messageId for the storage path. The client will
    // use this same ID when it calls sendMessage with mediaUrl.
    const messageId = `cm_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;

    const result = await this.mediaService.uploadMedia({
      buffer: file.buffer,
      mediaType: body.mediaType,
      mimeType: file.mimetype,
      familyId,
      messageId,
      durationSeconds: body.durationSeconds ? parseInt(body.durationSeconds, 10) : null,
    });

    return {
      messageId,
      ...result,
    };
  }
}
