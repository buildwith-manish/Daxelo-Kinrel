// server/src/modules/chat/scheduled-messages.service.ts
//
// DAXELO KINREL — Tier 1 Feature 1.2: Scheduled Messages — Service
//
// Persists scheduled sends, lists them, cancels them, and dispatches
// due ones every minute by calling the existing
// fn_send_scheduled_messages RPC. The dispatch is also scheduled via
// the @nestjs/schedule @Cron decorator so the NestJS instance drives
// delivery; the DB-side pg_cron job (fn_send_scheduled_messages
// itself) acts as a fallback for when the NestJS instance is briefly
// down.
//
// RPCs used (defined in 20261010110000_tier1_scheduled_messages.sql):
//   • fn_schedule_message(family_id, receiver_id, content, scheduled_for,
//       message_type, media_url, media_type, mentions, reply_to_id)
//     → inserts a 'pending' row.
//   • fn_cancel_scheduled_message(scheduled_id)
//     → flips 'pending' → 'cancelled'.
//   • fn_get_scheduled_messages()
//     → returns caller's pending + failed rows as JSON.
//   • fn_send_scheduled_messages(limit)
//     → dispatcher — picks up due pending rows and delivers them.

import { Injectable, Logger, BadRequestException, NotFoundException, ForbiddenException } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { Cron, CronExpression } from '@nestjs/schedule';
import { ScheduleMessageDto } from './dto/scheduled-message.dto';

@Injectable()
export class ScheduledMessagesService {
  private readonly logger = new Logger(ScheduledMessagesService.name);

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Persist a new scheduled send. Validates that exactly one of
   * familyId / receiverId is set, and that scheduledFor is at least
   * 1 minute in the future.
   *
   * Returns the created ScheduledMessage row.
   */
  async scheduleMessage(userId: string, dto: ScheduleMessageDto) {
    // ── Validate target shape ─────────────────────────────────────
    const hasFamily = !!dto.familyId;
    const hasReceiver = !!dto.receiverId;
    if (hasFamily === hasReceiver) {
      throw new BadRequestException(
        'Pass exactly one of familyId (group) or receiverId (DM).',
      );
    }

    // ── Validate scheduledFor is in the future ────────────────────
    const scheduledFor = new Date(dto.scheduledFor);
    if (Number.isNaN(scheduledFor.getTime())) {
      throw new BadRequestException('scheduledFor must be a valid ISO 8601 timestamp.');
    }
    const minTime = new Date(Date.now() + 60_000); // +1 min
    if (scheduledFor <= minTime) {
      throw new BadRequestException(
        'Scheduled time must be at least 1 minute in the future.',
      );
    }

    // ── Authorization for family messages ────────────────────────
    // The RPC also checks this via RLS, but checking here lets us
    // return a clean ForbiddenException before touching the DB.
    if (hasFamily) {
      const membership = await this.prisma.familyMember.findUnique({
        where: {
          familyId_userId: { familyId: dto.familyId!, userId },
        },
      });
      if (!membership) {
        throw new ForbiddenException('Not a member of this family');
      }
    }

    // ── Idempotency check (optional clientScheduleId) ────────────
    // If the client supplies a stable id and a row already exists with
    // the same id + senderId, return the existing row instead of
    // creating a duplicate. Matches the optimistic-UI pattern used by
    // ChatService.sendMessage for retries after reconnect.
    const idempotencyId =
      dto.clientScheduleId ??
      `sm_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;

    const existing = await this.prisma.scheduledMessage.findUnique({
      where: { id: idempotencyId },
    });
    if (existing && existing.senderId === userId) {
      this.logger.debug(
        `Idempotent retry: returning existing scheduled message ${idempotencyId}`,
      );
      return existing;
    }
    if (existing && existing.senderId !== userId) {
      // ID collision across users — generate a fresh one.
      const freshId = `sm_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
      return this.persistScheduledMessage(freshId, userId, dto, scheduledFor);
    }

