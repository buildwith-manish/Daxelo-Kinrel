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
import { createClient, SupabaseClient } from '@supabase/supabase-js';

/**
 * Freeze & Dash (Red Light, Green Light) — server-authoritative gateway.
 *
 * Architecture (Build Prompt §1):
 *   • This gateway is the single clock and referee — phase transitions
 *     and movement-during-red detection come exclusively from here.
 *   • Supabase stores lobby membership, final results, and cosmetic
 *     state. Realtime is used for lobby presence only.
 *   • All Supabase writes from this gateway use the service role key.
 *
 * Auth: dual-JWT verification (JWT_ACCESS_SECRET first, then
 * SUPABASE_JWT_SECRET) — copied verbatim from kinrel.gateway.ts.
 */

interface AuthPayload {
  sub: string;
  email: string;
  role: string;
}

interface RedlightPlayerState {
  userId: string;
  userName: string;
  socketId: string;
  progress: number; // 0–100
  alive: boolean;
  teamId: string | null;
  shieldActive: boolean;
  speedBoostActive: boolean;
  speedBoostExpiry: number | null; // Date.now() ms
  isRunning: boolean; // true while client holds "Run" button during GREEN
  lastProgressUpdate: number; // Date.now() ms — for rain rate-limiting
}

interface RedlightRoundState {
  roundId: string;
  familyId: string;
  hostSocketId: string;
  hostUserId: string;
  phase: 'green' | 'red';
  phaseTimer: NodeJS.Timeout | null;
  weatherModifier: string | null;
  eliminationMode: boolean;
  teamMode: boolean;
  callerCharacter: string;
  mapTheme: string;
  startedAt: number;
  hardCapTimer: NodeJS.Timeout | null;
  windTimer: NodeJS.Timeout | null;
  powerupTimer: NodeJS.Timeout | null;
  leaderboardTimer: NodeJS.Timeout | null;
  spawnedPowerups: Map<string, { type: 'shield' | 'speedBoost'; position: number }>;
  players: Map<string, RedlightPlayerState>;
}

