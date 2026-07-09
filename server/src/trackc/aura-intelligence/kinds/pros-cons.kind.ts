// =============================================================================
// Track C v2.0 — AURA Intelligence
// kinds/pros-cons.kind.ts
// =============================================================================

import { Injectable } from '@nestjs/common';
import { LLMRequest } from '../llm-provider';
import { RedactionService } from '../redaction';

export interface ProsConsPayload {
  pros: string[];
  cons: string[];
  balancedAssessment: string;
}

@Injectable()
export class ProsConsKind {
  readonly kind = 'pros_cons' as const;

  constructor(private readonly redaction: RedactionService) {}

  buildRequest(params: {
    decisionTitle: string;
    decisionDescription?: string;
    options: string[];
  }): LLMRequest {
    const { redacted: title } = this.redaction.redact(params.decisionTitle);
    const { redacted: description } = this.redaction.redact(params.decisionDescription ?? '');

    const system = `You are a balanced family-decision advisor. Generate pros and cons for the decision below. Return JSON with: pros (array of 3-4 short strings), cons (array of 3-4 short strings), balancedAssessment (one sentence). Respond ONLY with valid JSON.`;

    const user = `Title: ${title}
Description: ${description || '(none)'}
Options: ${params.options.join(' | ') || '(none)'}`;

    return {
      modelId: 'gpt-4o-mini',
      messages: [
        { role: 'system', content: system },
        { role: 'user', content: user },
      ],
      maxOutputTokens: 800,
      temperature: 0.5,
      responseFormat: 'json_object',
    };
  }

  parseResponse(content: string): ProsConsPayload {
    try {
      const parsed = JSON.parse(content);
      return {
        pros: Array.isArray(parsed.pros) ? parsed.pros : [],
        cons: Array.isArray(parsed.cons) ? parsed.cons : [],
        balancedAssessment:
          typeof parsed.balancedAssessment === 'string' ? parsed.balancedAssessment : '',
      };
    } catch {
      return { pros: [], cons: [], balancedAssessment: 'Unable to generate pros/cons analysis.' };
    }
  }
}
