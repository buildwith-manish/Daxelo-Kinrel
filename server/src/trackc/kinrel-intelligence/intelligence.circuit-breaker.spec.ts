// =============================================================================
// Track C v2.0 — Circuit Breaker Tests
// =============================================================================
// Section 14.5 chaos tests: LLM provider down → cached/degraded within 5s.
// =============================================================================

import { CircuitBreaker, DegradedModeError } from './intelligence.circuit-breaker';

describe('CircuitBreaker', () => {
  let breaker: CircuitBreaker;

  beforeEach(() => {
    breaker = new CircuitBreaker();
    // Use fake timers to control the 60s window and 5min recovery
    jest.useFakeTimers();
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it('starts in closed state', () => {
    expect(breaker.getState()).toBe('closed');
    expect(breaker.isOpen()).toBe(false);
  });

  it('stays closed when calls succeed', async () => {
    const result = await breaker.execute(async () => 'ok');
    expect(result).toBe('ok');
    expect(breaker.getState()).toBe('closed');
  });

  it('does NOT trip on isolated failures (below minCallsBeforeTrip)', async () => {
    for (let i = 0; i < 4; i++) {
      await expect(breaker.execute(async () => { throw new Error('fail'); })).rejects.toThrow('fail');
    }
    expect(breaker.getState()).toBe('closed');
  });

  it('trips after 5 calls with >10% error rate', async () => {
    // 5 calls, all failing → 100% error rate → trip
    for (let i = 0; i < 5; i++) {
      await expect(breaker.execute(async () => { throw new Error('fail'); })).rejects.toThrow('fail');
    }
    expect(breaker.getState()).toBe('open');
  });

  it('throws DegradedModeError when open', async () => {
    // Trip the breaker
    for (let i = 0; i < 5; i++) {
      await breaker.execute(async () => { throw new Error('fail'); }).catch(() => {});
    }
    expect(breaker.isOpen()).toBe(true);

    await expect(breaker.execute(async () => 'should not run')).rejects.toThrow(DegradedModeError);
  });

  it('recovers to half_open after 5 minutes', async () => {
    // Trip the breaker
    for (let i = 0; i < 5; i++) {
      await breaker.execute(async () => { throw new Error('fail'); }).catch(() => {});
    }
    expect(breaker.getState()).toBe('open');

    // Advance 5 minutes
    jest.advanceTimersByTime(5 * 60 * 1000 + 1000);

    expect(breaker.getState()).toBe('half_open');
  });

  it('closes if half_open trial succeeds', async () => {
    // Trip the breaker
    for (let i = 0; i < 5; i++) {
      await breaker.execute(async () => { throw new Error('fail'); }).catch(() => {});
    }
    jest.advanceTimersByTime(5 * 60 * 1000 + 1000);
    expect(breaker.getState()).toBe('half_open');

    await breaker.execute(async () => 'recovered');
    expect(breaker.getState()).toBe('closed');
  });

  it('re-opens if half_open trial fails', async () => {
    // Trip
    for (let i = 0; i < 5; i++) {
      await breaker.execute(async () => { throw new Error('fail'); }).catch(() => {});
    }
    jest.advanceTimersByTime(5 * 60 * 1000 + 1000);
    expect(breaker.getState()).toBe('half_open');

    await expect(breaker.execute(async () => { throw new Error('still broken'); })).rejects.toThrow('still broken');
    expect(breaker.getState()).toBe('open');
  });

  it('does NOT trip on DegradedModeError (avoid feedback loop)', async () => {
    // Manually trip
    for (let i = 0; i < 5; i++) {
      await breaker.execute(async () => { throw new Error('fail'); }).catch(() => {});
    }
    expect(breaker.isOpen()).toBe(true);

    // Try again — should throw DegradedModeError, not affect breaker state
    await expect(breaker.execute(async () => 'x')).rejects.toThrow(DegradedModeError);
    expect(breaker.isOpen()).toBe(true); // still open, no re-trip
  });
});
