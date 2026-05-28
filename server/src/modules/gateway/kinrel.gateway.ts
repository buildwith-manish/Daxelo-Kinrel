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

const JWT_SECRET = process.env.JWT_ACCESS_SECRET || process.env.JWT_SECRET || 'kinrel-dev-secret-change-in-production';

interface AuthPayload {
  sub: string;
  email: string;
  role: string;
}

/**
 * Minimal payload type for socket events.
 * Instead of emitting full objects, we emit only id + updatedAt + type.
 * The Flutter client fetches full data from Isar/API if needed.
 */
export interface MinimalPayload {
  id: string;
  updatedAt: string;
  type: string;
  familyId?: string;
  [key: string]: unknown;
}

@WebSocketGateway({
  cors: { origin: '*' },
  namespace: '/',
  transports: ['websocket'],       // Force WebSocket only — skip polling
  pingTimeout: 10000,              // 10s before server considers connection dead
  pingInterval: 25000,             // Heartbeat every 25s
})
export class KinrelGateway implements OnGatewayConnection, OnGatewayDisconnect {
  @WebSocketServer()
  server: Server;

  private connectedUsers = new Map<string, string>();

  /**
   * Debounce map for graph:updated events per family.
   * If the same family emits graph:updated < 500ms apart,
   * only the last one is sent.
   */
  private graphDebounceTimers = new Map<string, NodeJS.Timeout>();

  async handleConnection(client: Socket) {
    try {
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
      (client as any).userId = userId;

      console.log(`[WS] Connected: ${client.id} (user: ${userId})`);
    } catch (err) {
      console.warn(`[WS] Connection rejected — invalid token: ${client.id}`, (err as Error).message);
      client.disconnect(true);
    }
  }

  handleDisconnect(client: Socket) {
    const userId = this.connectedUsers.get(client.id);
    if (userId) {
      this.connectedUsers.delete(client.id);
    }
    console.log(`[WS] Disconnected: ${client.id}`);
  }

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
    client.emit('joined:family', { familyId: data.familyId });
    client.to(roomName).emit('user:joined', { userId, familyId: data.familyId });
  }

  @SubscribeMessage('leave:family')
  handleLeaveFamily(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: { familyId: string },
  ) {
    const userId = (client as any).userId;
    if (!userId) return;
    const roomName = `family:${data.familyId}`;
    client.leave(roomName);
    client.emit('left:family', { familyId: data.familyId });
    client.to(roomName).emit('user:left', { userId, familyId: data.familyId });
  }

  /**
   * Emit a minimal payload event to all members of a family room.
   *
   * @param familyId - The family ID (used for room name)
   * @param event - The event name (e.g., 'person:updated', 'person:created', 'graph:updated')
   * @param payload - Must include `id`, `updatedAt`, `type`, and optionally `familyId`
   *
   * IMPORTANT: Only emit minimal data (id + timestamp + type).
   * The Flutter client fetches full data from Isar/API if needed.
   */
  emitToFamily(familyId: string, event: string, payload: MinimalPayload) {
    // Throttle graph:updated events per family (< 500ms apart → debounce)
    if (event === 'graph:updated') {
      this._debouncedGraphEmit(familyId, payload);
      return;
    }

    this.server.to(`family:${familyId}`).emit(event, {
      ...payload,
      timestamp: new Date().toISOString(),
    });
  }

  /**
   * Debounced graph:updated emission per family.
   * If the same family emits graph:updated < 500ms apart,
   * cancel the previous timer and send only the last one.
   */
  private _debouncedGraphEmit(familyId: string, payload: MinimalPayload) {
    // Clear existing timer for this family if any
    const existingTimer = this.graphDebounceTimers.get(familyId);
    if (existingTimer) {
      clearTimeout(existingTimer);
    }

    // Set a new timer — emit after 500ms of silence
    const timer = setTimeout(() => {
      this.graphDebounceTimers.delete(familyId);
      this.server.to(`family:${familyId}`).emit('graph:updated', {
        ...payload,
        timestamp: new Date().toISOString(),
      });
    }, 500);

    this.graphDebounceTimers.set(familyId, timer);
  }
}
