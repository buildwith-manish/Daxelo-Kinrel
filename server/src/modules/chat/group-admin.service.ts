// server/src/modules/chat/group-admin.service.ts
//
// DAXELO KINREL — Tier 2: Group Admin Service
//
// Wraps the admin-only RPCs created by the Tier 2 migrations:
//   • fn_set_group_description
//   • fn_set_slow_mode
//   • fn_log_group_audit                  (internal — called by other services)
//   • fn_get_group_audit_log              (paginated read for admin-actions screen)
//   • fn_create_group_invite_link
//   • fn_revoke_group_invite_link
//   • fn_join_via_invite_link             (public — anyone with the token)
//   • fn_request_to_join_family
//   • fn_approve_join_request
//   • fn_reject_join_request
//   • fn_set_group_sticker_pack
//   • fn_set_group_custom_reactions
//
// All RPCs are SECURITY DEFINER + do their own auth checks, so this service
// is a thin wrapper that calls them via Prisma's $queryRaw. The RPCs return
// JSON blobs; we parse them into typed responses for the controller.
//
// Why RPCs instead of Prisma writes?
// 1. Atomicity — the RPC inserts the audit row in the same transaction as
//    the mutation. Prisma can't do this without a multi-statement transaction
//    helper (which is awkward for nested service calls).
// 2. RLS bypass — the RPCs run as SECURITY DEFINER so they can write to
//    GroupAuditLog (which has no INSERT policy by design).
// 3. Idempotency — the RPCs are idempotent (re-running them produces the
//    same state + a fresh audit row, which is safe).

