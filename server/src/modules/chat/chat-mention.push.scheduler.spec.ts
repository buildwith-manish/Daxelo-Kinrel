// server/src/modules/chat/chat-mention.push.scheduler.spec.ts
//
// Phase A-5 — quiet hours for mention pushes are evaluated in the RECIPIENT's
// stored NotificationPreference.quietHoursTimezone, not the server clock;
// mute and block are judged per mention (by that mention's own chat/sender).

import { ChatMentionPushScheduler } from './chat-mention.push.scheduler';

describe('ChatMentionPushScheduler — quiet hours', () => {
  const mockPrisma = {
    notificationPreference: { findFirst: jest.fn() },
    chatMessage: { findUnique: jest.fn() },
    chatSettings: { findFirst: jest.fn() },
    blockedUser: { findFirst: jest.fn() },
    chatMention: { findUnique: jest.fn(), update: jest.fn() },
  };
  const scheduler = new ChatMentionPushScheduler(
    mockPrisma as any,
    { sendToUser: jest.fn() } as any,
    { isUserConnected: jest.fn() } as any,
  );

  const shouldPush = (messageId = 'msg-1') =>
    (scheduler as any).shouldPushForRecipient('recipient-1', messageId) as Promise<boolean>;
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
    mockPrisma.chatMessage.findUnique.mockReset().mockResolvedValue({
      familyId: 'fam-1',
      senderId: 'sender-1',
    });
    mockPrisma.blockedUser.findFirst.mockReset().mockResolvedValue(null);
    mockPrisma.chatSettings.findFirst.mockReset().mockResolvedValue(null);
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

describe('ChatMentionPushScheduler — per-mention mute split and block check', () => {
  const mockPrisma = {
    notificationPreference: { findFirst: jest.fn() },
    chatMessage: { findUnique: jest.fn() },
    chatSettings: { findFirst: jest.fn() },
    blockedUser: { findFirst: jest.fn() },
    chatMention: { findUnique: jest.fn(), update: jest.fn() },
  };
  const gateway = { isUserConnected: jest.fn() };
  const scheduler = new ChatMentionPushScheduler(
    mockPrisma as any,
    { sendToUser: jest.fn() } as any,
    gateway as any,
  );
  const shouldPush = (messageId = 'msg-1') =>
    (scheduler as any).shouldPushForRecipient('recipient-1', messageId) as Promise<boolean>;
  const batches = () => (scheduler as any).pendingBatches as Map<string, { mentions: any[]; timer: NodeJS.Timeout }>;
  // No quiet hours configured, so only mute/block decide.
  const pref = (over: Record<string, unknown> = {}) => ({
    quietHoursStart: null,
    quietHoursEnd: null,
    quietHoursTimezone: 'Asia/Kolkata',
    mentionsBreakMute: true,
    ...over,
  });

  beforeEach(() => {
    jest.useFakeTimers();
    mockPrisma.notificationPreference.findFirst.mockReset().mockResolvedValue(pref());
    mockPrisma.chatMessage.findUnique.mockReset().mockResolvedValue({ familyId: 'fam-1', senderId: 'sender-1' });
    mockPrisma.chatSettings.findFirst.mockReset().mockResolvedValue(null);
    mockPrisma.blockedUser.findFirst.mockReset().mockResolvedValue(null);
    mockPrisma.chatMention.findUnique.mockReset();
    mockPrisma.chatMention.update.mockReset().mockResolvedValue({});
    gateway.isUserConnected.mockReset().mockReturnValue(false);
  });
  afterEach(() => {
    for (const b of batches().values()) clearTimeout(b.timer);
    batches().clear();
    jest.useRealTimers();
  });

  describe('mute', () => {
    it('mentionsBreakMute=false and the mention\'s family is muted -> no push; lookup is scoped to that family', async () => {
      mockPrisma.notificationPreference.findFirst.mockResolvedValue(pref({ mentionsBreakMute: false }));
      mockPrisma.chatSettings.findFirst.mockResolvedValue({ id: 's1' });

      expect(await shouldPush()).toBe(false);
      expect(mockPrisma.chatSettings.findFirst).toHaveBeenCalledWith({
        where: { userId: 'recipient-1', familyId: 'fam-1', isMuted: true },
        select: { id: true },
      });
    });

    it('mentionsBreakMute=false but the chat is not muted -> pushes', async () => {
      mockPrisma.notificationPreference.findFirst.mockResolvedValue(pref({ mentionsBreakMute: false }));

      expect(await shouldPush()).toBe(true);
    });

    it('mentionsBreakMute=true (default): a muted chat still pushes and mute is not even looked up', async () => {
      mockPrisma.chatSettings.findFirst.mockResolvedValue({ id: 's1' });

      expect(await shouldPush()).toBe(true);
      expect(mockPrisma.chatSettings.findFirst).not.toHaveBeenCalled();
    });

    it('no preference row behaves as mentionsBreakMute=true', async () => {
      mockPrisma.notificationPreference.findFirst.mockResolvedValue(null);
      mockPrisma.chatSettings.findFirst.mockResolvedValue({ id: 's1' });

      expect(await shouldPush()).toBe(true);
      expect(mockPrisma.chatSettings.findFirst).not.toHaveBeenCalled();
    });

    it('batch split: with mentionsBreakMute=false, a mention from a muted family is dropped (marked notified) while one from an unmuted family is queued', async () => {
      mockPrisma.notificationPreference.findFirst.mockResolvedValue(pref({ mentionsBreakMute: false }));
      mockPrisma.chatMention.findUnique.mockImplementation(async ({ where }: any) => ({
        id: where.id,
        messageId: `msg-${where.id}`,
        mentionedUserId: 'recipient-1',
        mentionedByName: 'Sender',
        groupId: null,
        notify: true,
      }));
      mockPrisma.chatMessage.findUnique.mockImplementation(async ({ where }: any) =>
        where.id === 'msg-m-muted'
          ? { familyId: 'fam-muted', senderId: 'sender-1' }
          : { familyId: 'fam-open', senderId: 'sender-1' },
      );
      mockPrisma.chatSettings.findFirst.mockImplementation(async ({ where }: any) =>
        where.familyId === 'fam-muted' ? { id: 's-muted' } : null,
      );

      await scheduler.enqueueMention('m-muted');
      await scheduler.enqueueMention('m-open');

      expect(batches().get('recipient-1')?.mentions.map((m) => m.mentionId)).toEqual(['m-open']);
      expect(mockPrisma.chatMention.update).toHaveBeenCalledTimes(1);
      expect(mockPrisma.chatMention.update).toHaveBeenCalledWith({
        where: { id: 'm-muted' },
        data: { notifiedAt: expect.any(Date) },
      });
    });

    it('the FIRST mention of a muted chat is dropped too (it used to slip through because the batch was empty when checked)', async () => {
      mockPrisma.notificationPreference.findFirst.mockResolvedValue(pref({ mentionsBreakMute: false }));
      mockPrisma.chatSettings.findFirst.mockResolvedValue({ id: 's1' });
      mockPrisma.chatMention.findUnique.mockResolvedValue({
        id: 'm1',
        messageId: 'msg-1',
        mentionedUserId: 'recipient-1',
        mentionedByName: 'Sender',
        groupId: null,
        notify: true,
      });

      await scheduler.enqueueMention('m1');

      expect(batches().size).toBe(0);
      expect(mockPrisma.chatMention.update).toHaveBeenCalledTimes(1);
    });
  });

  describe('block', () => {
    it('recipient has blocked the sender -> no push; query is (blocker=recipient, blocked=message sender)', async () => {
      mockPrisma.blockedUser.findFirst.mockResolvedValue({ id: 'b1' });

      expect(await shouldPush()).toBe(false);
      expect(mockPrisma.blockedUser.findFirst).toHaveBeenCalledWith({
        where: { blockerId: 'recipient-1', blockedId: 'sender-1' },
        select: { id: true },
      });
    });

    it('block wins even when mentionsBreakMute is true', async () => {
      mockPrisma.notificationPreference.findFirst.mockResolvedValue(pref({ mentionsBreakMute: true }));
      mockPrisma.blockedUser.findFirst.mockResolvedValue({ id: 'b1' });

      expect(await shouldPush()).toBe(false);
    });

    it('no block row -> pushes', async () => {
      expect(await shouldPush()).toBe(true);
    });
  });

  describe('fail-closed', () => {
    it('mention whose message cannot be found -> no push', async () => {
      mockPrisma.chatMessage.findUnique.mockResolvedValue(null);

      expect(await shouldPush()).toBe(false);
      expect(mockPrisma.blockedUser.findFirst).not.toHaveBeenCalled();
    });

    it('a lookup error -> no push', async () => {
      mockPrisma.blockedUser.findFirst.mockRejectedValue(new Error('db down'));

      expect(await shouldPush()).toBe(false);
    });
  });
});
