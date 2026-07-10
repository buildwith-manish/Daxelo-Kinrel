// =============================================================================
// Track C v2.0 — Kinrel Intelligence
// llm-provider.ts
// =============================================================================
// Abstract LLM provider interface. ADR-005: LLM provider behind circuit breaker
// + cost ceiling. Multiple providers can implement this interface; the
// `modelId` field on AIInsight records which provider/model produced each
// output, so insights are reproducible for audit.
// =============================================================================

export interface LLMMessage {
  role: 'system' | 'user' | 'assistant';
  content: string;
}

export interface LLMRequest {
  /** Model identifier (e.g. "glm-4.7-flash-2026-07"). Recorded on AIInsight for audit. */
  modelId: string;
  messages: LLMMessage[];
  /** Max output tokens. Server caps at 4000 (Section 8.3). */
  maxOutputTokens?: number;
  /** Sampling temperature. Defaults to 0.4 for analytical kinds. */
  temperature?: number;
  /** Response format. 'json_object' forces JSON output. */
  responseFormat?: 'text' | 'json_object';
}

export interface LLMResponse {
  modelId: string;
  content: string;
  tokensIn: number;
  tokensOut: number;
  costUsd: number;
  latencyMs: number;
}

export interface LLMUsageStats {
  totalRequests: number;
  totalTokensIn: number;
  totalTokensOut: number;
  totalCostUsd: number;
  errorCount: number;
}

export const LLM_PROVIDER = Symbol('LLM_PROVIDER');

export interface LLMProvider {
  /** Generate a completion. Throws on upstream errors (circuit breaker handles retry/fallback). */
  generate(req: LLMRequest): Promise<LLMResponse>;

  /** Provider identifier (e.g. "openai", "mock"). */
  readonly providerName: string;

  /** Get usage stats since process start (for observability). */
  getUsageStats(): LLMUsageStats;
}
