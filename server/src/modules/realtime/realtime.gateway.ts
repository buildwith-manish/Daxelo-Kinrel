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
import { Socket } from 'socket.io';
import * as jwt from 'jsonwebtoken';

@WebSocketGateway({
  cors: {
    origin: '*',
    credentials: true,
  },
  namespace: '/',
})
export class RealtimeGateway implements OnGatewayConnection, OnGatewayDisconnect {
  private server: any;
  private readonly logger = new Logger(RealtimeGateway.name);

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
  handleJoinFamily(
    @ConnectedSocket() client: any,
    @MessageBody() data: { familyId: string },
  ) {
    const userId = (client as any).userId;
    if (!userId) {
      client.emit('error', { message: 'Not authenticated' });
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
