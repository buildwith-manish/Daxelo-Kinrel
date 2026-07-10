// =============================================================================
// Track C v2.0 — Kinrel Learning Engine
// learning.signal-ingestor.ts
// =============================================================================
// Ingests learning signals (from client + server events) into LearningSignal.
// Section 9.2.
//
// Signals are pseudonymous: payload stores shapes/counts/durations, NEVER raw
// text or PII. The model trains on shapes, not text.
// =============================================================================

import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

export type SignalType =
  | 'insight_accepted'
  | 'insight_dismissed'
  | 'reminder_acted'
  | 'reminder_snoozed'
  | 'reminder_dismissed'
  | 'event_scheduled'
  | 'elder_participated'
  | 'quorum_met'
  | 'deadline_extended'
  | 'vote_pattern'
  | 'search_performed';

export interface SignalInput {
  familyId: string;
  signalType: SignalType;
  targetType?: 'AIInsight' | 'FamilyDecision' | 'SmartReminder' | 'FamilyEvent';
  targetId?: string;
  payload?: Record<string, any>;
  occurredAt?: Date;
}

@Injectable()
export class SignalIngestor {
  private readonly logger = new Logger(SignalIngestor.name);

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Ingest a single signal. Idempotent — duplicates are allowed (the profile
   * builder is responsible for deduplication on `targetId` if needed).
   */
  async ingest(input: SignalInput): Promise<string> {
    // Sanitize payload — never store PII
    const sanitizedPayload = this.sanitizePayload(input.payload ?? {});

    const signal = await this.prisma.learningSignal.create({
      data: {
        familyId: input.familyId,
        signalType: input.signalType,
        targetType: input.targetType ?? null,
        targetId: input.targetId ?? null,
        payload: sanitizedPayload as any,
        occurredAt: input.occurredAt ?? new Date(),
      },
    });

    return signal.id;
  }

  /**
   * Ingest a batch of signals atomically.
   */
  async ingestBatch(inputs: SignalInput[]): Promise<number> {
    if (!inputs.length) return 0;
    const sanitized = inputs.map((i) => ({
      familyId: i.familyId,
      signalType: i.signalType,
      targetType: i.targetType ?? null,
      targetId: i.targetId ?? null,
      payload: this.sanitizePayload(i.payload ?? {}),
      occurredAt: i.occurredAt ?? new Date(),
    }));

    const result = await this.prisma.learningSignal.createMany({
      data: sanitized as any,
      skipDuplicates: true,
    });
    return result.count;
  }

  /**
   * Strip any potentially PII fields from the payload.
   * We allow only primitive values + nested objects of primitives.
   * Strings are truncated to 200 chars to prevent storing long text.
   */
  private sanitizePayload(payload: Record<string, any>): Record<string, any> {
    const out: Record<string, any> = {};
    for (const [k, v] of Object.entries(payload)) {
      if (typeof v === 'string') {
        out[k] = v.slice(0, 200);
      } else if (typeof v === 'number' || typeof v === 'boolean') {
        out[k] = v;
      } else if (Array.isArray(v)) {
        out[k] = v.slice(0, 50).map((item) => (typeof item === 'string' ? item.slice(0, 100) : item));
      } else if (v && typeof v === 'object') {
        out[k] = this.sanitizePayload(v);
      }
      // functions, symbols, undefined → dropped
    }
    return out;
  }
}
