import { Injectable, BadRequestException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class FamilyService {
  constructor(private prisma: PrismaService) {}

  async listFamilies(userId: string) {
    const memberships = await this.prisma.familyMember.findMany({
      where: { userId },
      include: {
        family: {
          include: {
            _count: {
              select: { members: true, persons: true },
            },
          },
        },
      },
      orderBy: { joinedAt: 'desc' },
    });

    const families = memberships.map((m) => ({
      id: m.family.id,
      name: m.family.name,
      description: m.family.description,
      primaryLanguage: m.family.primaryLanguage,
      gotra: m.family.gotra,
      originVillage: m.family.originVillage,
      role: m.role,
      memberCount: m.family._count.members,
      personCount: m.family._count.persons,
      createdAt: m.family.createdAt,
      updatedAt: m.family.updatedAt,
    }));

    return { families };
  }

  async createFamily(userId: string, data: { name: string; description?: string; primaryLanguage?: string; gotra?: string; originVillage?: string }) {
    if (!data.name || typeof data.name !== 'string' || data.name.trim().length === 0) {
      throw new BadRequestException('Family name is required');
    }

    const family = await this.prisma.family.create({
      data: {
        name: data.name.trim(),
        description: data.description?.trim() || null,
        primaryLanguage: data.primaryLanguage || 'en',
        gotra: data.gotra?.trim() || null,
        originVillage: data.originVillage?.trim() || null,
      },
    });

    await this.prisma.familyMember.create({
      data: {
        familyId: family.id,
        userId,
        role: 'admin',
      },
    });

    await this.prisma.auditLog.create({
      data: {
        userId,
        action: 'FAMILY_CREATED',
        resource: 'Family',
        resourceId: family.id,
        details: JSON.stringify({ name: family.name }),
      },
    });

    return {
      family: {
        id: family.id,
        name: family.name,
        description: family.description,
        primaryLanguage: family.primaryLanguage,
        gotra: family.gotra,
        originVillage: family.originVillage,
        memberCount: 1,
        personCount: 0,
        role: 'admin',
        createdAt: family.createdAt,
        updatedAt: family.updatedAt,
      },
    };
  }
}
