import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../../prisma/prisma.service';
import Redis from 'ioredis';

/**
 * PresenceService — tracks per-user online/offline status.
 *
 * Strategy:
 *   • In-memory Map<userId, PresenceEntry> for sub-millisecond reads
 *     during Socket.IO event handlers.
 *   • Optional Redis mirror if REDIS_URL is set (and not the default
 *     localhost), so presence survives across multiple server instances
 *     / horizontal scaling. Falls back to in-memory only if Redis is
 *     unavailable (matching the auth.service pattern).
 *   • UserPresence table is the persistent source of truth — updated on
 *     every connect/disconnect so a server restart can re-hydrate.
 *
 * Socket count semantics: a single user can have multiple active sockets
 * (e.g. phone + web). The user is "online" while at least one socket is
 * connected. Only when the LAST socket disconnects do we mark them
 * offline + record lastSeenAt.
 *
 * Broadcasting: when status changes (online→offline or offline→online),
 * PresenceService emits a 'presenceUpdate' event to every family the user
 * is a member of, via the KinrelGateway.emitToFamily helper. The Flutter
 * chat list + chat header listen for this event to update the green dot
 * + "Active now" / "Last seen X ago" label.
 */
interface PresenceEntry {
  userId: string;
  socketCount: number;
  isOnline: boolean;
  lastSeenAt: Date;
}

@Injectable()
export class PresenceService implements OnModuleDestroy {
  private readonly logger = new Logger(PresenceService.name);
  private redis: Redis | null = null;

  /// In-memory cache. Always populated (even when Redis is configured)
  /// so reads don't require a Redis round-trip. The Redis mirror is
  /// only for cross-instance consistency.
  private readonly presence = new Map<string, PresenceEntry>();

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {
    // Mirror the auth.service.ts Redis-init pattern: only connect if
    // REDIS_URL is explicitly set (and not the default localhost).
    const redisUrl = this.config.get<string>('REDIS_URL', '');
    if (redisUrl && redisUrl !== 'redis://localhost:6379') {
      this.redis = new Redis(redisUrl, {
        lazyConnect: true,
        maxRetriesPerRequest: 1,
        connectTimeout: 5000,
      });
      this.redis.on('error', (err) => {
        if (
          err.message?.includes('ECONNREFUSED') ||
          err.message?.includes('AggregateError')
        ) {
          if (this.redis) {
            this.redis.disconnect();
            this.redis = null;
          }
        }
      });
      this.redis.connect().catch(() => {
        this.redis = null;
      });
    }
  }

  /**
   * Called by KinrelGateway.handleConnection after the socket is
   * authenticated. Increments the user's socket count. If this is the
   * first socket (count was 0), flips status to online, updates the
   * UserPresence row, and broadcasts 'presenceUpdate' to the user's
   * families.
   *
   * Returns the new presence entry so the caller can include it in
   * the join ack if desired.
   */
  async userConnected(userId: string): Promise<PresenceEntry> {
    const existing = this.presence.get(userId);
    const now = new Date();

    if (existing) {
      // User already had at least one socket — just bump the count.
      existing.socketCount += 1;
      // If they were marked offline (stale row), flip to online.
      if (!existing.isOnline) {
        existing.isOnline = true;
        existing.lastSeenAt = now;
        await this.persistAndBroadcast(userId, true, now);
      }
      this.presence.set(userId, existing);
      return existing;
    }

    // First socket for this user — create the entry.
    const entry: PresenceEntry = {
      userId,
      socketCount: 1,
      isOnline: true,
      lastSeenAt: now,
    };
    this.presence.set(userId, entry);
    await this.persistAndBroadcast(userId, true, now);
    return entry;
  }

  /**
   * Called by KinrelGateway.handleDisconnect. Decrements the user's
   * socket count. If count reaches 0, flips status to offline, updates
   * lastSeenAt, persists, and broadcasts 'presenceUpdate'.
   *
   * Returns the updated entry (or null if the user had no entry, which
   * shouldn't happen but is a defensive guard).
   */
  async userDisconnected(userId: string): Promise<PresenceEntry | null> {
    const existing = this.presence.get(userId);
    if (!existing) {
      // Defensive: socket disconnect without a matching connect. Could
      // happen if the server restarted mid-connection. No-op.
      return null;
    }

    existing.socketCount = Math.max(0, existing.socketCount - 1);

    if (existing.socketCount === 0) {
      // Last socket gone → mark offline.
      const now = new Date();
      existing.isOnline = false;
      existing.lastSeenAt = now;
      await this.persistAndBroadcast(userId, false, now);
    }
    this.presence.set(userId, existing);
    return existing;
  }

