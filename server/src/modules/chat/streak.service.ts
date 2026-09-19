import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

/**
 * StreakService — tracks consecutive-day messaging streaks per family chat.
 *
 * A streak increments when a message is sent within 24 hours of the
 * previous one. If the gap exceeds 24 hours, the streak resets to 1.
 *
 * "Within 24 hours" uses a rolling window — not calendar days. So if you
 * message at 10:00 Monday and again at 09:00 Tuesday (23 hours later),
 * that's still the same streak. If you message at 10:00 Monday and again
 * at 11:00 Tuesday (25 hours later), the streak resets.
 *
 * The streak is updated synchronously in the message-send flow so the
 * new count is available immediately for the response payload + the
 * `chat:streakUpdated` Socket.IO broadcast.
 *
 * NOTE: the 24-hour window is configurable via the `STREAK_WINDOW_HOURS`
 * env var (defaults to 24). Some products use a calendar-day model
 * instead ("message at least once per day"); we use the rolling window
 * because it's fairer to users in different timezones.
 */
@Injectable()
export class StreakService {
  private readonly logger = new Logger(StreakService.name);

  /// Rolling window in hours. If the gap between consecutive messages
  /// exceeds this, the streak resets. Default 24h.
  private readonly windowHours = Number(process.env.STREAK_WINDOW_HOURS ?? 24);

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Record a message-send event for a chat and return the updated streak.
   *
   * Logic:
   *   • No existing streak row → create one with currentStreak=1, longestStreak=1
   *   • Existing streak, lastMessageAt within window → increment currentStreak,
   *     bump longestStreak if the new current exceeds it
   *   • Existing streak, lastMessageAt outside window → reset currentStreak=1
   *     (longestStreak is preserved)
   *
   * The update is atomic via a Prisma upsert + conditional update. We use
   * a transaction to avoid a race where two concurrent messages both read
   * the old streak and double-increment.
   */
  async recordMessage(chatId: string): Promise<{
    chatId: string;
    currentStreak: number;
    longestStreak: number;
    lastMessageAt: Date;
    streakJustIncreased: boolean;
    streakReset: boolean;
  }> {
    const now = new Date();
    const windowMs = this.windowHours * 60 * 60 * 1000;
    const id = `cs_${chatId}`;

    return this.prisma.$transaction(async (tx) => {
      // Try to create the streak row. If it already exists (unique on chatId),
      // the create is a no-op and we read the existing row.
      try {
        await tx.chatStreak.create({
          data: {
            id,
            chatId,
            currentStreak: 1,
            longestStreak: 1,
            lastMessageAt: now,
          },
        });
        this.logger.debug(`Streak created for chat ${chatId} (first message)`);
        return {
          chatId,
          currentStreak: 1,
          longestStreak: 1,
          lastMessageAt: now,
          streakJustIncreased: false,
          streakReset: false,
        };
      } catch (err: any) {
        // P2002 = unique constraint violation → row already exists.
        // Any other error rethrows.
        if (err?.code !== 'P2002') throw err;
      }

      // Row exists — read it and decide increment vs reset.
      const existing = await tx.chatStreak.findUnique({
        where: { chatId },
      });
      if (!existing) {
        // Shouldn't happen (we just got P2002), but guard against races.
        this.logger.warn(`Streak row vanished for chat ${chatId} between upsert + read`);
        return {
          chatId,
          currentStreak: 1,
          longestStreak: 1,
          lastMessageAt: now,
          streakJustIncreased: false,
          streakReset: false,
        };
      }

      const gapMs = now.getTime() - existing.lastMessageAt.getTime();
      const withinWindow = gapMs <= windowMs;

      let newCurrent: number;
      let streakReset = false;
      let streakJustIncreased = false;

      if (withinWindow) {
        // Increment — but only if the last message was from a DIFFERENT
        // day (calendar-wise) to avoid double-counting rapid-fire messages
        // within the same minute. Two messages sent at 10:00:01 and 10:00:02
        // should count as one "day" of streak, not two.
        const sameCalendarDay =
          existing.lastMessageAt.getUTCFullYear() === now.getUTCFullYear() &&
          existing.lastMessageAt.getUTCMonth() === now.getUTCMonth() &&
          existing.lastMessageAt.getUTCDate() === now.getUTCDate();

        if (sameCalendarDay) {
          // Same calendar day — keep the streak, just update lastMessageAt.
          newCurrent = existing.currentStreak;
          streakJustIncreased = false;
        } else {
          // Different calendar day, still within the rolling window → increment.
          newCurrent = existing.currentStreak + 1;
          streakJustIncreased = true;
        }
      } else {
        // Outside the window → reset to 1.
        newCurrent = 1;
        streakReset = true;
      }

      const newLongest = Math.max(existing.longestStreak, newCurrent);

      await tx.chatStreak.update({
        where: { chatId },
        data: {
          currentStreak: newCurrent,
          longestStreak: newLongest,
          lastMessageAt: now,
          updatedAt: now,
        },
      });

      if (streakJustIncreased) {
        this.logger.log(
          `Streak for chat ${chatId} increased to ${newCurrent} (longest: ${newLongest})`,
        );
      } else if (streakReset) {
        this.logger.log(
          `Streak for chat ${chatId} reset to 1 (was ${existing.currentStreak}, gap ${Math.round(gapMs / 3600000)}h)`,
        );
      }

      return {
        chatId,
        currentStreak: newCurrent,
        longestStreak: newLongest,
        lastMessageAt: now,
        streakJustIncreased,
        streakReset,
      };
    });
  }

  /**
   * Get the current streak for a chat without modifying it. Returns null
   * if no streak row exists yet (chat has never received a message).
   */
  async getStreak(chatId: string) {
    return this.prisma.chatStreak.findUnique({
      where: { chatId },
    });
  }
}
