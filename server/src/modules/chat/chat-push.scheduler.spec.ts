import { Test, TestingModule } from '@nestjs/testing';
import { ChatPushScheduler } from './chat-push.scheduler';
import { PrismaService } from '../../prisma/prisma.service';
import { FcmService } from '../notifications/fcm.service';

/**
 * ChatPushScheduler unit tests.
 *
 * Verifies the batched-push cron logic:
 *   • No un-notified messages → no-op
 *   • Messages younger than 2 minutes → skipped (grace period)
 *   • Recipients who already read the message → not notified
 *   • Sender is never a recipient of their own message
 *   • Multiple messages from same sender to same recipient → ONE batched push
 *   • Messages are marked notified=true after the push (even if FCM fails)
 *   • In-app Notification row is created as a fallback
 */
describe('ChatPushScheduler', () => {
  let scheduler: ChatPushScheduler;

  const mockPrisma = {
    chatMessage: {
      findMany: jest.fn(),
      updateMany: jest.fn(),
    },
    familyMember: { findMany: jest.fn() },
    groupMember: { findMany: jest.fn() },
    family: { findUnique: jest.fn() },
    notification: { create: jest.fn() },
  };

  const mockFcm = {
    sendToUser: jest.fn(),
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        ChatPushScheduler,
        { provide: PrismaService, useValue: mockPrisma },
        { provide: FcmService, useValue: mockFcm },
      ],
    }).compile();
    scheduler = module.get<ChatPushScheduler>(ChatPushScheduler);
    jest.clearAllMocks();
  });

  it('is defined', () => {
    expect(scheduler).toBeDefined();
  });

  it('does nothing when there are no un-notified messages', async () => {
    mockPrisma.chatMessage.findMany.mockResolvedValue([]);
    await scheduler.handleBatchedPush();
    expect(mockFcm.sendToUser).not.toHaveBeenCalled();
    expect(mockPrisma.chatMessage.updateMany).not.toHaveBeenCalled();
  });

  it('skips recipients who already read the message', async () => {
    // Message was read by user-2 (the only other family member) → no push.
    mockPrisma.chatMessage.findMany.mockResolvedValue([
      {
        id: 'msg-1',
        familyId: 'fam-1',
        senderId: 'user-1',
        senderName: 'Manish',
        content: 'hello',
        createdAt: new Date(Date.now() - 10 * 60 * 1000), // 10 min ago
        readBy: ['user-2'],
      },
    ]);
    mockPrisma.familyMember.findMany.mockResolvedValue([
      { userId: 'user-1' }, // sender
      { userId: 'user-2' }, // reader
    ]);
    mockPrisma.family.findUnique.mockResolvedValue({ name: 'Sharmas' });
    mockPrisma.chatMessage.updateMany.mockResolvedValue({ count: 1 });

    await scheduler.handleBatchedPush();

    // No push sent (everyone already read it)
    expect(mockFcm.sendToUser).not.toHaveBeenCalled();
    // But message IS marked notified (so we don't re-process)
    expect(mockPrisma.chatMessage.updateMany).toHaveBeenCalledWith({
      where: { id: { in: ['msg-1'] } },
      data: expect.objectContaining({ notified: true }),
    });
  });

  it('never notifies the sender of their own message', async () => {
    mockPrisma.chatMessage.findMany.mockResolvedValue([
      {
        id: 'msg-1',
        familyId: 'fam-1',
        senderId: 'user-1',
        senderName: 'Manish',
        content: 'hello',
        createdAt: new Date(Date.now() - 10 * 60 * 1000),
        readBy: [],
      },
    ]);
    mockPrisma.familyMember.findMany.mockResolvedValue([
      { userId: 'user-1' }, // sender only
    ]);
    mockPrisma.family.findUnique.mockResolvedValue({ name: 'Sharmas' });
    mockPrisma.chatMessage.updateMany.mockResolvedValue({ count: 1 });

    await scheduler.handleBatchedPush();

    // Sender is the only member → no push
    expect(mockFcm.sendToUser).not.toHaveBeenCalled();
    expect(mockPrisma.chatMessage.updateMany).toHaveBeenCalledWith({
      where: { id: { in: ['msg-1'] } },
      data: expect.objectContaining({ notified: true }),
    });
  });

  it('batches multiple messages from same sender to same recipient into ONE push', async () => {
    mockPrisma.chatMessage.findMany.mockResolvedValue([
      {
        id: 'msg-1',
        familyId: 'fam-1',
        senderId: 'user-1',
        senderName: 'Manish',
        content: 'first message',
        createdAt: new Date(Date.now() - 10 * 60 * 1000),
        readBy: [],
      },
      {
        id: 'msg-2',
        familyId: 'fam-1',
        senderId: 'user-1',
        senderName: 'Manish',
        content: 'second message',
        createdAt: new Date(Date.now() - 9 * 60 * 1000),
        readBy: [],
      },
      {
        id: 'msg-3',
        familyId: 'fam-1',
        senderId: 'user-1',
        senderName: 'Manish',
        content: 'third message',
        createdAt: new Date(Date.now() - 8 * 60 * 1000),
        readBy: [],
      },
    ]);
    mockPrisma.familyMember.findMany.mockResolvedValue([
      { userId: 'user-1' }, // sender
      { userId: 'user-2' }, // recipient
    ]);
    mockPrisma.family.findUnique.mockResolvedValue({ name: 'Sharmas' });
    mockFcm.sendToUser.mockResolvedValue(true);
    mockPrisma.notification.create.mockResolvedValue({});
    mockPrisma.chatMessage.updateMany.mockResolvedValue({ count: 3 });

    await scheduler.handleBatchedPush();

    // Exactly ONE push for the 3 messages (single chat, single recipient)
    expect(mockFcm.sendToUser).toHaveBeenCalledTimes(1);
    const pushArgs = mockFcm.sendToUser.mock.calls[0];
    expect(pushArgs[0]).toBe('user-2'); // recipient
    // Feature 2: single-chat multi-message format is
    // "Manish sent 3 messages in Sharmas"
    expect(pushArgs[1].title).toContain('3 messages');
    expect(pushArgs[1].title).toContain('Manish');
    expect(pushArgs[1].body).toContain('3 new messages');
    // Data payload includes the count + deep link
    expect(pushArgs[1].data.messageCount).toBe('3');
    expect(pushArgs[1].data.familyId).toBe('fam-1');
    expect(pushArgs[1].data.actionUrl).toContain('fam-1');
    expect(pushArgs[1].data.actionUrl).toContain('/chat');

    // All 3 messages marked notified (order may vary — sorted by createdAt desc)
    expect(mockPrisma.chatMessage.updateMany).toHaveBeenCalledWith({
      where: { id: { in: expect.arrayContaining(['msg-1', 'msg-2', 'msg-3']) } },
      data: expect.objectContaining({ notified: true }),
    });
  });

  it('creates an in-app Notification row as a fallback', async () => {
    mockPrisma.chatMessage.findMany.mockResolvedValue([
      {
        id: 'msg-1',
        familyId: 'fam-1',
        senderId: 'user-1',
        senderName: 'Manish',
        content: 'hello',
        createdAt: new Date(Date.now() - 10 * 60 * 1000),
        readBy: [],
      },
    ]);
    mockPrisma.familyMember.findMany.mockResolvedValue([
      { userId: 'user-1' },
      { userId: 'user-2' },
    ]);
    mockPrisma.family.findUnique.mockResolvedValue({ name: 'Sharmas' });
    mockFcm.sendToUser.mockResolvedValue(true);
    mockPrisma.notification.create.mockResolvedValue({});
    mockPrisma.chatMessage.updateMany.mockResolvedValue({ count: 1 });

    await scheduler.handleBatchedPush();

    expect(mockPrisma.notification.create).toHaveBeenCalledTimes(1);
    const notifArgs = mockPrisma.notification.create.mock.calls[0][0];
    expect(notifArgs.data.userId).toBe('user-2');
    expect(notifArgs.data.eventType).toBe('chat_message');
    expect(notifArgs.data.familyId).toBe('fam-1');
    expect(notifArgs.data.actionUrl).toContain('fam-1');
  });

  it('marks messages notified=true even if FCM fails (no re-push on next run)', async () => {
    mockPrisma.chatMessage.findMany.mockResolvedValue([
      {
        id: 'msg-1',
        familyId: 'fam-1',
        senderId: 'user-1',
        senderName: 'Manish',
        content: 'hello',
        createdAt: new Date(Date.now() - 10 * 60 * 1000),
        readBy: [],
      },
    ]);
    mockPrisma.familyMember.findMany.mockResolvedValue([
      { userId: 'user-1' },
      { userId: 'user-2' },
    ]);
    mockPrisma.family.findUnique.mockResolvedValue({ name: 'Sharmas' });
    // FCM fails (e.g. no tokens registered, or Firebase down)
    mockFcm.sendToUser.mockResolvedValue(false);
    mockPrisma.notification.create.mockResolvedValue({});
    mockPrisma.chatMessage.updateMany.mockResolvedValue({ count: 1 });

    await scheduler.handleBatchedPush();

    // Still marked notified — in-app notification is the fallback
    expect(mockPrisma.chatMessage.updateMany).toHaveBeenCalledWith({
      where: { id: { in: ['msg-1'] } },
      data: expect.objectContaining({ notified: true }),
    });
  });

  it('handles multiple families + multiple recipients in one batch', async () => {
    mockPrisma.chatMessage.findMany.mockResolvedValue([
      {
        id: 'msg-a',
        familyId: 'fam-1',
        senderId: 'user-1',
        senderName: 'Manish',
        content: 'hi fam1',
        createdAt: new Date(Date.now() - 10 * 60 * 1000),
        readBy: [],
      },
      {
        id: 'msg-b',
        familyId: 'fam-2',
        senderId: 'user-3',
        senderName: 'Riya',
        content: 'hi fam2',
        createdAt: new Date(Date.now() - 10 * 60 * 1000),
        readBy: [],
      },
    ]);
    mockPrisma.familyMember.findMany.mockImplementation((args: any) => {
      if (args.where.familyId === 'fam-1') {
        return Promise.resolve([{ userId: 'user-1' }, { userId: 'user-2' }]);
      }
      return Promise.resolve([{ userId: 'user-3' }, { userId: 'user-4' }]);
    });
    mockPrisma.family.findUnique.mockImplementation((args: any) => {
      if (args.where.id === 'fam-1') return Promise.resolve({ name: 'Sharmas' });
      return Promise.resolve({ name: 'Patels' });
    });
    mockFcm.sendToUser.mockResolvedValue(true);
    mockPrisma.notification.create.mockResolvedValue({});
    mockPrisma.chatMessage.updateMany.mockResolvedValue({ count: 2 });

    await scheduler.handleBatchedPush();

    // Two separate pushes (one per recipient — each is in a different family)
    expect(mockFcm.sendToUser).toHaveBeenCalledTimes(2);
    const recipients = mockFcm.sendToUser.mock.calls.map((c) => c[0]);
    expect(recipients).toContain('user-2');
    expect(recipients).toContain('user-4');
  });

  it('Feature 2: groups messages across MULTIPLE chats for the SAME recipient into ONE push', async () => {
    // user-2 is a member of BOTH fam-1 and fam-2. With cross-chat grouping,
    // they should get ONE push summarizing messages from both chats.
    const tenMinAgo = new Date(Date.now() - 10 * 60 * 1000);
    const eightMinAgo = new Date(Date.now() - 8 * 60 * 1000);
    mockPrisma.chatMessage.findMany.mockResolvedValue([
      {
        id: 'msg-a',
        familyId: 'fam-1',
        senderId: 'user-1',
        senderName: 'Manish',
        content: 'hi from Sharmas',
        createdAt: tenMinAgo,
        readBy: [],
      },
      {
        id: 'msg-b',
        familyId: 'fam-2',
        senderId: 'user-3',
        senderName: 'Riya',
        content: 'hi from Patels',
        createdAt: eightMinAgo, // more recent
        readBy: [],
      },
    ]);
    // user-2 is a member of BOTH families
    mockPrisma.familyMember.findMany.mockImplementation((args: any) => {
      if (args.where.familyId === 'fam-1') {
        return Promise.resolve([
          { userId: 'user-1' }, // sender
          { userId: 'user-2' }, // shared recipient
        ]);
      }
      return Promise.resolve([
        { userId: 'user-3' }, // sender
        { userId: 'user-2' }, // same recipient, different family
      ]);
    });
    mockPrisma.family.findUnique.mockImplementation((args: any) => {
      if (args.where.id === 'fam-1') return Promise.resolve({ name: 'Sharmas' });
      return Promise.resolve({ name: 'Patels' });
    });
    mockFcm.sendToUser.mockResolvedValue(true);
    mockPrisma.notification.create.mockResolvedValue({});
    mockPrisma.chatMessage.updateMany.mockResolvedValue({ count: 2 });

    await scheduler.handleBatchedPush();

    // ONE push to user-2 (NOT one per family)
    expect(mockFcm.sendToUser).toHaveBeenCalledTimes(1);
    const pushArgs = mockFcm.sendToUser.mock.calls[0];
    expect(pushArgs[0]).toBe('user-2');
    // Cross-chat format: "2 new messages from Riya and 1 other"
    expect(pushArgs[1].title).toContain('2 new messages');
    expect(pushArgs[1].body).toContain('2 chats');
    // Deep-link points to the chat with the most recent message (fam-2)
    expect(pushArgs[1].data.familyId).toBe('fam-2');
    expect(pushArgs[1].data.actionUrl).toContain('fam-2');
    expect(pushArgs[1].data.distinctChats).toBe('2');

    // Both messages marked notified (order may vary)
    expect(mockPrisma.chatMessage.updateMany).toHaveBeenCalledWith({
      where: { id: { in: expect.arrayContaining(['msg-a', 'msg-b']) } },
      data: expect.objectContaining({ notified: true }),
    });
  });

  // ── DM Rebuild — STOP ITEM 1 fix (groupId privacy) ───────────────────
  //
  // A message with `groupId` set is a direct chat or a private group
  // chat. It must only notify the OTHER group members — NOT every member
  // of the family. The family-wide FamilyMember lookup must be skipped
  // for these rows, and the recipient cache must be keyed by groupId so
  // group and family recipients are never mixed. Sender-skip + readBy-skip
  // still apply.

  it('notifies only the OTHER group members for a groupId-scoped message (not the whole family)', async () => {
    // direct-group message: groupId='grp-dm-1', family='fam-1'.
    // The family has 3 members (user-1 sender, user-2 group member,
    // user-3 NOT in the group). Only user-2 should be notified.
    mockPrisma.chatMessage.findMany.mockResolvedValue([
      {
        id: 'msg-dm-1',
        familyId: 'fam-1',
        groupId: 'grp-dm-1',
        senderId: 'user-1',
        senderName: 'Manish',
        content: 'private hi',
        createdAt: new Date(Date.now() - 10 * 60 * 1000),
        readBy: [],
      },
    ]);
    // GroupMember lookup for grp-dm-1 returns only user-1 + user-2.
    mockPrisma.groupMember.findMany.mockResolvedValue([
      { userId: 'user-1' }, // sender (will be skipped)
      { userId: 'user-2' }, // sole recipient
    ]);
    // FamilyMember lookup should NOT be called for a groupId-scoped msg.
    mockPrisma.familyMember.findMany.mockResolvedValue([
      { userId: 'user-1' },
      { userId: 'user-2' },
      { userId: 'user-3' }, // would leak — must never be reached
    ]);
    mockPrisma.family.findUnique.mockResolvedValue({ name: 'Sharmas' });
    mockFcm.sendToUser.mockResolvedValue(true);
    mockPrisma.notification.create.mockResolvedValue({});
    mockPrisma.chatMessage.updateMany.mockResolvedValue({ count: 1 });

    await scheduler.handleBatchedPush();

    // Recipient resolution branched on groupId → groupMember.findMany
    // was called with that groupId, familyMember.findMany was NOT called.
    expect(mockPrisma.groupMember.findMany).toHaveBeenCalledWith({
      where: { groupId: 'grp-dm-1' },
      select: { userId: true },
    });
    expect(mockPrisma.familyMember.findMany).not.toHaveBeenCalled();

    // Exactly ONE push — only user-2 (the other group member).
    expect(mockFcm.sendToUser).toHaveBeenCalledTimes(1);
    expect(mockFcm.sendToUser.mock.calls[0][0]).toBe('user-2');

    // user-3 (family member but NOT group member) got NO push, NO in-app
    // Notification row. There is exactly ONE notification.create call and
    // it targets user-2.
    expect(mockPrisma.notification.create).toHaveBeenCalledTimes(1);
    expect(mockPrisma.notification.create.mock.calls[0][0].data.userId).toBe(
      'user-2',
    );
  });

  it('still notifies the whole family for a family-wide (groupId = null) message', async () => {
    // Family-wide message: groupId=null. Everyone in the family except
    // the sender should be notified. This is the pre-DM-rebuild behavior
    // and MUST still work after the fix.
    mockPrisma.chatMessage.findMany.mockResolvedValue([
      {
        id: 'msg-fam-1',
        familyId: 'fam-1',
        groupId: null,
        senderId: 'user-1',
        senderName: 'Manish',
        content: 'hi family',
        createdAt: new Date(Date.now() - 10 * 60 * 1000),
        readBy: [],
      },
    ]);
    mockPrisma.familyMember.findMany.mockResolvedValue([
      { userId: 'user-1' }, // sender (skipped)
      { userId: 'user-2' },
      { userId: 'user-3' },
    ]);
    // groupMember.findMany should NOT be called for a family-wide msg.
    mockPrisma.groupMember.findMany.mockResolvedValue([]);
    mockPrisma.family.findUnique.mockResolvedValue({ name: 'Sharmas' });
    mockFcm.sendToUser.mockResolvedValue(true);
    mockPrisma.notification.create.mockResolvedValue({});
    mockPrisma.chatMessage.updateMany.mockResolvedValue({ count: 1 });

    await scheduler.handleBatchedPush();

    // Family-wide resolution was used.
    expect(mockPrisma.familyMember.findMany).toHaveBeenCalledWith({
      where: { familyId: 'fam-1' },
      select: { userId: true },
    });
    expect(mockPrisma.groupMember.findMany).not.toHaveBeenCalled();

    // Two pushes: user-2 and user-3 (everyone except the sender).
    expect(mockFcm.sendToUser).toHaveBeenCalledTimes(2);
    const recipients = mockFcm.sendToUser.mock.calls.map((c) => c[0]);
    expect(recipients).toEqual(expect.arrayContaining(['user-2', 'user-3']));
    expect(recipients).not.toContain('user-1');
  });

  it('never notifies the sender of their own groupId-scoped message', async () => {
    // Direct group with ONLY the sender as a member (no other recipients).
    // No push should go out, but the message should still be marked
    // notified so we don't re-process next run.
    mockPrisma.chatMessage.findMany.mockResolvedValue([
      {
        id: 'msg-solo',
        familyId: 'fam-1',
        groupId: 'grp-solo',
        senderId: 'user-1',
        senderName: 'Manish',
        content: 'hello myself',
        createdAt: new Date(Date.now() - 10 * 60 * 1000),
        readBy: [],
      },
    ]);
    mockPrisma.groupMember.findMany.mockResolvedValue([
      { userId: 'user-1' }, // sender only
    ]);
    mockPrisma.family.findUnique.mockResolvedValue({ name: 'Sharmas' });
    mockPrisma.chatMessage.updateMany.mockResolvedValue({ count: 1 });

    await scheduler.handleBatchedPush();

    expect(mockFcm.sendToUser).not.toHaveBeenCalled();
    // Still marked notified so we don't re-evaluate next run.
    expect(mockPrisma.chatMessage.updateMany).toHaveBeenCalledWith({
      where: { id: { in: ['msg-solo'] } },
      data: expect.objectContaining({ notified: true }),
    });
  });

  it('keys the recipient cache by groupId so group and family recipients are never mixed', async () => {
    // Two messages from the same sender in the same family, but one is
    // group-scoped (groupId='grp-dm-1', members: user-1, user-2) and the
    // other is family-wide (groupId=null, members: user-1, user-2, user-3).
    // The cache MUST distinguish `group:grp-dm-1` from `family:fam-1`
    // so user-3 doesn't receive the group message and user-2 doesn't
    // receive a duplicate family lookup. Each lookup must run exactly
    // once, and the family lookup must NOT be used for the group message.
    const tenMinAgo = new Date(Date.now() - 10 * 60 * 1000);
    mockPrisma.chatMessage.findMany.mockResolvedValue([
      {
        id: 'msg-group',
        familyId: 'fam-1',
        groupId: 'grp-dm-1',
        senderId: 'user-1',
        senderName: 'Manish',
        content: 'group hi',
        createdAt: tenMinAgo,
        readBy: [],
      },
      {
        id: 'msg-family',
        familyId: 'fam-1',
        groupId: null,
        senderId: 'user-1',
        senderName: 'Manish',
        content: 'family hi',
        createdAt: tenMinAgo,
        readBy: [],
      },
    ]);
    mockPrisma.groupMember.findMany.mockResolvedValue([
      { userId: 'user-1' },
      { userId: 'user-2' },
    ]);
    mockPrisma.familyMember.findMany.mockResolvedValue([
      { userId: 'user-1' },
      { userId: 'user-2' },
      { userId: 'user-3' },
    ]);
    mockPrisma.family.findUnique.mockResolvedValue({ name: 'Sharmas' });
    mockFcm.sendToUser.mockResolvedValue(true);
    mockPrisma.notification.create.mockResolvedValue({});
    mockPrisma.chatMessage.updateMany.mockResolvedValue({ count: 2 });

    await scheduler.handleBatchedPush();

    // Each lookup ran exactly once — the cache did NOT collapse the two
    // scopes into a single entry.
    expect(mockPrisma.groupMember.findMany).toHaveBeenCalledTimes(1);
    expect(mockPrisma.familyMember.findMany).toHaveBeenCalledTimes(1);

    // Recipients: user-2 receives BOTH messages (they're in the group AND
    // the family). user-3 receives ONLY the family message. user-1 (the
    // sender) receives neither.
    const recipients = mockFcm.sendToUser.mock.calls.map((c) => c[0]);
    // user-2 appears once (cross-chat grouping: one push for both messages)
    // user-3 appears once (only the family message)
    expect(recipients).toEqual(expect.arrayContaining(['user-2', 'user-3']));
    expect(recipients).not.toContain('user-1');

    // The single user-2 push should reference BOTH messages (cross-chat
    // grouping across the group + family). user-3's push references only
    // the family message.
    const user2Call = mockFcm.sendToUser.mock.calls.find((c) => c[0] === 'user-2');
    const user3Call = mockFcm.sendToUser.mock.calls.find((c) => c[0] === 'user-3');
    expect(user2Call).toBeDefined();
    expect(user3Call).toBeDefined();
    // user-2's push covers 2 messages, user-3's push covers 1.
    expect(user2Call![1].data.messageCount).toBe('2');
    expect(user3Call![1].data.messageCount).toBe('1');

    // user-3 got NO notification row for the group message — only one
    // notification.create call total per recipient (user-2 once, user-3
    // once) → 2 calls.
    expect(mockPrisma.notification.create).toHaveBeenCalledTimes(2);
    const notifRecipients = mockPrisma.notification.create.mock.calls.map(
      (c) => c[0].data.userId,
    );
    expect(notifRecipients).toEqual(
      expect.arrayContaining(['user-2', 'user-3']),
    );
  });
});
