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
import { Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

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
  cors: {
    origin: (origin, callback) => {
      // Same whitelist as HTTP CORS in main.ts
      const allowed = [
        'http://localhost:3001',
        'http://localhost:8080',
        'https://kinrel.app',
        'https://daxelokinrel.com',
        'https://app.daxelokinrel.com',
        'https://daxelo-kinrel-server.onrender.com',
        'com.daxelo.kinrel://',
        'kinrel://',
      ];
      // Allow requests with no origin (mobile apps, Postman)
      if (!origin) return callback(null, true);
      // In development, allow any localhost
      if (process.env.NODE_ENV === 'development' && (origin.includes('localhost') || origin.includes('127.0.0.1'))) {
        return callback(null, true);
      }
      if (allowed.some(o => origin.startsWith(o))) {
        return callback(null, true);
      }
      // Also check CORS_ORIGINS env var
      const extraOrigins = process.env.CORS_ORIGINS?.split(',').map(s => s.trim()) ?? [];
      if (extraOrigins.some(o => origin.startsWith(o))) {
        return callback(null, true);
      }
      return callback(new Error('Not allowed by CORS'), false);
    },
  },
  namespace: '/',
  transports: ['websocket'],
  pingTimeout: 10000,
  pingInterval: 25000,
})
export class KinrelGateway implements OnGatewayConnection, OnGatewayDisconnect {
  @WebSocketServer()
  server: Server;

  private readonly logger = new Logger(KinrelGateway.name);
  private connectedUsers = new Map<string, string>();
  private graphDebounceTimers = new Map<string, NodeJS.Timeout>();

  constructor(private readonly prisma: PrismaService) {}

  async handleConnection(client: Socket) {
    try {
      const token =
        client.handshake.auth?.token ||
        client.handshake.query?.token ||
        client.handshake.headers?.authorization?.replace('Bearer ', '');

      if (!token) {
        this.logger.warn(`Connection rejected — no token: ${client.id}`);
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
        this.logger.warn(`Connection rejected — invalid token: ${client.id}`);
        client.disconnect(true);
        return;
      }

      const userId = payload.sub;
      this.connectedUsers.set(client.id, userId);
      (client as any).userId = userId;

      this.logger.log(`Connected: ${client.id} (user: ${userId})`);
    } catch (err) {
      this.logger.warn(`Connection rejected — error: ${client.id}: ${(err as Error).message}`);
      client.disconnect(true);
    }
  }

  handleDisconnect(client: Socket) {
    const userId = this.connectedUsers.get(client.id);
    if (userId) {
      this.connectedUsers.delete(client.id);
    }
    this.logger.log(`Disconnected: ${client.id}`);
  }

  @SubscribeMessage('join:family')
  async handleJoinFamily(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: { familyId: string },
  ) {
    const userId = (client as any).userId;
    if (!userId) {
      client.emit('error', { message: 'Not authenticated' });
      return;
    }

    // Validate familyId is a non-empty string
    if (!data.familyId || typeof data.familyId !== 'string') {
      client.emit('error', { message: 'Invalid family ID' });
      return;
    }

    // Verify the user is a member of this family
    try {
      const membership = await this.prisma.familyMember.findFirst({
        where: { userId, familyId: data.familyId },
      });
      if (!membership) {
        client.emit('error', { message: 'Not a member of this family' });
        return;
      }
    } catch (err) {
      this.logger.warn(`Membership check failed for user ${userId}, family ${data.familyId}: ${(err as Error).message}`);
      client.emit('error', { message: 'Unable to verify membership' });
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
   * Emit a notification event to a specific user.
   * Finds all socket connections for the user and sends the event.
   */
  emitToUser(userId: string, event: string, payload: Record<string, unknown>) {
    for (const [socketId, uid] of this.connectedUsers.entries()) {
      if (uid === userId) {
        this.server.to(socketId).emit(event, {
          ...payload,
          timestamp: new Date().toISOString(),
        });
      }
    }
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
