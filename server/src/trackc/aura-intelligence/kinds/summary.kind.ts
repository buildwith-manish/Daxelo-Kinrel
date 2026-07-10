// =============================================================================
// Track C v2.0 — AURA Intelligence
// kinds/summary.kind.ts
// =============================================================================

import { Injectable } from '@nestjs/common';
import { LLMRequest } from '../llm-provider';
import { RedactionService } from '../redaction';

export interface SummaryPayload {
  summary: string;
  keyTakeaways: string[];
}

@Injectable()
export class SummaryKind {
  readonly kind = 'summary' as const;

  constructor(private readonly redaction: RedactionService) {}

  buildRequest(params: {
    decisionTitle: string;
    decisionDescription?: string;
    outcome?: string;
    resolutionNote?: string;
  }): LLMRequest {
    const { redacted: title } = this.redaction.redact(params.decisionTitle);
    const { redacted: description } = this.redaction.redact(params.decisionDescription ?? '');
    const { redacted: outcome } = this.redaction.redact(params.outcome ?? '');
    const { redacted: note } = this.redaction.redact(params.resolutionNote ?? '');

    const system = `You are a family-governance secretary. Summarize the resolved decision below. Return JSON with: summary (2-3 sentences), keyTakeaways (3-5 short bullet strings). Respond ONLY with valid JSON.`;

    const user = `Title: ${title}
Description: ${description || '(none)'}
Outcome: ${outcome || '(pending)'}
Resolution note: ${note || '(none)'}`;

    return {
      modelId: 'glm-4.7-flash',
      messages: [
        { role: 'system', content: system },
        { role: 'user', content: user },
      ],
      maxOutputTokens: 700,
      temperature: 0.3,
      responseFormat: 'json_object',
    };
  }

  parseResponse(content: string): SummaryPayload {
    try {
      const parsed = JSON.parse(content);
      return {
        summary: typeof parsed.summary === 'string' ? parsed.summary : '',
        keyTakeaways: Array.isArray(parsed.keyTakeaways) ? parsed.keyTakeaways : [],
      };
    } catch {
      return { summary: 'Unable to generate summary.', keyTakeaways: [] };
    }
  }
}
