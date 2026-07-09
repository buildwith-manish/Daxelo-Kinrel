// =============================================================================
// Track C v2.0 — Mock LLM Provider Tests
// =============================================================================
// Verifies the mock provider produces valid structured payloads for every
// kind, so the rest of the AI pipeline works end-to-end in test mode.
// =============================================================================

import { MockLLMProvider } from './llm-providers/mock.provider';

describe('MockLLMProvider', () => {
  let provider: MockLLMProvider;

  beforeEach(() => {
    provider = new MockLLMProvider();
  });

  it('returns valid decision_analysis JSON', async () => {
    const response = await provider.generate({
      modelId: 'mock',
      responseFormat: 'json_object',
      messages: [
        { role: 'system', content: 'decision_analysis' },
        { role: 'user', content: 'Decision: family vacation' },
      ],
    });
    const parsed = JSON.parse(response.content);
    expect(parsed.qualityScore).toBeGreaterThan(0);
    expect(parsed.qualityScore).toBeLessThanOrEqual(1);
    expect(Array.isArray(parsed.strengths)).toBe(true);
    expect(Array.isArray(parsed.risks)).toBe(true);
    expect(parsed.recommendation).toBeTruthy();
    expect(['low', 'medium', 'high']).toContain(parsed.confidenceLevel);
  });

  it('returns valid pros_cons JSON', async () => {
    const response = await provider.generate({
      modelId: 'mock',
      responseFormat: 'json_object',
      messages: [{ role: 'system', content: 'pros_cons' }, { role: 'user', content: 'test' }],
    });
    const parsed = JSON.parse(response.content);
    expect(Array.isArray(parsed.pros)).toBe(true);
    expect(Array.isArray(parsed.cons)).toBe(true);
    expect(parsed.balancedAssessment).toBeTruthy();
  });

  it('returns valid summary JSON', async () => {
    const response = await provider.generate({
      modelId: 'mock',
      responseFormat: 'json_object',
      messages: [{ role: 'system', content: 'summary' }, { role: 'user', content: 'test' }],
    });
    const parsed = JSON.parse(response.content);
    expect(parsed.summary).toBeTruthy();
    expect(Array.isArray(parsed.keyTakeaways)).toBe(true);
  });

  it('returns valid duplicate_detection JSON', async () => {
    const response = await provider.generate({
      modelId: 'mock',
      responseFormat: 'json_object',
      messages: [{ role: 'system', content: 'duplicate_detection' }, { role: 'user', content: 'test' }],
    });
    const parsed = JSON.parse(response.content);
    expect(Array.isArray(parsed.duplicates)).toBe(true);
    expect(parsed.message).toBeTruthy();
  });

  it('returns valid action_items JSON', async () => {
    const response = await provider.generate({
      modelId: 'mock',
      responseFormat: 'json_object',
      messages: [{ role: 'system', content: 'action_items' }, { role: 'user', content: 'test' }],
    });
    const parsed = JSON.parse(response.content);
    expect(Array.isArray(parsed.actionItems)).toBe(true);
    for (const item of parsed.actionItems) {
      expect(item.assigneeRole).toBeTruthy();
      expect(item.text).toBeTruthy();
      expect(typeof item.dueOffsetDays).toBe('number');
    }
  });

  it('returns valid draft_minutes JSON', async () => {
    const response = await provider.generate({
      modelId: 'mock',
      responseFormat: 'json_object',
      messages: [{ role: 'system', content: 'draft_minutes' }, { role: 'user', content: 'test' }],
    });
    const parsed = JSON.parse(response.content);
    expect(parsed.draftMinutes).toContain('# Meeting Minutes');
  });

  it('tracks usage stats', async () => {
    await provider.generate({
      modelId: 'mock',
      messages: [{ role: 'system', content: 'test' }, { role: 'user', content: 'hello' }],
    });
    const stats = provider.getUsageStats();
    expect(stats.totalRequests).toBe(1);
    expect(stats.totalTokensIn).toBeGreaterThan(0);
    expect(stats.totalTokensOut).toBeGreaterThan(0);
    expect(stats.totalCostUsd).toBe(0); // mock is free
  });
});
