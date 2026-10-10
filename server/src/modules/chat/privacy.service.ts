// server/src/modules/chat/privacy.service.ts
//
// DAXELO KINREL — Tier 3 Feature 3.5: Privacy toggles — Service
//
// Wraps fn_set_privacy_settings + fn_get_privacy_settings RPCs.
// Also: gates the visibility of `lastSeenAt` returned by getGroupInfo
// based on the OTHER user's lastSeenVisibility setting + reciprocity.

import { Injectable, BadRequestException, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class PrivacyService {
  private readonly logger = new Logger(PrivacyService.name);

  constructor(private readonly prisma: PrismaService) {}

  async getMySettings(userId: string) {
    const row = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { lastSeenVisibility: true, readReceiptsEnabled: true },
    });
    return {
      lastSeenVisibility: row?.lastSeenVisibility ?? 'everyone',
      readReceiptsEnabled: row?.readReceiptsEnabled ?? true,
    };
  }

  async updateMySettings(
    userId: string,
    params: {
      lastSeenVisibility?: string | null;
      readReceiptsEnabled?: boolean | null;
    },
  ) {
    if (
      params.lastSeenVisibility !== null &&
      params.lastSeenVisibility !== undefined &&
      !['everyone', 'contacts', 'nobody'].includes(params.lastSeenVisibility)
    ) {
      throw new BadRequestException('lastSeenVisibility must be everyone | contacts | nobody');
    }
    const data: any = {};
    if (params.lastSeenVisibility !== undefined && params.lastSeenVisibility !== null) {
      data.lastSeenVisibility = params.lastSeenVisibility;
    }
    if (params.readReceiptsEnabled !== undefined && params.readReceiptsEnabled !== null) {
      data.readReceiptsEnabled = params.readReceiptsEnabled;
    }
    if (Object.keys(data).length === 0) {
      return this.getMySettings(userId);
    }
    await this.prisma.user.update({ where: { id: userId }, data });
    return this.getMySettings(userId);
  }

  /**
   * Decide whether the requester can see the target user's last-seen.
   * Rules (reciprocal, WhatsApp-style):
   *   • If requester's lastSeenVisibility == 'nobody' → can't see anyone.
   *   • Else if target's lastSeenVisibility == 'nobody' → can't see them.
   *   • Else if target's lastSeenVisibility == 'contacts' → can see only
   *     if requester shares a family with target.
   *   • Else (both 'everyone' or 'contacts' satisfied) → can see.
   */
  async canSeeLastSeenOf(requesterId: string, targetId: string): Promise<boolean> {
    if (requesterId === targetId) return true;

    const [requester, target] = await Promise.all([
      this.prisma.user.findUnique({
        where: { id: requesterId },
        select: { lastSeenVisibility: true },
      }),
      this.prisma.user.findUnique({
        where: { id: targetId },
        select: { lastSeenVisibility: true },
      }),
    ]);

    // Reciprocity: if the requester hides from everyone, they can't see anyone.
    if (requester?.lastSeenVisibility === 'nobody') return false;
    if (!target) return true; // default open when target row missing

    if (target.lastSeenVisibility === 'everyone') return true;
    if (target.lastSeenVisibility === 'nobody') return false;

    // 'contacts' — requester must share at least one family with target.
    // Prisma doesn't support nested-where subqueries directly, so we do
    // two queries: (1) find target's familyIds, (2) check if requester
    // is in any of those families.
    const targetFamilies = await this.prisma.familyMember.findMany({
      where: { userId: targetId },
      select: { familyId: true },
    });
    if (targetFamilies.length === 0) return false;
    const shared = await this.prisma.familyMember.findFirst({
      where: {
        userId: requesterId,
        familyId: { in: targetFamilies.map((r) => r.familyId) },
      },
      select: { id: true },
    });
    return !!shared;
  }

  /**
   * Returns true when the user has read receipts enabled (default true).
   * Used by ChatService.markAsRead to skip writing readBy entries for
   * users who have disabled read receipts (so they don't leak their
   * read state to others).
   */
  async hasReadReceiptsEnabled(userId: string): Promise<boolean> {
    const row = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { readReceiptsEnabled: true },
    });
    return row?.readReceiptsEnabled ?? true;
  }
}
