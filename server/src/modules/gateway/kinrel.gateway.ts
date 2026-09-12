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
  cors: { origin: '*' },
  namespace: '/',
  transports: ['websocket'],
  pingTimeout: 10000,
  pingInterval: 25000,
})
export class KinrelGateway implements OnGatewayConnection, OnGatewayDisconnect {
  @WebSocketServer()
  server: Server;

  constructor(private readonly prisma: PrismaService) {}

  private connectedUsers = new Map<string, string>();
  private graphDebounceTimers = new Map<string, NodeJS.Timeout>();

  /**
   * Presence tracker — for each socket, which game rooms it has joined.
   * Map<socketId, Array<{ gameTable, gameId, userId, userName, isHost }>>
   *
   * Used by handleDisconnect() to broadcast room:player_left events with
   * reason 'disconnected' to all rooms the disconnected socket was in,
   * and to detect host disconnects (which auto-close the room).
   */
  private socketGameRooms = new Map<
    string,
    Array<{
      gameTable: string;
      gameId: string;
      userId: string;
      userName: string;
      isHost: boolean;
    }>
  >();

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

    // Look up all the game rooms this socket had joined, and broadcast
    // room:player_left with reason 'disconnected' to each. If the
    // disconnecting user was the host of a waiting room, auto-close it.
    const rooms = this.socketGameRooms.get(client.id) || [];
    this.socketGameRooms.delete(client.id);
    for (const r of rooms) {
      const roomName = `game-room:${r.gameTable}:${r.gameId}`;
      const chatRoomName = `game-chat:${r.gameTable}:${r.gameId}`;

      // Broadcast a player_left event so all clients can update their
      // lobby UI immediately (no refresh needed).
      this.server.to(roomName).emit('room:player_left', {
        gameTable: r.gameTable,
        gameId: r.gameId,
        userId: r.userId,
        userName: r.userName,
        reason: 'disconnected',
        timestamp: new Date().toISOString(),
      });

      // Broadcast a system chat message: "Manish left the room (disconnected)"
      this.server.to(chatRoomName).emit('game:chat:message', {
        gameTable: r.gameTable,
        gameId: r.gameId,
        familyId: '',
        type: 'system',
        content: `${r.userName} disconnected`,
        senderName: 'System',
        senderId: 'system',
        isSpectator: false,
        timestamp: new Date().toISOString(),
      });

      // If the disconnecting user was the host AND the game is still in a
      // pre-game state, auto-close the room. All clients will receive a
      // 'room:closed' event and auto-navigate back to the game hub.
      if (r.isHost) {
        this._autoCloseRoom(r.gameTable, r.gameId, r.userName, 'host_disconnected');
      }
    }