@WebSocketGateway({
  cors: { origin: '*' },
  namespace: '/redlight',
  transports: ['websocket'],
  pingTimeout: 10000,
  pingInterval: 25000,
})
export class RedlightGateway
  implements OnGatewayConnection, OnGatewayDisconnect
{
  @WebSocketServer()
  server: Server;

  // Key: roundId
  private rounds = new Map<string, RedlightRoundState>();

  // Module-level singleton Supabase client (service role)
  private supabase: SupabaseClient | null = null;

  constructor() {
    this.initSupabase();
  }

  private initSupabase() {
    const supabaseUrl = process.env.SUPABASE_URL;
    const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!supabaseUrl || !serviceRoleKey) {
      console.warn(
        '[RedlightGateway] SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY not set — DB writes will fail.',
      );
      return;
    }
    this.supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    console.log('[RedlightGateway] Supabase service-role client initialized');
  }

  // ── Connection lifecycle (auth copied from kinrel.gateway.ts) ────────

  async handleConnection(client: Socket) {
    try {
      const token =
        client.handshake.auth?.token ||
        client.handshake.query?.token ||
        client.handshake.headers?.authorization?.replace('Bearer ', '');

      if (!token) {
        console.warn(
          `[Redlight] Connection rejected — no token: ${client.id}`,
        );
        client.disconnect(true);
        return;
      }

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
            payload = {
              sub: decoded.sub,
              email: decoded.email || '',
              role: decoded.role || 'user',
            };
          } catch {}
        }
      }

      if (!payload) {
        console.warn(
          `[Redlight] Connection rejected — invalid token: ${client.id}`,
        );
        client.disconnect(true);
        return;
      }

      const userId = payload.sub;
      (client as any).userId = userId;

      console.log(`[Redlight] Connected: ${client.id} (user: ${userId})`);
    } catch (err) {
      console.warn(
        `[Redlight] Connection rejected — error: ${client.id}`,
        (err as Error).message,
      );
      client.disconnect(true);
    }
  }

  handleDisconnect(client: Socket) {
    const userId = (client as any).userId as string | undefined;
    console.log(`[Redlight] Disconnected: ${client.id}`);

    if (!userId) return;

    // Remove the player from any round they were in
    for (const [roundId, round] of this.rounds.entries()) {
      const player = round.players.get(userId);
      if (player && player.socketId === client.id) {
        round.players.delete(userId);
        this.server
          .to(`redlight:${roundId}`)
          .emit('redlight:player_left', { userId });
        // Update Supabase row (best-effort)
        this.supabase
          ?.from('redlight_players')
          .delete()
          .eq('roundId', roundId)
          .eq('userId', userId)
          .then(
            () => {},
            () => {},
          );
      }
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  private roomName(roundId: string): string {
    return `redlight:${roundId}`;
  }

  private emitError(client: Socket, message: string) {
    client.emit('redlight:error', { message });
  }

  private broadcastLeaderboard(round: RedlightRoundState) {
    const players = [...round.players.values()].map((p) => ({
      userId: p.userId,
      userName: p.userName,
      progress: Math.round(p.progress * 100) / 100,
      alive: p.alive,
      teamId: p.teamId,
    }));
    this.server
      .to(this.roomName(round.roundId))
      .emit('redlight:leaderboard', { players });
  }

  // ── Incoming events ─────────────────────────────────────────────────

  @SubscribeMessage('redlight:join')
  async handleJoin(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: { roundId: string; userId: string; userName: string; teamId?: string | null },
  ) {
    const clientUserId = (client as any).userId as string;
    if (!clientUserId || clientUserId !== data.userId) {
      this.emitError(client, 'User ID mismatch');
      return;
    }

    let round = this.rounds.get(data.roundId);
    if (!round) {
      // Load round metadata from Supabase (host hasn't started yet)
      if (!this.supabase) {
        this.emitError(client, 'Server not configured');
        return;
      }
      const { data: row, error } = await this.supabase
        .from('redlight_rounds')
        .select('*')
        .eq('id', data.roundId)
        .single();
      if (error || !row) {
        this.emitError(client, 'Round not found');
        return;
      }
      round = {
        roundId: data.roundId,
        familyId: row.familyId,
        hostSocketId: '', // host will set itself when it joins
        hostUserId: row.hostUserId,
        phase: 'green',
        phaseTimer: null,
        weatherModifier: row.weatherModifier || null,
        eliminationMode: !!row.eliminationMode,
        teamMode: !!row.teamMode,
        callerCharacter: row.callerCharacter || 'grandma',
        mapTheme: row.mapTheme || 'forest',
        startedAt: Date.now(),
        hardCapTimer: null,
        windTimer: null,
        powerupTimer: null,
        leaderboardTimer: null,
        spawnedPowerups: new Map(),
        players: new Map(),
      };
      this.rounds.set(data.roundId, round);
    }

    if (round.players.size >= 20) {
      this.emitError(client, 'Round is full (max 20 players)');
      return;
    }

    client.join(this.roomName(data.roundId));

    const isHost = data.userId === round.hostUserId;
    if (isHost) {
      round.hostSocketId = client.id;
    }

    round.players.set(data.userId, {
      userId: data.userId,
      userName: data.userName,
      socketId: client.id,
      progress: 0,
      alive: true,
      teamId: data.teamId ?? null,
      shieldActive: false,
      speedBoostActive: false,
      speedBoostExpiry: null,
      isRunning: false,
      lastProgressUpdate: Date.now(),
    });

    this.server
      .to(this.roomName(data.roundId))
      .emit('redlight:player_joined', {
        userId: data.userId,
        userName: data.userName,
        teamId: data.teamId ?? null,
        isHost,
      });

    // Send current lobby snapshot to the newcomer
    this.broadcastLeaderboard(round);
  }

  @SubscribeMessage('redlight:start')
  async handleStart(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: { roundId: string },
  ) {
    const round = this.rounds.get(data.roundId);
    if (!round) {
      this.emitError(client, 'Round not found');
      return;
    }
    const clientUserId = (client as any).userId as string;
    if (clientUserId !== round.hostUserId) {
      this.emitError(client, 'Only the host can start the round');
      return;
    }
    if (round.players.size < 3) {
      this.emitError(
        client,
        'Need at least 3 players to start (currently ' +
          round.players.size +
          ')',
      );
      return;
    }

    // Countdown 3-2-1
    let countdown = 3;
    this.server
      .to(this.roomName(data.roundId))
      .emit('redlight:countdown', { secondsLeft: countdown });
    const countdownInterval = setInterval(() => {
      countdown -= 1;
      this.server
        .to(this.roomName(data.roundId))
        .emit('redlight:countdown', { secondsLeft: countdown });
      if (countdown <= 0) {
        clearInterval(countdownInterval);
        this.startActivePhase(round);
      }
    }, 1000);

    // Update Supabase status → 'countdown'
    if (this.supabase) {
      await this.supabase
        .from('redlight_rounds')
        .update({ status: 'countdown', startedAt: new Date().toISOString() })
        .eq('id', data.roundId);
    }
  }

  private startActivePhase(round: RedlightRoundState) {
    // Emit game_started
    this.server.to(this.roomName(round.roundId)).emit('redlight:game_started', {
      roundId: round.roundId,
      weatherModifier: round.weatherModifier,
      callerCharacter: round.callerCharacter,
      mapTheme: round.mapTheme,
    });

    // Update Supabase status → 'active'
    this.supabase
      ?.from('redlight_rounds')
      .update({ status: 'active' })
      .eq('id', round.roundId)
      .then(
        () => {},
        () => {},
      );

    // Start leaderboard broadcast (500ms)
    round.leaderboardTimer = setInterval(() => {
      this.broadcastLeaderboard(round);
    }, 500);

    // Start wind modifier (3s) if applicable
    if (round.weatherModifier === 'wind') {
      round.windTimer = setInterval(() => {
        for (const player of round.players.values()) {
          if (!player.alive) continue;
          const delta = (Math.random() - 0.5) * 4; // -2 to +2
          player.progress = Math.max(
            0,
            Math.min(100, player.progress + delta),
          );
        }
        this.broadcastLeaderboard(round);
        this.checkWinCondition(round);
      }, 3000);
    }

    // Start power-up spawning (8–15s)
    const schedulePowerup = () => {
      const delay = 8000 + Math.random() * 7000;
      round.powerupTimer = setTimeout(() => {
        this.spawnPowerup(round);
        schedulePowerup();
      }, delay);
    };
    schedulePowerup();

    // 90s hard cap
    round.hardCapTimer = setTimeout(() => {
      this.endRound(round, undefined, undefined, 'hard_cap');
    }, 90000);

    // Enter the first GREEN phase
    this.runGreenPhase(round);
  }

  private runGreenPhase(round: RedlightRoundState) {
    const durationMs = 2000 + Math.random() * 3000; // 2000–5000ms
    round.phase = 'green';
    this.server
      .to(this.roomName(round.roundId))
      .emit('redlight:phase_change', {
        phase: 'green',
        durationMs,
        roundId: round.roundId,
      });

    round.phaseTimer = setTimeout(() => {
      this.runRedPhase(round);
    }, durationMs);
  }

  private runRedPhase(round: RedlightRoundState) {
    const durationMs = 1000 + Math.random() * 2000; // 1000–3000ms
    round.phase = 'red';
    this.server
      .to(this.roomName(round.roundId))
      .emit('redlight:phase_change', {
        phase: 'red',
        durationMs,
        roundId: round.roundId,
      });

    // Apply penalties to any player still running
    for (const player of round.players.values()) {
      if (player.alive && player.isRunning) {
        this.applyPenalty(round, player);
      }
    }

    round.phaseTimer = setTimeout(() => {
      // Game might have ended during RED — check before scheduling another GREEN
      if (round.phase !== 'red') return;
      this.runGreenPhase(round);
    }, durationMs);
  }

  private applyPenalty(
    round: RedlightRoundState,
    player: RedlightPlayerState,
  ) {
    if (player.shieldActive) {
      player.shieldActive = false;
      this.server
        .to(this.roomName(round.roundId))
        .emit('redlight:caught', {
          userId: player.userId,
          penalty: 'shield_absorbed',
        });
      return;
    }
    if (round.eliminationMode) {
      player.alive = false;
      this.server
        .to(this.roomName(round.roundId))
        .emit('redlight:caught', {
          userId: player.userId,
          penalty: 'eliminated',
        });
    } else {
      player.progress = Math.max(0, player.progress - 10);
      this.server
        .to(this.roomName(round.roundId))
        .emit('redlight:caught', {
          userId: player.userId,
          penalty: 'knockback',
          knockbackAmount: 10,
        });
    }
  }

  @SubscribeMessage('redlight:run_start')
  handleRunStart(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: { roundId: string; userId: string },
  ) {
    const round = this.rounds.get(data.roundId);
    if (!round) return;
    const player = round.players.get(data.userId);
    if (!player || !player.alive) return;

    player.isRunning = true;

    // If we're in RED phase and they pressed run, penalize immediately
    if (round.phase === 'red') {
      this.applyPenalty(round, player);
    }
  }

  @SubscribeMessage('redlight:run_stop')
  handleRunStop(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: { roundId: string; userId: string },
  ) {
    const round = this.rounds.get(data.roundId);
    if (!round) return;
    const player = round.players.get(data.userId);
    if (!player) return;
    player.isRunning = false;
  }

  @SubscribeMessage('redlight:progress_tick')
  handleProgressTick(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: { roundId: string; userId: string; delta: number },
  ) {
    const round = this.rounds.get(data.roundId);
    if (!round) return;
    const player = round.players.get(data.userId);
    if (!player || !player.alive) return;

    // Throttle: max 1 update per 50ms per player
    const now = Date.now();
    if (now - player.lastProgressUpdate < 50) return;
    player.lastProgressUpdate = now;

    // Only honor progress ticks during GREEN
    if (round.phase !== 'green') return;

    this.applyProgressDelta(round, player, data.delta);
  }

  private applyProgressDelta(
    round: RedlightRoundState,
    player: RedlightPlayerState,
    delta: number,
  ) {
    let adjusted = delta;
    // Rain: -15% rate
    if (round.weatherModifier === 'rain') {
      adjusted *= 0.85;
    }
    // Speed boost: 2x for 3s
    if (
      player.speedBoostActive &&
      player.speedBoostExpiry !== null &&
      Date.now() < player.speedBoostExpiry
    ) {
      adjusted *= 2;
    } else if (player.speedBoostActive) {
      // Expired — clear flag
      player.speedBoostActive = false;
      player.speedBoostExpiry = null;
    }

    player.progress = Math.min(100, player.progress + adjusted);
    this.checkWinCondition(round);
  }

  private spawnPowerup(round: RedlightRoundState) {
    const id = `pu_${Date.now()}_${Math.floor(Math.random() * 10000)}`;
    const type: 'shield' | 'speedBoost' = Math.random() < 0.5 ? 'shield' : 'speedBoost';
    const position = Math.random() * 100;
    round.spawnedPowerups.set(id, { type, position });
    this.server
      .to(this.roomName(round.roundId))
      .emit('redlight:powerup_spawned', { powerupId: id, type, position });
  }

  @SubscribeMessage('redlight:powerup_collect')
  handlePowerupCollect(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: { roundId: string; userId: string; powerupType: string; powerupId?: string },
  ) {
    const round = this.rounds.get(data.roundId);
    if (!round) return;
    const player = round.players.get(data.userId);
    if (!player || !player.alive) return;

    // Find the powerup by id (if provided) or by position proximity
    let matchedId: string | null = null;
    if (data.powerupId && round.spawnedPowerups.has(data.powerupId)) {
      matchedId = data.powerupId;
    } else {
      // Find any powerup within 5 units of the player's progress
      for (const [pid, p] of round.spawnedPowerups.entries()) {
        if (Math.abs(p.position - player.progress) <= 5) {
          matchedId = pid;
          break;
        }
      }
    }
    if (!matchedId) {
      this.emitError(client, 'No powerup nearby to collect');
      return;
    }
    const powerup = round.spawnedPowerups.get(matchedId)!;
    round.spawnedPowerups.delete(matchedId);

    if (powerup.type === 'shield') {
      player.shieldActive = true;
    } else if (powerup.type === 'speedBoost') {
      player.speedBoostActive = true;
      player.speedBoostExpiry = Date.now() + 3000;
    }
  }

  @SubscribeMessage('redlight:leave')
  async handleLeave(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: { roundId: string; userId: string },
  ) {
    const round = this.rounds.get(data.roundId);
    if (!round) return;
    round.players.delete(data.userId);
    client.leave(this.roomName(data.roundId));
    this.server
      .to(this.roomName(data.roundId))
      .emit('redlight:player_left', { userId: data.userId });
    if (this.supabase) {
      await this.supabase
        .from('redlight_players')
        .delete()
        .eq('roundId', data.roundId)
        .eq('userId', data.userId);
    }
  }

  // ── Win condition & round end ────────────────────────────────────────

  private checkWinCondition(round: RedlightRoundState) {
    const alivePlayers = [...round.players.values()].filter((p) => p.alive);

    // Solo: first to 100
    if (!round.teamMode) {
      const winner = alivePlayers.find((p) => p.progress >= 100);
      if (winner) {
        this.endRound(round, winner.userId, winner.userName);
        return;
      }
      // All eliminated: most progress wins
      if (alivePlayers.length === 0 && round.players.size > 0) {
        const best = [...round.players.values()].sort(
          (a, b) => b.progress - a.progress,
        )[0];
        this.endRound(round, best?.userId, best?.userName, 'all_eliminated');
        return;
      }
      return;
    }

    // Team mode: first team with ALL members at 100
    const teams = new Map<string, RedlightPlayerState[]>();
    for (const p of alivePlayers) {
      if (!p.teamId) continue;
      const arr = teams.get(p.teamId) ?? [];
      arr.push(p);
      teams.set(p.teamId, arr);
    }
    for (const [teamId, members] of teams.entries()) {
      if (members.length > 0 && members.every((m) => m.progress >= 100)) {
        this.endRound(round, undefined, undefined, 'team_win', teamId);
        return;
      }
    }
  }

  private endRound(
    round: RedlightRoundState,
    winnerId?: string,
    winnerName?: string,
    reason: 'solo_win' | 'team_win' | 'all_eliminated' | 'hard_cap' = 'solo_win',
    teamWinnerId?: string,
  ) {
    // Prevent double-end
    if (round.phaseTimer === null && round.hardCapTimer === null) return;

    // Clear timers
    if (round.phaseTimer) clearTimeout(round.phaseTimer);
    if (round.hardCapTimer) clearTimeout(round.hardCapTimer);
    if (round.windTimer) clearInterval(round.windTimer);
    if (round.powerupTimer) clearTimeout(round.powerupTimer);
    if (round.leaderboardTimer) clearInterval(round.leaderboardTimer);
    round.phaseTimer = null;
    round.hardCapTimer = null;
    round.windTimer = null;
    round.powerupTimer = null;
    round.leaderboardTimer = null;

    // Compute placements
    const sorted = [...round.players.values()].sort(
      (a, b) => b.progress - a.progress,
    );
    const placements = sorted.map((p, i) => ({
      userId: p.userId,
      userName: p.userName,
      progress: Math.round(p.progress * 100) / 100,
      placement: i + 1,
      teamId: p.teamId,
      alive: p.alive,
    }));

    // For hard_cap team mode: pick the team with highest combined progress
    let resolvedTeamWinnerId: string | undefined = teamWinnerId;
    if (round.teamMode && reason === 'hard_cap' && !resolvedTeamWinnerId) {
      const teamTotals = new Map<string, number>();
      for (const p of sorted) {
        if (!p.teamId) continue;
        teamTotals.set(p.teamId, (teamTotals.get(p.teamId) ?? 0) + p.progress);
      }
      let bestTeam: string | undefined;
      let bestTotal = -1;
      for (const [tid, total] of teamTotals.entries()) {
        if (total > bestTotal) {
          bestTotal = total;
          bestTeam = tid;
        }
      }
      resolvedTeamWinnerId = bestTeam;
    }

    // Emit finished event
    this.server
      .to(this.roomName(round.roundId))
      .emit('redlight:game_finished', {
        winnerId,
        winnerName,
        placements,
        teamWinnerId: resolvedTeamWinnerId,
        reason,
      });

    // Persist to Supabase (best-effort)
    this.persistRoundEnd(round, winnerId, winnerName, placements).catch(
      (e) => {
        console.warn('[Redlight] persistRoundEnd failed:', e);
      },
    );

    // Clean up in-memory state after 30s
    setTimeout(() => {
      this.rounds.delete(round.roundId);
    }, 30000);
  }

  private async persistRoundEnd(
    round: RedlightRoundState,
    winnerId: string | undefined,
    winnerName: string | undefined,
    placements: Array<{
      userId: string;
      userName: string;
      progress: number;
      placement: number;
    }>,
  ) {
    if (!this.supabase) return;

    // 1. Update round row
    await this.supabase
      .from('redlight_rounds')
      .update({
        status: 'finished',
        winnerUserId: winnerId ?? null,
        winnerUserName: winnerName ?? null,
        finishedAt: new Date().toISOString(),
      })
      .eq('id', round.roundId);

    // 2. Insert results (one row per player)
    if (placements.length > 0) {
      const rows = placements.map((p) => ({
        roundId: round.roundId,
        userId: p.userId,
        userName: p.userName,
        finalProgress: p.progress,
        placement: p.placement,
      }));
      await this.supabase.from('redlight_results').insert(rows);
    }

    // 3. Update final redlight_players rows
    for (const p of placements) {
      await this.supabase
        .from('redlight_players')
        .update({
          progress: p.progress,
          alive: p.placement === 1 ? true : false,
        })
        .eq('roundId', round.roundId)
        .eq('userId', p.userId);
    }
  }
}