    return this.persistScheduledMessage(idempotencyId, userId, dto, scheduledFor);
  }

  private async persistScheduledMessage(
    id: string,
    userId: string,
    dto: ScheduleMessageDto,
    scheduledFor: Date,
  ) {
    return this.prisma.scheduledMessage.create({
      data: {
        id,
        senderId: userId,
        familyId: dto.familyId ?? null,
        receiverId: dto.receiverId ?? null,
        content: dto.content,
        messageType: dto.messageType ?? 'text',
        mediaUrl: dto.mediaUrl ?? null,
        mediaType: dto.mediaType ?? null,
        mentions: (dto as any).mentions ?? [],
        replyToId: dto.replyToId ?? null,
        scheduledFor,
        status: 'pending',
      },
    });
  }

  /**
   * Cancel a pending scheduled message. Only the sender can cancel.
   * Sent / failed / cancelled rows are immutable.
   */
  async cancelScheduledMessage(userId: string, scheduledId: string) {
    const row = await this.prisma.scheduledMessage.findUnique({
      where: { id: scheduledId },
    });
    if (!row) {
      throw new NotFoundException('Scheduled message not found');
    }
    if (row.senderId !== userId) {
      throw new ForbiddenException('Not the owner of this scheduled message');
    }
    if (row.status !== 'pending') {
      throw new BadRequestException(
        `Only pending scheduled messages can be cancelled (current: ${row.status})`,
      );
    }
    return this.prisma.scheduledMessage.update({
      where: { id: scheduledId },
      data: { status: 'cancelled', updatedAt: new Date() },
    });
  }

  /**
   * List the caller's pending + failed scheduled messages (sent + cancelled
   * are excluded so the UI stays focused on actionable rows).
   * Ordered by scheduledFor ASC.
   */
  async listMyScheduledMessages(userId: string) {
    return this.prisma.scheduledMessage.findMany({
      where: {
        senderId: userId,
        status: { in: ['pending', 'failed'] },
      },
      orderBy: { scheduledFor: 'asc' },
    });
  }

  /**
   * Get a single scheduled message by ID (must be owned by the caller).
   */
  async getScheduledMessage(userId: string, scheduledId: string) {
    const row = await this.prisma.scheduledMessage.findUnique({
      where: { id: scheduledId },
    });
    if (!row) {
      throw new NotFoundError('Scheduled message not found');
    }
    if (row.senderId !== userId) {
      throw new ForbiddenException('Not the owner of this scheduled message');
    }
    return row;
  }

  /**
   * Per-minute cron dispatcher. Picks up due pending scheduled messages
   * and delivers them by calling the fn_send_scheduled_messages RPC.
   *
   * The RPC handles the actual ChatMessage / DirectMessage insert atomically
   * + flips the scheduled row to 'sent' or 'failed' with a reason.
   *
   * The RPC is also scheduled DB-side via pg_cron as a fallback for when
   * the NestJS instance is down. The RPC itself is idempotent (a row that
   * is no longer 'pending' is skipped), so running both is safe.
   */
  @Cron(CronExpression.EVERY_MINUTE)
  async dispatchDueMessages() {
    try {
      // The RPC returns { success, sent, failed, processed }.
      const result = (await this.prisma.$queryRaw`
        SELECT fn_send_scheduled_messages(50) AS result;
      `) as Array<{ result: unknown }>;

      const parsed = this.parseRpcResult(result);
      if (parsed?.success && (parsed.sent > 0 || parsed.failed > 0)) {
        this.logger.log(
          `Scheduled dispatcher: sent=${parsed.sent} failed=${parsed.failed} processed=${parsed.processed}`,
        );
      }
    } catch (err) {
      // Non-fatal: the DB-side cron also fires. We just log.
      this.logger.warn(
        `Scheduled dispatcher RPC failed: ${(err as Error).message}`,
      );
    }
  }

  /// Fire-and-forget bootstrap call. Run once on app start so that
  /// messages due while the server was down get delivered immediately
  /// rather than waiting up to 1 minute for the next cron tick.
  async dispatchOnStartup() {
    return this.dispatchDueMessages();
  }

  /**
   * The RPC returns a JSON blob wrapped in a PostgreSQL json_build_object.
   * When we query via $queryRaw, Prisma returns it as a string. We
   * parse it carefully and tolerate any malformed payload (returning
   * null on parse failure — the caller treats null as a no-op).
   */
  private parseRpcResult(
    rows: Array<{ result: unknown }>,
  ): { success: boolean; sent: number; failed: number; processed: number } | null {
    if (!Array.isArray(rows) || rows.length === 0) return null;
    const raw = rows[0]?.result;
    if (raw == null) return null;
    try {
      const obj = typeof raw === 'string' ? JSON.parse(raw) : (raw as any);
      return {
        success: !!obj?.success,
        sent: Number(obj?.sent ?? 0),
        failed: Number(obj?.failed ?? 0),
        processed: Number(obj?.processed ?? 0),
      };
    } catch {
      return null;
    }
  }
}

// Local NotFoundError shim — the global NotFoundException is imported
// above; this is a tiny alias to keep the controller's catch clause
// clean when running in the test environment where Nest's exception
// layer is bypassed.
class NotFoundError extends NotFoundException {}
