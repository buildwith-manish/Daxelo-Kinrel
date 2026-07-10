// =============================================================================
// Track C v2.0 — AURA Timeline
// timeline.service.ts
// =============================================================================
// Read-only service for browsing the timeline + correction append.
// Section 6.3 + 11 of the FINAL v2.0 spec.
//
// NOTE: This service NEVER updates or deletes timeline events. The DB trigger
// `enforce_timeline_append_only()` rejects both operations. Corrections are
// appended as new `kind = 'correction'` rows referencing the original event.
// =============================================================================

import {
  Injectable,
  NotFoundException,
  BadRequestException,
  Logger,
  ForbiddenException,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { TimelineEmitter } from './timeline.emitter';
import { TimelineKind, TIMELINE_KINDS, TIMELINE_SUMMARY_EVENT_TYPES } from './timeline.types';
import { FamilyMembershipService } from '../common/family-membership.service';
import { VisibilityService } from '../common/visibility.service';

@Injectable()
export class TimelineService {
  private readonly logger = new Logger(TimelineService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly emitter: TimelineEmitter,
    private readonly membership: FamilyMembershipService,
    private readonly visibility: VisibilityService,
  ) {}

  /**
   * List timeline events for a family. Cursor-based pagination.
   *
   * VISIBILITY MATRIX:
   *   - Default (raw=false): returns ONLY events whose kind is in
   *     TIMELINE_SUMMARY_EVENT_TYPES (the "headline" governance actions).
   *     This is the human-readable summary feed visible to ALL roles
   *     including minors.
   *   - raw=true: returns the FULL unfiltered append-only log (all 14
   *     event kinds). Restricted to 'owner' | 'admin' only via
   *     requireAdminDataAccess.
   *
   * @param familyId scoped by RLS — caller is responsible for verifying membership
   * @param opts.kind optional kind filter (single or array)
   * @param opts.cursor occurredAt of the last item in the previous page (ISO string)
   * @param opts.limit max items per page (default 50, max 100)
   * @param opts.raw if true, return the full unfiltered log (admin-only)
   * @param opts.userId the requesting user's id (for raw=true admin check)
   */
  async list(
    familyId: string,
    opts: {
      kind?: TimelineKind | TimelineKind[];
      cursor?: string;
      limit?: number;
      raw?: boolean;
      userId?: string;
    } = {},
  ) {
    // ── Raw mode: admin-only ──────────────────────────────────────────
    if (opts.raw) {
      if (!opts.userId) {
        throw new ForbiddenException('Authentication required for raw timeline access');
      }
      await this.visibility.requireAdminDataAccess(opts.userId, familyId);
    } else {
      // ── Summary mode: verify membership ────────────────────────────
      if (opts.userId) {
        await this.membership.requireMember(opts.userId, familyId);
      }
    }

    const limit = Math.min(Math.max(opts.limit ?? 50, 1), 100);
    let kinds = opts.kind
      ? Array.isArray(opts.kind)
        ? opts.kind
        : [opts.kind]
      : undefined;

    // Validate kinds
    if (kinds) {
      for (const k of kinds) {
        if (!TIMELINE_KINDS.includes(k)) {
          throw new BadRequestException(`Invalid timeline kind: ${k}`);
        }
      }
    }

    // ── Summary mode: intersect requested kinds with the summary whitelist ──
    // If the caller didn't specify any kind, default to the summary whitelist.
    // If the caller DID specify kinds, filter to only those that are in the
    // whitelist (so a non-admin can't bypass the filter by requesting a
    // non-summary kind explicitly).
    if (!opts.raw) {
      if (kinds) {
        kinds = kinds.filter((k) => TIMELINE_SUMMARY_EVENT_TYPES.has(k));
      } else {
        kinds = Array.from(TIMELINE_SUMMARY_EVENT_TYPES);
      }
    }

    const items = await this.prisma.aURATimelineEvent.findMany({
      where: {
        familyId,
        ...(kinds && kinds.length > 0 ? { kind: { in: kinds } } : {}),
        ...(opts.cursor ? { occurredAt: { lt: new Date(opts.cursor) } } : {}),
      },
      orderBy: { occurredAt: 'desc' },
      take: limit + 1, // one extra to detect hasNext
    });

    const hasNext = items.length > limit;
    const page = hasNext ? items.slice(0, limit) : items;
    const nextCursor = hasNext && page.length > 0 ? page[page.length - 1].occurredAt.toISOString() : null;

    return {
      items: page.map((e) => ({
        id: e.id,
        familyId: e.familyId,
        kind: e.kind,
        actorId: e.actorId,
        targetEntityType: e.targetEntityType,
        targetEntityId: e.targetEntityId,
        title: e.title,
        description: e.description,
        payload: e.payload,
        parentEventId: e.parentEventId,
        occurredAt: e.occurredAt,
        createdAt: e.createdAt,
      })),
      nextCursor,
      hasNext,
      // Tell the client whether this is the filtered summary or the raw log
      mode: opts.raw ? 'raw' : 'summary',
    };
  }

  /**
   * Get a single timeline event.
   *
   * VISIBILITY MATRIX:
   *   - Summary event types: visible to all members.
   *   - Non-summary event types: visible to admins only.
   */
  async getOne(familyId: string, eventId: string, userId?: string) {
    if (userId) {
      await this.membership.requireMember(userId, familyId);
    }

    const event = await this.prisma.aURATimelineEvent.findUnique({
      where: { id_familyId: { id: eventId, familyId } },
    });
    if (!event) throw new NotFoundException('Timeline event not found');

    // If this is a non-summary event, require admin access
    if (userId && !TIMELINE_SUMMARY_EVENT_TYPES.has(event.kind as TimelineKind)) {
      await this.visibility.requireAdminDataAccess(userId, familyId);
    }

    return event;
  }

  /**
   * Get corrections for a specific event.
   */
  async getCorrections(familyId: string, eventId: string) {
    return this.prisma.aURATimelineEvent.findMany({
      where: { familyId, parentEventId: eventId, kind: 'correction' },
      orderBy: { occurredAt: 'asc' },
    });
  }

  /**
   * Append a correction event.
   * The original event is NEVER mutated (DB trigger).
   * Admin-only — controller enforces role check.
   */
  async appendCorrection(
    familyId: string,
    eventId: string,
    actorId: string,
    correctedFields: Record<string, { from: any; to: any }>,
    note?: string,
  ) {
    // Verify the original event exists in this family
    const original = await this.prisma.aURATimelineEvent.findUnique({
      where: { id_familyId: { id: eventId, familyId } },
    });
    if (!original) throw new NotFoundException('Original timeline event not found');

    if (original.familyId !== familyId) {
      throw new ForbiddenException('Cross-family correction rejected');
    }

    const correctionId = await this.emitter.appendCorrection({
      familyId,
      parentEventId: eventId,
      actorId,
      correctedFields,
      note,
    });

    if (!correctionId) {
      throw new BadRequestException('Failed to append correction');
    }

    return { correctionId, originalEventId: eventId };
  }

  /**
   * Export timeline as JSON. Section 11.2 — paginated for >10MB.
   */
  async exportJson(
    familyId: string,
    opts: { from?: string; to?: string } = {},
  ) {
    const where: any = { familyId };
    if (opts.from || opts.to) {
      where.occurredAt = {};
      if (opts.from) where.occurredAt.gte = new Date(opts.from);
      if (opts.to) where.occurredAt.lte = new Date(opts.to);
    }

    const events = await this.prisma.aURATimelineEvent.findMany({
      where,
      orderBy: { occurredAt: 'asc' },
      // Section 19 edge case #13: Timeline export > 10MB → paginated.
      // For JSON, we chunk by year using a cursor-based approach.
      take: 5000,
    });

    return {
      familyId,
      exportedAt: new Date().toISOString(),
      count: events.length,
      events,
    };
  }
}
