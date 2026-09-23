// server/src/modules/predictions/predictions.scheduler.ts
//
// Prediction Battle v1 — push notification scheduler.
//
// The backend pg_cron jobs (defined in migration
// `20260922160000_prediction_battle_v1_scheduled.sql`) handle:
//   - daily round creation at 8 AM IST
//   - reveal transition at 9 PM IST
//
// This NestJS scheduler is a thin **notification layer** that runs every
// 15 minutes and emits FCM + in-app `Notification` rows for the two
// lifecycle events that we want the user to actually hear about:
//
//   1. `prediction_v1_round_open`
//      Fires once per family per round, within ~15 minutes of the
//      round's `opens_at`. Title: "A new prediction is live". Action
//      URL deep-links the family hub.
//
//   2. `prediction_v1_reveal_done`
//      Fires once per family per round, within ~15 minutes of the
//      round transitioning to `revealed`. Title: "Prediction results
//      are in" (or "You won the Prediction Battle! 🎯" for winners).
//      Action URL deep-links the v1 reveal screen.
//
// Idempotency
// -----------
// We reuse the existing `Notification.personId` slot to store the
// round id. We check for existence of a notification with the same
// (userId, eventType, personId=roundId) before inserting. This gives
// us exactly-once delivery per (user, round, event) — which is what
// makes the backfill safe to run: it simply re-scans old rounds and
// silently skips the ones that already have notifications.
//
// Failure modes
// -------------
//   - Supabase env not configured: scheduler logs a warning on startup
//     and skips processing. The pg_cron jobs still run, so rounds
//     still get created and revealed — we just don't push.
//   - A single user's FCM send failure: logged and skipped; in-app
//     `Notification` row is still created so they see the bell badge.
//   - Whole-run failure: caught, logged, retried next tick.
//   - Server down for >15 min: missed events are picked up by the
//     `backfill()` method, which runs once on startup (via OnModuleInit)
//     and scans the last BACKFILL_LOOKBACK_HOURS (default 24h) for
//     rounds whose notifications were never sent.

import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { ConfigService } from '@nestjs/config';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { PrismaService } from '../../prisma/prisma.service';
import { FcmService } from '../notifications/fcm.service';
import { NotificationsService } from '../notifications/notifications.service';

// IST timezone — same as the rest of the notifications module.
const IST_TZ = 'Asia/Kolkata';

// Window: process rounds whose lifecycle event happened in the last
// 15 minutes. The cron also runs every 15 minutes, so this is a
// sliding window that covers exactly one tick of the scheduler.
const LOOKBACK_MS = 15 * 60 * 1000;

// Backfill window: on startup (or when triggered manually), scan
// rounds whose lifecycle event happened in the last N hours. 24h
// covers one full daily-tick + reveal-tick cycle; if the server has
// been down longer than that, we miss notifications for older
// rounds — but those rounds are already archived server-side, and
// sending a "round opened!" push for a round that's already revealed
// would be more confusing than helpful. 24h is the sweet spot.
const BACKFILL_LOOKBACK_HOURS = 24;

// Per-user-event cap — used as a safety net in case the idempotency
// check has a race. Should never be hit in practice.
const PER_USER_EVENT_CAP = 1;

interface PbV1Round {
  id: string;
  family_id: string;
  question_id: string;
  opens_at: string;
  reveal_at: string;
  status: 'open' | 'revealed';
  created_at: string;
}

interface PbV1Question {
  id: string;
  question_text: string;
  correct_answer: number;
  unit_label: string;
  category: string;
}

interface PbV1Guess {
  round_id: string;
  user_id: string;
  guess_value: number;
}

@Injectable()
export class PredictionsScheduler implements OnModuleInit {
  private readonly logger = new Logger(PredictionsScheduler.name);
  private supabase: SupabaseClient | null = null;

  constructor(
    private readonly configService: ConfigService,
    private readonly prisma: PrismaService,
    private readonly fcmService: FcmService,
    private readonly notificationsService: NotificationsService,
  ) {
    this.initSupabase();
  }

