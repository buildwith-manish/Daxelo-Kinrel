import {
  WebSocketGateway,
  WebSocketServer,
  SubscribeMessage,
  OnGatewayConnection,
  OnGatewayDisconnect,
  ConnectedSocket,
  MessageBody,
} from '@nestjs/websockets';
import { Server, Socket } from 'socket.io';
import * as jwt from 'jsonwebtoken';

const JWT_SECRET = process.env.JWT_SECRET || 'kinrel-dev-secret-change-in-production';

interface AuthPayload {
  sub: string;
  email: string;
  role: string;
}

@WebSocketGateway({
  cors: { origin: '*' },
  namespace: '/',
})
export class KinrelGateway implements OnGatewayConnection, OnGatewayDisconnect {
  @WebSocketServer()
  server: Server;

  // Track connected users: socketId -> userId
  private connectedUsers = new Map<string, string>();

  // Track user rooms: userId -> Set of familyId rooms
  private userRooms = new Map<string, Set<string>>();

  // ── Connection ──────────────────────────────────────────────────────

  async handleConnection(client: Socket) {
    try {
      // Extract JWT from handshake auth or query
      const token =
        client.handshake.auth?.token ||
        client.handshake.query?.token ||
        client.handshake.headers?.authorization?.replace('Bearer ', '');

      if (!token) {
        console.warn(`[WS] Connection rejected — no token: ${client.id}`);
        client.disconnect(true);
        return;
      }

      const payload = jwt.verify(token as string, JWT_SECRET) as AuthPayload;
      const userId = payload.sub;

      this.connectedUsers.set(client.id, userId);
      if (!this.userRooms.has(userId)) {
        this.userRooms.set(userId, new Set());
      }

      // Store userId on socket for easy access
      (client as any).userId = userId;

      console.log(`[WS] Connected: ${client.id} (user: ${userId})`);
    } catch (err) {
      console.warn(`[WS] Connection rejected — invalid token: ${client.id}`, (err as Error).message);
      client.disconnect(true);
    }
  }

  // ── Disconnect ──────────────────────────────────────────────────────

  handleDisconnect(client: Socket) {
    const userId = this.connectedUsers.get(client.id);
    if (userId) {
      this.connectedUsers.delete(client.id);

      // Clean up room tracking if no more sockets for this user
      const userStillConnected = Array.from(this.connectedUsers.values()).includes(userId);
      if (!userStillConnected) {
        this.userRooms.delete(userId);
      }
    }
    console.log(`[WS] Disconnected: ${client.id}`);
  }

  // ── Join Family Room ────────────────────────────────────────────────

  @SubscribeMessage('join:family')
  handleJoinFamily(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: { familyId: string },
  ) {
    const userId = (client as any).userId;
    if (!userId) {
      client.emit('error', { message: 'Not authenticated' });
      return;
    }

    const roomName = `family:${data.familyId}`;
    client.join(roomName);

    const rooms = this.userRooms.get(userId);
    if (rooms) rooms.add(data.familyId);

    console.log(`[WS] User ${userId} joined room ${roomName}`);

    client.emit('joined:family', { familyId: data.familyId });
    client.to(roomName).emit('user:joined', { userId, familyId: data.familyId });
  }

  // ── Leave Family Room ───────────────────────────────────────────────

  @SubscribeMessage('leave:family')
  handleLeaveFamily(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: { familyId: string },
  ) {
    const userId = (client as any).userId;
    if (!userId) return;

    const roomName = `family:${data.familyId}`;
    client.leave(roomName);

    const rooms = this.userRooms.get(userId);
    if (rooms) rooms.delete(data.familyId);

    console.log(`[WS] User ${userId} left room ${roomName}`);

    client.emit('left:family', { familyId: data.familyId });
    client.to(roomName).emit('user:left', { userId, familyId: data.familyId });
  }

  // ── Person Updated ──────────────────────────────────────────────────

  @SubscribeMessage('person:updated')
  handlePersonUpdated(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: { familyId: string; personId: string; updates: Record<string, unknown> },
  ) {
    const userId = (client as any).userId;
    if (!userId) return;

    const roomName = `family:${data.familyId}`;
    // Broadcast to other family members
    client.to(roomName).emit('person:updated', {
      familyId: data.familyId,
      personId: data.personId,
      updates: data.updates,
      updatedBy: userId,
      timestamp: new Date().toISOString(),
    });
  }

  // ── Relationship Created ────────────────────────────────────────────

  @SubscribeMessage('relationship:created')
  handleRelationshipCreated(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: { familyId: string; relationshipId: string; relationship: Record<string, unknown> },
  ) {
    const userId = (client as any).userId;
    if (!userId) return;

    const roomName = `family:${data.familyId}`;
    client.to(roomName).emit('relationship:created', {
      familyId: data.familyId,
      relationshipId: data.relationshipId,
      relationship: data.relationship,
      createdBy: userId,
      timestamp: new Date().toISOString(),
    });
  }

  // ── Relationship Deleted ────────────────────────────────────────────

  @SubscribeMessage('relationship:deleted')
  handleRelationshipDeleted(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: { familyId: string; relationshipId: string },
  ) {
    const userId = (client as any).userId;
    if (!userId) return;

    const roomName = `family:${data.familyId}`;
    client.to(roomName).emit('relationship:deleted', {
      familyId: data.familyId,
      relationshipId: data.relationshipId,
      deletedBy: userId,
      timestamp: new Date().toISOString(),
    });
  }

  // ── Emit Notification (called from services) ────────────────────────

  /**
   * Emit a real-time notification to a specific user
   */
  emitNotification(userId: string, notification: { eventType: string; title: string; body: string; data?: Record<string, unknown> }) {
    // Find all sockets for this user
    for (const [socketId, uid] of this.connectedUsers.entries()) {
      if (uid === userId) {
        this.server.to(socketId).emit('notification', {
          ...notification,
          timestamp: new Date().toISOString(),
        });
      }
    }
  }

  /**
   * Emit an event to a family room
   */
  emitToFamily(familyId: string, event: string, data: Record<string, unknown>) {
    this.server.to(`family:${familyId}`).emit(event, {
      ...data,
      timestamp: new Date().toISOString(),
    });
  }

  /**
   * Get count of online users in a family room
   */
  getFamilyOnlineCount(familyId: string): number {
    const room = this.server.sockets.adapter.rooms.get(`family:${familyId}`);
    return room ? room.size : 0;
  }
}