import { Injectable, BadRequestException, ForbiddenException, NotFoundException, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { ChatThrottlerService } from './chat-throttler.service';

@Injectable()
export class GroupAdminService {
  private readonly logger = new Logger(GroupAdminService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly throttler: ChatThrottlerService,
  ) {}

  // ── 2.11: Group description ────────────────────────────────────────────

  async setGroupDescription(familyId: string, userId: string, description: string | null) {
    const result = await this.callRpc('fn_set_group_description', [familyId, description]);
    if (result?.error === 'not_admin') throw new ForbiddenException('Only admins can change the description');
    if (result?.error === 'not_in_family') throw new ForbiddenException('Not a member of this family');
    if (result?.error === 'description_too_long') throw new BadRequestException('Description must be at most 500 characters');
    return result;
  }

  // ── 2.6: Slow mode ──────────────────────────────────────────────────────

  async setSlowMode(familyId: string, userId: string, seconds: number) {
    if (![0, 10, 30, 60, 300, 600, 3600].includes(seconds)) {
      throw new BadRequestException('Allowed: 0 (off), 10, 30, 60, 300, 600, 3600.');
    }
    const result = await this.callRpc('fn_set_slow_mode', [familyId, seconds]);
    if (result?.error === 'not_admin') throw new ForbiddenException('Only admins can change slow mode');
    if (result?.error === 'not_in_family') throw new ForbiddenException('Not a member of this family');
    // Invalidate the throttler's slow-mode cache so the new value applies
    // immediately (instead of waiting up to 60s for the TTL).
    this.throttler.invalidateSlowModeCache(familyId);
    return result;
  }

  // ── 2.8: Audit log read ────────────────────────────────────────────────

  async getAuditLog(familyId: string, userId: string, limit: number = 50, before?: string) {
    const result = await this.callRpc('fn_get_group_audit_log', [familyId, limit, before ?? null]);
    if (result?.error === 'not_in_family') throw new ForbiddenException('Not a member of this family');
    return result;
  }

  // ── 2.9: Group invite links ───────────────────────────────────────────

  async createInviteLink(
    familyId: string,
    userId: string,
    options: {
      label?: string;
      expiresAt?: Date;
      maxUses?: number;
      requireApproval?: boolean;
    } = {},
  ) {
    const result = await this.callRpc('fn_create_group_invite_link', [
      familyId,
      options.label ?? null,
      options.expiresAt ?? null,
      options.maxUses ?? null,
      options.requireApproval ?? false,
    ]);
    if (result?.error === 'not_admin') throw new ForbiddenException('Only admins can create invite links');
    if (result?.error === 'not_in_family') throw new ForbiddenException('Not a member of this family');
    if (result?.error === 'invalid_expiry') throw new BadRequestException('Expiry must be in the future');
    if (result?.error === 'invalid_max_uses') throw new BadRequestException('maxUses must be > 0');
    return result;
  }

  async listInviteLinks(familyId: string, userId: string) {
    // Direct Prisma read — no RPC needed (RLS lets members select).
    return this.prisma.groupInviteLink.findMany({
      where: { familyId, revokedAt: null },
      orderBy: { createdAt: 'desc' },
    });
  }

  async revokeInviteLink(token: string, userId: string) {
    const result = await this.callRpc('fn_revoke_group_invite_link', [token]);
    if (result?.error === 'not_found') throw new NotFoundException('Invite link not found');
    if (result?.error === 'not_allowed') throw new ForbiddenException('Only the creator or an admin can revoke');
    return result;
  }

  /// Public — anyone with the token can join (or submit a join request
  /// if the link requires approval). The RPC handles both paths.
  async joinViaInviteLink(token: string, userId: string) {
    const result = await this.callRpc('fn_join_via_invite_link', [token]);
    if (result?.error === 'link_not_found_or_revoked') throw new NotFoundException('Invite link not found or revoked');
    if (result?.error === 'link_expired') throw new BadRequestException('Invite link has expired');
    if (result?.error === 'link_exhausted') throw new BadRequestException('Invite link has reached its max uses');
    return result;
  }

  // ── 2.10: Join requests (when requireApproval=true OR public group) ──

  async requestToJoin(familyId: string, userId: string, details?: any) {
    const result = await this.callRpc('fn_request_to_join_family', [
      familyId,
      details ? JSON.stringify(details) : null,
    ]);
    if (result?.error === 'already_member') throw new BadRequestException('You are already a member');
    return result;
  }

  async listPendingJoinRequests(familyId: string, userId: string) {
    // RLS only lets admins see requests — the controller enforces admin
    // status here so we can use a direct Prisma query.
    const membership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId } },
      select: { role: true },
    });
    if (!membership) throw new ForbiddenException('Not a member of this family');
    if (membership.role !== 'admin' && membership.role !== 'creator') {
      throw new ForbiddenException('Only admins can see join requests');
    }
    return this.prisma.groupJoinRequest.findMany({
      where: { familyId, status: 'pending' },
      orderBy: { requestedAt: 'desc' },
      take: 100,
    });
  }

  async approveJoinRequest(joinRequestId: string, userId: string) {
    const result = await this.callRpc('fn_approve_join_request', [joinRequestId]);
    if (result?.error === 'not_found') throw new NotFoundException('Join request not found');
    if (result?.error === 'not_admin') throw new ForbiddenException('Only admins can approve');
    if (result?.error === 'not_pending') throw new BadRequestException('Join request is not pending');
    return result;
  }

  async rejectJoinRequest(joinRequestId: string, userId: string) {
    const result = await this.callRpc('fn_reject_join_request', [joinRequestId]);
    if (result?.error === 'not_found') throw new NotFoundException('Join request not found');
    if (result?.error === 'not_admin') throw new ForbiddenException('Only admins can reject');
    if (result?.error === 'not_pending') throw new BadRequestException('Join request is not pending');
    return result;
  }

  // ── 2.12: Sticker pack + custom reactions ────────────────────────────

  async setStickerPack(familyId: string, userId: string, stickerPackId: string | null) {
    const result = await this.callRpc('fn_set_group_sticker_pack', [familyId, stickerPackId ?? '']);
    if (result?.error === 'not_admin') throw new ForbiddenException('Only admins can change the sticker pack');
    if (result?.error === 'not_in_family') throw new ForbiddenException('Not a member of this family');
    return result;
  }

  async setCustomReactions(familyId: string, userId: string, reactions: string[]) {
    if (reactions.length > 8) throw new BadRequestException('Maximum 8 custom reactions.');
    const result = await this.callRpc('fn_set_group_custom_reactions', [
      familyId,
      JSON.stringify(reactions),
    ]);
    if (result?.error === 'not_admin') throw new ForbiddenException('Only admins can set custom reactions');
    if (result?.error === 'too_many_reactions') throw new BadRequestException('Maximum 8 custom reactions.');
    return result;
  }

  // ── 2.5: Forum topics ─────────────────────────────────────────────────

  async createTopic(familyId: string, userId: string, name: string, emoji?: string, iconUrl?: string) {
    if (!name?.trim()) throw new BadRequestException('Topic name is required');
    const result = await this.callRpc('fn_create_chat_topic', [
      familyId,
      name,
      emoji ?? null,
      iconUrl ?? null,
    ]);
    if (result?.error === 'not_admin') throw new ForbiddenException('Only admins can create topics');
    if (result?.error === 'not_in_family') throw new ForbiddenException('Not a member of this family');
    return result;
  }

  async listTopics(familyId: string, userId: string) {
    // RLS lets any family member read topics.
    const membership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId } },
      select: { role: true },
    });
    if (!membership) throw new ForbiddenException('Not a member of this family');
    return this.prisma.chatTopic.findMany({
      where: { familyId },
      orderBy: [{ isGeneral: 'desc' }, { lastMessageAt: 'desc' }],
    });
  }

  // ── Internal helper ────────────────────────────────────────────────────

  /**
   * Call a Postgres RPC by name with positional args. Returns the parsed
   * JSON result (or null on parse failure). The RPCs all return json_build_object
   * with { success, ... } on success or { success: false, error, message? }
   * on failure.
   */
  private async callRpc(name: string, args: any[]): Promise<any> {
    try {
      // Build a parameterized query — Prisma's $queryRaw lets us pass
      // args via tagged template.
      const placeholders = args.map((_, i) => `$${i + 1}`).join(', ');
      const sql = `SELECT ${name}(${placeholders}) AS result;`;
      const rows = await this.prisma.$queryRawUnsafe(sql, ...args);
      if (!Array.isArray(rows) || rows.length === 0) return null;
      const raw = (rows[0] as any).result;
      if (raw == null) return null;
      try {
        return typeof raw === 'string' ? JSON.parse(raw) : raw;
      } catch {
        return raw;
      }
    } catch (err: any) {
      this.logger.error(`RPC ${name} failed: ${err?.message}`, err?.stack);
      return { success: false, error: 'rpc_failed', message: err?.message };
    }
  }
}
