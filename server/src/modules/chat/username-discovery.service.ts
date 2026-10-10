// server/src/modules/chat/username-discovery.service.ts
//
// DAXELO KINREL — Tier 5 Feature 5.2: Public username discovery — Service
//
// Wraps the fn_set_username_only_account + fn_search_users_by_username
// RPCs. Lets a user flip their account to username-only (no email/phone
// required) + search the public user catalog by username prefix.

import { Injectable, BadRequestException, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class UsernameDiscoveryService {
  private readonly logger = new Logger(UsernameDiscoveryService.name);

  constructor(private readonly prisma: PrismaService) {}

  /// Set the caller's account to username-only (or back to email-based).
  /// When flipping to username-only, the user must already have a @username
  /// set (the RPC enforces this).
  async setAccountMode(
    userId: string,
    params: { isUsernameOnly: boolean; showOnUsernameSearch?: boolean | null },
  ) {
    if (params.isUsernameOnly) {
      const user = await this.prisma.user.findUnique({
        where: { id: userId },
        select: { username: true },
      });
      if (!user?.username?.trim()) {
        throw new BadRequestException('Set a @username before flipping to a username-only account');
      }
    }
    return this.callRpc('fn_set_username_only_account', [
      params.isUsernameOnly,
      params.showOnUsernameSearch ?? null,
    ]);
  }

  /// Search the public user catalog by username prefix. Excludes the
  /// caller. Sorted by similarity (best match first).
  async searchByUsername(userId: string, query: string, limit: number = 20) {
    const trimmed = query.trim();
    if (trimmed.length < 2) return [];
    return this.callRpc('fn_search_users_by_username', [trimmed, limit]);
  }

  /// Internal helper — same pattern as GroupAdminService.callRpc.
  private async callRpc(name: string, args: any[]): Promise<any> {
    try {
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
