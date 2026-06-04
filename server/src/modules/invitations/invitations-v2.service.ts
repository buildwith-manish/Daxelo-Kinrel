import {
  Injectable,
  BadRequestException,
  NotFoundException,
  ForbiddenException,
  ConflictException,
  Logger,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { FamilyIdService } from '../families/family-id.service';
import { KinrelGateway } from '../gateway/kinrel.gateway';
import { randomBytes } from 'crypto';
import {
  InviteResult,
  QrInviteResult,
  LinkInviteResult,
  AcceptInviteResult,
  InvitationDetail,
  InviteChannel,
  InviteStatus,
  MemberRole,
} from './dto/invitation-v2.dto';

// ── Constants ──────────────────────────────────────────────────────

const DEFAULT_EXPIRY_DAYS = 7;
const QR_DEFAULT_MAX_USES = 10;
const LINK_DEFAULT_MAX_USES = 0; // 0 = unlimited
const BASE_URL = 'https://kinrel.app';
const DEEP_LINK_PREFIX = 'kinrel://invite';

/** Allowed roles that can be assigned via invitation */
const ASSIGNABLE_ROLES: string[] = [
  MemberRole.ADMIN,
  MemberRole.EDITOR,
  MemberRole.MEMBER,
  MemberRole.VIEWER,
];

/** Roles that are allowed to create invitations */
const INVITER_ROLES: string[] = [MemberRole.ADMIN, MemberRole.EDITOR, MemberRole.MEMBER];

// ── Service ────────────────────────────────────────────────────────

@Injectable()
export class InvitationsV2Service {
  private readonly logger = new Logger(InvitationsV2Service.name);

  constructor(
    private prisma: PrismaService,
    private familyIdService: FamilyIdService,
    private gateway: KinrelGateway,
  ) {}

  // ── Family ID Invite ────────────────────────────────────────────

  /**
   * Create invitation via Family ID.
   * Validates the family exists and user is owner/admin.
   * Returns Family ID that invitee can use to join.
   */
  async createFamilyIdInvite(
    familyId: string,
    inviterId: string,
    role: string = MemberRole.MEMBER,
  ): Promise<InviteResult> {
    // ── Validate family and permission ──────────────────────────
    const { family, membership } = await this.validateFamilyAndPermission(
      familyId,
      inviterId,
    );

    // ── Validate role ───────────────────────────────────────────
    this.validateAssignableRole(role);

    // ── Ensure family has a kinFamilyId ─────────────────────────
    const kinFamilyId = await this.familyIdService.getOrCreateFamilyId(familyId);

    // ── Create a FamilyInvite record to track this invite ──────
    const inviteCode = this.generateInviteCode();

    const expiresAt = this.calculateExpiry(DEFAULT_EXPIRY_DAYS);

    await this.prisma.familyInvite.create({
      data: {
        familyId,
        invitedBy: membership.id,
        inviteCode,
        role,
        status: InviteStatus.PENDING,
        inviteType: InviteChannel.FAMILY_ID,
        maxUses: 1,
        currentUses: 0,
        useCount: 0,
        expiresAt,
      },
    });

    this.logger.log(
      `Family ID invite created: ${kinFamilyId} for family "${family.name}" by user ${inviterId}`,
    );

    return {
      inviteCode: kinFamilyId,
      familyId: family.id,
      familyName: family.name,
      expiresAt,
    };
  }

  // ── QR Code Invite ──────────────────────────────────────────────

  /**
   * Create invitation via QR Code.
   * Generates a unique invite code.
   * Returns QR code data (deep link URL + invite code + family info).
   * QR data format: kinrel://invite/{inviteCode}
   */
  async createQrCodeInvite(
    familyId: string,
    inviterId: string,
    options?: {
      expiresIn?: number;
      maxUses?: number;
      preFilledName?: string;
      role?: string;
    },
  ): Promise<QrInviteResult> {
    // ── Validate family and permission ──────────────────────────
    const { family, membership } = await this.validateFamilyAndPermission(
      familyId,
      inviterId,
    );

    const role = options?.role || MemberRole.MEMBER;
    this.validateAssignableRole(role);

    // ── Generate invite code and compute defaults ───────────────
    const inviteCode = this.generateInviteCode();
    const maxUses = options?.maxUses ?? QR_DEFAULT_MAX_USES;
    const expiryDays = options?.expiresIn ?? DEFAULT_EXPIRY_DAYS;
    const expiresAt = this.calculateExpiry(expiryDays);

    // ── Create FamilyInvite record ──────────────────────────────
    await this.prisma.familyInvite.create({
      data: {
        familyId,
        invitedBy: membership.id,
        inviteCode,
        role,
        status: InviteStatus.PENDING,
        inviteType: InviteChannel.QR_CODE,
        maxUses,
        currentUses: 0,
        useCount: 0,
        expiresAt,
      },
    });

    // ── Build deep link URL for the QR code ─────────────────────
    const qrData = `${DEEP_LINK_PREFIX}/${inviteCode}`;

    this.logger.log(
      `QR code invite created for family "${family.name}" by user ${inviterId}, code=${inviteCode}`,
    );

    return {
      qrData,
      inviteCode,
      familyId: family.id,
      familyName: family.name,
      expiresAt,
    };
  }

  // ── Link Invite ─────────────────────────────────────────────────

  /**
   * Create invitation via Shareable Link.
   * Generates a unique token.
   * Returns shareable URL.
   * URL format: https://kinrel.app/invite/{token}
   */
  async createLinkInvite(
    familyId: string,
    inviterId: string,
    options?: {
      expiresIn?: number;
      maxUses?: number;
      preFilledName?: string;
      suggestedRelation?: string;
      role?: string;
    },
  ): Promise<LinkInviteResult> {
    // ── Validate family and permission ──────────────────────────
    const { family, membership } = await this.validateFamilyAndPermission(
      familyId,
      inviterId,
    );

    const role = options?.role || MemberRole.MEMBER;
    this.validateAssignableRole(role);

    // ── Generate invite code for FamilyInvite ───────────────────
    const inviteCode = this.generateInviteCode();

    // ── Generate a unique token for the Invitation ──────────────
    const token = this.generateToken();

    const maxUses = options?.maxUses ?? LINK_DEFAULT_MAX_USES;
    const expiryDays = options?.expiresIn ?? DEFAULT_EXPIRY_DAYS;
    const expiresAt = this.calculateExpiry(expiryDays);

    // ── Build pre-filled data JSON ──────────────────────────────
    const preFilledData = JSON.stringify({
      name: options?.preFilledName || null,
      suggestedRelation: options?.suggestedRelation || null,
    });

    // ── Create both FamilyInvite and Invitation records ─────────
    await this.prisma.$transaction(async (tx) => {
      // FamilyInvite tracks usage / maxUses / inviteType
      await tx.familyInvite.create({
        data: {
          familyId,
          invitedBy: membership.id,
          inviteCode,
          role,
          status: InviteStatus.PENDING,
          inviteType: InviteChannel.LINK,
          maxUses,
          currentUses: 0,
          useCount: 0,
          expiresAt,
        },
      });

      // Invitation stores the token + deep link for URL-based lookup
      await tx.invitation.create({
        data: {
          token,
          familyId,
          inviterId,
          recipientName: options?.preFilledName || null,
          status: InviteStatus.PENDING,
          role,
          channel: 'direct_link',
          preFilledData,
          deepLinkPath: `${DEEP_LINK_PREFIX}/${token}`,
          expiresAt,
        },
      });
    });

    // ── Build share URL ─────────────────────────────────────────
    const shareUrl = `${BASE_URL}/invite/${token}`;

    this.logger.log(
      `Link invite created for family "${family.name}" by user ${inviterId}, token=${token}`,
    );

    return {
      shareUrl,
      token,
      familyId: family.id,
      familyName: family.name,
      expiresAt,
    };
  }

  // ── Accept Invite ───────────────────────────────────────────────

  /**
   * Accept an invitation.
   * - Validates invite code/token
   * - Creates FamilyMember + Person records
   * - Updates invite status and counts
   * - Emits WebSocket events
   * - Handles idempotency: if user is already a member, return existing membership
   */
  async acceptInvite(
    inviteCodeOrToken: string,
    userId: string,
  ): Promise<AcceptInviteResult> {
    // ── 1. Try to find the invite ───────────────────────────────
    // First try FamilyInvite by inviteCode, then Invitation by token
    let familyInvite = await this.prisma.familyInvite.findUnique({
      where: { inviteCode: inviteCodeOrToken },
      include: {
        family: { select: { id: true, name: true } },
      },
    });

    let invitation: {
      id: string;
      token: string;
      familyId: string;
      inviterId: string;
      status: string;
      role: string;
      channel: string;
      expiresAt: Date | null;
      preFilledData: string;
      recipientName: string | null;
    } | null = null;

    let targetFamilyId: string;
    let targetRole: string;
    let inviteChannel: string;

    if (familyInvite) {
      // Found via FamilyInvite.inviteCode
      targetFamilyId = familyInvite.familyId;
      targetRole = familyInvite.role;
      inviteChannel = familyInvite.inviteType;

      // ── Validate status ───────────────────────────────────────
      if (familyInvite.status !== InviteStatus.PENDING) {
        throw new BadRequestException(
          `This invitation is already ${familyInvite.status}`,
        );
      }

      // ── Validate expiry ───────────────────────────────────────
      if (familyInvite.expiresAt && familyInvite.expiresAt < new Date()) {
        await this.prisma.familyInvite.update({
          where: { id: familyInvite.id },
          data: { status: InviteStatus.EXPIRED },
        });
        throw new BadRequestException('This invitation has expired');
      }

      // ── Validate max uses ─────────────────────────────────────
      if (familyInvite.maxUses > 0 && familyInvite.currentUses >= familyInvite.maxUses) {
        await this.prisma.familyInvite.update({
          where: { id: familyInvite.id },
          data: { status: InviteStatus.EXPIRED },
        });
        throw new BadRequestException(
          'This invitation has reached its maximum number of uses',
        );
      }
    } else {
      // Try Invitation by token (for link invites)
      invitation = await this.prisma.invitation.findUnique({
        where: { token: inviteCodeOrToken },
        include: {
          family: { select: { id: true, name: true } },
        },
      });

      if (!invitation) {
        throw new NotFoundException(
          'Invitation not found. The code or link may be invalid.',
        );
      }

      targetFamilyId = invitation.familyId;
      targetRole = invitation.role;
      inviteChannel = invitation.channel;

      // ── Validate status ───────────────────────────────────────
      if (invitation.status !== InviteStatus.PENDING) {
        throw new BadRequestException(
          `This invitation is already ${invitation.status}`,
        );
      }

      // ── Validate expiry ───────────────────────────────────────
      if (invitation.expiresAt && invitation.expiresAt < new Date()) {
        await this.prisma.invitation.update({
          where: { id: invitation.id },
          data: { status: InviteStatus.EXPIRED },
        });
        throw new BadRequestException('This invitation has expired');
      }
    }

    // ── 2. Check if user is already a member (idempotency) ──────
    const existingMembership = await this.prisma.familyMember.findUnique({
      where: {
        familyId_userId: { familyId: targetFamilyId, userId },
      },
    });

    if (existingMembership) {
      // Idempotent: return existing membership info
      const family = await this.prisma.family.findUnique({
        where: { id: targetFamilyId },
        select: { name: true },
      });

      // Check if there's a person record for this user in this family
      const existingPerson = await this.prisma.person.findFirst({
        where: {
          familyId: targetFamilyId,
          name: { not: '' },
        },
        orderBy: { createdAt: 'desc' },
      });

      this.logger.log(
        `User ${userId} is already a member of family "${family?.name}" — returning existing membership (idempotent)`,
      );

      return {
        familyId: targetFamilyId,
        familyName: family?.name || 'Unknown',
        role: existingMembership.role,
        personId: existingPerson?.id || '',
      };
    }

    // ── 3. Get user info for Person creation ────────────────────
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, name: true, username: true },
    });

    // Determine person name: pre-filled data > user profile > fallback
    let personName = user?.name || user?.username || 'New Member';
    if (invitation?.recipientName) {
      personName = invitation.recipientName;
    }
    if (familyInvite) {
      // For FamilyInvite, no direct preFilledName stored — use user profile
      personName = user?.name || user?.username || 'New Member';
    }

    // ── 4. Create FamilyMember + Person in transaction ──────────
    const result = await this.prisma.$transaction(async (tx) => {
      // Create Person record
      const person = await tx.person.create({
        data: {
          familyId: targetFamilyId,
          name: personName,
          privacyLevel: 'family',
          generationIndex: 0,
          isAnchor: false,
        },
      });

      // Create FamilyMember record
      const familyMember = await tx.familyMember.create({
        data: {
          familyId: targetFamilyId,
          userId,
          role: targetRole,
        },
      });

      // Increment family member count and update last activity
      await tx.family.update({
        where: { id: targetFamilyId },
        data: {
          memberCount: { increment: 1 },
          lastActivityAt: new Date(),
        },
      });

      // ── Update FamilyInvite if applicable ─────────────────────
      if (familyInvite) {
        await tx.familyInvite.update({
          where: { id: familyInvite.id },
          data: {
            currentUses: { increment: 1 },
            useCount: { increment: 1 },
            // If this was the last allowed use, mark as accepted
            status:
              familyInvite.maxUses > 0 &&
              familyInvite.currentUses + 1 >= familyInvite.maxUses
                ? InviteStatus.ACCEPTED
                : InviteStatus.PENDING,
          },
        });
      }

      // ── Update Invitation if applicable ───────────────────────
      if (invitation) {
        await tx.invitation.update({
          where: { id: invitation.id },
          data: {
            status: InviteStatus.ACCEPTED,
            acceptedAt: new Date(),
          },
        });
      }

      return { familyMember, person };
    });

    // ── 5. Emit WebSocket events ────────────────────────────────
    const family = await this.prisma.family.findUnique({
      where: { id: targetFamilyId },
      select: { name: true },
    });

    // Notify family members that a new person was created
    this.gateway.emitToFamily(targetFamilyId, 'person:created', {
      id: result.person.id,
      updatedAt: new Date().toISOString(),
      type: 'person:created',
      familyId: targetFamilyId,
    });

    // Notify family members that someone joined
    this.gateway.emitToFamily(targetFamilyId, 'member:joined', {
      id: result.familyMember.id,
      updatedAt: new Date().toISOString(),
      type: 'member:joined',
      familyId: targetFamilyId,
      userId,
    });

    // Notify about graph update (debounced by gateway)
    this.gateway.emitToFamily(targetFamilyId, 'graph:updated', {
      id: targetFamilyId,
      updatedAt: new Date().toISOString(),
      type: 'graph:updated',
      familyId: targetFamilyId,
    });

    this.logger.log(
      `User ${userId} accepted invite to family "${family?.name}" (${targetFamilyId}) as ${targetRole} via ${inviteChannel}`,
    );

    return {
      familyId: targetFamilyId,
      familyName: family?.name || 'Unknown',
      role: targetRole,
      personId: result.person.id,
    };
  }

  // ── Reject Invite ───────────────────────────────────────────────

  /**
   * Reject an invitation.
   */
  async rejectInvite(inviteCode: string, userId: string): Promise<void> {
    // Try FamilyInvite first
    const familyInvite = await this.prisma.familyInvite.findUnique({
      where: { inviteCode },
    });

    if (familyInvite) {
      if (familyInvite.status !== InviteStatus.PENDING) {
        throw new BadRequestException(
          `Cannot reject an invitation that is ${familyInvite.status}`,
        );
      }

      await this.prisma.familyInvite.update({
        where: { id: familyInvite.id },
        data: { status: InviteStatus.REJECTED },
      });

      this.logger.log(
        `User ${userId} rejected FamilyInvite ${familyInvite.id}`,
      );
      return;
    }

    // Try Invitation by token
    const invitation = await this.prisma.invitation.findUnique({
      where: { token: inviteCode },
    });

    if (invitation) {
      if (invitation.status !== InviteStatus.PENDING) {
        throw new BadRequestException(
          `Cannot reject an invitation that is ${invitation.status}`,
        );
      }

      await this.prisma.invitation.update({
        where: { id: invitation.id },
        data: { status: InviteStatus.CANCELLED },
      });

      this.logger.log(
        `User ${userId} rejected Invitation ${invitation.id}`,
      );
      return;
    }

    throw new NotFoundException('Invitation not found');
  }

  // ── Get Pending Invitations ─────────────────────────────────────

  /**
   * Get pending invitations for a user.
   * Looks up invitations by the user's email or phone in the Invitation model,
   * plus any FamilyInvite records where the user was invited.
   */
  async getPendingInvitations(userId: string): Promise<InvitationDetail[]> {
    // Get user info for matching
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { email: true, phone: true },
    });

    if (!user) {
      return [];
    }

    // ── Invitation records matching user's email or phone ──────
    const invitations = await this.prisma.invitation.findMany({
      where: {
        status: InviteStatus.PENDING,
        OR: [
          { recipientEmail: user.email },
          ...(user.phone ? [{ recipientPhone: user.phone }] : []),
        ],
      },
      include: {
        family: { select: { name: true } },
        inviter: { select: { name: true } },
      },
      orderBy: { createdAt: 'desc' },
    });

    return invitations.map((inv) => ({
      id: inv.id,
      familyId: inv.familyId,
      familyName: inv.family.name,
      inviterName: inv.inviter?.name || 'Unknown',
      status: inv.status,
      role: inv.role,
      channel: inv.channel,
      createdAt: inv.createdAt,
      expiresAt: inv.expiresAt,
    }));
  }

  // ── Get Family Invitations ──────────────────────────────────────

  /**
   * Get invitations for a family (admin/owner only).
   */
  async getFamilyInvitations(
    familyId: string,
    requesterId: string,
  ): Promise<InvitationDetail[]> {
    // ── Validate permission ─────────────────────────────────────
    const membership = await this.prisma.familyMember.findUnique({
      where: {
        familyId_userId: { familyId, userId: requesterId },
      },
    });

    if (!membership) {
      throw new ForbiddenException(
        'You are not a member of this family',
      );
    }

    if (!INVITER_ROLES.includes(membership.role) && membership.role !== MemberRole.ADMIN) {
      throw new ForbiddenException(
        'Only admins, editors, and members can view family invitations',
      );
    }

    // ── Fetch both FamilyInvite and Invitation records ──────────
    const familyInvites = await this.prisma.familyInvite.findMany({
      where: { familyId },
      include: {
        family: { select: { name: true } },
        inviterMember: {
          include: {
            user: { select: { name: true } },
          },
        },
      },
      orderBy: { createdAt: 'desc' },
    });

    const invitations = await this.prisma.invitation.findMany({
      where: { familyId },
      include: {
        family: { select: { name: true } },
        inviter: { select: { name: true } },
      },
      orderBy: { createdAt: 'desc' },
    });

    // ── Merge and format results ────────────────────────────────
    const familyInviteDetails: InvitationDetail[] = familyInvites.map((fi) => ({
      id: fi.id,
      familyId: fi.familyId,
      familyName: fi.family.name,
      inviterName: fi.inviterMember?.user?.name || 'Unknown',
      status: fi.status,
      role: fi.role,
      channel: fi.inviteType,
      createdAt: fi.createdAt,
      expiresAt: fi.expiresAt,
    }));

    const invitationDetails: InvitationDetail[] = invitations.map((inv) => ({
      id: inv.id,
      familyId: inv.familyId,
      familyName: inv.family.name,
      inviterName: inv.inviter?.name || 'Unknown',
      status: inv.status,
      role: inv.role,
      channel: inv.channel,
      createdAt: inv.createdAt,
      expiresAt: inv.expiresAt,
    }));

    // Combine, deduplicate by id (FamilyInvite ids are uuid, Invitation ids are cuid — no overlap)
    const combined = [...familyInviteDetails, ...invitationDetails];

    // Sort by createdAt descending
    combined.sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime());

    return combined;
  }

  // ── Revoke Invite ───────────────────────────────────────────────

  /**
   * Revoke an invitation.
   * Only the inviter or a family admin can revoke.
   */
  async revokeInvite(inviteId: string, revokerId: string): Promise<void> {
    // ── Try FamilyInvite first ──────────────────────────────────
    const familyInvite = await this.prisma.familyInvite.findUnique({
      where: { id: inviteId },
    });

    if (familyInvite) {
      // Check permission: inviter member's user OR family admin
      await this.validateRevokePermissionFamilyInvite(
        familyInvite.familyId,
        familyInvite.invitedBy,
        revokerId,
      );

      if (familyInvite.status !== InviteStatus.PENDING) {
        throw new BadRequestException(
          `Cannot revoke an invitation that is ${familyInvite.status}`,
        );
      }

      await this.prisma.familyInvite.update({
        where: { id: inviteId },
        data: { status: InviteStatus.CANCELLED },
      });

      this.logger.log(
        `FamilyInvite ${inviteId} revoked by user ${revokerId}`,
      );
      return;
    }

    // ── Try Invitation ──────────────────────────────────────────
    const invitation = await this.prisma.invitation.findUnique({
      where: { id: inviteId },
    });

    if (invitation) {
      // Check permission: inviter OR family admin
      if (invitation.inviterId !== revokerId) {
        const membership = await this.prisma.familyMember.findUnique({
          where: {
            familyId_userId: {
              familyId: invitation.familyId,
              userId: revokerId,
            },
          },
        });

        if (!membership || membership.role !== MemberRole.ADMIN) {
          throw new ForbiddenException(
            'Only the inviter or a family admin can revoke this invitation',
          );
        }
      }

      if (invitation.status !== InviteStatus.PENDING) {
        throw new BadRequestException(
          `Cannot revoke an invitation that is ${invitation.status}`,
        );
      }

      await this.prisma.invitation.update({
        where: { id: inviteId },
        data: { status: InviteStatus.CANCELLED },
      });

      this.logger.log(
        `Invitation ${inviteId} revoked by user ${revokerId}`,
      );
      return;
    }

    throw new NotFoundException('Invitation not found');
  }

  // ── Expire Old Invitations ──────────────────────────────────────

  /**
   * Expire old invitations (called by cron job).
   * Returns the number of invitations expired.
   */
  async expireOldInvitations(): Promise<number> {
    const now = new Date();
    let totalExpired = 0;

    // ── Expire FamilyInvite records ─────────────────────────────
    const familyInviteResult = await this.prisma.familyInvite.updateMany({
      where: {
        status: InviteStatus.PENDING,
        expiresAt: { lt: now },
      },
      data: { status: InviteStatus.EXPIRED },
    });
    totalExpired += familyInviteResult.count;

    // ── Expire Invitation records ───────────────────────────────
    const invitationResult = await this.prisma.invitation.updateMany({
      where: {
        status: InviteStatus.PENDING,
        expiresAt: { lt: now },
      },
      data: { status: InviteStatus.EXPIRED },
    });
    totalExpired += invitationResult.count;

    if (totalExpired > 0) {
      this.logger.log(
        `Expired ${totalExpired} old invitations (${familyInviteResult.count} FamilyInvite + ${invitationResult.count} Invitation)`,
      );
    }

    return totalExpired;
  }

  // ── Private Helpers ─────────────────────────────────────────────

  /**
   * Validate that the user is a member of the family with permission to invite.
   * Returns the family and membership records.
   */
  private async validateFamilyAndPermission(
    familyId: string,
    userId: string,
  ): Promise<{
    family: { id: string; name: string; kinFamilyId: string | null };
    membership: { id: string; role: string };
  }> {
    // ── Verify family exists ────────────────────────────────────
    const family = await this.prisma.family.findUnique({
      where: { id: familyId },
      select: { id: true, name: true, kinFamilyId: true },
    });

    if (!family) {
      throw new NotFoundException('Family not found');
    }

    // ── Verify user is a member with permission to invite ──────
    const membership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId } },
    });

    if (!membership) {
      throw new ForbiddenException(
        'You are not a member of this family',
      );
    }

    if (!INVITER_ROLES.includes(membership.role)) {
      throw new ForbiddenException(
        'Only admins, editors, and members can create invitations',
      );
    }

    return { family, membership };
  }

  /**
   * Validate that a role can be assigned via invitation.
   */
  private validateAssignableRole(role: string): void {
    if (!ASSIGNABLE_ROLES.includes(role)) {
      throw new BadRequestException(
        `Invalid role "${role}". Must be one of: ${ASSIGNABLE_ROLES.join(', ')}`,
      );
    }
  }

  /**
   * Validate revoke permission for a FamilyInvite.
   * The revoker must be the user who created the invite (via FamilyMember)
   * or a family admin.
   */
  private async validateRevokePermissionFamilyInvite(
    familyId: string,
    invitedByMemberId: string,
    revokerId: string,
  ): Promise<void> {
    // Check if the revoker is the inviter (compare user IDs)
    const inviterMember = await this.prisma.familyMember.findUnique({
      where: { id: invitedByMemberId },
      select: { userId: true },
    });

    if (inviterMember?.userId === revokerId) {
      return; // Inviter can revoke their own invites
    }

    // Check if revoker is a family admin
    const membership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId: revokerId } },
    });

    if (!membership || membership.role !== MemberRole.ADMIN) {
      throw new ForbiddenException(
        'Only the inviter or a family admin can revoke this invitation',
      );
    }
  }

  /**
   * Generate a unique invite code.
   * Uses crypto.randomBytes for cryptographic randomness.
   * Format: 12-character alphanumeric string.
   */
  private generateInviteCode(): string {
    return randomBytes(9).toString('base64url').slice(0, 12);
  }

  /**
   * Generate a unique token for shareable links.
   * Uses crypto.randomBytes for cryptographic randomness.
   * Format: 48-character hex string.
   */
  private generateToken(): string {
    return randomBytes(24).toString('hex');
  }

  /**
   * Calculate expiry date from now.
   * @param days Number of days from now.
   */
  private calculateExpiry(days: number): Date {
    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + days);
    return expiresAt;
  }
}
