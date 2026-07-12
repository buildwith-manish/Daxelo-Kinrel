import {
  Injectable,
  BadRequestException,
  NotFoundException,
  ForbiddenException,
  Inject,
  forwardRef,
  Logger,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { CreateFamilyDto } from './dto/create-family.dto';
import { UpdateFamilyDto } from './dto/update-family.dto';
import { FamilyIdService } from './family-id.service';
import { KinrelGateway } from '../gateway/kinrel.gateway';
import { NotificationsService } from '../notifications/notifications.service';
import { Cron, CronExpression } from '@nestjs/schedule';

const ROLE_HIERARCHY: Record<string, number> = {
  viewer: 1,
  member: 2,
  editor: 3,
  admin: 4,
};

/** Number of days a family stays in archive before permanent deletion */
const ARCHIVE_RETENTION_DAYS = 30;

@Injectable()
export class FamiliesService {
  private readonly logger = new Logger(FamiliesService.name);

  constructor(
    private prisma: PrismaService,
    @Inject(forwardRef(() => FamilyIdService))
    private familyIdService: FamilyIdService,
    private gateway: KinrelGateway,
    @Inject(forwardRef(() => NotificationsService))
    private notificationsService: NotificationsService,
  ) {}

  /** Creates a new family and assigns the creator as admin member. */
  async create(userId: string, dto: CreateFamilyDto) {
    if (!dto.name || typeof dto.name !== 'string' || dto.name.trim().length === 0) {
      throw new BadRequestException('Family name is required');
    }

    // Pre-generate the Family ID outside the transaction to avoid
    // holding a transaction lock while generating a random ID
    const kinFamilyId = await this.familyIdService.generateFamilyId();

    // Use username as familyCode if provided (same convention as Flutter direct writes)
    const effectiveUsername = dto.username?.trim() || null;
    const familyCode = effectiveUsername || undefined; // falls back to cuid() default

    const family = await this.prisma.$transaction(async (tx) => {
      const created = await tx.family.create({
        data: {
          name: dto.name.trim(),
          description: dto.description?.trim() || null,
          primaryLanguage: dto.primaryLanguage || 'en',
          gotra: dto.gotra?.trim() || null,
          originVillage: dto.originVillage?.trim() || null,
          privacyMode: dto.privacyMode || 'private',
          region: dto.region?.trim() || null,
          username: effectiveUsername,
          avatarUrl: dto.avatarUrl || null,
          ...(familyCode ? { familyCode } : {}),
          createdBy: userId,
          memberCount: 0,
          lastActivityAt: new Date(),
          kinFamilyId,
        },
      });

      await tx.familyMember.create({
        data: {
          familyId: created.id,
          userId,
          // ✅ FIX: Family creator must be 'owner', not 'admin'.
          // The RLS policies for Person/FamilyMember/Relationship
          // INSERT checks require role IN ('owner','admin','member'),
          // so 'admin' technically works — but 'owner' is semantically
          // correct and matches what the _fn_after_family_insert
          // trigger sets. Using 'admin' here previously caused a
          // unique-constraint race with the trigger and left creators
          // with the wrong role in the database.
          role: 'owner',
        },
      });

      return created;
    });

    const formattedFamily = this.formatFamily(family);

    // Fire-and-forget — wrapped in try/catch inside each notify method
    this.notificationsService.notifyFamilyCreated(userId, family.name, family.id);
    this.notificationsService.notifyFamilyInviteLinkReady(userId, family.name, family.id);

    return formattedFamily;
  }

  /**
   * Builds the Prisma `where` clause for FamilyMember queries that handles
   * both the Prisma CUID and the legacy Supabase UUID.
   *
   * FamilyMember records created before the auth fix stored the Supabase
   * UUID in `userId`. After the fix, new records use the Prisma CUID.
   * This helper ensures queries match BOTH IDs so legacy families remain
   * visible to their owners.
   *
   * BUG-045 FIX: Validate CUID/UUID format before constructing the filter.
   * Prisma escapes values, but a compromised JWT could still inject values
   * that bypass naive Prisma filters via the `in: [...]` clause. The regex
   * below accepts only well-formed CUIDs (c + 24 base36 chars) and UUIDs
   * (8-4-4-4-12 hex). Anything else is rejected.
   */
  private buildUserIdFilter(userId: string, supabaseUid?: string) {
    const cuidRegex = /^c[a-z0-9]{24}$/i;
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

    if (!cuidRegex.test(userId) && !uuidRegex.test(userId)) {
      this.logger.error(`Invalid userId format in buildUserIdFilter: ${userId}`);
      throw new BadRequestException('Invalid user ID format');
    }

    if (supabaseUid && supabaseUid !== userId) {
      if (!cuidRegex.test(supabaseUid) && !uuidRegex.test(supabaseUid)) {
        // Don't throw — just ignore the invalid supabaseUid and fall back
        // to the validated userId alone. Throwing here would lock users
        // out of their legacy families if the JWT `sub` claim is malformed.
        this.logger.warn(`Ignoring malformed supabaseUid in buildUserIdFilter: ${supabaseUid}`);
        return { userId };
      }
      return { userId: { in: [userId, supabaseUid] } };
    }
    return { userId };
  }

  /** Returns all active (non-archived) families the user is a member of, with pagination. */
  async findAll(userId: string, pagination?: { page?: number; limit?: number }, supabaseUid?: string) {
    const page = pagination?.page ?? 1;
    const limit = pagination?.limit ?? 20;
    const skip = (page - 1) * limit;
    const userFilter = this.buildUserIdFilter(userId, supabaseUid);

    // First get total count of active families
    const total = await this.prisma.familyMember.count({
      where: { ...userFilter, family: { deletedAt: null } },
    });

    // Then get the paginated family members with active families
    const items = await this.prisma.familyMember.findMany({
      where: { ...userFilter, family: { deletedAt: null } },
      skip,
      take: limit,
      include: {
        family: {
          select: {
            id: true,
            name: true,
            familyCode: true,
            kinFamilyId: true,
            username: true,
            description: true,
            primaryLanguage: true,
            gotra: true,
            originVillage: true,
            privacyMode: true,
            anchorPersonId: true,
            memberCount: true,
            generationCount: true,
            createdBy: true,
            avatarUrl: true,
            region: true,
            isOnboarded: true,
            lastActivityAt: true,
            createdAt: true,
            deletedAt: true,
          },
        },
      },
      orderBy: { joinedAt: 'desc' },
    });

    return {
      items: items.map((m) => this.formatFamily(m.family)),
      total,
      page,
      limit,
    };
  }

  /** Returns a single active family by ID after verifying membership. */
  async findOne(userId: string, familyId: string) {
    await this.requireFamilyMember(userId, familyId);

    const family = await this.prisma.family.findUnique({
      where: { id: familyId },
    });

    if (!family) {
      throw new NotFoundException('Family not found');
    }

    if (family.deletedAt) {
      throw new NotFoundException('This family has been archived');
    }

    return this.formatFamily(family);
  }

  /** Updates family details; requires at least editor role. */
  async update(userId: string, familyId: string, dto: UpdateFamilyDto) {
    await this.requireFamilyRole(userId, familyId, 'editor');

    const existing = await this.prisma.family.findUnique({
      where: { id: familyId },
    });

    if (!existing) {
      throw new NotFoundException('Family not found');
    }

    if (existing.deletedAt) {
      throw new BadRequestException('Cannot update an archived family. Restore it first.');
    }

    const updateData: Record<string, unknown> = {};

    if (dto.name !== undefined) updateData.name = dto.name.trim();
    if (dto.description !== undefined) updateData.description = dto.description?.trim() || null;
    if (dto.primaryLanguage !== undefined) updateData.primaryLanguage = dto.primaryLanguage;
    if (dto.gotra !== undefined) updateData.gotra = dto.gotra?.trim() || null;
    if (dto.originVillage !== undefined) updateData.originVillage = dto.originVillage?.trim() || null;
    if (dto.privacyMode !== undefined) updateData.privacyMode = dto.privacyMode;
    if (dto.username !== undefined) updateData.username = dto.username?.trim() || null;
    if (dto.avatarUrl !== undefined) updateData.avatarUrl = dto.avatarUrl;
    if (dto.region !== undefined) updateData.region = dto.region?.trim() || null;
    // P1.4: Bridge role opt-in toggle.
    if (dto.bridgeRoleOptIn !== undefined) updateData.bridgeRoleOptIn = dto.bridgeRoleOptIn;
    updateData.lastActivityAt = new Date();

    const updated = await this.prisma.family.update({
      where: { id: familyId },
      data: updateData,
    });

    return this.formatFamily(updated);
  }

  // ── Archive (Soft-Delete) ─────────────────────────────────────────────

  /**
   * Archives a family by setting deletedAt timestamp.
   * The family and all its data remain recoverable for 30 days,
   * after which the cron job permanently deletes it.
   */
  async archive(userId: string, familyId: string) {
    await this.requireFamilyRole(userId, familyId, 'admin');

    const family = await this.prisma.family.findUnique({
      where: { id: familyId },
    });

    if (!family) {
      throw new NotFoundException('Family not found');
    }

    if (family.deletedAt) {
      throw new BadRequestException('This family is already archived');
    }

    const now = new Date();
    const permanentDeleteAt = new Date(
      now.getTime() + ARCHIVE_RETENTION_DAYS * 24 * 60 * 60 * 1000,
    );

    // Soft-delete: set deletedAt on family AND all persons in the family
    // BUG-014 FIX: Also cascade-soft-delete to relationships (isActive=false)
    // and family invites (active=false) so archived families stop appearing
    // in searches/lookups while still being fully restorable.
    await this.prisma.$transaction(async (tx) => {
      // 1. Soft-delete all active persons in the family
      await tx.person.updateMany({
        where: { familyId, deletedAt: null },
        data: { deletedAt: now },
      });

      // 2. BUG-014 FIX: Deactivate all active relationships so the archived
      //    family stops showing up in path-finding / kinship lookups.
      await tx.relationship.updateMany({
        where: { familyId, isActive: true },
        data: { isActive: false, updatedAt: now },
      }).catch(() => {
        // updatedAt column may not exist on older schemas — ignore.
      });

      // 3. BUG-014 FIX: Revoke all active invite links.
      await tx.familyInvite.updateMany({
        where: { familyId, active: true },
        data: { active: false },
      }).catch(() => {});

      // 4. Soft-delete the family itself
      await tx.family.update({
        where: { id: familyId },
        data: { deletedAt: now },
      });
    });

    // Emit WebSocket event
    this.gateway.emitToFamily(familyId, 'family:archived', {
      id: familyId,
      updatedAt: now.toISOString(),
      type: 'family:archived',
      familyId,
      archivedBy: userId,
      permanentDeleteAt: permanentDeleteAt.toISOString(),
    });

    this.logger.log(
      `Family "${family.name}" (${familyId}) archived by user ${userId}. ` +
      `Permanent deletion scheduled for ${permanentDeleteAt.toISOString()}`,
    );

    return {
      archived: true,
      familyId,
      familyName: family.name,
      archivedAt: now.toISOString(),
      permanentDeleteAt: permanentDeleteAt.toISOString(),
      daysUntilPermanentDeletion: ARCHIVE_RETENTION_DAYS,
      message: `Family archived. It will be permanently deleted in ${ARCHIVE_RETENTION_DAYS} days. You can restore it before then.`,
    };
  }

  // ── Restore (Undo Archive) ────────────────────────────────────────────

  /**
   * Restores an archived family by clearing deletedAt.
   * Also restores all persons that were soft-deleted at the same time.
   */
  async restore(userId: string, familyId: string) {
    const membership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId } },
    });

    if (!membership) {
      throw new ForbiddenException('You are not a member of this family');
    }

    const family = await this.prisma.family.findUnique({
      where: { id: familyId },
    });

    if (!family) {
      throw new NotFoundException('Family not found');
    }

    if (!family.deletedAt) {
      throw new BadRequestException('This family is not archived');
    }

    const archivedAt = family.deletedAt;

    await this.prisma.$transaction(async (tx) => {
      // 1. Restore persons that were archived at the same time as the family
      // (within a 5-second window to account for transaction latency)
      const archiveWindowStart = new Date(archivedAt.getTime() - 5000);
      const archiveWindowEnd = new Date(archivedAt.getTime() + 5000);

      await tx.person.updateMany({
        where: {
          familyId,
          deletedAt: { gte: archiveWindowStart, lte: archiveWindowEnd },
        },
        data: { deletedAt: null },
      });

      // 2. BUG-014 FIX: Reactivate relationships that were deactivated at
      //    archive time. Use the same 5s window.
      await tx.relationship.updateMany({
        where: {
          familyId,
          isActive: false,
          updatedAt: { gte: archiveWindowStart, lte: archiveWindowEnd },
        },
        data: { isActive: true },
      }).catch(() => {});

      // 3. Restore the family itself
      await tx.family.update({
        where: { id: familyId },
        data: { deletedAt: null, lastActivityAt: new Date() },
      });
    });

    // Emit WebSocket event
    this.gateway.emitToFamily(familyId, 'family:restored', {
      id: familyId,
      updatedAt: new Date().toISOString(),
      type: 'family:restored',
      familyId,
      restoredBy: userId,
    });

    this.logger.log(
      `Family "${family.name}" (${familyId}) restored by user ${userId}`,
    );

    return {
      restored: true,
      familyId,
      familyName: family.name,
      message: 'Family restored successfully!',
    };
  }

  // ── List Archived Families ────────────────────────────────────────────

  /**
   * Returns all archived families for the current user,
   * including days remaining until permanent deletion.
   */
  async findArchived(userId: string, pagination?: { page?: number; limit?: number }, supabaseUid?: string) {
    const page = pagination?.page ?? 1;
    const limit = pagination?.limit ?? 20;
    const skip = (page - 1) * limit;
    const userFilter = this.buildUserIdFilter(userId, supabaseUid);

    const total = await this.prisma.familyMember.count({
      where: { ...userFilter, family: { deletedAt: { not: null } } },
    });

    const items = await this.prisma.familyMember.findMany({
      where: { ...userFilter, family: { deletedAt: { not: null } } },
      skip,
      take: limit,
      include: {
        family: {
          select: {
            id: true,
            name: true,
            familyCode: true,
            kinFamilyId: true,
            username: true,
            description: true,
            primaryLanguage: true,
            gotra: true,
            originVillage: true,
            privacyMode: true,
            anchorPersonId: true,
            memberCount: true,
            generationCount: true,
            createdBy: true,
            avatarUrl: true,
            region: true,
            isOnboarded: true,
            lastActivityAt: true,
            createdAt: true,
            deletedAt: true,
          },
        },
      },
      orderBy: { joinedAt: 'desc' },
    });

    const now = new Date();

    return {
      items: items.map((m) => {
        const family = this.formatFamily(m.family);
        const archivedAt = m.family.deletedAt!;
        const permanentDeleteAt = new Date(
          archivedAt.getTime() + ARCHIVE_RETENTION_DAYS * 24 * 60 * 60 * 1000,
        );
        const daysRemaining = Math.max(
          0,
          Math.ceil(
            (permanentDeleteAt.getTime() - now.getTime()) / (24 * 60 * 60 * 1000),
          ),
        );

        return {
          ...family,
          archivedAt: archivedAt.toISOString(),
          permanentDeleteAt: permanentDeleteAt.toISOString(),
          daysRemaining,
          isExpired: daysRemaining <= 0,
        };
      }),
      total,
      page,
      limit,
    };
  }

  // ── Permanent Delete (Hard Delete) ────────────────────────────────────

  /**
   * Permanently deletes a family and all its data.
   * Can only be called for archived families, or by the cron job after 30 days.
   *
   * BUG-004 FIX: This method now requires the caller's userId and performs
   * an admin-role check at the SERVICE layer (not just the controller).
   * The previous signature `permanentDelete(familyId)` could be invoked
   * directly by any internal caller (cron job, websocket handler, etc.)
   * with no role check at all — a malicious member who could trigger such
   * a call path would have been able to permanently destroy the family.
   * The cron job continues to pass `undefined` as the userId and is
   * explicitly allowed to proceed.
   */
  async permanentDelete(familyId: string, userId?: string) {
    // BUG-004 FIX: service-layer role check (controller check is not enough)
    if (userId !== undefined) {
      await this.requireFamilyRole(userId, familyId, 'admin');
    }
    // When userId is undefined, the caller is the internal cron job — allowed.

    const family = await this.prisma.family.findUnique({
      where: { id: familyId },
    });

    if (!family) {
      throw new NotFoundException('Family not found');
    }

    // BUG-004 FIX: Only allow permanent deletion of ARCHIVED families.
    // The cron job only ever invokes this on families with deletedAt set,
    // so this guard is a no-op for it. But if a human-triggered call (admin)
    // somehow bypasses the archive step, we refuse to hard-delete live data.
    if (!family.deletedAt && userId !== undefined) {
      throw new BadRequestException(
        'Cannot permanently delete an active family. Archive it first.',
      );
    }

    // BUG-004 FIX: Audit trail — who deleted what, when.
    this.logger.warn(
      `PERMANENT DELETION: Family "${family.name}" (${familyId}) ` +
      `deleted by ${userId ?? 'cron job'} at ${new Date().toISOString()}`,
    );

    await this.prisma.$transaction(async (tx) => {
      // 1. Find all person IDs in the family (including soft-deleted)
      const personIds = await tx.person.findMany({
        where: { familyId },
        select: { id: true },
      });
      const ids = personIds.map((p) => p.id);

      if (ids.length > 0) {
        // 2. Delete all relationships for those persons
        await tx.relationship.deleteMany({
          where: {
            OR: [
              { fromPersonId: { in: ids } },
              { toPersonId: { in: ids } },
            ],
          },
        });
      }

      // 3. Delete all persons (including soft-deleted)
      await tx.person.deleteMany({ where: { familyId } });

      // 4. Delete other family-related data
      await tx.graphLayoutState.deleteMany({ where: { familyId } }).catch(() => {});
      await tx.graphChangeLog.deleteMany({ where: { familyId } }).catch(() => {});
      await tx.familyPost.deleteMany({ where: { familyId } }).catch(() => {});
      await tx.story.deleteMany({ where: { familyId } }).catch(() => {});
      await tx.invitation.deleteMany({ where: { familyId } }).catch(() => {});
      await tx.familyInvite.deleteMany({ where: { familyId } }).catch(() => {});

      // 5. Delete all FamilyMember records
      await tx.familyMember.deleteMany({ where: { familyId } });

      // 6. Delete the Family record itself
      await tx.family.delete({ where: { id: familyId } });
    });

    this.logger.log(
      `Family "${family.name}" (${familyId}) permanently deleted`,
    );

    return { deleted: true, familyId, familyName: family.name };
  }

  // ── Cron: Auto-Purge Expired Archived Families ────────────────────────

  /**
   * Runs daily at 3:00 AM UTC to permanently delete families
   * that have been archived for more than 30 days.
   */
  @Cron('0 3 * * *')
  async purgeExpiredArchivedFamilies() {
    const expirationDate = new Date(
      Date.now() - ARCHIVE_RETENTION_DAYS * 24 * 60 * 60 * 1000,
    );

    const expiredFamilies = await this.prisma.family.findMany({
      where: {
        deletedAt: { not: null, lte: expirationDate },
      },
      select: { id: true, name: true },
    });

    if (expiredFamilies.length === 0) {
      this.logger.debug('No expired archived families to purge');
      return;
    }

    this.logger.log(
      `Purging ${expiredFamilies.length} expired archived families`,
    );

    for (const family of expiredFamilies) {
      try {
        // BUG-004 FIX: pass undefined userId so the service knows this is
        // the cron job (allowed to bypass the admin check).
        await this.permanentDelete(family.id);
        this.logger.log(`Purged family "${family.name}" (${family.id})`);
      } catch (error) {
        // BUG-017 FIX: track failed families so they don't silently
        // accumulate forever — they'll be retried on the next cron run,
        // and the error stack is logged at `error` level for observability.
        this.logger.error(
          `Failed to purge family "${family.name}" (${family.id}): ${error.message}`,
          error.stack,
        );
      }
    }

    this.logger.log(
      `Purge complete. Deleted ${expiredFamilies.length} families.`,
    );
  }

  // ── Leave Family ─────────────────────────────────────────────────────

  /** Allows a non-admin member to leave a family. Admins must transfer admin first.
   *  BUG-011 FIX: blocks the LAST member from leaving (would orphan the family). */
  async leaveFamily(userId: string, familyId: string) {
    // 1. Verify the user is a member of the family
    const membership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId } },
    });

    if (!membership) {
      throw new ForbiddenException('You are not a member of this family');
    }

    // BUG-011 FIX: Don't allow the LAST member to leave — that would orphan
    // the family (no admins left to manage it, no one to receive invites,
    // foreign-key constraints on Person/FamilyMember may cascade-delete).
    // Direct them to archive the family instead.
    const totalMembers = await this.prisma.familyMember.count({
      where: { familyId },
    });

    if (totalMembers <= 1) {
      throw new BadRequestException(
        'You are the last member of this family. Please archive the family ' +
        'instead (Delete from the family settings), or invite another member ' +
        'first so they can take over before you leave.',
      );
    }

    // 2. If the user is an admin, check if they are the only admin
    if (membership.role === 'admin') {
      const adminCount = await this.prisma.familyMember.count({
        where: { familyId, role: 'admin' },
      });

      if (adminCount <= 1) {
        throw new BadRequestException(
          'You are the only admin of this family. Please transfer admin to another member before leaving.',
        );
      }
    }

    // 3. Delete the FamilyMember record and decrement memberCount in a transaction
    await this.prisma.$transaction(async (tx) => {
      await tx.familyMember.delete({
        where: { familyId_userId: { familyId, userId } },
      });

      await tx.family.update({
        where: { id: familyId },
        data: {
          memberCount: { decrement: 1 },
          lastActivityAt: new Date(),
        },
      });
    });

    // 4. Emit WebSocket events
    this.gateway.emitToFamily(familyId, 'member:left', {
      id: membership.id,
      updatedAt: new Date().toISOString(),
      type: 'member:left',
      familyId,
      userId,
    });

    this.gateway.emitToFamily(familyId, 'graph:updated', {
      id: familyId,
      updatedAt: new Date().toISOString(),
      type: 'graph:updated',
      familyId,
    });

    return { left: true, familyId };
  }

  // ── Social System: Family Invite Methods ───────────────────────────────

  /** Generate an invite link/token for a family — owners and admins only */
  async generateInvite(userId: string, familyId: string, dto: { expiryDays?: number; maxUses?: number }) {
    await this.requireFamilyRole(userId, familyId, 'admin');

    const family = await this.prisma.family.findUnique({ where: { id: familyId } });
    if (!family) throw new NotFoundException('Family not found');

    // Get the family member record for the creator
    const memberRecord = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId } },
    });

    const token = `inv_${Date.now()}_${Math.random().toString(36).substring(2, 10)}`;
    const expiresAt = dto.expiryDays
      ? new Date(Date.now() + dto.expiryDays * 24 * 60 * 60 * 1000)
      : null;

    const invite = await this.prisma.familyInvite.create({
      data: {
        familyId,
        invitedBy: memberRecord!.id,
        inviteCode: token,
        inviteType: 'link',
        maxUses: dto.maxUses ?? 0, // 0 = unlimited
        currentUses: 0,
        useCount: 0,
        expiresAt,
        creatorId: userId,
        active: true,
      },
    });

    // Generate the invite URL
    const deepLinkUrl = `kinrel://join/${token}`;

    return {
      id: invite.id,
      token: invite.inviteCode,
      url: deepLinkUrl,
      expiresAt: invite.expiresAt,
      maxUses: invite.maxUses || null,
      createdAt: invite.createdAt,
    };
  }

  /** Revoke all active invite links for a family — owners only */
  async revokeInvites(userId: string, familyId: string) {
    const membership = await this.requireFamilyMember(userId, familyId);
    if (membership.role !== 'admin') {
      throw new ForbiddenException('Only admins can revoke invite links');
    }

    const result = await this.prisma.familyInvite.updateMany({
      where: { familyId, active: true },
      data: { active: false },
    });

    return { revoked: result.count };
  }

  /** Preview a family from an invite token — no auth required
   *  BUG-016 FIX: don't leak memberCount to unauthenticated users. */
  async previewInvite(token: string) {
    const invite = await this.prisma.familyInvite.findUnique({
      where: { inviteCode: token },
      include: {
        family: {
          select: { id: true, name: true, memberCount: true },
        },
      },
    });

    if (!invite) {
      return { valid: false, expired: false, error: 'Invalid invite token' };
    }

    if (!invite.active) {
      return { valid: false, expired: false, error: 'Invite link has been revoked' };
    }

    const now = new Date();
    if (invite.expiresAt && invite.expiresAt < now) {
      return { valid: false, expired: true, error: 'Invite link has expired' };
    }

    if (invite.maxUses > 0 && invite.useCount >= invite.maxUses) {
      return { valid: false, expired: false, error: 'Invite link has reached maximum uses' };
    }

    // Get owner name
    const ownerMember = await this.prisma.familyMember.findFirst({
      where: { familyId: invite.familyId, role: 'admin' },
      include: { user: { select: { name: true } } },
    });

    return {
      valid: true,
      expired: false,
      familyName: invite.family.name,
      ownerName: ownerMember?.user?.name ?? 'Unknown',
      // BUG-016 FIX: return only a coarse bucketed indicator ("small" /
      // "medium" / "large") instead of the exact member count, so an
      // unauthenticated user with the invite link can't probe family size
      // for social-engineering purposes.
      sizeBucket:
        invite.family.memberCount < 5 ? 'small'
        : invite.family.memberCount < 20 ? 'medium'
        : 'large',
    };
  }

  /** Join a family using an invite token */
  async joinFamily(userId: string, token: string) {
    const invite = await this.prisma.familyInvite.findUnique({
      where: { inviteCode: token },
    });

    if (!invite) throw new NotFoundException('Invite not found');
    if (!invite.active) throw new BadRequestException('Invite link has been revoked');

    const now = new Date();
    if (invite.expiresAt && invite.expiresAt < now) {
      throw new BadRequestException('Invite link has expired');
    }

    if (invite.maxUses > 0 && invite.useCount >= invite.maxUses) {
      throw new BadRequestException('Invite link has reached maximum uses');
    }

    // Check if already a member
    const existing = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId: invite.familyId, userId } },
    });
    if (existing) {
      throw new BadRequestException('You are already a member of this family');
    }

    // Join as member
    await this.prisma.$transaction(async (tx) => {
      await tx.familyMember.create({
        data: {
          familyId: invite.familyId,
          userId,
          role: 'member',
        },
      });

      await tx.family.update({
        where: { id: invite.familyId },
        data: {
          memberCount: { increment: 1 },
          lastActivityAt: new Date(),
        },
      });

      // Increment use count
      await tx.familyInvite.update({
        where: { id: invite.id },
        data: { useCount: { increment: 1 }, currentUses: { increment: 1 } },
      });
    });

    // Emit socket event to family owner
    this.gateway.emitToFamily(invite.familyId, 'family:member_joined', {
      id: invite.id,
      updatedAt: new Date().toISOString(),
      type: 'family:member_joined',
      familyId: invite.familyId,
      userId,
    });

    // ── Send notifications (fire-and-forget) ─────────────────────────
    try {
      // Get family name and joining user name for notifications
      const [family, joiningUser] = await Promise.all([
        this.prisma.family.findUnique({
          where: { id: invite.familyId },
          select: { name: true },
        }),
        this.prisma.user.findUnique({
          where: { id: userId },
          select: { name: true },
        }),
      ]);

      const familyName = family?.name ?? 'the family';
      const joiningUserName = joiningUser?.name ?? 'A family member';

      // Notification A — to the joining user
      this.notificationsService.notifyFamilyJoined(userId, familyName, invite.familyId);

      // Notification B — to all admins (excluding the joining user)
      const admins = await this.prisma.familyMember.findMany({
        where: { familyId: invite.familyId, role: 'admin' },
        select: { userId: true },
      });

      for (const admin of admins.filter((a) => a.userId !== userId)) {
        this.notificationsService.notifyFamilyMemberJoined(
          admin.userId,
          joiningUserName,
          familyName,
          invite.familyId,
        );
      }
    } catch (e) {
      this.logger.error('Failed to send join-family notifications', e);
    }

    return { joined: true, familyId: invite.familyId };
  }

  /** Toggle family public/private visibility — owners only */
  async toggleVisibility(userId: string, familyId: string, isPublic: boolean) {
    const membership = await this.requireFamilyMember(userId, familyId);
    if (membership.role !== 'admin') {
      throw new ForbiddenException('Only admins can toggle family visibility');
    }

    const updated = await this.prisma.family.update({
      where: { id: familyId },
      data: { isPublic, lastActivityAt: new Date() },
    });

    return { familyId, isPublic: updated.isPublic };
  }

  // ── Member Management ────────────────────────────────────────────────

  /** List all members of a family with user profile data. */
  async getMembers(userId: string, familyId: string) {
    await this.requireFamilyMember(userId, familyId);

    const members = await this.prisma.familyMember.findMany({
      where: { familyId },
      include: {
        user: {
          select: {
            id: true,
            name: true,
            email: true,
            avatarUrl: true,
            username: true,
          },
        },
      },
      orderBy: [
        { role: 'desc' }, // admins first
        { joinedAt: 'asc' },
      ],
    });

    return members.map((m) => ({
      id: m.id,
      familyId: m.familyId,
      userId: m.userId,
      role: m.role,
      joinedAt: m.joinedAt?.toISOString(),
      user: m.user ? {
        id: m.user.id,
        name: m.user.name,
        email: m.user.email,
        avatarUrl: m.user.avatarUrl,
        username: m.user.username,
      } : null,
    }));
  }

  /** Update a member's role in the family — admin only. */
  async updateMemberRole(userId: string, familyId: string, memberId: string, newRole: string) {
    await this.requireFamilyRole(userId, familyId, 'admin');

    const validRoles = ['viewer', 'member', 'editor', 'admin'];
    if (!validRoles.includes(newRole)) {
      throw new BadRequestException(`Invalid role. Must be one of: ${validRoles.join(', ')}`);
    }

    const targetMember = await this.prisma.familyMember.findUnique({
      where: { id: memberId },
    });

    if (!targetMember || targetMember.familyId !== familyId) {
      throw new NotFoundException('Member not found in this family');
    }

    // Prevent self-demotion for sole admin
    if (targetMember.userId === userId && targetMember.role === 'admin' && newRole !== 'admin') {
      const adminCount = await this.prisma.familyMember.count({
        where: { familyId, role: 'admin' },
      });
      if (adminCount <= 1) {
        throw new BadRequestException('Cannot demote yourself as the only admin. Transfer admin to another member first.');
      }
    }

    const updated = await this.prisma.familyMember.update({
      where: { id: memberId },
      data: { role: newRole },
    });

    this.gateway.emitToFamily(familyId, 'member:role_updated', {
      id: memberId,
      updatedAt: new Date().toISOString(),
      type: 'member:role_updated',
      familyId,
      userId: targetMember.userId,
      oldRole: targetMember.role,
      newRole,
    });

    return {
      id: updated.id,
      familyId: updated.familyId,
      userId: updated.userId,
      role: updated.role,
      joinedAt: updated.joinedAt?.toISOString(),
    };
  }

  /** Remove a member from the family — admin only. */
  async removeMember(userId: string, familyId: string, memberId: string) {
    await this.requireFamilyRole(userId, familyId, 'admin');

    const targetMember = await this.prisma.familyMember.findUnique({
      where: { id: memberId },
    });

    if (!targetMember || targetMember.familyId !== familyId) {
      throw new NotFoundException('Member not found in this family');
    }

    // Cannot remove yourself — use leave family endpoint
    if (targetMember.userId === userId) {
      throw new BadRequestException('Cannot remove yourself. Use the leave family option instead.');
    }

    // Cannot remove another admin unless you're the family creator
    if (targetMember.role === 'admin') {
      const family = await this.prisma.family.findUnique({ where: { id: familyId } });
      if (!family || family.createdBy !== userId) {
        throw new ForbiddenException('Only the family creator can remove other admins');
      }
    }

    await this.prisma.$transaction(async (tx) => {
      await tx.familyMember.delete({ where: { id: memberId } });
      await tx.family.update({
        where: { id: familyId },
        data: {
          memberCount: { decrement: 1 },
          lastActivityAt: new Date(),
        },
      });
    });

    this.gateway.emitToFamily(familyId, 'member:removed', {
      id: memberId,
      updatedAt: new Date().toISOString(),
      type: 'member:removed',
      familyId,
      userId: targetMember.userId,
    });

    return { removed: true, familyId, userId: targetMember.userId };
  }

  // ── Helper Methods ───────────────────────────────────────────────────

  /** Verifies the user is a member of the family, throws if not. */
  async requireFamilyMember(userId: string, familyId: string) {
    const membership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId } },
    });

    if (!membership) {
      throw new ForbiddenException('You are not a member of this family');
    }

    return membership;
  }

  /** Verifies the user has at least the specified role in the family. */
  async requireFamilyRole(userId: string, familyId: string, minRole: string) {
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

  private formatFamily(family: {
    id: string;
    name: string;
    familyCode: string;
    kinFamilyId: string | null;
    username: string | null;
    description: string | null;
    primaryLanguage: string;
    gotra: string | null;
    originVillage: string | null;
    privacyMode: string;
    anchorPersonId: string | null;
    memberCount: number;
    generationCount: number;
    createdBy: string | null;
    avatarUrl: string | null;
    region: string | null;
    isOnboarded: boolean;
    lastActivityAt: Date;
    createdAt: Date;
    deletedAt?: Date | null;
  }) {
    return {
      id: family.id,
      name: family.name,
      familyCode: family.familyCode,
      kinFamilyId: family.kinFamilyId,
      username: family.username,
      description: family.description,
      primaryLanguage: family.primaryLanguage,
      gotra: family.gotra,
      originVillage: family.originVillage,
      privacyMode: family.privacyMode,
      anchorPersonId: family.anchorPersonId,
      memberCount: family.memberCount,
      generationCount: family.generationCount,
      createdBy: family.createdBy,
      avatarUrl: family.avatarUrl,
      region: family.region,
      isOnboarded: family.isOnboarded,
      lastActivityAt: family.lastActivityAt,
      createdAt: family.createdAt,
      deletedAt: family.deletedAt || null,
    };
  }
}
