// =============================================================================
// Track C v2.0 — AURA Intelligence
// kinds/decision-analysis.kind.ts
// =============================================================================
// Decision quality analysis. Analyzes a decision's structure, options, deadline,
// quorum, and produces a quality score + strengths/risks/recommendation.
// =============================================================================

import { Injectable } from '@nestjs/common';
import { LLMProvider, LLMRequest } from '../llm-provider';
import { RedactionService } from '../redaction';

export interface DecisionAnalysisPayload {
  qualityScore: number; // 0..1
  strengths: string[];
  risks: string[];
  recommendation: string;
  confidenceLevel: 'low' | 'medium' | 'high';
}

@Injectable()
export class DecisionAnalysisKind {
  readonly kind = 'decision_analysis' as const;

  constructor(private readonly redaction: RedactionService) {}

  buildRequest(params: {
    decisionTitle: string;
    decisionDescription?: string;
    decisionType: string;
    options: string[];
    eligibleCount: number;
    quorumPct: number;
    deadlineHours: number;
    familySize: number;
  }): LLMRequest {
    const { redacted: title } = this.redaction.redact(params.decisionTitle);
    const { redacted: description } = this.redaction.redact(params.decisionDescription ?? '');

    const system = `You are an AI governance analyst for a family decision-making platform. Analyze the decision below and return a JSON object with:
- qualityScore (0..1): how well-structured is this decision
- strengths: array of strings (2-3 items)
- risks: array of strings (2-3 items)
- recommendation: a single sentence of practical advice
- confidenceLevel: "low" | "medium" | "high" based on input completeness

Respond ONLY with valid JSON. No prose.`;

    const user = `Decision Analysis Request
Title: ${title}
Description: ${description || '(none)'}
Type: ${params.decisionType}
Options: ${params.options.join(' | ') || '(none)'}
Eligible voters: ${params.eligibleCount} of ${params.familySize} family members
Quorum required: ${params.quorumPct}%
Deadline: ${params.deadlineHours.toFixed(1)} hours from now

Return JSON with keys: qualityScore, strengths, risks, recommendation, confidenceLevel.`;

    return {
      modelId: 'gpt-4o-mini',
      messages: [
        { role: 'system', content: system },
        { role: 'user', content: user },
      ],
      maxOutputTokens: 1000,
      temperature: 0.4,
      responseFormat: 'json_object',
    };
  }

  parseResponse(content: string): DecisionAnalysisPayload {
    try {
      const parsed = JSON.parse(content);
      return {
        qualityScore: typeof parsed.qualityScore === 'number'
          ? Math.max(0, Math.min(1, parsed.qualityScore))
          : 0.5,
        strengths: Array.isArray(parsed.strengths) ? parsed.strengths : [],
        risks: Array.isArray(parsed.risks) ? parsed.risks : [],
        recommendation: typeof parsed.recommendation === 'string' ? parsed.recommendation : '',
        confidenceLevel: ['low', 'medium', 'high'].includes(parsed.confidenceLevel)
          ? parsed.confidenceLevel
          : 'medium',
      };
    } catch {
      // Edge case #4: LLM returns invalid JSON → return a minimal valid payload
      return {
        qualityScore: 0.5,
        strengths: [],
        risks: ['LLM returned invalid response'],
        recommendation: 'Review the decision manually.',
        confidenceLevel: 'low',
      };
    }
  }
}
