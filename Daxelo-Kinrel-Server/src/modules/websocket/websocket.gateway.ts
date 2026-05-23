import { Injectable, Logger } from '@nestjs/common';
import {
  WebSocketGateway,
  WebSocketServer,
  OnGatewayConnection,
  OnGatewayDisconnect,
  OnGatewayInit,
} from '@nestjs/websockets';
import { Server, Socket } from 'socket.io';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import type {
  ServerEvent,
  ServerEventMap,
  FamilyUpdatedPayload,
  PersonEventPayload,
  RelationshipEventPayload,
  GraphUpdatedPayload,
  NotificationNewPayload,
  InvitationEventPayload,
  UserPresencePayload,
} from './dto/socket-event.dto';

/**
 * WebSocketGateway — Real-time updates via Socket.IO
 *
 * Events emitted:
 * 1. family:updated        — When family details change
 * 2. person:created        — Person added
 * 3. person:updated        — Person details changed
 * 4. person:deleted        — Person removed
 * 5. relationship:created  — Relationship added
 * 6. relationship:deleted  — Relationship removed
 * 7. graph:updated         — Graph structure changed
 * 8. notification:new      — New notification
 * 9. invitation:created    — Invitation sent
 * 10. invitation:accepted  — Invitation accepted
 * 11. user:online          — User came online
 * 12. user:offline         — User went offline
 *
 * Rooms:
 * - family:${familyId}  — Per-family room
 * - user:${userId}      — Per-user room
 */
