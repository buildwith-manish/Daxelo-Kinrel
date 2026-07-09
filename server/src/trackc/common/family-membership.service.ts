// =============================================================================
// Track C v2.0 — Common: Family membership guard service
// =============================================================================
// Verifies that the current user is an active member of the requested family
// and optionally has a specific role. Used by all Track C controllers.
// =============================================================================

import {
  Injectable,
  ForbiddenException,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

export type FamilyRole = 'owner' | 'admin' | 'elder' | 'member' | 'viewer';

@Injectable()
export class FamilyMembershipService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Verify the user is an active member of the family.
   * Returns the FamilyMember row (with role) on success.
   * Throws NotFoundException if family doesn't exist (or user not member —
   * we don't leak family existence to non-members).
   */
  async requireMember(userId: string, familyId: string) {
    const membership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId } },
    });
    if (!membership) {
      throw new NotFoundException('Family not found');
    }
    return membership;
  }

  /**
   * Verify the user has one of the allowed roles in the family.
   */
  async requireRole(userId: string, familyId: string, roles: FamilyRole[]) {
    const membership = await this.requireMember(userId, familyId);
    if (!roles.includes(membership.role as FamilyRole)) {
      throw new ForbiddenException(`This action requires one of: ${roles.join(', ')}`);
    }
    return membership;
  }

  /**
   * Require admin-or-above. 'admin' and 'owner' qualify.
   */
  async requireAdmin(userId: string, familyId: string) {
    return this.requireRole(userId, familyId, ['admin', 'owner']);
  }

  /**
   * Get the list of elder user IDs in a family. Used by the elder_council
   * decision workflow (Section 10.2).
   */
  async getElderUserIds(familyId: string): Promise<string[]> {
    const elders = await this.prisma.familyMember.findMany({
      where: { familyId, role: 'elder' },
      select: { userId: true },
    });
    return elders.map((e) => e.userId);
  }

  /**
   * Get all active member user IDs in a family.
   */
  async getActiveMemberUserIds(familyId: string): Promise<string[]> {
    const members = await this.prisma.familyMember.findMany({
      where: { familyId, role: { in: ['owner', 'admin', 'elder', 'member'] } },
      select: { userId: true },
    });
    return members.map((m) => m.userId);
  }
}
