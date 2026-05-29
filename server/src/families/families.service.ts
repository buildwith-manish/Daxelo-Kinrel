import { Injectable, NotFoundException, ForbiddenException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class FamiliesService {
  constructor(private readonly prisma: PrismaService) {}

  async listFamilies(userId: string) {
    const memberships = await this.prisma.familyMember.findMany({
      where: { userId },
      include: { family: { include: { persons: true } } },
    });
    return memberships.map((m) => ({
      ...m.family,
      role: m.role,
      joinedAt: m.joinedAt,
    }));
  }

  async createFamily(userId: string, data: any) {
    const familyCode = Math.random().toString(36).substring(2, 8).toUpperCase();
    const family = await this.prisma.family.create({
      data: {
        name: data.name,
        username: data.username || null,
        familyCode,
        avatarUrl: data.avatarUrl || null,
        region: data.region || null,
        privacyMode: data.privacyMode || 'public',
        isOnboarded: false,
        createdBy: userId,
        description: data.description || null,
        primaryLanguage: data.primaryLanguage || 'en',
        gotra: data.gotra || null,
        originVillage: data.originVillage || null,
        memberCount: 1,
        generationCount: 1,
      },
    });

    // Add creator as admin
    await this.prisma.familyMember.create({
      data: {
        familyId: family.id,
        userId,
        role: 'admin',
      },
    });

    return family;
  }

  async getFamily(userId: string, familyId: string) {
    // Check membership
    const membership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId } },
    });
    if (!membership) {
      throw new ForbiddenException('Not a member of this family');
    }

    const family = await this.prisma.family.findUnique({
      where: { id: familyId },
      include: {
        persons: { where: { deletedAt: null } },
        members: true,
      },
    });

    if (!family) {
      throw new NotFoundException('Family not found');
    }

    return {
      ...family,
      role: membership.role,
    };
  }

  async updateFamily(userId: string, familyId: string, data: any) {
    // Check admin role
    const membership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId } },
    });
    if (!membership || membership.role !== 'admin') {
      throw new ForbiddenException('Only admins can update family');
    }

    const allowedFields = [
      'name', 'username', 'avatarUrl', 'region', 'privacyMode',
      'isOnboarded', 'anchorPersonId', 'memberCount', 'generationCount',
      'description', 'primaryLanguage', 'gotra', 'originVillage',
    ];
    const updateData: any = {};
    for (const field of allowedFields) {
      if (data[field] !== undefined) {
        updateData[field] = data[field];
      }
    }

    return this.prisma.family.update({
      where: { id: familyId },
      data: updateData,
    });
  }

  async deleteFamily(userId: string, familyId: string) {
    // Check admin role
    const membership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId } },
    });
    if (!membership || membership.role !== 'admin') {
      throw new ForbiddenException('Only admins can delete family');
    }

    // Delete all related data
    await this.prisma.relationship.deleteMany({ where: { familyId } });
    await this.prisma.person.deleteMany({ where: { familyId } });
    await this.prisma.familyMember.deleteMany({ where: { familyId } });
    await this.prisma.family.delete({ where: { id: familyId } });

    return { message: 'Family deleted successfully' };
  }

  async exportFamily(userId: string, familyId: string) {
    const membership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId } },
    });
    if (!membership) {
      throw new ForbiddenException('Not a member of this family');
    }

    const family = await this.prisma.family.findUnique({
      where: { id: familyId },
      include: {
        persons: { where: { deletedAt: null } },
      },
    });

    return {
      export: family,
      exportedAt: new Date().toISOString(),
      format: 'json',
    };
  }
}
