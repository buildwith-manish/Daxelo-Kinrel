// =============================================================================
// Track C v2.0 — Kinrel Timeline
// timeline.emitter.ts
// =============================================================================
// Single entry point for appending events to the Kinrel Timeline.
//
// Other modules call `timelineEmitter.append(...)` to record governance events.
// This service guarantees:
//   1. The event is INSERTed (never UPDATEd — DB trigger rejects UPDATE/DELETE)
//   2. The payload is validated against the per-kind schema
//   3. Realtime subscribers on the family's timeline channel are notified
//   4. Failures are logged but NEVER bubble up to the caller — timeline
//      emission is best-effort by design (a failed emission must not roll back
//      the governance action that triggered it).
//
// ADR-001: Append-only enforced at DB layer.
// =============================================================================

import { Injectable, Logger, Optional } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { RealtimeService } from '../common/realtime.proxy';
import {
  TimelineKind,
  TimelineEventPayloadSchemas,
  TimelineEventPayload,
} from './timeline.types';

@Injectable()
export class TimelineEmitter {
  private readonly logger = new Logger(TimelineEmitter.name);

  constructor(
    private readonly prisma: PrismaService,
    @Optional() private readonly realtime: RealtimeService,
  ) {}

  /**
   * Append a timeline event. Best-effort: logs but does not throw on failure.
   *
   * @returns the created event id, or null if emission failed
   */
  async append(params: {
    familyId: string;
    kind: TimelineKind;
    actorId?: string | null;
    targetEntityType?: string | null;
    targetEntityId?: string | null;
    title: string;
    description?: string | null;
    payload?: TimelineEventPayload;
    parentEventId?: string | null;
  }): Promise<string | null> {
    try {
      // Validate payload shape per kind
      const schema = TimelineEventPayloadSchemas[params.kind];
      const payload = schema ? schema(params.payload ?? {}) : (params.payload ?? {});

      const event = await this.prisma.kinrelTimelineEvent.create({
        data: {
          familyId: params.familyId,
          kind: params.kind,
          actorId: params.actorId ?? null,
          targetEntityType: params.targetEntityType ?? null,
          targetEntityId: params.targetEntityId ?? null,
          title: params.title,
          description: params.description ?? null,
          payload: payload as any,
          parentEventId: params.parentEventId ?? null,
        },
      });

      // Notify realtime subscribers (best-effort)
      if (this.realtime) {
        try {
          await this.realtime.broadcastFamily(params.familyId, 'timeline:event', {
            id: event.id,
            kind: event.kind,
            title: event.title,
            occurredAt: event.occurredAt,
          });
        } catch (rtErr) {
          this.logger.warn(
            `Realtime broadcast failed for family ${params.familyId}: ${(rtErr as Error).message}`,
          );
        }
      }

      return event.id;
    } catch (err) {
      // CRITICAL: never throw — timeline emission is best-effort.
      // A failed emission must not roll back the governance action.
      this.logger.error(
        `Timeline emission failed for family=${params.familyId} kind=${params.kind}: ${(err as Error).message}`,
        (err as Error).stack,
      );
      return null;
    }
  }

  /**
   * Append a correction event referencing a previous event.
   * The original event is NEVER mutated (DB trigger forbids UPDATE).
   */
  async appendCorrection(params: {
    familyId: string;
    parentEventId: string;
    actorId: string;
    correctedFields: Record<string, { from: any; to: any }>;
    note?: string;
  }): Promise<string | null> {
    return this.append({
      familyId: params.familyId,
      kind: 'correction',
      actorId: params.actorId,
      parentEventId: params.parentEventId,
      title: 'Correction',
      description: params.note ?? 'A previous event has been corrected.',
      payload: {
        parentEventId: params.parentEventId,
        correctedFields: params.correctedFields,
        note: params.note,
      },
    });
  }
}
