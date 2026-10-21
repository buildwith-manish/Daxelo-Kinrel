import {
  WebSocketGateway,
  WebSocketServer,
  SubscribeMessage,
  ConnectedSocket,
  MessageBody,
} from '@nestjs/websockets';
import { Server, Socket } from 'socket.io';
import { Logger } from '@nestjs/common';
import { CircleService } from './circle.service';
import {
  SendCircleMessageDto,
  AddCircleReactionDto,
} from './dto/circle.dto';

/**
 * CircleGateway — Socket.IO gateway for real-time circle chat.
 *
 * Room name pattern: `circle:${circleId}` (parallel to the existing
 * `chat:family:${familyId}` pattern in chat.gateway.ts).
 *
 * Events emitted by the server (clients listen for these):
 *   • `circle:messageReceived`   — new message broadcast to the circle room
 *   • `circle:messageSent`       — ack to the sender that the message was persisted
 *   • `circle:readReceipt`       — { messageId, readBy, readAt } a message was read
 *   • `circle:reactionAdded`     — { messageId, userId, emoji, counts } a reaction was added
 *   • `circle:reactionRemoved`   — { messageId, userId, emoji, counts } a reaction was removed
 *   • `circle:memberAdded`       — { circleId, userId, displayName, role } a member was added
 *   • `circle:memberRemoved`     — { circleId, userId } a member was removed
 *   • `circle:settingsUpdated`   — { circleId, changes } settings were changed
 *   • `circle:messagePinned`      — { messageId, pinnedBy } a message was pinned
 *   • `circle:messageUnpinned`    — { messageId } a message was unpinned
 *
 * Events received from the client (handled via @SubscribeMessage):
 *   • `circle:join`        — join the circle's Socket.IO room
 *   • `circle:leave`       — leave the room (navigated away)
 *   • `circle:sendMessage` — send a message (delegates to CircleService)
 *   • `circle:addReaction` — add a reaction (delegates to CircleService)
 *   • `circle:markRead`    — mark a message as read
 */
@WebSocketGateway({
  namespace: '/circles',
  cors: { origin: '*', credentials: true },
})
export class CircleGateway {
  private readonly logger = new Logger(CircleGateway.name);

  @WebSocketServer()
  server: Server;

  constructor(private readonly circleService: CircleService) {}

  // ── Room management ──────────────────────────────────────────

  @SubscribeMessage('circle:join')
  async handleJoin(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: { circleId: string },
  ) {
    const userId = (client.data as { userId?: string })?.userId;
    if (!userId || !data?.circleId) return;

    // The JWT auth middleware (connected to the same gateway namespace)
    // sets client.data.userId. The room name follows the
    // `circle:${circleId}` pattern.
    const roomName = `circle:${data.circleId}`;
    await client.join(roomName);
    this.logger.debug(`Client ${client.id} joined room ${roomName}`);
  }

  @SubscribeMessage('circle:leave')
  async handleLeave(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: { circleId: string },
  ) {
    if (!data?.circleId) return;
    const roomName = `circle:${data.circleId}`;
    await client.leave(roomName);
    this.logger.debug(`Client ${client.id} left room ${roomName}`);
  }

  // ── Send message via Socket.IO ──────────────────────────────

  @SubscribeMessage('circle:sendMessage')
  async handleSendMessage(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: { circleId: string } & SendCircleMessageDto,
  ) {
    const userId = (client.data as { userId?: string })?.userId;
    if (!userId || !data?.circleId) return;

    try {
      const message = await this.circleService.sendMessage(
        data.circleId,
        userId,
        data,
      );

      // Broadcast to the circle room (all connected members)
      const roomName = `circle:${data.circleId}`;
      this.server.to(roomName).emit('circle:messageReceived', {
        ...message,
        tempId: data.tempId,
      });

      // Ack to the sender
      client.emit('circle:messageSent', {
        tempId: data.tempId,
        message,
      });
    } catch (error) {
      this.logger.error(
        `circle:sendMessage failed: ${error.message}`,
      );
      client.emit('circle:messageFailed', {
        tempId: data.tempId,
        error: error.message,
      });
    }
  }

  // ── Add reaction via Socket.IO ──────────────────────────────

  @SubscribeMessage('circle:addReaction')
  async handleAddReaction(
    @ConnectedSocket() client: Socket,
    @MessageBody()
    data: { circleId: string; messageId: string } & AddCircleReactionDto,
  ) {
    const userId = (client.data as { userId?: string })?.userId;
    if (!userId || !data?.circleId) return;

    try {
      await this.circleService.addReaction(
        data.circleId,
        userId,
        data.messageId,
        { emoji: data.emoji },
      );

      const roomName = `circle:${data.circleId}`;
      this.server.to(roomName).emit('circle:reactionAdded', {
        messageId: data.messageId,
        userId,
        emoji: data.emoji,
      });
    } catch (error) {
      this.logger.error(`circle:addReaction failed: ${error.message}`);
    }
  }

  @SubscribeMessage('circle:markRead')
  async handleMarkRead(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: { circleId: string; messageId?: string },
  ) {
    const userId = (client.data as { userId?: string })?.userId;
    if (!userId || !data?.circleId) return;

    try {
      await this.circleService.markAsRead(
        data.circleId,
        userId,
        data.messageId,
      );

      const roomName = `circle:${data.circleId}`;
      this.server.to(roomName).emit('circle:readReceipt', {
        userId,
        messageId: data.messageId,
        circleId: data.circleId,
      });
    } catch (error) {
      this.logger.error(`circle:markRead failed: ${error.message}`);
    }
  }
}
