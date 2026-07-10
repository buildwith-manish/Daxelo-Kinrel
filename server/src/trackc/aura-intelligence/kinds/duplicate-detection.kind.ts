// =============================================================================
// Track C v2.0 — AURA Intelligence
// kinds/duplicate-detection.kind.ts
// =============================================================================

import { Injectable } from '@nestjs/common';
import { LLMRequest } from '../llm-provider';
import { RedactionService } from '../redaction';

export interface DuplicateDetectionPayload {
  duplicates: Array<{ decisionId: string; similarity: number; reason: string }>;
  closestMatch: { decisionId: string; similarity: number; reason: string } | null;
  message: string;
}

@Injectable()
export class DuplicateDetectionKind {
  readonly kind = 'duplicate_detection' as const;

  constructor(private readonly redaction: RedactionService) {}

  /**
   * Build a request that includes the new decision + recent prior decisions in the family.
   * The LLM identifies potential duplicates.
   */
  buildRequest(params: {
    newDecisionTitle: string;
    newDecisionDescription?: string;
    priorDecisions: Array<{ id: string; title: string; description?: string }>;
  }): LLMRequest {
    const { redacted: newTitle } = this.redaction.redact(params.newDecisionTitle);
    const { redacted: newDesc } = this.redaction.redact(params.newDecisionDescription ?? '');

    const priors = params.priorDecisions.map((d) => {
      const t = this.redaction.redact(d.title).redacted;
      const desc = this.redaction.redact(d.description ?? '').redacted;
      return `ID: ${d.id}\nTitle: ${t}\nDescription: ${desc || '(none)'}`;
    });

    const system = `You are a duplicate-detection assistant for a family decision platform. Given a new decision and a list of prior decisions, identify duplicates. Return JSON with: duplicates (array of {decisionId, similarity (0..1), reason}), closestMatch ({decisionId, similarity, reason} or null), message (string). Respond ONLY with valid JSON.`;

    const user = `NEW DECISION
Title: ${newTitle}
Description: ${newDesc || '(none)'}

PRIOR DECISIONS
${priors.join('\n---\n') || '(no prior decisions)'}`;

    return {
      modelId: 'glm-4.7-flash',
      messages: [
        { role: 'system', content: system },
        { role: 'user', content: user },
      ],
      maxOutputTokens: 900,
      temperature: 0.2, // low temp for deterministic matching
      responseFormat: 'json_object',
    };
  }

  parseResponse(content: string): DuplicateDetectionPayload {
    try {
      const parsed = JSON.parse(content);
      return {
        duplicates: Array.isArray(parsed.duplicates) ? parsed.duplicates : [],
        closestMatch: parsed.closestMatch ?? null,
        message: typeof parsed.message === 'string' ? parsed.message : '',
      };
    } catch {
      return { duplicates: [], closestMatch: null, message: 'Duplicate detection failed.' };
    }
  }
}
