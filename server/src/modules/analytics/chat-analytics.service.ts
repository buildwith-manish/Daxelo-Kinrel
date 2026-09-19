import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

/**
 * ChatAnalyticsService — fire-and-forget event tracking for chat engagement.
 *
 * Writes rows to the Event table without blocking the caller. Every method
 * returns immediately (the Prisma create is awaited but errors are caught +
 * logged, never thrown). This is critical: analytics must NEVER break the
 * chat flow.
 *
 * Tracked events:
 *   message_sent         — a chat message was persisted
 *   streak_continued     — streak incremented (different calendar day, within 24h)
 *   streak_broken        — streak reset to 1 (gap > 24h)
 *   reaction_added       — a user added an emoji reaction
 *   voice_note_sent      — a voice note was uploaded + sent
 *   search_used          — a user ran a chat search query
 *   first_message_in_chat — the first-ever message in a chat (drives onboarding)
 *   notification_tapped   — a user tapped a push notification (deep-link open)
 *   message_read          — a user marked a message as read
 *   mention_sent          — a message with @mentions was sent
 *
 * Query: GET /api/admin/analytics/events?eventName=X&from=Y&to=Z
 */
@Injectable()
export class ChatAnalyticsService {
  private readonly logger = new Logger(ChatAnalyticsService.name);

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Track an analytics event. Fire-and-forget — errors are logged but
   * never thrown. Returns a Promise that resolves to true on success,
   * false on failure (so callers can await if they want, but don't have to).
   *
   * [eventName] — one of the constants above.
   * [userId] — the user who triggered the event.
   * [chatId] — the familyId/chatId the event occurred in (nullable for
   *   global events like notification_tapped when the chatId isn't known).
   * [metadata] — arbitrary JSON (messageId, emoji, query, etc.).
   */
  async track(
    eventName: string,
    userId: string,
    metadata: Record<string, unknown> = {},
    chatId?: string | null,
  ): Promise<boolean> {
    try {
      await this.prisma.event.create({
        data: {
          eventName,
          userId,
          chatId: chatId ?? null,
          metadata: metadata as any,
        },
      });
      return true;
    } catch (err: any) {
      // Analytics failure must NEVER break the caller. Log + swallow.
      this.logger.debug(
        `Analytics track failed for '${eventName}' by ${userId}: ${err?.message}`,
      );
      return false;
    }
  }

  /**
   * Convenience: track a message send. Includes the messageId + messageType
   * in metadata so we can join back to the message for funnel analysis.
   */
  trackMessageSent(
    userId: string,
    chatId: string,
    messageId: string,
    metadata: Record<string, unknown> = {},
  ): Promise<boolean> {
    return this.track(
      'message_sent',
      userId,
      { messageId, ...metadata },
      chatId,
    );
  }

  /**
   * Convenience: track a reaction add.
   */
  trackReactionAdded(
    userId: string,
    chatId: string,
    messageId: string,
    emoji: string,
  ): Promise<boolean> {
    return this.track(
      'reaction_added',
      userId,
      { messageId, emoji },
      chatId,
    );
  }

  /**
   * Convenience: track a voice note send.
   */
  trackVoiceNoteSent(
    userId: string,
    chatId: string,
    messageId: string,
    durationSeconds: number,
  ): Promise<boolean> {
    return this.track(
      'voice_note_sent',
      userId,
      { messageId, durationSeconds },
      chatId,
    );
  }

  /**
   * Convenience: track a search query.
   */
  trackSearchUsed(
    userId: string,
    chatId: string,
    query: string,
    resultCount: number,
  ): Promise<boolean> {
    return this.track(
      'search_used',
      userId,
      { query, resultCount },
      chatId,
    );
  }

  /**
   * Convenience: track the first-ever message in a chat. Drives the
   * chat onboarding flow (Feature 7) — the Flutter app watches this
   * event to trigger the tooltip sequence.
   */
  trackFirstMessageInChat(
    userId: string,
    chatId: string,
    messageId: string,
  ): Promise<boolean> {
    return this.track(
      'first_message_in_chat',
      userId,
      { messageId },
      chatId,
    );
  }

  /**
   * Convenience: track a notification tap (deep-link open).
   */
  trackNotificationTapped(
    userId: string,
    chatId: string | null,
    notificationType: string,
  ): Promise<boolean> {
    return this.track(
      'notification_tapped',
      userId,
      { notificationType },
      chatId,
    );
  }

  /**
   * Convenience: track streak continued (incremented) or broken (reset).
   * Called by the StreakService.
   */
  trackStreakEvent(
    chatId: string,
    currentStreak: number,
    event: 'continued' | 'broken',
  ): Promise<boolean> {
    // For streak events, we don't have a specific userId — use the chatId
    // as a placeholder. The metadata has the streak count.
    return this.track(
      event === 'continued' ? 'streak_continued' : 'streak_broken',
      chatId, // userId field (used as chatId here for aggregate queries)
      { chatId, currentStreak },
      chatId,
    );
  }

  // ── Query methods (admin-only, exposed via AdminModule) ──────────────

  /**
   * Get aggregate counts per event per day, optionally filtered by
   * eventName + date range. Used by the admin analytics endpoint.
   *
   * Returns rows like:
   *   { date: '2026-09-19', eventName: 'message_sent', count: 42 }
   */
  async getDailyCounts(params: {
    eventName?: string;
    from?: Date;
    to?: Date;
  }): Promise<Array<{ date: string; eventName: string; count: bigint }>> {
    const where: Record<string, unknown> = {};
    if (params.eventName) where.eventName = params.eventName;
    if (params.from || params.to) {
      where.createdAt = {};
      if (params.from) (where.createdAt as any).gte = params.from;
      if (params.to) (where.createdAt as any).lt = params.to;
    }

    // Group by date (truncated to day) + eventName.
    // Prisma doesn't support date_trunc in groupBy, so we use a raw query.
    const events = await this.prisma.event.findMany({
      where,
      select: { eventName: true, createdAt: true },
    });

    // Aggregate in JS (fine for typical analytics volumes < 100k events).
    const counts = new Map<string, bigint>();
    for (const e of events) {
      const date = e.createdAt.toISOString().slice(0, 10); // YYYY-MM-DD
      const key = `${date}|${e.eventName}`;
      counts.set(key, (counts.get(key) ?? BigInt(0)) + BigInt(1));
    }

    return Array.from(counts.entries())
      .map(([key, count]) => {
        const [date, eventName] = key.split('|');
        return { date, eventName, count };
      })
      .sort((a, b) => {
        if (a.date !== b.date) return a.date.localeCompare(b.date);
        return a.eventName.localeCompare(b.eventName);
      });
  }

  /**
   * Get the total count of a specific event, optionally filtered by
   * userId (for the onboarding flow's "has the user sent their first
   * message?" check).
   */
  async getEventCount(
    eventName: string,
    userId?: string,
  ): Promise<number> {
    const where: Record<string, unknown> = { eventName };
    if (userId) where.userId = userId;
    return this.prisma.event.count({ where });
  }
}
