// server/src/modules/chat/chat-mention.push.scheduler.spec.ts
//
// Phase A-5 — quiet hours for mention pushes are evaluated in the RECIPIENT's
// stored NotificationPreference.quietHoursTimezone, not the server clock.

import { ChatMentionPushScheduler } from './chat-mention.push.scheduler';

describe('ChatMentionPushScheduler — quiet hours', () => {
  const mockPrisma = {
    notificationPreference: { findFirst: jest.fn() },
    chatMessage: { findUnique: jest.fn() },
    chatSettings: { findMany: jest.fn() },
  };
  const scheduler = new ChatMentionPushScheduler(
    mockPrisma as any,
    { sendToUser: jest.fn() } as any,
    { isUserConnected: jest.fn() } as any,
  );

  const shouldPush = () => (scheduler as any).shouldPushForRecipient('recipient-1', 'Sender') as Promise<boolean>;
  const pref = (over: Record<string, unknown> = {}) => ({
    quietHoursStart: '22:00',
    quietHoursEnd: '08:00',
    quietHoursTimezone: 'Asia/Kolkata',
    mentionsBreakMute: true,
    ...over,
  });
  const at = (iso: string) => jest.setSystemTime(new Date(iso));

  beforeEach(() => {
    jest.useFakeTimers();
    mockPrisma.notificationPreference.findFirst.mockReset();
  });
  afterEach(() => jest.useRealTimers());

  it('suppresses the push inside the window in the recipient timezone (IST 22:30 = 17:00 UTC, server clock is outside the window)', async () => {
    at('2026-11-20T17:00:00.000Z');
    mockPrisma.notificationPreference.findFirst.mockResolvedValue(pref());

    expect(await shouldPush()).toBe(false);
    expect(mockPrisma.notificationPreference.findFirst).toHaveBeenCalledWith({
      where: { userId: 'recipient-1' },
    });
  });

  it('does not require any "quietHoursEnabled" flag (the column does not exist)', async () => {
    at('2026-11-20T17:00:00.000Z');
    const p = pref();
    expect('quietHoursEnabled' in p).toBe(false);
    mockPrisma.notificationPreference.findFirst.mockResolvedValue(p);

    expect(await shouldPush()).toBe(false);
  });

  it('pushes outside the window (IST 08:00 = 02:30 UTC; end minute is not quiet)', async () => {
    at('2026-11-21T02:30:00.000Z');
    mockPrisma.notificationPreference.findFirst.mockResolvedValue(pref());

    expect(await shouldPush()).toBe(true);
  });

  it('same instant, different stored timezone: New York at 17:00 UTC is midday, so it pushes', async () => {
    at('2026-11-20T17:00:00.000Z');
    mockPrisma.notificationPreference.findFirst.mockResolvedValue(
      pref({ quietHoursTimezone: 'America/New_York' }),
    );

    expect(await shouldPush()).toBe(true);
  });

  it('a recipient in New York is quiet at 03:00 UTC (22:00 EST)', async () => {
    at('2026-11-21T03:00:00.000Z');
    mockPrisma.notificationPreference.findFirst.mockResolvedValue(
      pref({ quietHoursTimezone: 'America/New_York' }),
    );

    expect(await shouldPush()).toBe(false);
  });

  it('invalid stored timezone falls back to IST instead of throwing (fail-closed path not hit)', async () => {
    at('2026-11-20T17:00:00.000Z');
    mockPrisma.notificationPreference.findFirst.mockResolvedValue(pref({ quietHoursTimezone: 'Nope/Nowhere' }));

    expect(await shouldPush()).toBe(false); // 22:30 IST -> quiet
  });

  it('no start/end configured -> not quiet, pushes', async () => {
    at('2026-11-20T17:00:00.000Z');
    mockPrisma.notificationPreference.findFirst.mockResolvedValue(
      pref({ quietHoursStart: null, quietHoursEnd: null }),
    );

    expect(await shouldPush()).toBe(true);
  });

  it('no preference row -> pushes (unchanged)', async () => {
    mockPrisma.notificationPreference.findFirst.mockResolvedValue(null);

    expect(await shouldPush()).toBe(true);
  });
});