  /**
   * OnModuleInit — runs once after NestJS finishes wiring the module
   * graph. We use this hook to run the backfill pass: scan the last
   * BACKFILL_LOOKBACK_HOURS for rounds whose notifications were never
   * sent (because the server was down during the regular 15-min tick).
   *
   * The backfill is safe to run on every restart because `sendOnce`
   * is idempotent — it checks for an existing Notification row with
   * the same (userId, eventType, roundId) triple before inserting.
   *
   * We intentionally do NOT await this in onModuleInit — the backfill
   * is fire-and-forget. NestJS will proceed with booting the rest of
   * the app while the backfill runs in the background. A long backfill
   * (e.g., 1000 families × 50 notifications) should take <30s in
   * practice; running it asynchronously avoids blocking app startup.
   */
  async onModuleInit() {
    if (!this.supabase) return;
    // Fire-and-forget — don't block app startup.
    this.backfill().catch((err: any) => {
      this.logger.error(`Backfill on startup failed: ${err?.message}`);
    });
  }

  /**
   * Backfill pass: scan the last `hours` (default 24h) for rounds whose
   * notifications were never sent, and dispatch them. Safe to call
   * multiple times — `sendOnce` is idempotent.
   *
   * Public so it can be triggered manually by an admin endpoint or a
   * CLI script. The startup hook calls this once with the default
   * window.
   */
  async backfill(hours: number = BACKFILL_LOOKBACK_HOURS): Promise<void> {
    if (!this.supabase) return;
    const since = new Date(Date.now() - hours * 60 * 60 * 1000).toISOString();
    this.logger.log(`[prediction_v1] backfill scan: rounds since ${since}`);

    try {
      let openedCount = 0;
      let revealedCount = 0;

      // ── Open rounds ────────────────────────────────────────────────
      // We look at rounds in status='open' OR 'revealed' (a round may
      // have transitioned to revealed during the downtime) whose
      // opens_at is within the backfill window. For each, we attempt
      // to dispatch the round-open notification — `sendOnce` will
      // silently skip if a notification already exists.
      const { data: openedRows, error: openedErr } = await this.supabase
        .from('pb_v1_rounds')
        .select('id, family_id, question_id, opens_at, reveal_at, status, created_at')
        .gte('opens_at', since)
        .order('opens_at', { ascending: true });

      if (openedErr) {
        this.logger.warn(`backfill open query failed: ${openedErr.message}`);
      } else if (openedRows && openedRows.length > 0) {
        for (const row of openedRows as PbV1Round[]) {
          try {
            await this.dispatchRoundOpened(row);
            openedCount++;
          } catch (err: any) {
            this.logger.error(`backfill dispatchRoundOpened failed for ${row.id}: ${err?.message}`);
          }
        }
      }

      // ── Revealed rounds ───────────────────────────────────────────
      const { data: revealedRows, error: revealedErr } = await this.supabase
        .from('pb_v1_rounds')
        .select('id, family_id, question_id, opens_at, reveal_at, status, created_at')
        .eq('status', 'revealed')
        .gte('reveal_at', since)
        .order('reveal_at', { ascending: true });

      if (revealedErr) {
        this.logger.warn(`backfill reveal query failed: ${revealedErr.message}`);
      } else if (revealedRows && revealedRows.length > 0) {
        for (const row of revealedRows as PbV1Round[]) {
          try {
            await this.dispatchRoundRevealed(row);
            revealedCount++;
          } catch (err: any) {
            this.logger.error(`backfill dispatchRoundRevealed failed for ${row.id}: ${err?.message}`);
          }
        }
      }

      this.logger.log(
        `[prediction_v1] backfill complete: scanned ${openedCount} open + ${revealedCount} revealed rounds`,
      );
    } catch (err: any) {
      this.logger.error(`Backfill failed: ${err?.message}`);
    }
  }

