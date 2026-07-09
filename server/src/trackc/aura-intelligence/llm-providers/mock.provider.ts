// =============================================================================
// Track C v2.0 — AURA Intelligence
// llm-providers/mock.provider.ts
// =============================================================================
// Deterministic mock LLM provider for tests. Returns canned responses based
// on a heuristic detection of the request content. Used by:
//   - Unit tests (jest)
//   - Integration tests (testcontainers)
//   - Local development without an OpenAI key
//   - Circuit-breaker fallback (returns degraded cached-style responses)
//
// The mock is NOT a placeholder — it produces structured, valid JSON outputs
// that match the per-kind payload schemas, so the rest of the pipeline
// (caching, persistence, UI rendering) works end-to-end in test mode.
// =============================================================================

import { Injectable, Logger } from '@nestjs/common';
import { LLMProvider, LLMRequest, LLMResponse, LLMUsageStats } from '../llm-provider';

@Injectable()
export class MockLLMProvider implements LLMProvider {
  readonly providerName = 'mock';
  private readonly logger = new Logger(MockLLMProvider.name);
  private stats: LLMUsageStats = {
    totalRequests: 0,
    totalTokensIn: 0,
    totalTokensOut: 0,
    totalCostUsd: 0,
    errorCount: 0,
  };

  async generate(req: LLMRequest): Promise<LLMResponse> {
    const start = Date.now();
    const userContent = req.messages.find((m) => m.role === 'user')?.content ?? '';
    const systemContent = req.messages.find((m) => m.role === 'system')?.content ?? '';

    let content: string;
    if (req.responseFormat === 'json_object') {
      content = this.generateJsonResponse(systemContent, userContent);
    } else {
      content = this.generateTextResponse(systemContent, userContent);
    }

    const tokensIn = Math.ceil((systemContent.length + userContent.length) / 4);
    const tokensOut = Math.ceil(content.length / 4);

    this.stats.totalRequests++;
    this.stats.totalTokensIn += tokensIn;
    this.stats.totalTokensOut += tokensOut;
    // Mock is free
    this.stats.totalCostUsd += 0;

    return {
      modelId: req.modelId,
      content,
      tokensIn,
      tokensOut,
      costUsd: 0,
      latencyMs: Date.now() - start,
    };
  }

  getUsageStats(): LLMUsageStats {
    return { ...this.stats };
  }

  private generateJsonResponse(system: string, user: string): string {
    // Heuristic: detect which kind of insight is being requested based on system prompt keywords
    if (system.includes('decision_analysis')) {
      return JSON.stringify({
        qualityScore: 0.72,
        strengths: ['Clear options', 'Inclusive eligibility'],
        risks: ['Tight deadline may reduce participation'],
        recommendation: 'Consider extending the deadline by 48 hours to maximize participation.',
        confidenceLevel: 'medium',
      });
    }
    if (system.includes('pros_cons')) {
      return JSON.stringify({
        pros: ['Aligns with family values', 'Transparent process', 'Builds shared understanding'],
        cons: ['Time-intensive', 'May surface disagreement', 'Requires follow-through'],
        balancedAssessment: 'Net positive if the family commits to acting on the outcome.',
      });
    }
    if (system.includes('duplicate_detection')) {
      return JSON.stringify({
        duplicates: [],
        closestMatch: null,
        message: 'No similar decisions found in family history.',
      });
    }
    if (system.includes('summary')) {
      return JSON.stringify({
        summary: 'The family discussed the proposal and reached consensus on next steps.',
        keyTakeaways: ['Consensus reached', 'Action items assigned', 'Follow-up scheduled'],
      });
    }
    if (system.includes('action_items')) {
      return JSON.stringify({
        actionItems: [
          { assigneeRole: 'admin', text: 'Schedule follow-up meeting within 2 weeks', dueOffsetDays: 14 },
          { assigneeRole: 'member', text: 'Draft proposal for next discussion', dueOffsetDays: 7 },
        ],
      });
    }
    if (system.includes('draft_minutes')) {
      return JSON.stringify({
        draftMinutes: `# Meeting Minutes\n\n## Held On\n${new Date().toISOString()}\n\n## Agenda\n- Item 1\n- Item 2\n\n## Discussion\nThe family discussed the items on the agenda.\n\n## Decisions\n- Decision 1\n\n## Action Items\n- [ ] Action 1\n`,
      });
    }
    return JSON.stringify({ message: 'Mock response', echo: (user || '').slice(0, 200) });
  }

  private generateTextResponse(system: string, user: string): string {
    return `[Mock LLM response]\n\nSystem context: ${system.slice(0, 100)}...\n\nUser input: ${user.slice(0, 200)}...\n\nThis is a deterministic mock response for testing.`;
  }
}
