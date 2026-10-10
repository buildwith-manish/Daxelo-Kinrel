// server/src/modules/chat/group-admin.service.spec.ts
//
// Unit tests for GroupAdminService — Tier 2.
// Verifies the RPC-call wrapper pattern: every public method calls the
// right RPC with the right args + maps known errors to the right Nest
// exceptions.

import { Test, TestingModule } from '@nestjs/testing';
import { GroupAdminService } from './group-admin.service';
import { ChatThrottlerService } from './chat-throttler.service';
import { PrismaService } from '../../prisma/prisma.service';
import { BadRequestException, ForbiddenException, NotFoundException } from '@nestjs/common';

describe('GroupAdminService', () => {
  let service: GroupAdminService;

  const mockPrisma = {
    $queryRawUnsafe: jest.fn(),
    groupInviteLink: { findMany: jest.fn() },
    familyMember: { findUnique: jest.fn() },
    groupJoinRequest: { findMany: jest.fn() },
    chatTopic: { findMany: jest.fn() },
  };

  const mockThrottler = {
    invalidateSlowModeCache: jest.fn(),
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        GroupAdminService,
        { provide: PrismaService, useValue: mockPrisma },
        { provide: ChatThrottlerService, useValue: mockThrottler },
      ],
    }).compile();
    service = module.get<GroupAdminService>(GroupAdminService);
    jest.clearAllMocks();
  });

  /// Helper: stub the $queryRawUnsafe call to return the given JSON payload
  /// (parsed). The callRpc helper in the service expects rows with a .result
  /// field that's either a string (to JSON.parse) or already an object.
  const stubRpc = (result: any) => {
    mockPrisma.$queryRawUnsafe.mockResolvedValue([{ result: typeof result === 'string' ? result : JSON.stringify(result) }]);
  };

  // ── 2.11: Group description ──────────────────────────────────────────

  describe('setGroupDescription', () => {
    it('calls fn_set_group_description with the right args', async () => {
      stubRpc({ success: true, action: 'updated' });
      const result = await service.setGroupDescription('fam-1', 'user-1', 'New rules');
      expect(result).toEqual({ success: true, action: 'updated' });
      expect(mockPrisma.$queryRawUnsafe).toHaveBeenCalledWith(
        'SELECT fn_set_group_description($1, $2) AS result;',
        'fam-1', 'New rules',
      );
    });

    it('throws ForbiddenException when the RPC returns not_admin', async () => {
      stubRpc({ success: false, error: 'not_admin' });
      await expect(
        service.setGroupDescription('fam-1', 'user-1', 'X'),
      ).rejects.toBeInstanceOf(ForbiddenException);
    });

    it('throws BadRequestException when the RPC returns description_too_long', async () => {
      stubRpc({ success: false, error: 'description_too_long' });
      await expect(
        service.setGroupDescription('fam-1', 'user-1', 'X'.repeat(600)),
      ).rejects.toBeInstanceOf(BadRequestException);
    });
  });

  // ── 2.6: Slow mode ───────────────────────────────────────────────────

  describe('setSlowMode', () => {
    it('calls fn_set_slow_mode + invalidates the throttler cache', async () => {
      stubRpc({ success: true, slowModeSeconds: 60 });
      const result = await service.setSlowMode('fam-1', 'user-1', 60);
      expect(result).toEqual({ success: true, slowModeSeconds: 60 });
      expect(mockPrisma.$queryRawUnsafe).toHaveBeenCalledWith(
        'SELECT fn_set_slow_mode($1, $2) AS result;',
        'fam-1', 60,
      );
      expect(mockThrottler.invalidateSlowModeCache).toHaveBeenCalledWith('fam-1');
    });

    it('throws BadRequestException for an invalid seconds value', async () => {
      await expect(
        service.setSlowMode('fam-1', 'user-1', 999),
      ).rejects.toBeInstanceOf(BadRequestException);
      expect(mockPrisma.$queryRawUnsafe).not.toHaveBeenCalled();
    });

    it('throws ForbiddenException when the RPC returns not_admin', async () => {
      stubRpc({ success: false, error: 'not_admin' });
      await expect(
        service.setSlowMode('fam-1', 'user-1', 60),
      ).rejects.toBeInstanceOf(ForbiddenException);
    });
  });

  // ── 2.8: Audit log ──────────────────────────────────────────────────

  describe('getAuditLog', () => {
    it('calls fn_get_group_audit_log with paginated args', async () => {
      const rows = [{ id: 'gal_1', actionType: 'slow_mode_set' }];
      stubRpc(rows);
      const result = await service.getAuditLog('fam-1', 'user-1', 50, undefined);
      expect(result).toEqual(rows);
      expect(mockPrisma.$queryRawUnsafe).toHaveBeenCalledWith(
        'SELECT fn_get_group_audit_log($1, $2, $3) AS result;',
        'fam-1', 50, null,
      );
    });

    it('passes the before cursor through', async () => {
      stubRpc([]);
      await service.getAuditLog('fam-1', 'user-1', 50, '2026-01-01T00:00:00Z');
      expect(mockPrisma.$queryRawUnsafe).toHaveBeenCalledWith(
        expect.any(String),
        'fam-1', 50, '2026-01-01T00:00:00Z',
      );
    });
  });

  // ── 2.9: Group invite links ─────────────────────────────────────────

  describe('createInviteLink', () => {
    it('calls fn_create_group_invite_link with the options', async () => {
      stubRpc({ success: true, token: 'tok_1', url: 'https://kinrel.app/join/tok_1' });
      const result = await service.createInviteLink('fam-1', 'user-1', {
        label: 'Diwali 2026',
        maxUses: 5,
        requireApproval: false,
      });
      expect(result).toEqual({ success: true, token: 'tok_1', url: 'https://kinrel.app/join/tok_1' });
      expect(mockPrisma.$queryRawUnsafe).toHaveBeenCalledWith(
        expect.any(String),
        'fam-1', 'Diwali 2026', null, 5, false,
      );
    });

    it('throws ForbiddenException when the RPC returns not_admin', async () => {
      stubRpc({ success: false, error: 'not_admin' });
      await expect(
        service.createInviteLink('fam-1', 'user-1'),
      ).rejects.toBeInstanceOf(ForbiddenException);
    });

    it('throws BadRequestException for invalid_expiry', async () => {
      stubRpc({ success: false, error: 'invalid_expiry' });
      await expect(
        service.createInviteLink('fam-1', 'user-1'),
      ).rejects.toBeInstanceOf(BadRequestException);
    });
  });

  describe('revokeInviteLink', () => {
    it('throws NotFoundException when the RPC returns not_found', async () => {
      stubRpc({ success: false, error: 'not_found' });
      await expect(
        service.revokeInviteLink('missing_token', 'user-1'),
      ).rejects.toBeInstanceOf(NotFoundException);
    });

    it('throws ForbiddenException when the RPC returns not_allowed', async () => {
      stubRpc({ success: false, error: 'not_allowed' });
      await expect(
        service.revokeInviteLink('tok_1', 'user-1'),
      ).rejects.toBeInstanceOf(ForbiddenException);
    });
  });

  describe('joinViaInviteLink', () => {
    it('throws NotFoundException when the link is missing/revoked', async () => {
      stubRpc({ success: false, error: 'link_not_found_or_revoked' });
      await expect(
        service.joinViaInviteLink('tok_1', 'user-1'),
      ).rejects.toBeInstanceOf(NotFoundException);
    });

    it('throws BadRequestException when the link is expired', async () => {
      stubRpc({ success: false, error: 'link_expired' });
      await expect(
        service.joinViaInviteLink('tok_1', 'user-1'),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('returns the join action on success', async () => {
      stubRpc({ success: true, action: 'joined', familyId: 'fam-1' });
      const result = await service.joinViaInviteLink('tok_1', 'user-1');
      expect(result).toEqual({ success: true, action: 'joined', familyId: 'fam-1' });
    });
  });

  // ── 2.10: Join requests ─────────────────────────────────────────────

  describe('listPendingJoinRequests', () => {
    it('throws ForbiddenException for non-admin members', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue({ role: 'member' });
      await expect(
        service.listPendingJoinRequests('fam-1', 'user-1'),
      ).rejects.toBeInstanceOf(ForbiddenException);
      expect(mockPrisma.groupJoinRequest.findMany).not.toHaveBeenCalled();
    });

    it('returns the pending requests for admins', async () => {
      mockPrisma.familyMember.findUnique.mockResolvedValue({ role: 'admin' });
      const rows = [{ id: 'gjr_1', status: 'pending' }];
      mockPrisma.groupJoinRequest.findMany.mockResolvedValue(rows);
      const result = await service.listPendingJoinRequests('fam-1', 'user-1');
      expect(result).toBe(rows);
    });
  });

  describe('approveJoinRequest', () => {
    it('throws NotFoundException when the request is missing', async () => {
      stubRpc({ success: false, error: 'not_found' });
      await expect(
        service.approveJoinRequest('gjr_missing', 'user-1'),
      ).rejects.toBeInstanceOf(NotFoundException);
    });

    it('throws BadRequestException when the request is not pending', async () => {
      stubRpc({ success: false, error: 'not_pending' });
      await expect(
        service.approveJoinRequest('gjr_1', 'user-1'),
      ).rejects.toBeInstanceOf(BadRequestException);
    });
  });

  // ── 2.12: Sticker pack + custom reactions ──────────────────────────

  describe('setCustomReactions', () => {
    it('throws BadRequestException when more than 8 reactions are passed', async () => {
      await expect(
        service.setCustomReactions('fam-1', 'user-1', ['😀','😁','😂','🤣','😃','😄','😅','😆','😉']),
      ).rejects.toBeInstanceOf(BadRequestException);
      expect(mockPrisma.$queryRawUnsafe).not.toHaveBeenCalled();
    });

    it('calls fn_set_group_custom_reactions with the array as JSON', async () => {
      stubRpc({ success: true, customReactions: ['😀','❤️'] });
      const result = await service.setCustomReactions('fam-1', 'user-1', ['😀','❤️']);
      expect(result).toEqual({ success: true, customReactions: ['😀','❤️'] });
      expect(mockPrisma.$queryRawUnsafe).toHaveBeenCalledWith(
        expect.any(String),
        'fam-1', JSON.stringify(['😀','❤️']),
      );
    });
  });

  // ── 2.5: Forum topics ───────────────────────────────────────────────

  describe('createTopic', () => {
    it('throws BadRequestException when the name is empty', async () => {
      await expect(
        service.createTopic('fam-1', 'user-1', '   '),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('calls fn_create_chat_topic with name + emoji + iconUrl', async () => {
      stubRpc({ success: true, topicId: 'ct_1' });
      const result = await service.createTopic('fam-1', 'user-1', 'Wedding', '💍', null);
      expect(result).toEqual({ success: true, topicId: 'ct_1' });
      expect(mockPrisma.$queryRawUnsafe).toHaveBeenCalledWith(
        expect.any(String),
        'fam-1', 'Wedding', '💍', null,
      );
    });
  });

  // ── Internal RPC error tolerance ────────────────────────────────────

  describe('callRpc — error tolerance', () => {
    it('returns a structured error when $queryRawUnsafe throws', async () => {
      mockPrisma.$queryRawUnsafe.mockRejectedValue(new Error('connection lost'));
      const result = await service.setSlowMode('fam-1', 'user-1', 60);
      // setSlowMode doesn't throw on rpc_failed — it returns the structured error.
      // The known-error branches (not_admin etc) throw; unknown rpc_failed returns.
      expect(result).toEqual(expect.objectContaining({ success: false, error: 'rpc_failed' }));
    });
  });
});
