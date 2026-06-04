import {
  Injectable,
  Logger,
  OnModuleInit,
  OnModuleDestroy,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createClient, SupabaseClient, RealtimeChannel } from '@supabase/supabase-js';

// ── Types ───────────────────────────────────────────────────────────

export interface FamilyUpdateEvent {
  familyId: string;
  eventType:
    | 'person:created'
    | 'person:updated'
    | 'person:deleted'
    | 'relationship:created'
    | 'relationship:updated'
    | 'relationship:deleted'
    | 'graph:updated'
    | 'invite:created'
    | 'invite:updated';
  payload: {
    id?: string;
    familyId: string;
    personId?: string;
    updatedAt?: string;
    [key: string]: unknown;
  };
  timestamp: string;
}

export interface PresenceState {
  userId: string;
  familyId: string;
  status: 'online' | 'offline';
  lastSeen: string;
}

// ── Debounce Map ────────────────────────────────────────────────────

class DebounceMap {
  private timers: Map<string, NodeJS.Timeout> = new Map();
  private readonly delayMs: number;

  constructor(delayMs: number = 500) {
    this.delayMs = delayMs;
  }

  debounce(key: string, callback: () => void): void {
    const existing = this.timers.get(key);
    if (existing) {
      clearTimeout(existing);
    }
    this.timers.set(
      key,
      setTimeout(() => {
        this.timers.delete(key);
        callback();
      }, this.delayMs),
    );
  }

  clear(): void {
    for (const timer of this.timers.values()) {
      clearTimeout(timer);
    }
    this.timers.clear();
  }
}

// ── Supabase Realtime Service ───────────────────────────────────────

