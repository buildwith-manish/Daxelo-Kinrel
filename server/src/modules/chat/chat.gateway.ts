import {
  WebSocketGateway,
  WebSocketServer,
  SubscribeMessage,
  ConnectedSocket,
  MessageBody,
} from '@nestjs/websockets';
import { Server, Socket } from 'socket.io';
import { Logger } from '@nestjs/common';
import { ChatService } from './chat.service';
import { AddReactionDto, MarkAsReadDto, SendChatMessageDto, TypingDto } from './dto/chat.dto';

/**
 * ChatGateway — Socket.IO gateway for real-time family chat.
 *
 * Events emitted by the server (clients listen for these):
 *   • `chat:messageReceived`  — new message broadcast to the family room
 *   • `chat:messageSent`      — ack to the sender that their message was persisted
 *   • `chat:userTyping`       — { userId, userName, familyId } someone started typing
 *   • `chat:userStoppedTyping` — { userId, userName, familyId } someone stopped typing
 *   • `chat:readReceipt`      — { messageId, readBy, readAt } a message was read
 *   • `chat:reactionAdded`    — { messageId, userId, emoji, counts } a reaction was added
 *   • `chat:reactionRemoved`   — { messageId, userId, emoji, counts } a reaction was removed
 *   • `chat:streakUpdated`    — { chatId, currentStreak, longestStreak } streak changed
 *   • `presenceUpdate`        — { userId, status, lastSeenAt } user went online/offline
 *
 * Events clients emit to the server (handlers below):
 *   • `chat:joinFamily`        — join a family chat room (also subscribes to presence updates)
 *   • `chat:leaveFamily`       — leave a family chat room
 *   • `chat:sendMessage`       — send a new message (persisted + broadcast)
 *   • `chat:typing`           — { familyId, isTyping, userName }
 *   • `chat:markAsRead`       — { familyId, messageId? }
 *   • `chat:addReaction`      — { messageId, emoji }
 *   • `chat:removeReaction`   — { messageId, emoji }
 *
 * The gateway reuses the root namespace `/` (same as KinrelGateway) so a
 * single Socket.IO connection serves both family-chat and game-room events.
 * Auth is handled by KinrelGateway.handleConnection, which sets
 * `(client as any).userId` before any chat handler can fire — so we can
 * trust that field here.
 *
 * NOTE: This gateway is registered AFTER KinrelGateway in ChatModule's
 * imports. NestJS allows multiple gateways on the same namespace as long
 * as they handle different event names. The `chat:*` namespace for events
 * avoids collisions with KinrelGateway's `game:*` / `join:family` events.
 */
@WebSocketGateway({
  cors: { origin: '*' },
  namespace: '/',
  transports: ['websocket'],
  pingTimeout: 10000,
  pingInterval: 25000,
})
export class ChatGateway {
  private readonly logger = new Logger(ChatGateway.name);

  @WebSocketServer()
  server: Server;

  // ── Per-socket typing timer ──────────────────────────────────────────
  // When a client sends `chat:typing` with isTyping=true, we set a 3-second
  // timer that auto-fires `chat:userStoppedTyping` if the client doesn't
  // send another typing event or a `chat:sendMessage` within 3 seconds.
  // This ensures the "User is typing..." indicator clears even if the
  // client crashes or the user walks away mid-sentence.
  private typingTimers = new Map<string, NodeJS.Timeout>(); // key: `${familyId}:${userId}`

  constructor(private readonly chatService: ChatService) {}

  // ── Room join/leave ────────────────────────────────────────────────────

  @SubscribeMessage('chat:joinFamily')
  async handleJoinFamily(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: { familyId: string },
  ) {
    const userId = (client as any).userId as string | undefined;
    if (!userId) {
      client.emit('error', { message: 'Not authenticated', event: 'chat:joinFamily' });
      return;
    }
    const roomName = `chat:family:${data.familyId}`;
    await client.join(roomName);
    client.emit('chat:joinedFamily', { familyId: data.familyId });

    // Broadcast to the room that this user joined (so other clients can
    // refresh their presence dots). Not strictly required for typing, but
    // useful for "X is online" indicators.
    client.to(roomName).emit('chat:userJoined', {
      userId,
      familyId: data.familyId,
      timestamp: new Date().toISOString(),
    });
    this.logger.debug(`User ${userId} joined chat room ${roomName}`);
  }

