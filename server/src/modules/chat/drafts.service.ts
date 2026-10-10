// server/src/modules/chat/drafts.service.ts
//
// DAXELO KINREL — Tier 1 Feature 1.3: Auto-saved Drafts — Service
//
// Persists per-chat drafts so the user can resume typing after leaving
// the chat. Backed by the ChatDraft table; the Flutter client
// debounce-writes via this service 800ms after the last keystroke.
//
// Multi-device sync: the ChatDraft table is in the supabase_realtime
// publication, so the user's other devices see the draft update live
// via Supabase Realtime (not Socket.IO). The NestJS service here is
// the HTTP write path; reads also go through here for clients that
// prefer HTTP over Realtime.
//
// A draft targets EITHER a family group (familyId set, receiverId null)
// OR a DM (receiverId set, familyId null). One row per
// (userId, familyId-or-receiverId). Empty text clears the draft
// (matches WhatsApp — sending a message clears the draft).

import {
  Injectable,
  BadRequestException,
  ForbiddenException,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class DraftsService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Upsert a draft for the caller. Pass either familyId (group) or
   * receiverId (DM). Pass empty draftText to CLEAR (delete the row).
   * Returns { action: 'created'|'updated'|'cleared', draftId? }.
   */
  async saveDraft(
    userId: string,
    params: {
      familyId?: string | null;
      receiverId?: string | null;
      draftText: string;
      replyToId?: string | null;
    },
  ) {
    const familyId = params.familyId ?? null;
    const receiverId = params.receiverId ?? null;

    // Validate: exactly one of family / receiver must be set.
    if ((familyId == null) === (receiverId == null)) {
      throw new BadRequestException(
        'Pass exactly one of familyId (group) or receiverId (DM).',
      );
    }

    const trimmed = (params.draftText ?? '').trim();

    // ── Empty draft = delete ────────────────────────────────────
    // Matches WhatsApp behavior: send clears the draft.
    if (trimmed === '') {
      await this.prisma.chatDraft.deleteMany({
        where: {
          userId,
          familyId,
          receiverId,
        },
      });
      return { action: 'cleared' as const };
    }

    // ── Authorization for family drafts ────────────────────────
    // Don't write a draft for a family the user isn't a member of.
    if (familyId) {
      const membership = await this.prisma.familyMember.findUnique({
        where: { familyId_userId: { familyId, userId } },
      });
      if (!membership) {
        throw new ForbiddenException('Not a member of this family');
      }
    }

    // ── Upsert ──────────────────────────────────────────────────
    // We can't use the Prisma upsert helper directly because the
    // @@unique is on (userId, familyId, receiverId) and Prisma can't
    // upsert on a nullable composite unique. We do findFirst + create
    // or update instead.
    const existing = await this.prisma.chatDraft.findFirst({
      where: {
        userId,
        familyId,
        receiverId,
      },
    });

    if (existing) {
      const updated = await this.prisma.chatDraft.update({
        where: { id: existing.id },
        data: {
          draftText: params.draftText,
          replyToId: params.replyToId ?? null,
          updatedAt: new Date(),
        },
      });
      return { action: 'updated' as const, draftId: updated.id };
    }

    const id = `cd_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
    const created = await this.prisma.chatDraft.create({
      data: {
        id,
        userId,
        familyId,
        receiverId,
        draftText: params.draftText,
        replyToId: params.replyToId ?? null,
      },
    });
    return { action: 'created' as const, draftId: created.id };
  }

  /**
   * Load the caller's draft for a specific chat. Returns
   * { hasDraft, draftText, replyToId, updatedAt } — hasDraft=false
   * when no row exists.
   */
  async getDraft(
    userId: string,
    params: { familyId?: string | null; receiverId?: string | null },
  ) {
    const familyId = params.familyId ?? null;
    const receiverId = params.receiverId ?? null;
    if ((familyId == null) === (receiverId == null)) {
      throw new BadRequestException(
        'Pass exactly one of familyId (group) or receiverId (DM).',
      );
    }

    const row = await this.prisma.chatDraft.findFirst({
      where: { userId, familyId, receiverId },
    });
    if (!row) {
      return { hasDraft: false, draftText: null, replyToId: null };
    }
    return {
      hasDraft: true,
      draftText: row.draftText,
      replyToId: row.replyToId,
      updatedAt: row.updatedAt,
    };
  }

  /**
   * List all drafts for the caller. Used by the Flutter client on app
   * startup to hydrate the local draft cache.
   */
  async listDrafts(userId: string) {
    return this.prisma.chatDraft.findMany({
      where: { userId },
      orderBy: { updatedAt: 'desc' },
    });
  }
}