    console.log(`[WS] Disconnected: ${client.id}`);
  }

  /**
   * Auto-close a room: broadcast room:closed to all participants, then
   * attempt to delete the game row + invites via direct DB call.
   * Used when the host disconnects or leaves without explicitly closing.
   */
  private async _autoCloseRoom(
    gameTable: string,
    gameId: string,
    closedByName: string,
    reason: string,
  ) {
    // Whitelist of allowed game tables — prevents SQL injection since
    // gameTable is interpolated into raw SQL below.
    const allowedTables = new Set([
      'antakshari_games', 'chitmatch_games', 'bingo_games', 'ludo_games',
      'sos_games', 'dotsboxes_games', 'nameplace_games',
      'truthordare_games', 'twotruths_games', 'redlight_rounds',
      'chess_games', 'tictactoe_games', 'checkers_games', 'carrom_games',
    ]);
    if (!allowedTables.has(gameTable)) {
      console.warn(`[WS] _autoCloseRoom: refusing unknown game table: ${gameTable}`);
      return;
    }

    const roomName = `game-room:${gameTable}:${gameId}`;
    const chatRoomName = `game-chat:${gameTable}:${gameId}`;

    // Broadcast close event to everyone in the room.
    this.server.to(roomName).emit('room:closed', {
      gameTable,
      gameId,
      closedBy: closedByName,
      reason, // 'host_disconnected' | 'host_left' | 'host_closed' | 'expired'
      timestamp: new Date().toISOString(),
    });

    // Broadcast a system chat message.
    this.server.to(chatRoomName).emit('game:chat:message', {
      gameTable,
      gameId,
      familyId: '',
      type: 'system',
      content: `${closedByName} closed the room`,
      senderName: 'System',
      senderId: 'system',
      isSpectator: false,
      timestamp: new Date().toISOString(),
    });

    // Best-effort DB cleanup: delete the game row + invites. The
    // cascade FK on the game table will delete child rows (players,
    // turns, moves, etc.). We wrap in a try/catch because the game
    // table might already be gone (e.g., host cancelled twice).
    try {
      // Delete invites first (no FK to game table).
      await this.prisma.$executeRawUnsafe(
        `DELETE FROM "public"."game_invites" WHERE "gameTable" = $1 AND "gameId" = $2`,
        gameTable,
        gameId,
      );
      // Then delete the game row itself. gameTable is whitelisted above.
      await this.prisma.$executeRawUnsafe(
        `DELETE FROM "public"."${gameTable}" WHERE "id" = $1`,
        gameId,
      );
    } catch (err) {
      console.warn(
        `[WS] _autoCloseRoom: DB cleanup failed for ${gameTable}:${gameId}:`,
        (err as Error).message,
      );
    }
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
  async handleGameInviteSend(
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

    // Also persist a Notification row so the recipient sees the invite
    // even if they were offline when it was sent (the socket event only
    // reaches currently-connected users). This closes the gap where
    // game invites were silently lost for offline users.
    try {
      await this.prisma.notification.create({
        data: {
          id: 'game_notif_' + Date.now() + '_' + data.toUserId,
          userId: data.toUserId,
          eventType: 'game_invite',
          title: `${data.fromName} invited you to play`,
          body: data.message ?? `Join ${data.fromName} in a game on Daxelo Kinrel!`,
          familyId: data.familyId,
          actionUrl: `kinrel://game/${data.gameType}?roomCode=${data.roomCode}&gameId=${data.gameId}`,
          priority: 'high',
          read: false,
          channels: [],
          createdAt: new Date(),
          updatedAt: new Date(),
        },
      });
    } catch (e) {
      // Don't fail the invite if the notification insert fails —
      // the realtime event may still reach an online user.
      console.error('[KinrelGateway] Failed to persist game invite notification:', e);
    }
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

  @SubscribeMessage('game:chat:typing')
  handleGameChatTyping(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: {
      gameTable: string;
      gameId: string;
      userId: string;
      userName: string;
      isTyping: boolean;
      timestamp: string;
    },
  ) {
    const roomName = `game-chat:${data.gameTable}:${data.gameId}`;
    // Broadcast typing indicator to everyone in the chat room EXCEPT the
    // sender (they already know they're typing).
    this.server.to(roomName).emit('game:chat:typing', {
      ...data,
      timestamp: new Date().toISOString(),
    });
    // Note: socket.io's `to(roomName)` includes the sender; to exclude them
    // we'd use `broadcast.to(roomName)`. We deliberately include the sender
    // so the sender's own client gets an echo confirmation that the typing
    // event was received by the server (which the client uses to clear the
    // local optimistic typing state). The client filters out its own typing
    // events in the _onTyping handler.
  }

  // ── Game room presence + lifecycle ───────────────────────────────────
  //
  // These events track which sockets are in which game rooms so that
  // handleDisconnect() can broadcast room:player_left events when a
  // socket drops. They also drive the system chat messages
  // ("X joined the room", "X left the room") and the host-close flow.
  //
  // NOTE: Supabase Realtime already broadcasts the player_row INSERT /
  // UPDATE / DELETE events to all subscribers. The events below ADD:
  //   • Instant presence awareness (no DB round-trip needed for "X is
  //     typing" / "X just joined")
  //   • System chat messages
  //   • Disconnect detection (Supabase Realtime can't detect a closed
  //     socket — only the Socket.IO gateway knows when a client drops)
  //   • Host-close auto-navigation (room:closed event)

  @SubscribeMessage('game:room:join')
  handleGameRoomJoin(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: {
      gameTable: string;
      gameId: string;
      userId: string;
      userName: string;
      isHost: boolean;
    },
  ) {
    const userId = (client as any).userId || data.userId;
    if (!userId || userId !== data.userId) {
      client.emit('error', { message: 'Not authenticated' });
      return;
    }

    const roomName = `game-room:${data.gameTable}:${data.gameId}`;
    const chatRoomName = `game-chat:${data.gameTable}:${data.gameId}`;
    client.join(roomName);
    // Also auto-join the chat room so they receive system messages.
    client.join(chatRoomName);

    // Track this socket's room membership so handleDisconnect can clean up.
    const rooms = this.socketGameRooms.get(client.id) || [];
    // Avoid duplicate entries if the client emits join twice.
    if (!rooms.some(
      (r) => r.gameTable === data.gameTable && r.gameId === data.gameId,
    )) {
      rooms.push({
        gameTable: data.gameTable,
        gameId: data.gameId,
        userId: data.userId,
        userName: data.userName,
        isHost: data.isHost,
      });
      this.socketGameRooms.set(client.id, rooms);
    }

    // Broadcast a player_joined event so all clients can update their
    // lobby UI immediately (no refresh needed). This fires IN ADDITION
    // to the Supabase Realtime player_row INSERT event — clients should
    // dedupe by userId.
    this.server.to(roomName).emit('room:player_joined', {
      gameTable: data.gameTable,
      gameId: data.gameId,
      userId: data.userId,
      userName: data.userName,
      isHost: data.isHost,
      timestamp: new Date().toISOString(),
    });

    // Broadcast a system chat message: "Manish joined the room"
    this.server.to(chatRoomName).emit('game:chat:message', {
      gameTable: data.gameTable,
      gameId: data.gameId,
      familyId: '',
      type: 'system',
      content: `${data.userName} joined the room`,
      senderName: 'System',
      senderId: 'system',
      isSpectator: false,
      timestamp: new Date().toISOString(),
    });
  }

  @SubscribeMessage('game:room:leave')
  handleGameRoomLeave(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: {
      gameTable: string;
      gameId: string;
      userId: string;
      userName: string;
      isHost: boolean;
    },
  ) {
    const roomName = `game-room:${data.gameTable}:${data.gameId}`;
    const chatRoomName = `game-chat:${data.gameTable}:${data.gameId}`;

    // Broadcast player_left BEFORE removing the socket from the room,
    // so the leaving socket also receives the event (it can use it to
    // confirm its leave was acked).
    this.server.to(roomName).emit('room:player_left', {
      gameTable: data.gameTable,
      gameId: data.gameId,
      userId: data.userId,
      userName: data.userName,
      reason: 'left',
      timestamp: new Date().toISOString(),
    });

    // System chat message: "Manish left the room"
    this.server.to(chatRoomName).emit('game:chat:message', {
      gameTable: data.gameTable,
      gameId: data.gameId,
      familyId: '',
      type: 'system',
      content: `${data.userName} left the room`,
      senderName: 'System',
      senderId: 'system',
      isSpectator: false,
      timestamp: new Date().toISOString(),
    });

    // If the host is leaving a waiting room, auto-close it (deletes the
    // game row, broadcasts room:closed). Otherwise just remove the player.
    if (data.isHost) {
      this._autoCloseRoom(
        data.gameTable,
        data.gameId,
        data.userName,
        'host_left',
      );
    }

    // Remove the socket from the room.
    client.leave(roomName);
    client.leave(chatRoomName);

    // Remove from the presence tracker.
    const rooms = this.socketGameRooms.get(client.id) || [];
    const filtered = rooms.filter(
      (r) => !(r.gameTable === data.gameTable && r.gameId === data.gameId),
    );
    if (filtered.length === 0) {
      this.socketGameRooms.delete(client.id);
    } else {
      this.socketGameRooms.set(client.id, filtered);
    }
  }

  @SubscribeMessage('game:room:close')
  handleGameRoomClose(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: {
      gameTable: string;
      gameId: string;
      userId: string;
      userName: string;
    },
  ) {
    const userId = (client as any).userId;
    if (!userId || userId !== data.userId) {
      client.emit('error', { message: 'Not authenticated' });
      return;
    }
    // Host explicitly closes the room — auto-close with reason 'host_closed'.
    this._autoCloseRoom(
      data.gameTable,
      data.gameId,
      data.userName,
      'host_closed',
    );
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