  @SubscribeMessage('chat:leaveFamily')
  async handleLeaveFamily(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: { familyId: string },
  ) {
    const userId = (client as any).userId as string | undefined;
    const roomName = `chat:family:${data.familyId}`;
    await client.leave(roomName);
    // Clear any pending typing timer for this family+user
    this.clearTypingTimer(data.familyId, userId ?? '');
    client.emit('chat:leftFamily', { familyId: data.familyId });
    client.to(roomName).emit('chat:userLeft', {
      userId: userId ?? '',
      familyId: data.familyId,
      timestamp: new Date().toISOString(),
    });
  }

  // ── Send message ───────────────────────────────────────────────────────

  @SubscribeMessage('chat:sendMessage')
  async handleSendMessage(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: SendChatMessageDto & { familyId: string },
  ) {
    const userId = (client as any).userId as string | undefined;
    if (!userId) {
      client.emit('error', { message: 'Not authenticated', event: 'chat:sendMessage' });
      return;
    }
    const familyId = data.familyId;
    try {
      const message = await this.chatService.sendMessage(familyId, userId, data.content, {
        messageType: data.messageType,
        replyToId: data.replyToId,
        senderPersonId: data.senderPersonId,
        senderInitials: data.senderInitials,
      });

      // Ack to sender with the persisted message (so the client can update
      // its optimistic ID -> real ID mapping).
      client.emit('chat:messageSent', { message });

      // Broadcast to everyone else in the family chat room.
      const roomName = `chat:family:${familyId}`;
      this.server.to(roomName).emit('chat:messageReceived', { message });

      // Clear the sender's typing indicator in this family — sending a
      // message implies they stopped typing.
      this.clearTypingTimer(familyId, userId);
      await this.chatService.setTypingStatus(familyId, userId, false);
      client.to(roomName).emit('chat:userStoppedTyping', {
        userId,
        familyId,
        timestamp: new Date().toISOString(),
      });
    } catch (err: any) {
      this.logger.error(`chat:sendMessage failed: ${err?.message}`, err?.stack);
      client.emit('error', {
        message: err?.message ?? 'Failed to send message',
        event: 'chat:sendMessage',
      });
    }
  }

  // ── Typing indicator ───────────────────────────────────────────────────

  @SubscribeMessage('chat:typing')
  async handleTyping(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: TypingDto,
  ) {
    const userId = (client as any).userId as string | undefined;
    if (!userId) {
      client.emit('error', { message: 'Not authenticated', event: 'chat:typing' });
      return;
    }
    const roomName = `chat:family:${data.familyId}`;

    // Persist typing status (for late-joiners / polling clients)
    await this.chatService.setTypingStatus(data.familyId, userId, data.isTyping);

    if (data.isTyping) {
      // Broadcast to everyone EXCEPT the sender that this user is typing.
      client.to(roomName).emit('chat:userTyping', {
        userId,
        userName: data.userName,
        familyId: data.familyId,
        timestamp: new Date().toISOString(),
      });

      // Set / reset the 3-second auto-clear timer. If the user doesn't send
      // another typing event or a message within 3 seconds, we auto-fire
      // `chat:userStoppedTyping` so the "User is typing..." indicator clears
      // even if the client disappears.
      this.setTypingTimer(data.familyId, userId, data.userName ?? '', client);
    } else {
      // Explicit stop — clear the timer + broadcast.
      this.clearTypingTimer(data.familyId, userId);
      client.to(roomName).emit('chat:userStoppedTyping', {
        userId,
        userName: data.userName,
        familyId: data.familyId,
        timestamp: new Date().toISOString(),
      });
    }
  }

  /**
   * Set (or refresh) the 3-second auto-clear timer for a family+user pair.
   * If a timer already exists for this pair, clear it first — each new
   * `chat:typing` event extends the timeout by another 3 seconds.
   */
  private setTypingTimer(
    familyId: string,
    userId: string,
    userName: string,
    client: Socket,
  ) {
    const key = `${familyId}:${userId}`;
    const existing = this.typingTimers.get(key);
    if (existing) clearTimeout(existing);

    const timer = setTimeout(
      () => {
        this.typingTimers.delete(key);
        // Auto-stop: broadcast to everyone except the sender
        client
          .to(`chat:family:${familyId}`)
          .emit('chat:userStoppedTyping', {
            userId,
            userName,
            familyId,
            timestamp: new Date().toISOString(),
            autoCleared: true,
          });
        // Best-effort DB clear — fire-and-forget
        this.chatService.setTypingStatus(familyId, userId, false).catch(() => {});
      },
      3_000, // 3 seconds of inactivity = stop typing
    );
    this.typingTimers.set(key, timer);
  }