@WebSocketGateway({
  cors: {
    origin: '*', // Configured via CORS_ORIGINS in production
    methods: ['GET', 'POST'],
    credentials: true,
  },
  namespace: '/',
})
@Injectable()
export class WebSocketGatewayService
  implements OnGatewayInit, OnGatewayConnection, OnGatewayDisconnect
{
  @WebSocketServer()
  server!: Server;

  private readonly logger = new Logger(WebSocketGatewayService.name);

  /** Track connected users: socketId → userId */
  private readonly connectedUsers = new Map<string, string>();

  /** Track user rooms: userId → Set of socket IDs */
  private readonly userSockets = new Map<string, Set<string>>();

  constructor(
    private readonly configService: ConfigService,
    private readonly jwtService: JwtService,
  ) {}

  // ═════════════════════════════════════════════════════════════════════
  // Gateway Lifecycle
  // ═════════════════════════════════════════════════════════════════════

  afterInit(server: Server) {
    this.logger.log('🔌 WebSocket Gateway initialized');
  }

  async handleConnection(client: Socket) {
    try {
      // Authenticate using JWT token from handshake auth
      const token =
        (client.handshake.auth?.token as string) ||
        (client.handshake.headers?.authorization as string)?.replace(
          'Bearer ',
          '',
        );

      if (!token) {
        this.logger.warn(
          `WebSocket connection rejected: No token provided (socket: ${client.id})`,
        );
        client.emit('error', { message: 'Authentication required' });
        client.disconnect(true);
        return;
      }

      // Verify JWT
      const secret =
        this.configService.get<string>('JWT_ACCESS_SECRET') ??
        'fallback-dev-secret';

      let payload: { sub: string; email: string; type: string };

      try {
        payload = this.jwtService.verify(token, { secret });
      } catch {
        this.logger.warn(
          `WebSocket connection rejected: Invalid token (socket: ${client.id})`,
        );
        client.emit('error', { message: 'Invalid or expired token' });
        client.disconnect(true);
        return;
      }

      if (payload.type !== 'access') {
        this.logger.warn(
          `WebSocket connection rejected: Invalid token type (socket: ${client.id})`,
        );
        client.emit('error', { message: 'Invalid token type' });
        client.disconnect(true);
        return;
      }

      const userId = payload.sub;

      // Store connection
      this.connectedUsers.set(client.id, userId);

      // Track user sockets
      if (!this.userSockets.has(userId)) {
        this.userSockets.set(userId, new Set());
      }
      this.userSockets.get(userId)!.add(client.id);

      // Join user's personal room
      client.join(`user:${userId}`);

      this.logger.log(
        `🔌 User connected: ${userId} (socket: ${client.id})`,
      );

      // Notify others that user is online
      this.emitUserPresence(userId, 'online');
    } catch (error) {
      this.logger.error(
        `WebSocket connection error: ${error instanceof Error ? error.message : String(error)}`,
      );
      client.disconnect(true);
    }
  }

  async handleDisconnect(client: Socket) {
    const userId = this.connectedUsers.get(client.id);

    if (userId) {
      // Remove from tracking
      this.connectedUsers.delete(client.id);

      const sockets = this.userSockets.get(userId);
      if (sockets) {
        sockets.delete(client.id);
        // If no more sockets for this user, mark as offline
        if (sockets.size === 0) {
          this.userSockets.delete(userId);
          this.emitUserPresence(userId, 'offline');
        }
      }

      this.logger.log(
        `🔌 User disconnected: ${userId} (socket: ${client.id})`,
      );
    }
  }

  // ═════════════════════════════════════════════════════════════════════
  // Room Management
  // ═════════════════════════════════════════════════════════════════════

  /**
   * Join a user to a family room
   */
  joinFamilyRoom(userId: string, familyId: string) {
    const sockets = this.userSockets.get(userId);
    if (sockets) {
      for (const socketId of sockets) {
        const socket = this.server.sockets.sockets.get(socketId);
        if (socket) {
          socket.join(`family:${familyId}`);
        }
      }
    }
  }

  /**
   * Remove a user from a family room
   */
  leaveFamilyRoom(userId: string, familyId: string) {
    const sockets = this.userSockets.get(userId);
    if (sockets) {
      for (const socketId of sockets) {
        const socket = this.server.sockets.sockets.get(socketId);
        if (socket) {
          socket.leave(`family:${familyId}`);
        }
      }
    }
  }

  // ═════════════════════════════════════════════════════════════════════
  // Event Emitters
  // ═════════════════════════════════════════════════════════════════════

  /**
   * Emit family:updated to all members of a family
   */
  emitFamilyUpdated(payload: FamilyUpdatedPayload) {
    this.server.to(`family:${payload.familyId}`).emit('family:updated', payload);
    this.logger.debug(`Emitted family:updated for family ${payload.familyId}`);
  }

  /**
   * Emit person events to all members of a family
   */
  emitPersonCreated(payload: PersonEventPayload) {
    this.server.to(`family:${payload.familyId}`).emit('person:created', payload);
    this.emitGraphUpdated({
      familyId: payload.familyId,
      changeType: 'person',
      changedBy: payload.actionBy,
    });
  }

  emitPersonUpdated(payload: PersonEventPayload) {
    this.server.to(`family:${payload.familyId}`).emit('person:updated', payload);
  }

  emitPersonDeleted(payload: PersonEventPayload) {
    this.server.to(`family:${payload.familyId}`).emit('person:deleted', payload);
    this.emitGraphUpdated({
      familyId: payload.familyId,
      changeType: 'person',
      changedBy: payload.actionBy,
    });
  }

  /**
   * Emit relationship events to all members of a family
   */
  emitRelationshipCreated(payload: RelationshipEventPayload) {
    this.server
      .to(`family:${payload.familyId}`)
      .emit('relationship:created', payload);
    this.emitGraphUpdated({
      familyId: payload.familyId,
      changeType: 'relationship',
      changedBy: payload.actionBy,
    });
  }

  emitRelationshipDeleted(payload: RelationshipEventPayload) {
    this.server
      .to(`family:${payload.familyId}`)
      .emit('relationship:deleted', payload);
    this.emitGraphUpdated({
      familyId: payload.familyId,
      changeType: 'relationship',
      changedBy: payload.actionBy,
    });
  }

  /**
   * Emit graph:updated to all members of a family
   */
  emitGraphUpdated(payload: GraphUpdatedPayload) {
    this.server.to(`family:${payload.familyId}`).emit('graph:updated', payload);
  }

  /**
   * Emit notification:new to a specific user
   */
  emitNotificationNew(payload: NotificationNewPayload) {
    this.server.to(`user:${payload.userId}`).emit('notification:new', payload);
  }

  /**
   * Emit invitation events to a specific user
   */
  emitInvitationCreated(payload: InvitationEventPayload) {
    // Notify the inviter
    this.server.to(`user:${payload.inviterId}`).emit('invitation:created', payload);
    // Notify family members
    this.server.to(`family:${payload.familyId}`).emit('invitation:created', payload);
  }

  emitInvitationAccepted(payload: InvitationEventPayload) {
    // Notify the inviter
    this.server.to(`user:${payload.inviterId}`).emit('invitation:accepted', payload);
    // Notify family members
    this.server.to(`family:${payload.familyId}`).emit('invitation:accepted', payload);
  }

  // ═════════════════════════════════════════════════════════════════════
  // Presence
  // ═════════════════════════════════════════════════════════════════════

  private emitUserPresence(userId: string, status: 'online' | 'offline') {
    const payload: UserPresencePayload = {
      userId,
      status,
      timestamp: new Date(),
    };
    this.server.emit('user:' + status, payload);
    this.logger.debug(`User ${userId} is now ${status}`);
  }

  /**
   * Check if a user is online
   */
  isUserOnline(userId: string): boolean {
    const sockets = this.userSockets.get(userId);
    return !!sockets && sockets.size > 0;
  }

  /**
   * Get count of online users
   */
  getOnlineUserCount(): number {
    return this.userSockets.size;
  }

  /**
   * Get all online user IDs
   */
  getOnlineUserIds(): string[] {
    return Array.from(this.userSockets.keys());
  }
}
