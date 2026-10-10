// server/src/modules/chat/secret-chats.controller.ts
//
// DAXELO KINREL — Tier 5 Feature 5.1: Secret Chats — Controller

import { Body, Controller, Delete, Get, Param, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { SecretChatsService } from './secret-chats.service';

@Controller('chat/secret')
@UseGuards(JwtAuthGuard)
export class SecretChatsController {
  constructor(private readonly service: SecretChatsService) {}

  /// POST /chat/secret/public-key
  /// Upsert the caller's public key (x25519 or ed25519).
  @Post('public-key')
  async upsertPublicKey(
    @CurrentUser('id') userId: string,
    @Body() body: { keyType: string; publicKeyB64: string },
  ) {
    return this.service.upsertPublicKey(userId, body);
  }

  /// GET /chat/secret/public-key/:userId?keyType=x25519
  /// Public read of any user's public key (to compute the shared secret).
  @Get('public-key/:userId')
  async getPublicKey(
    @Param('userId') userId: string,
    @Query('keyType') keyType?: string,
  ) {
    return this.service.getPublicKey(userId, keyType ?? 'x25519');
  }

  /// POST /chat/secret/initiate
  /// Initiate a secret chat with a peer. Body: { peerUserId, keyFingerprint }
  @Post('initiate')
  async initiate(
    @CurrentUser('id') userId: string,
    @Body() body: { peerUserId: string; keyFingerprint: string },
  ) {
    return this.service.initiateSecretChat(userId, body);
  }

  /// PATCH /chat/secret/:id/respond
  /// Peer accepts or rejects a pending chat. Body: { accept, keyFingerprint? }
  @Patch(':id/respond')
  async respond(
    @CurrentUser('id') userId: string,
    @Param('id') id: string,
    @Body() body: { accept: boolean; keyFingerprint?: string | null },
  ) {
    return this.service.respondToSecretChat(userId, { secretChatId: id, ...body });
  }

  /// GET /chat/secret
  /// List the caller's secret chats (pending incoming + active).
  @Get()
  async list(@CurrentUser('id') userId: string) {
    return this.service.listMySecretChats(userId);
  }

  /// POST /chat/secret/:id/messages
  /// Send a ciphertext message. Body: { ciphertext, iv, messageType?, expiresAt? }
  @Post(':id/messages')
  async sendMessage(
    @CurrentUser('id') userId: string,
    @Param('id') id: string,
    @Body() body: { ciphertext: string; iv: string; messageType?: string; expiresAt?: string | null },
  ) {
    return this.service.sendSecretMessage(userId, {
      secretChatId: id,
      ciphertext: body.ciphertext,
      iv: body.iv,
      messageType: body.messageType,
      expiresAt: body.expiresAt ? new Date(body.expiresAt) : null,
    });
  }

  /// GET /chat/secret/:id/messages?limit=&before=
  /// List messages (ciphertext only).
  @Get(':id/messages')
  async listMessages(
    @CurrentUser('id') userId: string,
    @Param('id') id: string,
    @Query('limit') limit?: string,
    @Query('before') before?: string,
  ) {
    return this.service.listMessages(
      userId,
      id,
      limit ? parseInt(limit, 10) : 50,
      before ? new Date(before) : undefined,
    );
  }

  /// POST /chat/secret/:id/read
  /// Mark messages as read (flips isRead, no content exposure).
  @Post(':id/read')
  async markRead(
    @CurrentUser('id') userId: string,
    @Param('id') id: string,
    @Body() body: { messageIds?: string[] },
  ) {
    return this.service.markRead(userId, id, body.messageIds);
  }

  /// DELETE /chat/secret/:id
  /// Close the secret chat. All messages are hard-deleted via CASCADE.
  @Delete(':id')
  async close(@CurrentUser('id') userId: string, @Param('id') id: string) {
    return this.service.closeSecretChat(userId, id);
  }
}
