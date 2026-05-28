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

  handleConnection(client: any) {
    this.logger.log(`Client connected: ${client.id}`);
  }

  handleDisconnect(client: any) {
    this.logger.log(`Client disconnected: ${client.id}`);
  }

  @SubscribeMessage('family:join')
  handleJoinFamily(
    @ConnectedSocket() client: any,
    @MessageBody() data: { familyId: string },
  ) {
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
