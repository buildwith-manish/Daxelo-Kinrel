/**
 * ViewerService — v2.2 Viewer-Driven Relationship Engine
 * ═══════════════════════════════════════════════════════════════════════
 *
 * Resolves the current viewer's Person ID for a given family and
 * orchestrates the Person-link lifecycle (claim / unlink / invite /
 * accept-invite).
 *
 * Resolution chain (matches the Flutter `viewerPersonIdProvider`):
 *   1. Query Person where linkedUserId = currentUser.id AND familyId
 *   2. If not found → query Person where isAnchor = true AND familyId
 *      (legacy fallback for unclaimed profiles)
 *   3. If not found → return null (caller should prompt user to claim)
 *
 * Server-side enforcement (architecture §15):
 *   - Family membership is verified before any data is returned.
 *   - Soft-deleted Person nodes are excluded.
 *   - Profile claim ownership, impersonation prevention, and duplicate
 *     prevention are all enforced here — never on the client.
 */

import {
  Injectable,
  ForbiddenException,
  NotFoundException,
  Logger,
  BadRequestException,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

const ROLE_HIERARCHY: Record<string, number> = {
  viewer: 1,
  member: 2,
  editor: 3,
  admin: 4,
  owner: 5,
};

const INVITATION_TTL_DAYS = 7;

export interface ViewerResolution {
  familyId: string;
  viewerPersonId: string | null;
  /** "linked" = resolved via Person.linkedUserId; "anchor" = legacy fallback. */
  resolution: 'linked' | 'anchor' | 'none';
  /** Whether the resolved Person exists (always true when viewerPersonId is set). */
  isLinked: boolean;
}

@Injectable()
export class ViewerService {
  private readonly logger = new Logger(ViewerService.name);

  constructor(private readonly prisma: PrismaService) {}

  /**
   * GET /families/:familyId/viewer
   *
   * Returns the viewer Person ID for the authenticated user.
   */
  async resolveViewer(userId: string, familyId: string): Promise<ViewerResolution> {
    await this.requireFamilyMember(userId, familyId);

    // Step 1: Query Person where linkedUserId = userId AND familyId
    const linked = await this.prisma.person.findFirst({
      where: {
        familyId,
        linkedUserId: userId,
        deletedAt: null,
      },
      select: { id: true, linkedAt: true },
    });

    if (linked) {
      return {
        familyId,
        viewerPersonId: linked.id,
        resolution: 'linked',
        isLinked: true,
      };
    }

    // Step 2: Fall back to anchor person (legacy)
    const anchor = await this.prisma.person.findFirst({
      where: {
        familyId,
        isAnchor: true,
        deletedAt: null,
      },
      select: { id: true },
    });

    if (anchor) {
      return {
        familyId,
        viewerPersonId: anchor.id,
        resolution: 'anchor',
        isLinked: false,
      };
    }

    // Step 3: No viewer found — user should be prompted to claim a profile.
    return {
      familyId,
      viewerPersonId: null,
      resolution: 'none',
      isLinked: false,
    };
  }

  /**
   * POST /families/:familyId/persons/:personId/claim
   *
   * Links the authenticated user to a Person node. Server-side checks:
   *   - User is a family member.
   *   - Person exists in the family and is not soft-deleted.
   *   - Person is not already linked to another user (impersonation prevention).
   *   - The user is not already linked to a different Person in the same family
   *     (duplicate prevention).
   */
  async claimPerson(
    userId: string,
    familyId: string,
    personId: string,
  ): Promise<{ personId: string; linkedUserId: string; linkedAt: Date }> {
    await this.requireFamilyMember(userId, familyId);

    const person = await this.prisma.person.findFirst({
      where: { id: personId, familyId, deletedAt: null },
      select: { id: true, linkedUserId: true, name: true },
    });

    if (!person) {
      throw new NotFoundException('Person not found in this family');
    }

    // Impersonation prevention
    if (person.linkedUserId && person.linkedUserId !== userId) {
      throw new ForbiddenException(
        'This profile is already claimed by another user',
      );
    }

    // Duplicate prevention: a user can only be linked to ONE Person per family.
    const existing = await this.prisma.person.findFirst({
      where: { familyId, linkedUserId: userId, deletedAt: null },
      select: { id: true, name: true },
    });

    if (existing && existing.id !== personId) {
      throw new ForbiddenException(
        `You are already linked to "${existing.name}". Unlink first to claim a different profile.`,
      );
    }

    const now = new Date();
    const updated = await this.prisma.person.update({
      where: { id: personId },
      data: {
        linkedUserId: userId,
        linkedAt: now,
      },
      select: { id: true, linkedUserId: true, linkedAt: true },
    });

    this.logger.log(
      `User ${userId} claimed Person ${personId} in family ${familyId}`,
    );

    return {
      personId: updated.id,
      linkedUserId: updated.linkedUserId!,
      linkedAt: updated.linkedAt!,
    };
  }

  /**
   * DELETE /families/:familyId/persons/:personId/unlink
   *
   * Removes the link between the authenticated user and a Person node.
   * Server-side checks:
   *   - User is a family member.
   *   - Person exists in the family and is not soft-deleted.
   *   - Either the user owns the link OR the user is a family admin/owner.
   */
  async unlinkPerson(
    userId: string,
    familyId: string,
    personId: string,
  ): Promise<{ personId: string; unlinked: true }> {
    const membership = await this.requireFamilyMember(userId, familyId);

    const person = await this.prisma.person.findFirst({
      where: { id: personId, familyId, deletedAt: null },
      select: { id: true, linkedUserId: true, name: true },
    });

    if (!person) {
      throw new NotFoundException('Person not found in this family');
    }

    const isOwner = person.linkedUserId === userId;
    const isAdmin = membership.role === 'admin' || membership.role === 'owner';

    if (!isOwner && !isAdmin) {
      throw new ForbiddenException(
        'Only the linked user or a family admin can unlink this profile',
      );
    }

    if (!person.linkedUserId) {
      // Idempotent: already unlinked.
      return { personId, unlinked: true };
    }

    await this.prisma.person.update({
      where: { id: personId },
      data: {
        linkedUserId: null,
        linkedAt: null,
      },
    });

    this.logger.log(
      `User ${userId} unlinked Person ${personId} in family ${familyId}`,
    );

    return { personId, unlinked: true };
  }

  /**
   * POST /families/:familyId/persons/:personId/invite
   *
   * Creates a PersonLinkInvitation row and returns a one-time code.
   * The recipient uses `acceptInvitation` to bind their userId to the
   * target Person.
   */
  async invitePerson(
    userId: string,
    familyId: string,
    personId: string,
    payload: {
      recipientName?: string;
      recipientEmail?: string;
      recipientPhone?: string;
      role?: string;
    },
  ): Promise<{
    personId: string;
    invitationCode: string;
    recipientEmail?: string;
    recipientPhone?: string;
    expiresAt: Date;
    createdAt: Date;
  }> {
    await this.requireFamilyRole(userId, familyId, 'editor');

    if (!payload.recipientEmail && !payload.recipientPhone) {
      throw new BadRequestException(
        'Either recipientEmail or recipientPhone is required',
      );
    }

    const person = await this.prisma.person.findFirst({
      where: { id: personId, familyId, deletedAt: null },
      select: { id: true, linkedUserId: true, name: true },
    });

    if (!person) {
      throw new NotFoundException('Person not found in this family');
    }

    if (person.linkedUserId) {
      throw new ForbiddenException(
        'This profile is already claimed. Unlink first to invite a new user.',
      );
    }

    // Generate a one-time invitation code (URL-safe, 11 chars).
    const crypto = await import('crypto');
    const invitationCode = crypto.randomBytes(8).toString('base64url');
    const now = new Date();
    const expiresAt = new Date(
      now.getTime() + INVITATION_TTL_DAYS * 24 * 60 * 60 * 1000,
    );

    const invite = await this.prisma.personLinkInvitation.create({
      data: {
        familyId,
        personId,
        code: invitationCode,
        inviterUserId: userId,
        recipientName: payload.recipientName ?? person.name,
        recipientEmail: payload.recipientEmail ?? null,
        recipientPhone: payload.recipientPhone ?? null,
        role: payload.role ?? 'member',
        status: 'pending',
        expiresAt,
      },
    });

    this.logger.log(
      `User ${userId} invited ${payload.recipientEmail ?? payload.recipientPhone} ` +
        `to claim Person ${personId} in family ${familyId} (code ${invitationCode})`,
    );

    return {
      personId,
      invitationCode: invite.code,
      recipientEmail: invite.recipientEmail ?? undefined,
      recipientPhone: invite.recipientPhone ?? undefined,
      expiresAt: invite.expiresAt,
      createdAt: invite.createdAt,
    };
  }

  /**
   * POST /families/:familyId/invitations/:code/accept
   *
   * Accepts a pending PersonLinkInvitation. Links the authenticated user
   * to the Person referenced by the invitation.
   *
   * Server-side checks:
   *   - User is a family member (they must have joined the family first).
   *   - Invitation exists, belongs to this family, is still pending, and
   *     has not expired.
   *   - Person referenced by the invitation is not already claimed.
   *   - The user is not already linked to a different Person in the family.
   */
  async acceptInvitation(
    userId: string,
    familyId: string,
    code: string,
  ): Promise<{
    personId: string;
    linkedUserId: string;
    linkedAt: Date;
    invitationCode: string;
  }> {
    await this.requireFamilyMember(userId, familyId);

    const invite = await this.prisma.personLinkInvitation.findFirst({
      where: {
        familyId,
        code,
        status: 'pending',
      },
    });

    if (!invite) {
      throw new NotFoundException('Invitation not found or already used');
    }

    if (invite.expiresAt && invite.expiresAt < new Date()) {
      await this.prisma.personLinkInvitation.update({
        where: { id: invite.id },
        data: { status: 'expired' },
      });
      throw new ForbiddenException('Invitation has expired');
    }

    const target = await this.prisma.person.findFirst({
      where: { id: invite.personId, familyId, deletedAt: null },
      select: { id: true, linkedUserId: true, name: true },
    });

    if (!target) {
      throw new NotFoundException('Target profile not found');
    }

    if (target.linkedUserId) {
      throw new ForbiddenException(
        'This profile is already claimed by another user',
      );
    }

    // Duplicate prevention
    const existing = await this.prisma.person.findFirst({
      where: { familyId, linkedUserId: userId, deletedAt: null },
      select: { id: true, name: true },
    });
    if (existing && existing.id !== target.id) {
      throw new ForbiddenException(
        `You are already linked to "${existing.name}". Unlink first.`,
      );
    }

    const now = new Date();
    await this.prisma.$transaction(async (tx) => {
      await tx.person.update({
        where: { id: target.id },
        data: {
          linkedUserId: userId,
          linkedAt: now,
        },
      });

      await tx.personLinkInvitation.update({
        where: { id: invite.id },
        data: {
          status: 'accepted',
          acceptedAt: now,
          acceptedByUserId: userId,
        },
      });
    });

    this.logger.log(
      `User ${userId} accepted invitation ${code} and is now linked to Person ${target.id}`,
    );

    return {
      personId: target.id,
      linkedUserId: userId,
      linkedAt: now,
      invitationCode: code,
    };
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  private async requireFamilyMember(userId: string, familyId: string) {
    const membership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId } },
    });

    if (!membership) {
      throw new ForbiddenException('You are not a member of this family');
    }

    return membership;
  }

  private async requireFamilyRole(userId: string, familyId: string, minRole: string) {
    const membership = await this.requireFamilyMember(userId, familyId);

    const userLevel = ROLE_HIERARCHY[membership.role] || 0;
    const requiredLevel = ROLE_HIERARCHY[minRole] || 0;

    if (userLevel < requiredLevel) {
      throw new ForbiddenException(
        `Insufficient permissions. Required: ${minRole}, current: ${membership.role}`,
      );
    }

    return membership;
  }
}
