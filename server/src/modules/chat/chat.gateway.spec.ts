// server/src/modules/chat/chat.gateway.spec.ts
//
// Phase A-5 — per-group Socket.IO rooms. chat:joinFamily joins the socket to
// `chat:group:<id>` for every group of that family the user is a GroupMember
// of, and group/DM messages are delivered to that room ONLY (never to the
// family room), so non-members' sockets never receive the frame.

import { ChatGateway } from './chat.gateway';

describe('ChatGateway — group rooms', () => {
  const chatService = {
    assertFamilyMember: jest.fn(),
    sendMessageWithMentions: jest.fn(),
    setTypingStatus: jest.fn(),
  };
  const prisma = {
    group: { findMany: jest.fn() },
    groupMember: { findMany: jest.fn() },
  };
  const kinrelGateway = { emitToUser: jest.fn() };
  const serverEmit = jest.fn();
  const server = { to: jest.fn(() => ({ emit: serverEmit })) };

  let gateway: ChatGateway;

  const makeClient = (id = 'sock-1', userId = 'user-1') => {
    const roomEmit = jest.fn();
    return {
      id,
      userId,
      join: jest.fn().mockResolvedValue(undefined),
      leave: jest.fn().mockResolvedValue(undefined),
      emit: jest.fn(),
      to: jest.fn(() => ({ emit: roomEmit })),
    };
  };
  const joined = (c: ReturnType<typeof makeClient>) => c.join.mock.calls.map((a) => a[0]);
  const left = (c: ReturnType<typeof makeClient>) => c.leave.mock.calls.map((a) => a[0]);

  const setGroups = (familyGroupIds: string[], memberOf: string[]) => {
    prisma.group.findMany.mockResolvedValue(familyGroupIds.map((id) => ({ id })));
    prisma.groupMember.findMany.mockResolvedValue(memberOf.map((groupId) => ({ groupId })));
  };

  beforeEach(() => {
    jest.clearAllMocks();
    chatService.assertFamilyMember.mockResolvedValue(undefined);
    chatService.setTypingStatus.mockResolvedValue(undefined);
    gateway = new ChatGateway(
      chatService as any,
      { check: jest.fn() } as any,
      kinrelGateway as any,
      prisma as any,
    );
    (gateway as any).server = server;
  });

  describe('chat:joinFamily', () => {
    it('joins the family room and ONLY the group rooms the user is a member of', async () => {
      const c = makeClient();
      setGroups(['g1', 'g2', 'g3'], ['g1', 'g3']);

      await gateway.handleJoinFamily(c as any, { familyId: 'fam-1' });

      expect(joined(c)).toEqual(['chat:family:fam-1', 'chat:group:g1', 'chat:group:g3']);
      expect(joined(c)).not.toContain('chat:group:g2');
      // group lookup is scoped to the family, membership lookup to this user + those groups
      expect(prisma.group.findMany).toHaveBeenCalledWith({ where: { familyId: 'fam-1' }, select: { id: true } });
      expect(prisma.groupMember.findMany).toHaveBeenCalledWith({
        where: { userId: 'user-1', groupId: { in: ['g1', 'g2', 'g3'] } },
        select: { groupId: true },
      });
      expect(c.emit).toHaveBeenCalledWith('chat:joinedFamily', { familyId: 'fam-1' });
    });

    it('a non-member of the family joins nothing (existing authorization is unchanged)', async () => {
      const c = makeClient();
      chatService.assertFamilyMember.mockRejectedValue(new Error('Not a member of this family'));

      await gateway.handleJoinFamily(c as any, { familyId: 'fam-1' });

      expect(c.join).not.toHaveBeenCalled();
      expect(prisma.group.findMany).not.toHaveBeenCalled();
      expect(c.emit).toHaveBeenCalledWith('error', expect.objectContaining({ event: 'chat:joinFamily' }));
    });

    it('fail-closed: if the group lookup throws, the socket still joins the family room but NO group room', async () => {
      const c = makeClient();
      prisma.group.findMany.mockRejectedValue(new Error('db down'));

      await gateway.handleJoinFamily(c as any, { familyId: 'fam-1' });

      expect(joined(c)).toEqual(['chat:family:fam-1']);
      expect(c.emit).toHaveBeenCalledWith('chat:joinedFamily', { familyId: 'fam-1' });
    });

    it('a family with no groups does not query GroupMember', async () => {
      const c = makeClient();
      setGroups([], []);

      await gateway.handleJoinFamily(c as any, { familyId: 'fam-1' });

      expect(prisma.groupMember.findMany).not.toHaveBeenCalled();
      expect(joined(c)).toEqual(['chat:family:fam-1']);
    });

    it('re-emitting chat:joinFamily re-syncs: joins new groups, leaves ones the user was removed from, no duplicate joins', async () => {
      const c = makeClient();
      setGroups(['g1', 'g2'], ['g1']);
      await gateway.handleJoinFamily(c as any, { familyId: 'fam-1' });
      c.join.mockClear();

      setGroups(['g1', 'g2'], ['g2']); // removed from g1, added to g2
      await gateway.handleJoinFamily(c as any, { familyId: 'fam-1' });

      expect(left(c)).toEqual(['chat:group:g1']);
      expect(joined(c)).toEqual(['chat:family:fam-1', 'chat:group:g2']);
    });

    it('group rooms are tracked per family (syncing family B does not leave family A\'s rooms)', async () => {
      const c = makeClient();
      setGroups(['a1'], ['a1']);
      await gateway.handleJoinFamily(c as any, { familyId: 'fam-A' });
      setGroups(['b1'], ['b1']);
      await gateway.handleJoinFamily(c as any, { familyId: 'fam-B' });

      expect(left(c)).toEqual([]);
    });
  });

  describe('chat:leaveFamily / disconnect', () => {
    it('leaves the family room and the group rooms it joined for that family', async () => {
      const c = makeClient();
      setGroups(['g1', 'g2'], ['g1', 'g2']);
      await gateway.handleJoinFamily(c as any, { familyId: 'fam-1' });

      await gateway.handleLeaveFamily(c as any, { familyId: 'fam-1' });

      expect(left(c)).toEqual(['chat:family:fam-1', 'chat:group:g1', 'chat:group:g2']);
    });

    it('disconnect drops the socket bookkeeping', async () => {
      const c = makeClient();
      setGroups(['g1'], ['g1']);
      await gateway.handleJoinFamily(c as any, { familyId: 'fam-1' });
      expect((gateway as any).groupRoomsBySocket.has(c.id)).toBe(true);

      gateway.handleDisconnect(c as any);

      expect((gateway as any).groupRoomsBySocket.has(c.id)).toBe(false);
    });
  });

  describe('chat:sendMessageWithMentions routing', () => {
    const payload = (over: Record<string, unknown> = {}) => ({
      familyId: 'fam-1',
      content: 'hi @Bob',
      mentions: [{ userId: 'bob', name: 'Bob', start: 3, end: 7 }],
      ...over,
    });

    beforeEach(() => {
      chatService.sendMessageWithMentions.mockResolvedValue({ id: 'msg-1', senderName: 'Alice' });
    });

    it('family-wide message (no groupId) -> family room, as before', async () => {
      const c = makeClient();

      await gateway.handleSendMessageWithMentions(c as any, payload() as any);

      expect(server.to).toHaveBeenCalledWith('chat:family:fam-1');
      expect(server.to).not.toHaveBeenCalledWith(expect.stringContaining('chat:group:'));
      expect(c.join).not.toHaveBeenCalled();
      expect(serverEmit).toHaveBeenCalledWith('chat:messageReceived', { message: { id: 'msg-1', senderName: 'Alice' } });
    });

    it('group message -> ONLY the group room, never the family room', async () => {
      const c = makeClient();

      await gateway.handleSendMessageWithMentions(c as any, payload({ groupId: 'g1' }) as any);

      expect(server.to).toHaveBeenCalledWith('chat:group:g1');
      expect(server.to).not.toHaveBeenCalledWith('chat:family:fam-1');
      expect(serverEmit).toHaveBeenCalledWith('chat:messageReceived', expect.anything());
    });

    it('group message: the (verified) sender\'s own socket is put in the group room even if the group was created after joinFamily, and is tracked for cleanup', async () => {
      const c = makeClient();

      await gateway.handleSendMessageWithMentions(c as any, payload({ groupId: 'g-new' }) as any);

      expect(joined(c)).toEqual(['chat:group:g-new']);
      await gateway.handleLeaveFamily(c as any, { familyId: 'fam-1' });
      expect(left(c)).toContain('chat:group:g-new');
    });

    it('if the service rejects (not a group member), nothing is broadcast and the socket is not joined', async () => {
      const c = makeClient();
      chatService.sendMessageWithMentions.mockRejectedValue(new Error('Not a member of this group'));

      await gateway.handleSendMessageWithMentions(c as any, payload({ groupId: 'g1' }) as any);

      expect(server.to).not.toHaveBeenCalled();
      expect(c.join).not.toHaveBeenCalled();
      expect(c.emit).toHaveBeenCalledWith('chat:messageFailed', expect.objectContaining({ familyId: 'fam-1' }));
    });

    it('per-user mention events are unchanged (emitToUser, no content)', async () => {
      const c = makeClient();

      await gateway.handleSendMessageWithMentions(c as any, payload({ groupId: 'g1' }) as any);

      expect(kinrelGateway.emitToUser).toHaveBeenCalledWith(
        'bob',
        'chat:mentionReceived',
        expect.objectContaining({ messageId: 'msg-1', familyId: 'fam-1', groupId: 'g1' }),
      );
      const sent = kinrelGateway.emitToUser.mock.calls[0][2];
      expect(sent).not.toHaveProperty('content');
    });
  });
});
