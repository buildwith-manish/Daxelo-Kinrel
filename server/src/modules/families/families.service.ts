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
  ) {}

  /** Creates a new family and assigns the creator as admin member. */
  async create(userId: string, dto: CreateFamilyDto) {
    if (!dto.name || typeof dto.name !== 'string' || dto.name.trim().length === 0) {
      throw new BadRequestException('Family name is required');
    }

    // Pre-generate the Family ID outside the transaction to avoid
    // holding a transaction lock while generating a random ID
    const kinFamilyId = await this.familyIdService.generateFamilyId();

    const family = await this.prisma.$transaction(async (tx) => {
      const created = await tx.family.create({
        data: {
          name: dto.name.trim(),
          description: dto.description?.trim() || null,
          primaryLanguage: dto.primaryLanguage || 'en',
          gotra: dto.gotra?.trim() || null,
          originVillage: dto.originVillage?.trim() || null,
          privacyMode: dto.privacyMode || 'private',
          createdBy: userId,
          memberCount: 1,
          lastActivityAt: new Date(),
          kinFamilyId,
        },
      });

      await tx.familyMember.create({
        data: {
          familyId: created.id,
          userId,
          role: 'admin',
        },
      });

      return created;
    });

    return this.formatFamily(family);
  }

  /** Returns all active (non-archived) families the user is a member of, with pagination. */
  async findAll(userId: string, pagination?: { page?: number; limit?: number }) {
    const page = pagination?.page ?? 1;
    const limit = pagination?.limit ?? 20;
    const skip = (page - 1) * limit;

    // First get total count of active families
    const total = await this.prisma.familyMember.count({
      where: { userId, family: { deletedAt: null } },
    });

    // Then get the paginated family members with active families
    const items = await this.prisma.familyMember.findMany({
      where: { userId, family: { deletedAt: null } },
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
    await this.prisma.$transaction(async (tx) => {
      // 1. Soft-delete all active persons in the family
      await tx.person.updateMany({
        where: { familyId, deletedAt: null },
        data: { deletedAt: now },
      });

      // 2. Soft-delete the family itself
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
    // Only admins can restore a family — viewers should not undo an admin's archival
    const membership = await this.requireFamilyRole(userId, familyId, 'admin');

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
      // 1. Restore persons that were soft-deleted as part of the family archive.
      // We restore ALL currently-soft-deleted persons in this family because:
      //   - The archive() method soft-deletes every person in the family atomically
      //   - No other code path sets person.deletedAt while the family is active
      //   - Using a time-window heuristic (5s) could miss persons under high latency
      //     or accidentally restore persons manually deleted before archival.
      //   - Since the family is archived, no one can add/delete persons anyway.
      await tx.person.updateMany({
        where: {
          familyId,
          deletedAt: { not: null },
        },
        data: { deletedAt: null },
      });

      // 2. Restore the family itself
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
  async findArchived(userId: string, pagination?: { page?: number; limit?: number }) {
    const page = pagination?.page ?? 1;
    const limit = pagination?.limit ?? 20;
    const skip = (page - 1) * limit;

    const total = await this.prisma.familyMember.count({
      where: { userId, family: { deletedAt: { not: null } } },
    });

    const items = await this.prisma.familyMember.findMany({
      where: { userId, family: { deletedAt: { not: null } } },
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
   */
  async permanentDelete(familyId: string) {
    const family = await this.prisma.family.findUnique({
      where: { id: familyId },
    });

    if (!family) {
      throw new NotFoundException('Family not found');
    }

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
        await this.permanentDelete(family.id);
        this.logger.log(`Purged family "${family.name}" (${family.id})`);
      } catch (error) {
        this.logger.error(
          `Failed to purge family "${family.name}" (${family.id}): ${error.message}`,
        );
      }
    }

    this.logger.log(
      `Purge complete. Deleted ${expiredFamilies.length} families.`,
    );
  }

  // ── Leave Family ─────────────────────────────────────────────────────

  /** Allows a non-admin member to leave a family. Admins must transfer admin first. */
  async leaveFamily(userId: string, familyId: string) {
    // 1. Verify the user is a member of the family
    const membership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId } },
    });

    if (!membership) {
      throw new ForbiddenException('You are not a member of this family');
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
