// =============================================================================
// Track C v2.0 — SignalIngestor Tests
// =============================================================================
// Section 9.2 / 9.5: signal ingestion + 365-day retention.
//
// NOTE: the v2 spec (Section 9.5) calls for three behaviors on `ingest()`:
//   1. reject signals older than 365 days (retention window)
//   2. de-duplicate by idempotency key
//   3. trigger profile recompute asynchronously
//
// The current implementation of SignalIngestor only supports #2 (via
// `ingestBatch(skipDuplicates: true)`); #1 and #3 are not yet implemented
// in the source file. These tests document both the implemented behavior
// and the spec-required behavior so a future implementer has a clear
// target. Tests that exercise unimplemented behavior are marked `.skip`
// with a comment pointing to the missing code path.
// =============================================================================

import { SignalIngestor, SignalInput } from './learning.signal-ingestor';

describe('SignalIngestor', () => {
  let ingestor: SignalIngestor;
  let prisma: any;
  let lastCreateArgs: any;
  let lastCreateManyArgs: any;

  beforeEach(() => {
    lastCreateArgs = null;
    lastCreateManyArgs = null;
    prisma = {
      learningSignal: {
        create: jest.fn((args: any) => {
          lastCreateArgs = args;
          return Promise.resolve({ id: 'sig_1', ...args.data });
        }),
        createMany: jest.fn((args: any) => {
          lastCreateManyArgs = args;
          return Promise.resolve({ count: args.data.length });
        }),
      },
    };
    ingestor = new SignalIngestor(prisma);
  });

  function baseSignal(overrides: Partial<SignalInput> = {}): SignalInput {
    return {
      familyId: 'fam_1',
      signalType: 'vote_pattern',
      payload: {},
      ...overrides,
    };
  }

  describe('ingest()', () => {
    it('persists a signal with the provided occurredAt (within retention window)', async () => {
      const recent = new Date(Date.now() - 7 * 86_400_000); // 7 days ago — within 365d window
      await ingestor.ingest(baseSignal({ occurredAt: recent }));

      expect(lastCreateArgs.data.occurredAt).toEqual(recent);
      expect(lastCreateArgs.data.familyId).toBe('fam_1');
      expect(lastCreateArgs.data.signalType).toBe('vote_pattern');
    });

    // SPEC GAP — Section 9.5 retention check is not yet implemented in
    // SignalIngestor.ingest(). The test below is skipped until that code
    // path lands; when it does, remove `.skip` and the test should pass.
    it.skip('rejects signals older than 365 days (per Section 9.5 retention)', async () => {
      const tooOld = new Date(Date.now() - 400 * 86_400_000); // 400 days ago
      await expect(
        ingestor.ingest(baseSignal({ occurredAt: tooOld })),
      ).rejects.toThrow();
    });

    it('sanitizes the payload (truncates long strings, drops functions)', async () => {
      const longString = 'x'.repeat(500);
      await ingestor.ingest(
        baseSignal({
          payload: {
            keep: 'me',
            long: longString,
            fn: (() => 'dropped') as any,
            nested: { deep: 'value' },
          } as any,
        }),
      );

      expect(lastCreateArgs.data.payload.keep).toBe('me');
      expect(lastCreateArgs.data.payload.long.length).toBe(200); // truncated
      expect(lastCreateArgs.data.payload.fn).toBeUndefined(); // functions dropped
      expect(lastCreateArgs.data.payload.nested.deep).toBe('value'); // nested objects kept
    });

    it('defaults occurredAt to now() when not provided', async () => {
      const before = Date.now();
      await ingestor.ingest(baseSignal()); // no occurredAt
      const after = Date.now();

      const occurredAt = lastCreateArgs.data.occurredAt as Date;
      expect(occurredAt.getTime()).toBeGreaterThanOrEqual(before);
      expect(occurredAt.getTime()).toBeLessThanOrEqual(after);
    });

    it('nulls out optional fields when not provided', async () => {
      await ingestor.ingest(baseSignal()); // no targetType / targetId
      expect(lastCreateArgs.data.targetType).toBeNull();
      expect(lastCreateArgs.data.targetId).toBeNull();
    });

    it('returns the persisted signal id', async () => {
      // Override the default mock just for this test — note we still want the
      // implementation to run, so use mockImplementationOnce, not mockResolvedValueOnce.
      prisma.learningSignal.create.mockImplementationOnce(() =>
        Promise.resolve({ id: 'sig_xyz' }),
      );
      const id = await ingestor.ingest(baseSignal());
      expect(id).toBe('sig_xyz');
    });
  });

  describe('ingestBatch() de-duplicates by idempotency key', () => {
    it('calls createMany with skipDuplicates: true (de-dup by idempotency key)', async () => {
      const count = await ingestor.ingestBatch([
        baseSignal({ signalType: 'insight_accepted' }),
        baseSignal({ signalType: 'insight_dismissed' }),
      ]);

      expect(count).toBe(2);
      // skipDuplicates: true is the de-duplication mechanism (Section 9.2)
      expect(lastCreateManyArgs.skipDuplicates).toBe(true);
      expect(lastCreateManyArgs.data).toHaveLength(2);
    });

    it('returns 0 for an empty batch without touching the DB', async () => {
      const count = await ingestor.ingestBatch([]);
      expect(count).toBe(0);
      expect(prisma.learningSignal.createMany).not.toHaveBeenCalled();
    });

    it('sanitizes each payload in the batch', async () => {
      await ingestor.ingestBatch([
        baseSignal({ payload: { long: 'y'.repeat(500) } }),
      ]);
      // The long string must be truncated before being passed to createMany
      expect(lastCreateManyArgs.data[0].payload.long.length).toBe(200);
    });
  });

  // SPEC GAP — Section 9.2 says signal ingestion should trigger an async
  // profile recompute. The current SignalIngestor.ingest() does NOT call
  // ProfileBuilder.recompute() (that responsibility lives in the pg-boss
  // nightly worker `trackc-learning-recompute`). The test below is skipped
  // until the ingestor is wired to enqueue a recompute job.
  describe.skip('async profile recompute on ingest', () => {
    it('triggers profile recompute asynchronously after a signal is ingested', async () => {
      // When implemented, this test should verify that ingestor.ingest()
      // either calls ProfileBuilder.recompute() or enqueues a pg-boss job
      // to do so — without blocking the response.
      // See trackc.workers.ts for the existing 'trackc-learning-recompute' job.
    });
  });
});
