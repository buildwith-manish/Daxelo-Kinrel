import { Test, TestingModule } from '@nestjs/testing';
import { ChatService } from './chat.service';
import { StreakService } from './streak.service';
import { PrismaService } from '../../prisma/prisma.service';
import { ForbiddenException, NotFoundException } from '@nestjs/common';

/**
 * ChatService unit tests.
 *
 * Mocks PrismaService so these tests run without a database. Verifies:
 *   • Membership enforcement (assertMember throws for non-members)
 *   • sendMessage resolves sender display name + initials, persists with
 *     the right fields, and links replyTo parent fields.
 *   • markAsRead inserts ChatReadReceipt rows, updates the denormalized
 *     readBy/readAt cache, and skips the user's own messages.
 *   • addReaction is idempotent (returns alreadyExists on P2002) and
 *     enforces family-scoped message ownership.
 *   • removeReaction returns deleted=false when nothing was removed.
 *   • getReactionCounts groups by emoji and sorts by count desc.
 *   • setTypingStatus upserts the typing row.
 *   • getTypingUsers filters out rows older than 5 seconds.
 */
describe('ChatService', () => {
  let service: ChatService;

  const mockPrisma = {
    familyMember: { findUnique: jest.fn(), findMany: jest.fn() },
    family: { findUnique: jest.fn() },
    user: { findUnique: jest.fn(), findMany: jest.fn() },
    person: { findMany: jest.fn() },
    chatMessage: {
      findUnique: jest.fn(),
      findMany: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
      updateMany: jest.fn(),
      count: jest.fn(),
    },
    chatReadReceipt: { createMany: jest.fn() },
    chatTypingStatus: { upsert: jest.fn(), findMany: jest.fn() },
    chatReaction: { create: jest.fn(), deleteMany: jest.fn(), findMany: jest.fn() },
  };

  const mockStreakService = {
    recordMessage: jest.fn(),
    getStreak: jest.fn(),
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        ChatService,
        { provide: PrismaService, useValue: mockPrisma },
        { provide: StreakService, useValue: mockStreakService },
      ],
    }).compile();
    service = module.get<ChatService>(ChatService);
    jest.clearAllMocks();
  });

  describe('sendMessage', () => {
    it('throws ForbiddenException for non-members', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue(null);
      await expect(
        service.sendMessage('fam-1', 'user-1', 'hello'),
      ).rejects.toBeInstanceOf(ForbiddenException);
    });

    it('persists a message with sender display name + initials', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue({ id: 'fm-1' });
      mockPrisma.user.findUnique.mockResolvedValue({
        id: 'user-1',
        name: 'Manish Sharma',
        username: 'manish08',
        avatarUrl: null,
      });
      const created = { id: 'cm_1', senderName: 'Manish Sharma' };
      mockPrisma.chatMessage.create.mockResolvedValue(created);

      const result = await service.sendMessage('fam-1', 'user-1', 'hello');

      expect(result).toEqual(created);
      const createArgs = mockPrisma.chatMessage.create.mock.calls[0][0];
      expect(createArgs.data.senderName).toBe('Manish Sharma');
      expect(createArgs.data.senderInitials).toBe('MS');
      expect(createArgs.data.messageStatus).toBe('sent');
      expect(createArgs.data.readBy).toEqual([]);
      expect(createArgs.data.notified).toBe(false);
      expect(createArgs.data.id).toMatch(/^cm_\d+_/);
    });

    it('rejects replyToId pointing to a different family', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue({ id: 'fm-1' });
      mockPrisma.user.findUnique.mockResolvedValue({ id: 'user-1', name: 'Manish' });
      mockPrisma.chatMessage.findUnique.mockResolvedValue({
        familyId: 'different-fam',
        content: 'hi',
        senderName: 'X',
      });
      await expect(
        service.sendMessage('fam-1', 'user-1', 'reply', { replyToId: 'msg-1' }),
      ).rejects.toBeInstanceOf(ForbiddenException);
    });

    it('throws NotFoundException when replyToId does not exist', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue({ id: 'fm-1' });
      mockPrisma.user.findUnique.mockResolvedValue({ id: 'user-1', name: 'Manish' });
      mockPrisma.chatMessage.findUnique.mockResolvedValue(null);
      await expect(
        service.sendMessage('fam-1', 'user-1', 'reply', { replyToId: 'missing' }),
      ).rejects.toBeInstanceOf(NotFoundException);
    });
  });

  describe('markAsRead', () => {
    it('returns empty arrays when no unread messages', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue({ id: 'fm-1' });
      mockPrisma.chatMessage.findMany.mockResolvedValue([]);
      const result = await service.markAsRead('fam-1', 'user-2');
      expect(result).toEqual({ markedReadIds: [], senderIds: [] });
    });

    it('skips the user own messages and marks others read', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue({ id: 'fm-1' });
      mockPrisma.chatMessage.findMany.mockResolvedValue([
        { id: 'msg-1', senderId: 'user-1' },
        { id: 'msg-2', senderId: 'user-1' },
        { id: 'msg-3', senderId: 'user-3' },
      ]);
      mockPrisma.chatReadReceipt.createMany.mockResolvedValue({ count: 3 });
      mockPrisma.chatMessage.update.mockResolvedValue({});

      const result = await service.markAsRead('fam-1', 'user-2');

      expect(result.markedReadIds).toEqual(['msg-1', 'msg-2', 'msg-3']);
      expect(result.senderIds).toEqual(['user-1', 'user-3']);
      expect(mockPrisma.chatReadReceipt.createMany).toHaveBeenCalledTimes(1);
      // 3 distinct message updates
      expect(mockPrisma.chatMessage.update).toHaveBeenCalledTimes(3);
      // Verify push semantics — readBy array gets the userId appended
      const updateCall = mockPrisma.chatMessage.update.mock.calls[0][0];
      expect(updateCall.data.readBy).toEqual({ push: 'user-2' });
      expect(updateCall.data.messageStatus).toBe('read');
    });

    it('scopes to a single messageId when given', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue({ id: 'fm-1' });
      mockPrisma.chatMessage.findMany.mockResolvedValue([
        { id: 'msg-1', senderId: 'user-1' },
      ]);
      mockPrisma.chatReadReceipt.createMany.mockResolvedValue({ count: 1 });
      mockPrisma.chatMessage.update.mockResolvedValue({});

      await service.markAsRead('fam-1', 'user-2', 'msg-1');

      const findArgs = mockPrisma.chatMessage.findMany.mock.calls[0][0];
      expect(findArgs.where.id).toBe('msg-1');
    });
  });

  describe('addReaction', () => {
    it('creates a reaction and returns action=added', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue({ id: 'fm-1' });
      mockPrisma.chatMessage.findUnique.mockResolvedValue({ familyId: 'fam-1' });
      mockPrisma.chatReaction.create.mockResolvedValue({ id: 'cr-1' });

      const result = await service.addReaction('fam-1', 'user-1', {
        messageId: 'msg-1',
        emoji: '❤️',
      });
      expect(result.action).toBe('added');
    });

    it('returns action=alreadyExists on P2002 unique violation (idempotent)', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue({ id: 'fm-1' });
      mockPrisma.chatMessage.findUnique.mockResolvedValue({ familyId: 'fam-1' });
      const err = Object.assign(new Error('dup'), { code: 'P2002' });
      mockPrisma.chatReaction.create.mockRejectedValue(err);

      const result = await service.addReaction('fam-1', 'user-1', {
        messageId: 'msg-1',
        emoji: '❤️',
      });
      expect(result.action).toBe('alreadyExists');
    });

    it('throws ForbiddenException if message belongs to another family', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue({ id: 'fm-1' });
      mockPrisma.chatMessage.findUnique.mockResolvedValue({ familyId: 'fam-other' });
      await expect(
        service.addReaction('fam-1', 'user-1', { messageId: 'msg-1', emoji: '❤️' }),
      ).rejects.toBeInstanceOf(ForbiddenException);
    });
  });

  describe('removeReaction', () => {
    it('returns deleted=true when a row was removed', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue({ id: 'fm-1' });
      mockPrisma.chatReaction.deleteMany.mockResolvedValue({ count: 1 });
      const result = await service.removeReaction('fam-1', 'user-1', {
        messageId: 'msg-1',
        emoji: '❤️',
      });
      expect(result.deleted).toBe(true);
    });

    it('returns deleted=false when nothing was removed', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue({ id: 'fm-1' });
      mockPrisma.chatReaction.deleteMany.mockResolvedValue({ count: 0 });
      const result = await service.removeReaction('fam-1', 'user-1', {
        messageId: 'msg-1',
        emoji: '❤️',
      });
      expect(result.deleted).toBe(false);
    });
  });

  describe('getReactionCounts', () => {
    it('groups by emoji and sorts by count desc', async () => {
      mockPrisma.chatReaction.findMany.mockResolvedValue([
        { emoji: '❤️', userId: 'u1' },
        { emoji: '❤️', userId: 'u2' },
        { emoji: '😂', userId: 'u3' },
        { emoji: '❤️', userId: 'u4' },
        { emoji: '🎉', userId: 'u5' },
      ]);
      const result = await service.getReactionCounts('msg-1');
      expect(result).toEqual([
        { emoji: '❤️', count: 3, userIds: ['u1', 'u2', 'u4'] },
        { emoji: '😂', count: 1, userIds: ['u3'] },
        { emoji: '🎉', count: 1, userIds: ['u5'] },
      ]);
    });

    it('returns empty array when no reactions', async () => {
      mockPrisma.chatReaction.findMany.mockResolvedValue([]);
      const result = await service.getReactionCounts('msg-1');
      expect(result).toEqual([]);
    });
  });

  describe('setTypingStatus', () => {
    it('upserts the typing row', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue({ id: 'fm-1' });
      mockPrisma.chatTypingStatus.upsert.mockResolvedValue({});
      await service.setTypingStatus('fam-1', 'user-1', true);
      const args = mockPrisma.chatTypingStatus.upsert.mock.calls[0][0];
      expect(args.where.id).toBe('cts_fam-1_user-1');
      expect(args.update.isTyping).toBe(true);
    });
  });

  describe('getTypingUsers', () => {
    it('filters out stale rows + resolves display names', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue({ id: 'fm-1' });
      const recent = new Date();
      mockPrisma.chatTypingStatus.findMany.mockResolvedValue([
        { userId: 'u2', updatedAt: recent },
      ]);
      mockPrisma.user.findMany.mockResolvedValue([{ id: 'u2', name: 'Riya' }]);

      const result = await service.getTypingUsers('fam-1', 'u1');
      expect(result).toEqual([
        { userId: 'u2', name: 'Riya', updatedAt: recent },
      ]);
    });

    it('returns empty array when no one is typing', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue({ id: 'fm-1' });
      mockPrisma.chatTypingStatus.findMany.mockResolvedValue([]);
      const result = await service.getTypingUsers('fam-1', 'u1');
      expect(result).toEqual([]);
    });
  });

  describe('listMessages', () => {
    it('returns messages newest first with reactions included', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue({ id: 'fm-1' });
      const msgs = [{ id: 'msg-1', reactions: [] }];
      mockPrisma.chatMessage.findMany.mockResolvedValue(msgs);
      const result = await service.listMessages('fam-1', 'user-1', 50);
      expect(result).toBe(msgs);
      const args = mockPrisma.chatMessage.findMany.mock.calls[0][0];
      expect(args.orderBy).toEqual({ createdAt: 'desc' });
      expect(args.include).toEqual({ reactions: true });
      expect(args.where.isDeletedForEveryone).toBe(false);
    });

    it('caps limit at 200 to prevent abuse', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue({ id: 'fm-1' });
      mockPrisma.chatMessage.findMany.mockResolvedValue([]);
      await service.listMessages('fam-1', 'user-1', 1000);
      const args = mockPrisma.chatMessage.findMany.mock.calls[0][0];
      expect(args.take).toBe(200);
    });
  });

  // ── Feature 1: delivery status ──────────────────────────────────────────

  describe('markDelivered', () => {
    it('updates messageStatus from sent to delivered', async () => {
      mockPrisma.chatMessage.updateMany.mockResolvedValue({ count: 1 });
      await service.markDelivered('msg-1', 'user-2');
      const args = mockPrisma.chatMessage.updateMany.mock.calls[0][0];
      expect(args.where.id).toBe('msg-1');
      expect(args.where.messageStatus).toBe('sent'); // guard against downgrade
      expect(args.data.messageStatus).toBe('delivered');
    });

    it('is idempotent — calling twice does not throw', async () => {
      mockPrisma.chatMessage.updateMany.mockResolvedValue({ count: 0 }); // already delivered
      await expect(service.markDelivered('msg-1', 'user-2')).resolves.toBeUndefined();
    });
  });

  describe('getMessageSender', () => {
    it('returns senderId + familyId for an active message', async () => {
      mockPrisma.chatMessage.findUnique.mockResolvedValue({
        senderId: 'user-1',
        familyId: 'fam-1',
        isDeletedForEveryone: false,
      });
      const result = await service.getMessageSender('msg-1');
      expect(result).toEqual({ senderId: 'user-1', familyId: 'fam-1' });
    });

    it('returns null for a deleted-for-everyone message', async () => {
      mockPrisma.chatMessage.findUnique.mockResolvedValue({
        senderId: 'user-1',
        familyId: 'fam-1',
        isDeletedForEveryone: true,
      });
      const result = await service.getMessageSender('msg-1');
      expect(result).toBeNull();
    });

    it('returns null when the message does not exist', async () => {
      mockPrisma.chatMessage.findUnique.mockResolvedValue(null);
      const result = await service.getMessageSender('msg-missing');
      expect(result).toBeNull();
    });
  });

  // ── Feature 3: empty-state nudge ───────────────────────────────────────

  describe('getEmptyStateNudge', () => {
    it('returns familyName + memberCount + suggestions', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue({ id: 'fm-1' });
      mockPrisma.family.findUnique.mockResolvedValue({ name: 'Sharmas' });
      mockPrisma.familyMember.findMany.mockResolvedValue([
        { userId: 'user-1', user: { id: 'user-1', name: 'Manish' } },
      ]);
      mockPrisma.person.findMany.mockResolvedValue([]); // no upcoming birthdays

      const result = await service.getEmptyStateNudge('fam-1', 'user-1');

      expect(result.familyName).toBe('Sharmas');
      expect(result.memberCount).toBe(1);
      expect(result.upcomingEvents).toEqual([]);
      // Suggestions should include generic greetings + family-name greeting
      expect(result.suggestions).toContain('Namaste everyone 🙏');
      expect(result.suggestions).toContain('How is everyone doing?');
      expect(result.suggestions.some((s) => s.includes('Sharmas'))).toBe(true);
    });

    it('includes upcoming birthday suggestion when a birthday is within 30 days', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue({ id: 'fm-1' });
      mockPrisma.family.findUnique.mockResolvedValue({ name: 'Sharmas' });
      mockPrisma.familyMember.findMany.mockResolvedValue([]);
      // Birthday in 5 days
      const fiveDaysFromNow = new Date();
      fiveDaysFromNow.setDate(fiveDaysFromNow.getDate() + 5);
      mockPrisma.person.findMany.mockResolvedValue([
        {
          id: 'person-1',
          name: 'Mama ji',
          dateOfBirth: fiveDaysFromNow,
          gender: 'male',
        },
      ]);

      const result = await service.getEmptyStateNudge('fam-1', 'user-1');

      expect(result.upcomingEvents).toHaveLength(1);
      expect(result.upcomingEvents[0].name).toBe('Mama ji');
      expect(result.upcomingEvents[0].eventType).toBe('birthday');
      expect(result.upcomingEvents[0].daysUntil).toBe(5);
      // First suggestion should reference the birthday
      expect(result.suggestions[0]).toContain('Mama ji');
      expect(result.suggestions[0]).toContain('🎂');
    });

    it('sorts upcoming events by soonest first', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue({ id: 'fm-1' });
      mockPrisma.family.findUnique.mockResolvedValue({ name: 'Sharmas' });
      mockPrisma.familyMember.findMany.mockResolvedValue([]);
      const in3Days = new Date();
      in3Days.setDate(in3Days.getDate() + 3);
      const in10Days = new Date();
      in10Days.setDate(in10Days.getDate() + 10);
      mockPrisma.person.findMany.mockResolvedValue([
        { id: 'p1', name: 'Late', dateOfBirth: in10Days, gender: 'female' },
        { id: 'p2', name: 'Soon', dateOfBirth: in3Days, gender: 'male' },
      ]);

      const result = await service.getEmptyStateNudge('fam-1', 'user-1');

      expect(result.upcomingEvents[0].name).toBe('Soon');
      expect(result.upcomingEvents[0].daysUntil).toBe(3);
      expect(result.upcomingEvents[1].name).toBe('Late');
      expect(result.upcomingEvents[1].daysUntil).toBe(10);
    });
  });

  // ── Feature 5: message search ─────────────────────────────────────────

  describe('searchMessages', () => {
    it('returns empty results for empty query', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue({ id: 'fm-1' });
      const result = await service.searchMessages('fam-1', 'user-1', '');
      expect(result.results).toEqual([]);
      expect(result.total).toBe(0);
      // Should NOT hit the DB for empty queries.
      expect(mockPrisma.chatMessage.findMany).not.toHaveBeenCalled();
    });

    it('returns matches sorted by createdAt desc with total count', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue({ id: 'fm-1' });
      const matches = [
        {
          id: 'msg-2',
          content: 'hello world',
          senderId: 'user-1',
          senderName: 'Manish',
          createdAt: new Date('2026-06-15'),
          messageType: 'text',
          mediaUrl: null,
          replyToId: null,
          replyToContent: null,
          replyToSenderName: null,
        },
        {
          id: 'msg-1',
          content: 'world peace',
          senderId: 'user-2',
          senderName: 'Riya',
          createdAt: new Date('2026-06-14'),
          messageType: 'text',
          mediaUrl: null,
          replyToId: null,
          replyToContent: null,
          replyToSenderName: null,
        },
      ];
      mockPrisma.chatMessage.findMany.mockResolvedValue(matches);
      mockPrisma.chatMessage.count.mockResolvedValue(5);

      const result = await service.searchMessages('fam-1', 'user-1', 'world');

      expect(result.results).toEqual(matches);
      expect(result.total).toBe(5);
      const findArgs = mockPrisma.chatMessage.findMany.mock.calls[0][0];
      expect(findArgs.where.content.contains).toBe('world');
      expect(findArgs.where.content.mode).toBe('insensitive');
      expect(findArgs.where.isDeletedForEveryone).toBe(false);
      expect(findArgs.orderBy).toEqual({ createdAt: 'desc' });
    });

    it('escapes ILIKE wildcard characters in the query', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue({ id: 'fm-1' });
      mockPrisma.chatMessage.findMany.mockResolvedValue([]);
      mockPrisma.chatMessage.count.mockResolvedValue(0);

      await service.searchMessages('fam-1', 'user-1', '100%');

      const findArgs = mockPrisma.chatMessage.findMany.mock.calls[0][0];
      // The % should be escaped to \% so ILIKE doesn't treat it as a wildcard.
      expect(findArgs.where.content.contains).toBe('100\\%');
    });

    it('caps limit at 50 to prevent abuse', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue({ id: 'fm-1' });
      mockPrisma.chatMessage.findMany.mockResolvedValue([]);
      mockPrisma.chatMessage.count.mockResolvedValue(0);

      await service.searchMessages('fam-1', 'user-1', 'test', 1000);

      const findArgs = mockPrisma.chatMessage.findMany.mock.calls[0][0];
      expect(findArgs.take).toBe(50);
    });

    it('throws ForbiddenException for non-members', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue(null);
      await expect(
        service.searchMessages('fam-1', 'user-1', 'test'),
      ).rejects.toBeInstanceOf(ForbiddenException);
    });
  });
});