@Injectable()
export class SupabaseRealtimeService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(SupabaseRealtimeService.name);
  private supabase: SupabaseClient | null = null;
  private channels: Map<string, RealtimeChannel> = new Map();
  private debounceMap: DebounceMap;
  private isInitialized = false;

  constructor(private configService: ConfigService) {
    this.debounceMap = new DebounceMap(500);
  }

  // ── Lifecycle ──────────────────────────────────────────────────────

  async onModuleInit() {
    const supabaseUrl = this.configService.get<string>('SUPABASE_URL');
    const serviceRoleKey = this.configService.get<string>(
      'SUPABASE_SERVICE_ROLE_KEY',
    );

    if (!supabaseUrl || !serviceRoleKey) {
      this.logger.warn(
        'SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY not set — Supabase Realtime is disabled. ' +
          'Real-time updates will fall back to Socket.IO.',
      );
      return;
    }

    try {
      this.supabase = createClient(supabaseUrl, serviceRoleKey, {
        realtime: {
          params: {
            eventsPerSecond: 10,
          },
        },
      });

      this.isInitialized = true;
      this.logger.log('✅ Supabase Realtime client initialized');

      // Subscribe to Postgres Changes for server-side event processing
      this.subscribeToPostgresChanges();
    } catch (error) {
      this.logger.error(
        `Failed to initialize Supabase Realtime: ${error instanceof Error ? error.message : 'Unknown error'}`,
      );
    }
  }

  async onModuleDestroy() {
    this.debounceMap.clear();

    for (const [name, channel] of this.channels.entries()) {
      try {
        await this.supabase?.removeChannel(channel);
        this.logger.debug(`Removed channel: ${name}`);
      } catch (error) {
        this.logger.warn(
          `Error removing channel ${name}: ${error instanceof Error ? error.message : 'Unknown'}`,
        );
      }
    }
    this.channels.clear();
    this.isInitialized = false;
    this.logger.log('Supabase Realtime service destroyed');
  }

  // ── Postgres Change Subscriptions ──────────────────────────────────

  private subscribeToPostgresChanges() {
    if (!this.supabase) return;

    // Subscribe to Person table changes
    const personChannel = this.supabase
      .channel('server:person-changes')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'Person' },
        (payload) => {
          this.handlePostgresChange('Person', payload);
        },
      )
      .subscribe((status) => {
        this.logger.debug(`Person channel status: ${status}`);
      });

    this.channels.set('server:person-changes', personChannel);

    // Subscribe to Relationship table changes
    const relationshipChannel = this.supabase
      .channel('server:relationship-changes')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'Relationship' },
        (payload) => {
          this.handlePostgresChange('Relationship', payload);
        },
      )
      .subscribe((status) => {
        this.logger.debug(`Relationship channel status: ${status}`);
      });

    this.channels.set('server:relationship-changes', relationshipChannel);

    // Subscribe to FamilyInvite table changes
    const inviteChannel = this.supabase
      .channel('server:invite-changes')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'FamilyInvite' },
        (payload) => {
          this.handlePostgresChange('FamilyInvite', payload);
        },
      )
      .subscribe((status) => {
        this.logger.debug(`Invite channel status: ${status}`);
      });

    this.channels.set('server:invite-changes', inviteChannel);

    // Subscribe to Notification table changes
    const notificationChannel = this.supabase
      .channel('server:notification-changes')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'Notification' },
        (payload) => {
          this.handlePostgresChange('Notification', payload);
        },
      )
      .subscribe((status) => {
        this.logger.debug(`Notification channel status: ${status}`);
      });

    this.channels.set('server:notification-changes', notificationChannel);
  }

  private handlePostgresChange(
    table: string,
    payload: { eventType: string; new: any; old: any },
  ) {
    const { eventType, new: newRecord, old: oldRecord } = payload;
    const record = newRecord || oldRecord;
    const familyId = record?.familyId;
    const userId = record?.userId;

    this.logger.debug(
      `Postgres change: ${table} ${eventType} (familyId: ${familyId}, userId: ${userId})`,
    );

    // Broadcast to the appropriate family channel
    if (familyId && table !== 'Notification') {
      const eventMap: Record<string, string> = {
        INSERT: 'created',
        UPDATE: 'updated',
        DELETE: 'deleted',
      };

      const tableEventMap: Record<string, string> = {
        Person: 'person',
        Relationship: 'relationship',
        FamilyInvite: 'invite',
      };

      const resourceName = tableEventMap[table] || table.toLowerCase();
      const action = eventMap[eventType] || eventType.toLowerCase();

      const event: FamilyUpdateEvent = {
        familyId,
        eventType: `${resourceName}:${action}` as FamilyUpdateEvent['eventType'],
        payload: {
          id: record?.id,
          familyId,
          personId: record?.personId || record?.fromPersonId,
          updatedAt: record?.updatedAt || new Date().toISOString(),
          ...record,
        },
        timestamp: new Date().toISOString(),
      };

      // Debounce graph:updated events to prevent spamming
      if (
        table === 'Person' ||
        table === 'Relationship'
      ) {
        this.debounceMap.debounce(
          `graph:${familyId}`,
          () => {
            this.broadcastFamilyUpdate(familyId, {
              familyId,
              eventType: 'graph:updated',
              payload: { familyId, updatedAt: new Date().toISOString() },
              timestamp: new Date().toISOString(),
            });
          },
        );
      }

      this.broadcastFamilyUpdate(familyId, event);
    }

    // Broadcast to user-specific channel for notifications
    if (userId && table === 'Notification') {
      this.broadcastToUser(userId, {
        eventType: 'notification:new',
        payload: record,
        timestamp: new Date().toISOString(),
      });
    }
  }

  // ── Broadcast Methods ──────────────────────────────────────────────

  /**
   * Broadcast a family graph update.
   * Called when persons or relationships change.
   */
  async broadcastFamilyUpdate(
    familyId: string,
    event: FamilyUpdateEvent,
  ): Promise<void> {
    if (!this.supabase || !this.isInitialized) {
      this.logger.debug(
        `Supabase not initialized — skipping broadcast for family:${familyId}`,
      );
      return;
    }

    try {
      const channelName = `family:${familyId}`;

      let channel = this.channels.get(channelName);
      if (!channel) {
        channel = this.supabase.channel(channelName);
        this.channels.set(channelName, channel);
      }

      await channel.send({
        type: 'broadcast',
        event: event.eventType,
        payload: event,
      });

      this.logger.debug(
        `Broadcast to ${channelName}: ${event.eventType}`,
      );
    } catch (error) {
      this.logger.error(
        `Failed to broadcast family update: ${error instanceof Error ? error.message : 'Unknown'}`,
      );
    }
  }

  /**
   * Broadcast a member update.
   */
  async broadcastMemberUpdate(
    familyId: string,
    personId: string,
    updateType: 'created' | 'updated' | 'deleted',
  ): Promise<void> {
    const event: FamilyUpdateEvent = {
      familyId,
      eventType: `person:${updateType}`,
      payload: {
        id: personId,
        familyId,
        personId,
        updatedAt: new Date().toISOString(),
      },
      timestamp: new Date().toISOString(),
    };

    await this.broadcastFamilyUpdate(familyId, event);

    // Also trigger a debounced graph:updated event
    this.debounceMap.debounce(
      `graph:${familyId}`,
      () => {
        this.broadcastFamilyUpdate(familyId, {
          familyId,
          eventType: 'graph:updated',
          payload: { familyId, updatedAt: new Date().toISOString() },
          timestamp: new Date().toISOString(),
        });
      },
    );
  }

  /**
   * Broadcast an invitation update.
   */
  async broadcastInvitationUpdate(
    userId: string,
    invitation: any,
  ): Promise<void> {
    if (!this.supabase || !this.isInitialized) {
      this.logger.debug(
        `Supabase not initialized — skipping invitation broadcast for user:${userId}`,
      );
      return;
    }

    try {
      await this.broadcastToUser(userId, {
        eventType: 'invite:updated',
        payload: invitation,
        timestamp: new Date().toISOString(),
      });
    } catch (error) {
      this.logger.error(
        `Failed to broadcast invitation update: ${error instanceof Error ? error.message : 'Unknown'}`,
      );
    }
  }

  /**
   * Broadcast presence (online/offline).
   */
  async updatePresence(
    userId: string,
    familyId: string,
    status: 'online' | 'offline',
  ): Promise<void> {
    if (!this.supabase || !this.isInitialized) {
      return;
    }

    try {
      const channelName = `family:${familyId}`;
      let channel = this.channels.get(channelName);

      if (!channel) {
        channel = this.supabase.channel(channelName, {
          config: {
            presence: {
              key: userId,
            },
          },
        });
        this.channels.set(channelName, channel);
        await channel.subscribe();
      }

      if (status === 'online') {
        await channel.track({
          userId,
          familyId,
          status: 'online',
          lastSeen: new Date().toISOString(),
        } as PresenceState);
      } else {
        await channel.untrack();
      }

      this.logger.debug(
        `Presence updated: ${userId} → ${status} in family:${familyId}`,
      );
    } catch (error) {
      this.logger.error(
        `Failed to update presence: ${error instanceof Error ? error.message : 'Unknown'}`,
      );
    }
  }

  // ── User-Specific Broadcast ────────────────────────────────────────

  private async broadcastToUser(
    userId: string,
    event: { eventType: string; payload: any; timestamp: string },
  ): Promise<void> {
    if (!this.supabase) return;

    try {
      const channelName = `user:${userId}`;
      let channel = this.channels.get(channelName);

      if (!channel) {
        channel = this.supabase.channel(channelName);
        this.channels.set(channelName, channel);
      }

      await channel.send({
        type: 'broadcast',
        event: event.eventType,
        payload: event,
      });
    } catch (error) {
      this.logger.error(
        `Failed to broadcast to user:${userId}: ${error instanceof Error ? error.message : 'Unknown'}`,
      );
    }
  }

  // ── Presence Helpers ───────────────────────────────────────────────

  /**
   * Get online users in a family.
   */
  async getOnlineMembers(
    familyId: string,
  ): Promise<PresenceState[]> {
    if (!this.supabase || !this.isInitialized) {
      return [];
    }

    try {
      const channelName = `family:${familyId}`;
      const channel = this.channels.get(channelName);

      if (!channel) {
        return [];
      }

      const state = channel.presenceState();
      const users: PresenceState[] = [];

      for (const [, presences] of Object.entries(state)) {
        for (const presence of presences) {
          users.push(presence as unknown as PresenceState);
        }
      }

      return users;
    } catch (error) {
      this.logger.error(
        `Failed to get online members: ${error instanceof Error ? error.message : 'Unknown'}`,
      );
      return [];
    }
  }

  // ── Health Check ───────────────────────────────────────────────────

  isAvailable(): boolean {
    return this.isInitialized && this.supabase !== null;
  }
}