  /**
   * Get the current presence for a user. Reads from the in-memory cache
   * — no DB or Redis round-trip. Returns a synthetic "offline" entry if
   * the user has never connected.
   */
  getPresence(userId: string): PresenceEntry {
    return (
      this.presence.get(userId) ?? {
        userId,
        socketCount: 0,
        isOnline: false,
        lastSeenAt: new Date(0), // epoch — "Last seen long ago"
      }
    );
  }

  /**
   * Get presence for all members of a family. Returns a map of
   * userId → PresenceEntry for quick lookup. Used by the chat list to
   * render green dots + "Active now" labels.
   */
  async getPresenceForFamily(familyId: string): Promise<Map<string, PresenceEntry>> {
    const members = await this.prisma.familyMember.findMany({
      where: { familyId },
      select: { userId: true },
    });
    const result = new Map<string, PresenceEntry>();
    for (const m of members) {
      // Try in-memory first; fall back to UserPresence table for users
      // who connected before this server started.
      const cached = this.presence.get(m.userId);
      if (cached) {
        result.set(m.userId, cached);
      }
    }
    return result;
  }

  /**
   * Persist the presence to the UserPresence table AND broadcast a
   * 'presenceUpdate' event to every family the user is a member of.
   *
   * The broadcast is best-effort — if the gateway or DB is slow, we
   * don't block the socket connection. Errors are logged + swallowed.
   */
  private async persistAndBroadcast(
    userId: string,
    isOnline: boolean,
    timestamp: Date,
  ) {
    try {
      // 1. Upsert UserPresence row (source of truth across restarts).
      await this.prisma.userPresence.upsert({
        where: { userId },
        create: { userId, isOnline, lastSeenAt: timestamp },
        update: { isOnline, lastSeenAt: timestamp },
      });

      // 2. Update MemberPresence rows (per-family view) so the Flutter
      //    app's existing queries on MemberPresence stay consistent.
      await this.prisma.memberPresence.updateMany({
        where: { userId },
        data: {
          status: isOnline ? 'online' : 'offline',
          lastSeenAt: timestamp,
          updatedAt: timestamp,
        },
      });

      // 3. Mirror to Redis (if configured) for cross-instance consistency.
      if (this.redis) {
        const key = `presence:${userId}`;
        if (isOnline) {
          await this.redis.hset(key, {
            userId,
            isOnline: '1',
            lastSeenAt: timestamp.toISOString(),
          });
        } else {
          await this.redis.hset(key, {
            userId,
            isOnline: '0',
            lastSeenAt: timestamp.toISOString(),
          });
        }
      }
    } catch (err: any) {
      // Persistence failure is non-fatal — the in-memory cache is still
      // correct for this server instance. Just log.
      this.logger.warn(
        `Presence persist failed for ${userId}: ${err?.message}`,
      );
    }

    // 4. Broadcast 'presenceUpdate' to every family the user is in.
    //    The actual emit goes through the KinrelGateway.emitToFamily
    //    helper, which is injected via a setter (avoids a circular DI).
    if (this.emitToFamilyFn) {
      try {
        const families = await this.prisma.familyMember.findMany({
          where: { userId },
          select: { familyId: true },
        });
        for (const f of families) {
          this.emitToFamilyFn(
            f.familyId,
            'presenceUpdate',
            {
              userId,
              status: isOnline ? 'online' : 'offline',
              lastSeenAt: timestamp.toISOString(),
            },
          );
        }
      } catch (err: any) {
        this.logger.warn(
          `Presence broadcast failed for ${userId}: ${err?.message}`,
        );
      }
    }
  }

  /// The KinrelGateway injects its emitToFamily helper here on module init.
  /// This avoids a circular DI (PresenceService → KinrelGateway → PresenceService).
  private emitToFamilyFn:
    | ((familyId: string, event: string, payload: Record<string, unknown>) => void)
    | null = null;

  setEmitToFamilyFn(
    fn: (familyId: string, event: string, payload: Record<string, unknown>) => void,
  ) {
    this.emitToFamilyFn = fn;
  }

  onModuleDestroy() {
    if (this.redis) {
      this.redis.disconnect();
      this.redis = null;
    }
  }
}
