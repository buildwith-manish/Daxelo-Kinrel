// =============================================================================
// Track C v2.0 — Kinrel Intelligence
// llm-providers/openai.provider.ts
// =============================================================================
// OpenAI-compatible LLM provider. Uses fetch against the OpenAI Chat Completions
// API. Compatible with any OpenAI-API-compatible endpoint (Azure OpenAI,
// Together, Groq, local vLLM, etc.) by overriding the base URL.
// =============================================================================

import { Injectable, Logger } from '@nestjs/common';
import {
  LLMProvider,
  LLMRequest,
  LLMResponse,
  LLMUsageStats,
} from '../llm-provider';

export interface OpenAIProviderConfig {
  apiKey: string;
  baseUrl?: string; // default https://api.openai.com/v1
  defaultModelId?: string; // default 'glm-4.7-flash'
}

@Injectable()
export class OpenAIProvider implements LLMProvider {
  readonly providerName = 'openai';
  private readonly logger = new Logger(OpenAIProvider.name);
  private readonly baseUrl: string;
  private readonly apiKey: string;
  private readonly defaultModelId: string;

  private stats: LLMUsageStats = {
    totalRequests: 0,
    totalTokensIn: 0,
    totalTokensOut: 0,
    totalCostUsd: 0,
    errorCount: 0,
  };

  // Rough per-1K-token cost in USD. Used for budget tracking.
  // Real cost is read from API response when available; this is a fallback.
  private readonly costTable: Record<string, { in: number; out: number }> = {
    'glm-4.7-flash': { in: 0.00015, out: 0.0006 },
    'gpt-4o': { in: 0.0025, out: 0.01 },
    'gpt-4.1-mini': { in: 0.0004, out: 0.0016 },
    'gpt-4.1': { in: 0.002, out: 0.008 },
  };

  constructor(config: OpenAIProviderConfig) {
    this.apiKey = config.apiKey;
    this.baseUrl = config.baseUrl ?? 'https://api.openai.com/v1';
    this.defaultModelId = config.defaultModelId ?? 'glm-4.7-flash';
  }

  async generate(req: LLMRequest): Promise<LLMResponse> {
    const modelId = req.modelId || this.defaultModelId;
    const start = Date.now();

    const body: any = {
      model: modelId,
      messages: req.messages,
      max_tokens: Math.min(req.maxOutputTokens ?? 1500, 4000), // hard cap per Section 8.3
      temperature: req.temperature ?? 0.4,
    };
    if (req.responseFormat === 'json_object') {
      body.response_format = { type: 'json_object' };
    }

    const res = await fetch(`${this.baseUrl}/chat/completions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${this.apiKey}`,
      },
      body: JSON.stringify(body),
    });

    if (!res.ok) {
      const errText = await res.text().catch(() => '');
      this.stats.errorCount++;
      throw new Error(`OpenAI API ${res.status}: ${errText.slice(0, 500)}`);
    }

    const data: any = await res.json();
    const content = data.choices?.[0]?.message?.content ?? '';
    const tokensIn = data.usage?.prompt_tokens ?? this.estimateTokens(req.messages);
    const tokensOut = data.usage?.completion_tokens ?? this.estimateTokens([{ role: 'assistant', content }] as any);
    const costUsd = this.computeCost(modelId, tokensIn, tokensOut);
    const latencyMs = Date.now() - start;

    this.stats.totalRequests++;
    this.stats.totalTokensIn += tokensIn;
    this.stats.totalTokensOut += tokensOut;
    this.stats.totalCostUsd += costUsd;

    return { modelId, content, tokensIn, tokensOut, costUsd, latencyMs };
  }

  getUsageStats(): LLMUsageStats {
    return { ...this.stats };
  }

  private computeCost(modelId: string, tokensIn: number, tokensOut: number): number {
    const rates = this.costTable[modelId] ?? this.costTable[this.defaultModelId] ?? { in: 0.001, out: 0.002 };
    return (tokensIn / 1000) * rates.in + (tokensOut / 1000) * rates.out;
  }

  private estimateTokens(messages: { content: string }[]): number {
    // Rough estimate: 1 token ≈ 4 chars
    return Math.ceil(messages.reduce((acc, m) => acc + (m?.content?.length ?? 0), 0) / 4);
  }
}
