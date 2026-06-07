import {
  WebSocketGateway,
  WebSocketServer,
  OnGatewayConnection,
  OnGatewayDisconnect,
  ConnectedSocket,
  SubscribeMessage,
  MessageBody,
} from '@nestjs/websockets';
import { Logger } from '@nestjs/common';
import { Server, Socket } from 'socket.io';
import * as jwt from 'jsonwebtoken';
import { PrismaService } from '../../prisma/prisma.service';

@WebSocketGateway({
  cors: {
    origin: (origin, callback) => {
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
    credentials: true,
  },
  namespace: '/',
})
export class RealtimeGateway implements OnGatewayConnection, OnGatewayDisconnect {
  @WebSocketServer()
  server: Server;
  private readonly logger = new Logger(RealtimeGateway.name);

  constructor(private readonly prisma: PrismaService) {}

  async handleConnection(client: Socket) {
    try {
      const token =
        client.handshake.auth?.token ||
        client.handshake.query?.token ||
        client.handshake.headers?.authorization?.replace('Bearer ', '');

      if (!token) {
        this.logger.warn(`Realtime connection rejected — no token: ${client.id}`);
        client.disconnect(true);
        return;
      }

      // Try NestJS JWT first, then Supabase JWT
      let userId: string | null = null;

      const nestSecret = process.env.JWT_ACCESS_SECRET;
      if (nestSecret) {
        try {
          const payload = jwt.verify(token as string, nestSecret) as any;
          userId = payload.sub;
        } catch {}
      }

      if (!userId) {
        const supabaseSecret = process.env.SUPABASE_JWT_SECRET;
        if (supabaseSecret) {
          try {
            const payload = jwt.verify(token as string, supabaseSecret) as any;
            userId = payload.sub;
          } catch {}
        }
      }

      if (!userId) {
        this.logger.warn(`Realtime connection rejected — invalid token: ${client.id}`);
        client.disconnect(true);
        return;
      }

      (client as any).userId = userId;
      this.logger.log(`Realtime client connected: ${client.id} (user: ${userId})`);
    } catch (err) {
      this.logger.warn(`Realtime connection error: ${(err as Error).message}`);
      client.disconnect(true);
    }
  }

  handleDisconnect(client: any) {
    this.logger.log(`Realtime client disconnected: ${client.id}`);
  }

  @SubscribeMessage('family:join')
  async handleJoinFamily(
    @ConnectedSocket() client: any,
    @MessageBody() data: { familyId: string },
  ) {
    const userId = (client as any).userId;
    if (!userId) {
      client.emit('error', { message: 'Not authenticated' });
      return;
    }

    // Validate familyId
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

    client.join(`family:${data.familyId}`);
    this.logger.debug(`Client ${client.id} joined family:${data.familyId}`);
    return { event: 'family:joined', familyId: data.familyId };
  }

  @SubscribeMessage('family:leave')
  handleLeaveFamily(
    @ConnectedSocket() client: any,
    @MessageBody() data: { familyId: string },
  ) {
    client.leave(`family:${data.familyId}`);
    this.logger.debug(`Client ${client.id} left family:${data.familyId}`);
    return { event: 'family:left', familyId: data.familyId };
  }

  broadcastToFamily(familyId: string, event: string, payload: any) {
    this.server.to(`family:${familyId}`).emit(event, payload);
  }
}
