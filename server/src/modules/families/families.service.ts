import {
  Injectable,
  BadRequestException,
  NotFoundException,
  ForbiddenException,
  Inject,
  forwardRef,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { CreateFamilyDto } from './dto/create-family.dto';
import { UpdateFamilyDto } from './dto/update-family.dto';
import { FamilyIdService } from './family-id.service';

const ROLE_HIERARCHY: Record<string, number> = {
  viewer: 1,
  member: 2,
  editor: 3,
  admin: 4,
};

@Injectable()
export class FamiliesService {
  constructor(
    private prisma: PrismaService,
    @Inject(forwardRef(() => FamilyIdService))
    private familyIdService: FamilyIdService,
  ) {}

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

  async findAll(userId: string) {
    const memberships = await this.prisma.familyMember.findMany({
      where: { userId },
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
          },
        },
      },
      orderBy: { joinedAt: 'desc' },
    });

    return memberships.map((m) => this.formatFamily(m.family));
  }

  async findOne(userId: string, familyId: string) {
    await this.requireFamilyMember(userId, familyId);

    const family = await this.prisma.family.findUnique({
      where: { id: familyId },
    });

    if (!family) {
      throw new NotFoundException('Family not found');
    }

    return this.formatFamily(family);
  }

  async update(userId: string, familyId: string, dto: UpdateFamilyDto) {
    await this.requireFamilyRole(userId, familyId, 'editor');

    const existing = await this.prisma.family.findUnique({
      where: { id: familyId },
    });

    if (!existing) {
      throw new NotFoundException('Family not found');
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

  async remove(userId: string, familyId: string) {
    await this.requireFamilyRole(userId, familyId, 'admin');

    const family = await this.prisma.family.findUnique({
      where: { id: familyId },
    });

    if (!family) {
      throw new NotFoundException('Family not found');
    }

    await this.prisma.$transaction(async (tx) => {
      const personIds = await tx.person.findMany({
        where: { familyId },
        select: { id: true },
      });
      const ids = personIds.map((p) => p.id);

      if (ids.length > 0) {
        await tx.relationship.deleteMany({
          where: {
            OR: [
              { fromPersonId: { in: ids } },
              { toPersonId: { in: ids } },
            ],
          },
        });
      }

      await tx.person.deleteMany({ where: { familyId } });
      await tx.familyMember.deleteMany({ where: { familyId } });
      await tx.family.delete({ where: { id: familyId } });
    });

    return { deleted: true, familyId };
  }

  async requireFamilyMember(userId: string, familyId: string) {
    const membership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId } },
    });

    if (!membership) {
      throw new ForbiddenException('You are not a member of this family');
    }

    return membership;
  }

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
    };
  }
}
