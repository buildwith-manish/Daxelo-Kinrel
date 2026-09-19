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
});