  private clearTypingTimer(familyId: string, userId: string) {
    const key = `${familyId}:${userId}`;
    const t = this.typingTimers.get(key);
    if (t) {
      clearTimeout(t);
      this.typingTimers.delete(key);
    }
  }

  // ── Read receipts ──────────────────────────────────────────────────────

  @SubscribeMessage('chat:markAsRead')
  async handleMarkAsRead(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: MarkAsReadDto & { familyId: string },
  ) {
    const userId = (client as any).userId as string | undefined;
    if (!userId) {
      client.emit('error', { message: 'Not authenticated', event: 'chat:markAsRead' });
      return;
    }
    try {
      const { markedReadIds, senderIds } = await this.chatService.markAsRead(
        data.familyId,
        userId,
        data.messageId,
      );

      if (markedReadIds.length === 0) {
        client.emit('chat:readReceipt', {
          familyId: data.familyId,
          markedReadIds: [],
          message: 'No unread messages to mark',
        });
        return;
      }

      const now = new Date().toISOString();

      // Emit to the sender(s) of each marked message so their client can
      // flip the checkmark from double-grey (delivered) to double-blue (read).
      // We use emitToUser-style lookup by iterating connected sockets.
      // The KinrelGateway already maintains a `connectedUsers` map; here we
      // do our own lookup via the server's sockets adapter since we don't
      // have a reference to KinrelGateway.
      const roomName = `chat:family:${data.familyId}`;
      const payload = {
        familyId: data.familyId,
        messageIds: markedReadIds,
        readByUserId: userId,
        readAt: now,
      };

      // Broadcast to the family room (sender included, if they're connected)
      // — clients filter on their own senderId to decide whether to update
      // the checkmark.
      this.server.to(roomName).emit('chat:readReceipt', payload);

      this.logger.debug(
        `chat:markAsRead: ${markedReadIds.length} message(s) marked read by ${userId} in family ${data.familyId}`,
      );
    } catch (err: any) {
      this.logger.error(`chat:markAsRead failed: ${err?.message}`, err?.stack);
      client.emit('error', {
        message: err?.message ?? 'Failed to mark as read',
        event: 'chat:markAsRead',
      });
    }
  }

  // ── Reactions ──────────────────────────────────────────────────────────
  //
  // Reaction events are implemented in Feature 2 but declared here so the
  // Flutter client only needs one socket-connection setup. The handlers
  // persist the reaction and broadcast to the family room.

  @SubscribeMessage('chat:addReaction')
  async handleAddReaction(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: AddReactionDto & { familyId: string },
  ) {
    const userId = (client as any).userId as string | undefined;
    if (!userId) {
      client.emit('error', { message: 'Not authenticated', event: 'chat:addReaction' });
      return;
    }
    try {
      const result = await this.chatService.addReaction(data.familyId, userId, {
        messageId: data.messageId,
        emoji: data.emoji,
      });
      const counts = await this.chatService.getReactionCounts(data.messageId);

      const payload = {
        messageId: data.messageId,
        userId,
        emoji: data.emoji,
        action: result.action,
        counts,
        timestamp: new Date().toISOString(),
      };

      // Broadcast to everyone in the family chat room (including the sender
      // so their optimistic UI is reconciled with the server's canonical
      // reaction counts).
      this.server.to(`chat:family:${data.familyId}`).emit('chat:reactionAdded', payload);
    } catch (err: any) {
      this.logger.error(`chat:addReaction failed: ${err?.message}`, err?.stack);
      client.emit('error', {
        message: err?.message ?? 'Failed to add reaction',
        event: 'chat:addReaction',
      });
    }
  }

  @SubscribeMessage('chat:removeReaction')
  async handleRemoveReaction(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: AddReactionDto & { familyId: string },
  ) {
    const userId = (client as any).userId as string | undefined;
    if (!userId) {
      client.emit('error', { message: 'Not authenticated', event: 'chat:removeReaction' });
      return;
    }
    try {
      const result = await this.chatService.removeReaction(data.familyId, userId, {
        messageId: data.messageId,
        emoji: data.emoji,
      });
      const counts = await this.chatService.getReactionCounts(data.messageId);

      this.server.to(`chat:family:${data.familyId}`).emit('chat:reactionRemoved', {
        messageId: data.messageId,
        userId,
        emoji: data.emoji,
        deleted: result.deleted,
        counts,
        timestamp: new Date().toISOString(),
      });
    } catch (err: any) {
      this.logger.error(`chat:removeReaction failed: ${err?.message}`, err?.stack);
      client.emit('error', {
        message: err?.message ?? 'Failed to remove reaction',
        event: 'chat:removeReaction',
      });
    }
  }
}
