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

interface AuthPayload {
  sub: string;
  email: string;
  role: string;
}

/**
 * Minimal payload type for socket events.
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
  transports: ['websocket'],
  pingTimeout: 10000,
  pingInterval: 25000,
})
export class KinrelGateway implements OnGatewayConnection, OnGatewayDisconnect {
  @WebSocketServer()
  server: Server;

  private connectedUsers = new Map<string, string>();
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

      // Try to verify with available secrets — support both NestJS and Supabase tokens
      let payload: AuthPayload | null = null;

      // 1. Try NestJS JWT_ACCESS_SECRET
      const nestSecret = process.env.JWT_ACCESS_SECRET;
      if (nestSecret) {
        try {
          payload = jwt.verify(token as string, nestSecret) as AuthPayload;
        } catch {}
      }

      // 2. Try Supabase JWT_SECRET
      if (!payload) {
        const supabaseSecret = process.env.SUPABASE_JWT_SECRET;
        if (supabaseSecret) {
          try {
            const decoded = jwt.verify(token as string, supabaseSecret) as any;
            // Supabase tokens have 'sub' as UUID and 'aud' as 'authenticated'
            payload = {
              sub: decoded.sub,
              email: decoded.email || '',
              role: decoded.role || 'user',
            };
          } catch {}
        }
      }

      if (!payload) {
        console.warn(`[WS] Connection rejected — invalid token: ${client.id}`);
        client.disconnect(true);
        return;
      }

      const userId = payload.sub;
      this.connectedUsers.set(client.id, userId);
      (client as any).userId = userId;

      console.log(`[WS] Connected: ${client.id} (user: ${userId})`);
    } catch (err) {
      console.warn(`[WS] Connection rejected — error: ${client.id}`, (err as Error).message);
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

  emitToFamily(familyId: string, event: string, payload: MinimalPayload) {
    if (event === 'graph:updated') {
      this._debouncedGraphEmit(familyId, payload);
      return;
    }

    this.server.to(`family:${familyId}`).emit(event, {
      ...payload,
      timestamp: new Date().toISOString(),
    });
  }

  private _debouncedGraphEmit(familyId: string, payload: MinimalPayload) {
    const existingTimer = this.graphDebounceTimers.get(familyId);
    if (existingTimer) {
      clearTimeout(existingTimer);
    }

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
