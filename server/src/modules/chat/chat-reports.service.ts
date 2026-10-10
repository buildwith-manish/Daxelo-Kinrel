// server/src/modules/chat/chat-reports.service.ts
//
// DAXELO KINREL — Tier 3 Feature 3.6: Block + Report from chat — Service
//
// Wraps the fn_report_chat + fn_block_user RPCs.

import { Injectable, BadRequestException, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class ChatReportsService {
  private readonly logger = new Logger(ChatReportsService.name);

  constructor(private readonly prisma: PrismaService) {}

  async reportUser(
    reporterId: string,
    params: {
      reportedUserId?: string | null;
      familyId?: string | null;
      messageId?: string | null;
      reason: string;
      details?: string | null;
    },
  ) {
    if (!['spam', 'abuse', 'fake', 'harassment', 'other'].includes(params.reason)) {
      throw new BadRequestException('Invalid reason');
    }
    if (params.details && params.details.length > 1000) {
      throw new BadRequestException('Details must be at most 1000 characters');
    }
    return this.callRpc('fn_report_chat', [
      params.reportedUserId ?? null,
      params.familyId ?? null,
      params.messageId ?? null,
      params.reason,
      params.details ?? null,
    ]);
  }

  async blockUser(blockerId: string, blockedId: string) {
    if (!blockedId) throw new BadRequestException('blockedId is required');
    if (blockedId === blockerId) {
      throw new BadRequestException('You cannot block yourself');
    }
    return this.callRpc('fn_block_user', [blockedId]);
  }

  async listMyReports(userId: string) {
    return this.prisma.chatReport.findMany({
      where: { reporterId: userId },
      orderBy: { createdAt: 'desc' },
      take: 50,
    });
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