  private initSupabase() {
    const url = this.configService.get<string>('SUPABASE_URL');
    const serviceKey = this.configService.get<string>('SUPABASE_SERVICE_ROLE_KEY');
    if (!url || !serviceKey) {
      this.logger.warn(
        'SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY not set — prediction notifications disabled.',
      );
      return;
    }
    this.supabase = createClient(url, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    this.logger.log('Supabase service-role client initialized for prediction scheduler');
  }

  /**
   * Runs every 15 minutes. Picks up:
   *   - rounds opened in the last 15 min (status='open', opens_at within window)
   *   - rounds revealed in the last 15 min (status='revealed', reveal_at within window)
   * and dispatches push + in-app notifications to each family member.
   */
  @Cron('*/15 * * * *', {
    name: 'prediction-v1-notifications',
    timeZone: IST_TZ,
  })
  async handlePredictionNotifications() {
    if (!this.supabase) {
      return; // not configured
    }
    try {
      await this.handleRoundOpened();
      await this.handleRoundRevealed();
    } catch (err: any) {
      this.logger.error(`Prediction scheduler tick failed: ${err?.message}`);
    }
  }

  // ── Round opened ───────────────────────────────────────────────────

  private async handleRoundOpened() {
    const since = new Date(Date.now() - LOOKBACK_MS).toISOString();
    const { data, error } = await this.supabase!
      .from('pb_v1_rounds')
      .select('id, family_id, question_id, opens_at, reveal_at, status, created_at')
      .eq('status', 'open')
      .gte('opens_at', since);

    if (error) {
      this.logger.warn(`handleRoundOpened query failed: ${error.message}`);
      return;
    }
    if (!data || data.length === 0) return;

    this.logger.log(`[prediction_v1] ${data.length} round(s) opened in last 15 min`);

    for (const row of data as PbV1Round[]) {
      try {
        await this.dispatchRoundOpened(row);
      } catch (err: any) {
        this.logger.error(`dispatchRoundOpened failed for round ${row.id}: ${err?.message}`);
      }
    }
  }

  private async dispatchRoundOpened(round: PbV1Round) {
    // Get the question for the notification body
    const { data: qRow } = await this.supabase!
      .from('pb_v1_questions')
      .select('id, question_text, unit_label, category')
      .eq('id', round.question_id)
      .single();
    const question = (qRow as unknown as PbV1Question) || null;

    const familyMembers = await this.getFamilyMemberUserIds(round.family_id);
    if (familyMembers.length === 0) return;

    const title = 'A new prediction is live';
    const body = question
      ? `${truncate(question.question_text, 90)} — guess before 9 PM IST`
      : 'Today’s Prediction Battle is open — guess before 9 PM IST';
    const actionUrl = `/family/${round.family_id}`;

    for (const userId of familyMembers) {
      await this.sendOnce({
        userId,
        eventType: 'prediction_v1_round_open',
        roundId: round.id,
        title,
        body,
        familyId: round.family_id,
        actionUrl,
      });
    }
  }

  // ── Round revealed ─────────────────────────────────────────────────

  private async handleRoundRevealed() {
    const since = new Date(Date.now() - LOOKBACK_MS).toISOString();
    const { data, error } = await this.supabase!
      .from('pb_v1_rounds')
      .select('id, family_id, question_id, opens_at, reveal_at, status, created_at')
      .eq('status', 'revealed')
      .gte('reveal_at', since);

    if (error) {
      this.logger.warn(`handleRoundRevealed query failed: ${error.message}`);
      return;
    }
    if (!data || data.length === 0) return;

    this.logger.log(`[prediction_v1] ${data.length} round(s) revealed in last 15 min`);

    for (const row of data as PbV1Round[]) {
      try {
        await this.dispatchRoundRevealed(row);
      } catch (err: any) {
        this.logger.error(`dispatchRoundRevealed failed for round ${row.id}: ${err?.message}`);
      }
    }
  }

  private async dispatchRoundRevealed(round: PbV1Round) {
    // Fetch question + all guesses
    const { data: qRow } = await this.supabase!
      .from('pb_v1_questions')
      .select('id, question_text, correct_answer, unit_label, category')
      .eq('id', round.question_id)
      .single();
    const question = (qRow as unknown as PbV1Question) | null;

    const { data: guessRows } = await this.supabase!
      .from('pb_v1_guesses')
      .select('round_id, user_id, guess_value')
      .eq('round_id', round.id);
    const guesses = (guessRows as unknown as PbV1Guess[]) || [];

    // Compute winner set (mirrors the SQL in fn_pb_v1_reveal_all_due)
    let winnerIds: string[] = [];
    if (question && guesses.length > 0) {
      let minDistance = Infinity;
      const distById = new Map<string, number>();
      for (const g of guesses) {
        const d = computeDistance(g.guess_value, question.correct_answer);
        distById.set(g.user_id, d);
        if (d < minDistance) minDistance = d;
      }
      winnerIds = [...distById.entries()]
        .filter(([, d]) => d === minDistance)
        .map(([uid]) => uid);
    }

    const familyMembers = await this.getFamilyMemberUserIds(round.family_id);
    if (familyMembers.length === 0) return;

    const actionUrl = `/family/${round.family_id}/prediction-battle-v1/reveal/${round.id}`;

    for (const userId of familyMembers) {
      const isWinner = winnerIds.includes(userId);
      const participated = guesses.some((g) => g.user_id === userId);
      const title = isWinner
        ? 'You won the Prediction Battle!'
        : 'Prediction results are in';
      const body = isWinner
        ? `Closest guess on “${truncate(question?.question_text ?? '', 60)}” — see by how much!`
        : participated
          ? `The reveal is ready — see how your guess compared.`
          : `Missed today’s round — come see who got closest.`;

      await this.sendOnce({
        userId,
        eventType: 'prediction_v1_reveal_done',
        roundId: round.id,
        title,
        body,
        familyId: round.family_id,
        actionUrl,
      });
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────

  /**
   * Send both an in-app `Notification` row and an FCM push, but only if
   * no prior notification exists for this (user, event, roundId) triple.
   * Uses `Notification.personId` to store the round id (the column is
   * a free-form string, reused for similar "secondary entity id" slots
   * elsewhere in this codebase — e.g. birthday reminders store the
   * person id there).
   */
  private async sendOnce(args: {
    userId: string;
    eventType: string;
    roundId: string;
    title: string;
    body: string;
    familyId: string;
    actionUrl: string;
  }): Promise<void> {
    try {
      // Idempotency check
      const existing = await this.prisma.notification.findFirst({
        where: {
          userId: args.userId,
          eventType: args.eventType,
          personId: args.roundId,
        },
        select: { id: true },
      });
      if (existing) return; // already sent

      // 1. In-app notification row
      await this.notificationsService.create({
        userId: args.userId,
        eventType: args.eventType,
        title: args.title,
        body: args.body,
        familyId: args.familyId,
        personId: args.roundId,
        priority: 'normal',
        actionUrl: args.actionUrl,
      });

      // 2. FCM push (best-effort)
      await this.fcmService.sendToUser(args.userId, {
        title: args.title,
        body: args.body,
        data: {
          eventType: args.eventType,
          familyId: args.familyId,
          roundId: args.roundId,
          actionUrl: args.actionUrl,
        },
      });

      // Safety cap: ensure we never have > PER_USER_EVENT_CAP rows for
      // this (user, eventType, roundId) triple. Cleanup the extras in
      // case of a race.
      const dupes = await this.prisma.notification.findMany({
        where: {
          userId: args.userId,
          eventType: args.eventType,
          personId: args.roundId,
        },
        orderBy: { createdAt: 'asc' },
        select: { id: true },
      });
      if (dupes.length > PER_USER_EVENT_CAP) {
        const toDelete = dupes.slice(0, dupes.length - PER_USER_EVENT_CAP).map((d) => d.id);
        await this.prisma.notification.deleteMany({ where: { id: { in: toDelete } } });
      }
    } catch (err: any) {
      this.logger.error(
        `sendOnce failed for user ${args.userId} event ${args.eventType} round ${args.roundId}: ${err?.message}`,
      );
    }
  }

  /**
   * Look up the user ids of all members of a family. Uses Prisma
   * (relational DB) — these ids match the Supabase `auth.uid()` values
   * because both systems share the same `User` table.
   */
  private async getFamilyMemberUserIds(familyId: string): Promise<string[]> {
    const members = await this.prisma.familyMember.findMany({
      where: { familyId },
      select: { userId: true },
    });
    return members
      .map((m) => m.userId)
      .filter((id): id is string => typeof id === 'string' && id.length > 0);
  }
}

// ── Pure helpers (exported for unit testing) ─────────────────────────

export function computeDistance(guess: number, correct: number): number {
  if (correct > 1000) {
    return Math.abs(guess - correct) / correct * 100;
  }
  return Math.abs(guess - correct);
}

export function truncate(s: string, max: number): string {
  if (s.length <= max) return s;
  return s.slice(0, Math.max(0, max - 1)).trimEnd() + '…';
}
