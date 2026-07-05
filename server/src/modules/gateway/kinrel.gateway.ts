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

  // ── Game invites ────────────────────────────────────────────────────
  // Real-time game-room invites sent from a host's lobby screen to a
  // linked family member. The Flutter client calls SocketService.sendGameInvite()
  // which emits 'game:invite:send'; this handler relays it to the recipient
  // via emitToUser as 'game:invite:received'. The recipient's
  // GameInviteListener shows an Accept / Decline dialog; their response is
  // relayed back to the sender via 'game:invite:accept' / 'game:invite:decline'.

  @SubscribeMessage('game:invite:send')
  handleGameInviteSend(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: {
      inviteId: string;
      gameType: string;
      gameId: string;
      roomCode: string;
      familyId: string;
      fromUserId: string;
      fromName: string;
      maxPlayers: number;
      currentPlayers: number;
      message?: string;
      toUserId: string;
    },
  ) {
    const senderId = (client as any).userId;
    if (!senderId || senderId !== data.fromUserId) {
      // Sanity check: the sender must be the authenticated user.
      client.emit('error', { message: 'Sender mismatch' });
      return;
    }

    // Relay the invite to the recipient — emitToUser injects a timestamp.
    this.emitToUser(data.toUserId, 'game:invite:received', {
      inviteId: data.inviteId,
      gameType: data.gameType,
      gameId: data.gameId,
      roomCode: data.roomCode,
      familyId: data.familyId,
      fromUserId: data.fromUserId,
      fromName: data.fromName,
      maxPlayers: data.maxPlayers,
      currentPlayers: data.currentPlayers,
      message: data.message ?? null,
    });
  }

  @SubscribeMessage('game:invite:accept')
  handleGameInviteAccept(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: {
      inviteId: string;
      gameType: string;
      gameId: string;
      familyId: string;
      fromUserId: string;
    },
  ) {
    // Notify the original sender that their invite was accepted.
    this.emitToUser(data.fromUserId, 'game:invite:accepted', {
      inviteId: data.inviteId,
      gameType: data.gameType,
      gameId: data.gameId,
      familyId: data.familyId,
      acceptedByUserId: (client as any).userId,
    });
  }

  @SubscribeMessage('game:invite:decline')
  handleGameInviteDecline(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: {
      inviteId: string;
      fromUserId: string;
      gameId?: string;
    },
  ) {
    this.emitToUser(data.fromUserId, 'game:invite:declined', {
      inviteId: data.inviteId,
      gameId: data.gameId ?? '',
      declinedByUserId: (client as any).userId,
    });
  }

  // ── In-lobby chat / reactions ────────────────────────────────────────
  // Ephemeral (not persisted). Broadcast to everyone in the game's chat room.

  @SubscribeMessage('game:chat:join')
  handleGameChatJoin(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: { gameTable: string; gameId: string },
  ) {
    const roomName = `game-chat:${data.gameTable}:${data.gameId}`;
    client.join(roomName);
    client.emit('game:chat:joined', { gameTable: data.gameTable, gameId: data.gameId });
  }

  @SubscribeMessage('game:chat:leave')
  handleGameChatLeave(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: { gameTable: string; gameId: string },
  ) {
    client.leave(`game-chat:${data.gameTable}:${data.gameId}`);
  }

  @SubscribeMessage('game:chat:message')
  handleGameChatMessage(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: {
      gameTable: string;
      gameId: string;
      familyId: string;
      type: string; // 'text' | 'emoji'
      content: string;
      senderName: string;
      senderId: string;
      isSpectator: boolean;
      timestamp: string;
    },
  ) {
    const roomName = `game-chat:${data.gameTable}:${data.gameId}`;
    // Broadcast to everyone in the chat room (including sender for echo confirmation)
    this.server.to(roomName).emit('game:chat:message', {
      ...data,
      timestamp: new Date().toISOString(),
    });
  }

  // ── Spectator count tracking ─────────────────────────────────────────
  // Players + spectators both join the game's spectator room. The server
  // maintains a count of connected sockets per room and broadcasts updates.

  @SubscribeMessage('game:spectator:join')
  handleGameSpectatorJoin(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: {
      gameTable: string;
      gameId: string;
      familyId: string;
      userId: string;
      userName: string;
    },
  ) {
    const roomName = `game-spectators:${data.gameTable}:${data.gameId}`;
    client.join(roomName);
    // Broadcast updated count to everyone in the room
    const room = this.server.sockets.adapter.rooms.get(roomName);
    const count = room ? room.size : 0;
    this.server.to(roomName).emit('game:spectator:count', {
      gameTable: data.gameTable,
      gameId: data.gameId,
      count,
    });
  }

  @SubscribeMessage('game:spectator:leave')
  handleGameSpectatorLeave(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: { gameTable: string; gameId: string; userId: string },
  ) {
    const roomName = `game-spectators:${data.gameTable}:${data.gameId}`;
    client.leave(roomName);
    const room = this.server.sockets.adapter.rooms.get(roomName);
    const count = room ? room.size : 0;
    this.server.to(roomName).emit('game:spectator:count', {
      gameTable: data.gameTable,
      gameId: data.gameId,
      count,
    });
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
