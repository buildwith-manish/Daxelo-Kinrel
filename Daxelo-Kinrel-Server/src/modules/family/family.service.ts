import {
  Injectable,
  NotFoundException,
  ForbiddenException,
  ConflictException,
  UnprocessableEntityException,
  Logger,
} from '@nestjs/common';
import { PrismaService } from '@/common/prisma/prisma.service';
import { CreateFamilyDto } from './dto/create-family.dto';
import { UpdateFamilyDto } from './dto/update-family.dto';
import { CreatePersonDto } from './dto/create-person.dto';
import { UpdatePersonDto } from './dto/update-person.dto';
import { CreateRelationshipDto } from './dto/create-relationship.dto';
import { validateAndNormalizeKey } from '@/lib/kinship-validator';

// ── Inverse Relationship Map ────────────────────────────────────────────

const INVERSE_RELATIONSHIP_MAP: Record<string, string> = {
  father: 'child',
  mother: 'child',
  son: 'parent',
  daughter: 'parent',
  husband: 'wife',
  wife: 'husband',
  elder_brother: 'younger_sibling',
  younger_brother: 'elder_sibling',
  elder_sister: 'younger_sibling',
  younger_sister: 'elder_sibling',
  brother: 'sibling',
  sister: 'sibling',
  paternal_grandfather: 'grandchild',
  paternal_grandmother: 'grandchild',
  maternal_grandfather: 'grandchild',
  maternal_grandmother: 'grandchild',
  husbands_father: 'daughters_in_law',
  husbands_mother: 'daughters_in_law',
  wives_father: 'sons_in_law',
  wives_mother: 'sons_in_law',
  sons_wife: 'fathers_in_law',
  daughters_husband: 'mothers_in_law',
};

export function getInverseRelationship(type: string): string {
  return INVERSE_RELATIONSHIP_MAP[type] || 'related_to';
}

// ── Family Role Check Helper ────────────────────────────────────────────

type FamilyRole = 'admin' | 'editor' | 'member' | 'viewer';

const MIN_ROLES: Record<string, FamilyRole[]> = {
  createPerson: ['admin', 'editor', 'member'],
  updatePerson: ['admin', 'editor'],
  deletePerson: ['admin'],
  createRelationship: ['admin', 'editor', 'member'],
  deleteRelationship: ['admin', 'editor'],
  updateFamily: ['admin'],
  deleteFamily: ['admin'],
};

function hasMinRole(userRole: string, action: string): boolean {
  const allowed = MIN_ROLES[action];
  if (!allowed) return true;
  return allowed.includes(userRole as FamilyRole);
}

// ═══════════════════════════════════════════════════════════════════════
// FamilyService
// ═══════════════════════════════════════════════════════════════════════

@Injectable()
export class FamilyService {
  private readonly logger = new Logger(FamilyService.name);

  constructor(private readonly prisma: PrismaService) {}

  // ═════════════════════════════════════════════════════════════════════
  // Family CRUD
  // ═════════════════════════════════════════════════════════════════════

  /**
   * GET /api/families — List user's families
   */
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

  /**
   * POST /api/families — Create family
   */
  async createFamily(userId: string, dto: CreateFamilyDto) {
    const family = await this.prisma.family.create({
      data: {
        name: dto.name.trim(),
        description: dto.description?.trim() || null,
        primaryLanguage: dto.primaryLanguage || 'en',
        gotra: dto.gotra?.trim() || null,
        originVillage: dto.originVillage?.trim() || null,
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

    // Audit log
    await this.prisma.auditLog.create({
      data: {
        userId,
        action: 'FAMILY_CREATED',
        resource: 'Family',
        resourceId: family.id,
        details: JSON.stringify({ name: family.name }),
      },
    });

    this.logger.log(`Family created: ${family.id} by user: ${userId}`);

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

  /**
   * GET /api/families/:familyId — Get family details
   */
  async getFamily(familyId: string, userId: string) {
    const membership = await this.requireFamilyMember(familyId, userId);

    const family = await this.prisma.family.findUnique({
      where: { id: familyId },
      include: {
        _count: {
          select: { members: true, persons: true },
        },
      },
    });

    if (!family) {
      throw new NotFoundException('Family not found');
    }

    return {
      family: {
        id: family.id,
        name: family.name,
        description: family.description,
        primaryLanguage: family.primaryLanguage,
        gotra: family.gotra,
        originVillage: family.originVillage,
        memberCount: family._count.members,
        personCount: family._count.persons,
        createdAt: family.createdAt,
        updatedAt: family.updatedAt,
      },
      role: membership.role,
    };
  }

  /**
   * PATCH /api/families/:familyId — Update family (admin only)
   */
  async updateFamily(familyId: string, userId: string, dto: UpdateFamilyDto) {
    await this.requireFamilyRole(familyId, userId, 'updateFamily');

    const allowedFields = ['name', 'description', 'primaryLanguage', 'gotra', 'originVillage'] as const;
    const updateData: Record<string, unknown> = {};

    for (const field of allowedFields) {
      if ((dto as Record<string, unknown>)[field] !== undefined) {
        updateData[field] = (dto as Record<string, unknown>)[field];
      }
    }

    if (Object.keys(updateData).length === 0) {
      throw new UnprocessableEntityException('No valid fields to update');
    }

    const family = await this.prisma.family.update({
      where: { id: familyId },
      data: updateData,
    });

    // Audit log
    await this.prisma.auditLog.create({
      data: {
        userId,
        action: 'FAMILY_UPDATED',
        resource: 'Family',
        resourceId: familyId,
        details: JSON.stringify({ changedFields: Object.keys(updateData) }),
      },
    });

    this.logger.log(`Family updated: ${familyId} by user: ${userId}`);
    return { family };
  }

  /**
   * DELETE /api/families/:familyId — Delete family (admin only)
   */
  async deleteFamily(familyId: string, userId: string) {
    await this.requireFamilyRole(familyId, userId, 'deleteFamily');

    // Get cascade counts before deletion
    const [personCount, memberCount, relationshipCount] = await Promise.all([
      this.prisma.person.count({ where: { familyId } }),
      this.prisma.familyMember.count({ where: { familyId } }),
      this.prisma.relationship.count({ where: { familyId } }),
    ]);

    // Delete family (cascade will handle related records)
    await this.prisma.family.delete({
      where: { id: familyId },
    });

    // Audit log
    await this.prisma.auditLog.create({
      data: {
        userId,
        action: 'FAMILY_DELETED',
        resource: 'Family',
        resourceId: familyId,
        details: JSON.stringify({ personCount, memberCount, relationshipCount }),
      },
    });

    this.logger.log(`Family deleted: ${familyId} by user: ${userId}`);

    return {
      deleted: true,
      familyId,
      cascadeCounts: {
        persons: personCount,
        members: memberCount,
        relationships: relationshipCount,
      },
    };
  }

  // ═════════════════════════════════════════════════════════════════════
  // Person CRUD
  // ═════════════════════════════════════════════════════════════════════

  /**
   * GET /api/families/:familyId/persons — List persons (paginated)
   */
  async listPersons(
    familyId: string,
    userId: string,
    options: {
      page?: number;
      limit?: number;
      includeRelationships?: boolean;
      deceased?: string;
      search?: string;
      sort?: string;
      order?: string;
    } = {},
  ) {
    await this.requireFamilyMember(familyId, userId);

    const page = Math.max(1, options.page ?? 1);
    const limit = Math.min(100, Math.max(1, options.limit ?? 20));
    const includeRelationships = options.includeRelationships ?? false;
    const sort = options.sort || 'createdAt';
    const order = options.order || 'desc';

    const where: Record<string, unknown> = {
      familyId,
      deletedAt: null,
    };

    if (options.deceased === 'true') where.isDeceased = true;
    if (options.deceased === 'false') where.isDeceased = false;
    if (options.search) {
      where.OR = [
        { name: { contains: options.search } },
        { relationship: { contains: options.search } },
        { occupation: { contains: options.search } },
        { city: { contains: options.search } },
      ];
    }

    const include = includeRelationships
      ? { relationshipsFrom: true, relationshipsTo: true }
      : {};

    const [persons, total] = await Promise.all([
      this.prisma.person.findMany({
        where,
        include,
        orderBy: { [sort]: order === 'asc' ? 'asc' : 'desc' },
        skip: (page - 1) * limit,
        take: limit,
      }),
      this.prisma.person.count({ where }),
    ]);

    return {
      data: persons,
      pagination: {
        page,
        limit,
        total,
        hasMore: page * limit < total,
        totalPages: Math.ceil(total / limit),
      },
    };
  }

  /**
   * POST /api/families/:familyId/persons — Create person
   */
  async createPerson(familyId: string, userId: string, dto: CreatePersonDto) {
    await this.requireFamilyRole(familyId, userId, 'createPerson');

    // Validate and normalize relationship key
    const normalizedKey = validateAndNormalizeKey(dto.relationship);
    if (!normalizedKey) {
      throw new UnprocessableEntityException(
        `Invalid relationship key: "${dto.relationship}". Please provide a valid kinship term.`,
      );
    }

    // Verify family exists
    const family = await this.prisma.family.findUnique({ where: { id: familyId } });
    if (!family) {
      throw new NotFoundException('Family not found');
    }

    const person = await this.prisma.person.create({
      data: {
        familyId,
        name: dto.name,
        dateOfBirth: dto.dateOfBirth ? new Date(dto.dateOfBirth) : null,
        gotra: dto.gotra,
        occupation: dto.occupation,
        city: dto.city,
        isDeceased: dto.isDeceased ?? false,
        privacyLevel: dto.privacyLevel ?? 'family',
      },
    });

    // Audit log
    await this.prisma.auditLog.create({
      data: {
        userId,
        action: 'PERSON_CREATED',
        resource: 'Person',
        resourceId: person.id,
        details: JSON.stringify({ name: dto.name, familyId, relationship: normalizedKey }),
      },
    });

    this.logger.log(`Person created: ${person.id} in family: ${familyId}`);

    return { data: person };
  }

  /**
   * GET /api/families/:familyId/persons/:personId — Get person with relationships
   */
  async getPerson(familyId: string, personId: string, userId: string) {
    await this.requireFamilyMember(familyId, userId);

    const person = await this.prisma.person.findFirst({
      where: { id: personId, familyId, deletedAt: null },
      include: {
        relationshipsFrom: true,
        relationshipsTo: true,
      },
    });

    if (!person) {
      throw new NotFoundException('Person not found');
    }

    return { data: person };
  }

  /**
   * PATCH /api/families/:familyId/persons/:personId — Update person
   */
  async updatePerson(familyId: string, personId: string, userId: string, dto: UpdatePersonDto) {
    await this.requireFamilyRole(familyId, userId, 'updatePerson');

    // Verify person exists and is not soft-deleted
    const existingPerson = await this.prisma.person.findFirst({
      where: { id: personId, familyId, deletedAt: null },
    });

    if (!existingPerson) {
      throw new NotFoundException('Person not found');
    }

    // Validate relationship key if provided
    if (dto.relationship) {
      const normalizedKey = validateAndNormalizeKey(dto.relationship);
      if (!normalizedKey) {
        throw new UnprocessableEntityException(
          `Invalid relationship key: "${dto.relationship}". Please provide a valid kinship term.`,
        );
      }
      dto.relationship = normalizedKey;
    }

    const updateData: Record<string, unknown> = {};

    if (dto.name !== undefined) updateData.name = dto.name;
    if (dto.relationship !== undefined) updateData.relationship = dto.relationship;
    if (dto.dateOfBirth !== undefined)
      updateData.dateOfBirth = dto.dateOfBirth ? new Date(dto.dateOfBirth) : null;
    if (dto.gotra !== undefined) updateData.gotra = dto.gotra;
    if (dto.occupation !== undefined) updateData.occupation = dto.occupation;
    if (dto.city !== undefined) updateData.city = dto.city;
    if (dto.isDeceased !== undefined) updateData.isDeceased = dto.isDeceased;
    if (dto.privacyLevel !== undefined) updateData.privacyLevel = dto.privacyLevel;

    if (Object.keys(updateData).length === 0) {
      throw new UnprocessableEntityException('No valid fields to update');
    }

    const updatedPerson = await this.prisma.person.update({
      where: { id: personId },
      data: updateData,
    });

    // Audit log
    await this.prisma.auditLog.create({
      data: {
        userId,
        action: 'PERSON_UPDATED',
        resource: 'Person',
        resourceId: personId,
        details: JSON.stringify({ changedFields: Object.keys(updateData) }),
      },
    });

    return { data: updatedPerson };
  }

  /**
   * DELETE /api/families/:familyId/persons/:personId — Soft-delete person
   */
  async deletePerson(familyId: string, personId: string, userId: string) {
    await this.requireFamilyRole(familyId, userId, 'deletePerson');

    const existingPerson = await this.prisma.person.findFirst({
      where: { id: personId, familyId, deletedAt: null },
    });

    if (!existingPerson) {
      throw new NotFoundException('Person not found');
    }

    // Soft delete
    await this.prisma.person.update({
      where: { id: personId },
      data: { deletedAt: new Date() },
    });

    // Audit log
    await this.prisma.auditLog.create({
      data: {
        userId,
        action: 'PERSON_DELETED',
        resource: 'Person',
        resourceId: personId,
        details: JSON.stringify({ softDelete: true, familyId }),
      },
    });

    this.logger.log(`Person soft-deleted: ${personId} in family: ${familyId}`);
    return null; // 204 No Content
  }

  // ═════════════════════════════════════════════════════════════════════
  // Relationship CRUD
  // ═════════════════════════════════════════════════════════════════════

  /**
   * GET /api/families/:familyId/relationships — List relationships
   */
  async listRelationships(
    familyId: string,
    userId: string,
    options: {
      page?: number;
      limit?: number;
      personId?: string;
    } = {},
  ) {
    await this.requireFamilyMember(familyId, userId);

    const page = Math.max(1, options.page ?? 1);
    const limit = Math.min(100, Math.max(1, options.limit ?? 20));

    const where: Record<string, unknown> = { familyId };

    if (options.personId) {
      where.OR = [
        { fromPersonId: options.personId },
        { toPersonId: options.personId },
      ];
    }

    const [relationships, total] = await Promise.all([
      this.prisma.relationship.findMany({
        where,
        include: {
          fromPerson: true,
          toPerson: true,
        },
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * limit,
        take: limit,
      }),
      this.prisma.relationship.count({ where }),
    ]);

    // Filter out relationships where either person is soft-deleted
    const filteredRelationships = relationships.filter(
      (r) => r.fromPerson && r.toPerson && r.fromPerson.deletedAt === null && r.toPerson.deletedAt === null,
    );

    return {
      data: filteredRelationships,
      pagination: {
        page,
        limit,
        total,
        hasMore: page * limit < total,
        totalPages: Math.ceil(total / limit),
      },
    };
  }

  /**
   * POST /api/families/:familyId/relationships — Create relationship (auto-creates inverse)
   */
  async createRelationship(familyId: string, userId: string, dto: CreateRelationshipDto) {
    await this.requireFamilyRole(familyId, userId, 'createRelationship');

    // Validate and normalize relationship type
    const normalizedType = validateAndNormalizeKey(dto.type);
    if (!normalizedType) {
      throw new UnprocessableEntityException(
        `Invalid relationship type: "${dto.type}". Please provide a valid kinship term.`,
      );
    }

    // Cannot relate person to themselves
    if (dto.fromPersonId === dto.toPersonId) {
      throw new UnprocessableEntityException(
        'Cannot create a relationship from a person to themselves',
      );
    }

    // Check both persons exist, belong to the family, and are not soft-deleted
    const [fromPerson, toPerson] = await Promise.all([
      this.prisma.person.findFirst({
        where: { id: dto.fromPersonId, familyId, deletedAt: null },
      }),
      this.prisma.person.findFirst({
        where: { id: dto.toPersonId, familyId, deletedAt: null },
      }),
    ]);

    if (!fromPerson) {
      throw new NotFoundException('From person not found in this family or is deleted');
    }
    if (!toPerson) {
      throw new NotFoundException('To person not found in this family or is deleted');
    }

    // Check for duplicate relationship
    const existing = await this.prisma.relationship.findFirst({
      where: {
        familyId,
        fromPersonId: dto.fromPersonId,
        toPersonId: dto.toPersonId,
        relationshipKey: normalizedType,
      },
    });

    if (existing) {
      throw new ConflictException(
        `Relationship of type "${normalizedType}" already exists between these persons`,
      );
    }

    // Calculate inverse type
    const inverseType = getInverseRelationship(normalizedType);

    // Create relationship and inverse in a transaction
    const relationship = await this.prisma.$transaction(async (tx) => {
      const rel = await tx.relationship.create({
        data: {
          familyId,
          fromPersonId: dto.fromPersonId,
          toPersonId: dto.toPersonId,
          relationshipKey: normalizedType,
          direction: 'from',
        },
        include: {
          fromPerson: true,
          toPerson: true,
        },
      });

      // Check if inverse already exists before creating
      const existingInverse = await tx.relationship.findFirst({
        where: {
          familyId,
          fromPersonId: dto.toPersonId,
          toPersonId: dto.fromPersonId,
          relationshipKey: inverseType,
        },
      });

      if (!existingInverse) {
        await tx.relationship.create({
          data: {
            familyId,
            fromPersonId: dto.toPersonId,
            toPersonId: dto.fromPersonId,
            relationshipKey: inverseType,
            direction: 'from',
          },
        });
      }

      return rel;
    });

    // Audit log
    await this.prisma.auditLog.create({
      data: {
        userId,
        action: 'RELATIONSHIP_CREATED',
        resource: 'Relationship',
        resourceId: relationship.id,
        details: JSON.stringify({
          familyId,
          fromPersonId: dto.fromPersonId,
          toPersonId: dto.toPersonId,
          type: normalizedType,
          inverseType,
        }),
      },
    });

    this.logger.log(`Relationship created: ${relationship.id} in family: ${familyId}`);

    return { data: relationship };
  }

  /**
   * DELETE /api/families/:familyId/relationships — Delete relationship (and inverse)
   */
  async deleteRelationship(familyId: string, userId: string, relationshipId: string) {
    await this.requireFamilyRole(familyId, userId, 'deleteRelationship');

    const relationship = await this.prisma.relationship.findFirst({
      where: { id: relationshipId, familyId },
    });

    if (!relationship) {
      throw new NotFoundException('Relationship not found');
    }

    // Delete the relationship and its inverse in a transaction
    await this.prisma.$transaction(async (tx) => {
      // Delete the primary relationship
      await tx.relationship.delete({
        where: { id: relationshipId },
      });

      // Find and delete the inverse relationship
      const inverseType = getInverseRelationship(relationship.relationshipKey);

      const inverse = await tx.relationship.findFirst({
        where: {
          familyId,
          fromPersonId: relationship.toPersonId,
          toPersonId: relationship.fromPersonId,
          relationshipKey: inverseType,
        },
      });

      if (inverse) {
        await tx.relationship.delete({
          where: { id: inverse.id },
        });
      }
    });

    // Audit log
    await this.prisma.auditLog.create({
      data: {
        userId,
        action: 'RELATIONSHIP_DELETED',
        resource: 'Relationship',
        resourceId: relationshipId,
        details: JSON.stringify({
          familyId,
          fromPersonId: relationship.fromPersonId,
          toPersonId: relationship.toPersonId,
          type: relationship.relationshipKey,
        }),
      },
    });

    this.logger.log(`Relationship deleted: ${relationshipId} in family: ${familyId}`);
    return null; // 204 No Content
  }

  // ═════════════════════════════════════════════════════════════════════
  // V1 Family Stats
  // ═════════════════════════════════════════════════════════════════════

  /**
   * GET /api/v1/families/:familyId/stats — Family stats
   */
  async getFamilyStats(familyId: string, userId: string) {
    await this.requireFamilyMember(familyId, userId);

    const persons = await this.prisma.person.findMany({
      where: { familyId },
      select: {
        id: true,
        isDeceased: true,
        dateOfBirth: true,
        gender: true,
      },
    });

    const relationships = await this.prisma.relationship.findMany({
      where: { familyId },
      select: { relationshipKey: true },
    });

    const totalCount = persons.length;
    const livingCount = persons.filter((p) => !p.isDeceased).length;
    const deceasedCount = persons.filter((p) => p.isDeceased).length;

    // Gender distribution using Person gender field
    const genderDistribution: Record<string, number> = { male: 0, female: 0, unknown: 0 };
    for (const person of persons) {
      if (person.gender === 'male') {
        genderDistribution.male++;
      } else if (person.gender === 'female') {
        genderDistribution.female++;
      } else {
        genderDistribution.unknown++;
      }
    }

    // Average age
    const now = new Date();
    const livingWithDOB = persons.filter((p) => !p.isDeceased && p.dateOfBirth);
    let avgAge = 0;
    if (livingWithDOB.length > 0) {
      const totalAge = livingWithDOB.reduce((acc, p) => {
        const dob = p.dateOfBirth!;
        const age = (now.getTime() - dob.getTime()) / (365.25 * 24 * 60 * 60 * 1000);
        return acc + age;
      }, 0);
      avgAge = Math.round((totalAge / livingWithDOB.length) * 10) / 10;
    }

    const generationRange = avgAge > 0
      ? { youngest: Math.max(0, Math.round(avgAge - 30)), oldest: Math.round(avgAge + 30) }
      : null;

    // Top relationship types from Relationship model
    const relTypeCounts: Record<string, number> = {};
    for (const rel of relationships) {
      relTypeCounts[rel.relationshipKey] = (relTypeCounts[rel.relationshipKey] || 0) + 1;
    }
    const topRelTypes = Object.entries(relTypeCounts)
      .sort(([, a], [, b]) => b - a)
      .slice(0, 10)
      .map(([type, count]) => ({ type, count }));

    return {
      totalPersons: totalCount,
      livingCount,
      deceasedCount,
      genderDistribution,
      generationRange,
      averageAge: avgAge,
      topRelationshipTypes: topRelTypes,
      totalRelationships: relationships.length,
      memberCount: await this.prisma.familyMember.count({ where: { familyId } }),
    };
  }

  /**
   * GET /api/v1/families/:familyId/leaderboard — Family leaderboard
   */
  async getFamilyLeaderboard(
    familyId: string,
    options: {
      period?: string;
      page?: number;
      limit?: number;
    } = {},
  ) {
    // Verify family exists
    const family = await this.prisma.family.findUnique({ where: { id: familyId } });
    if (!family) {
      throw new NotFoundException('Family not found');
    }

    const page = Math.max(1, options.page ?? 1);
    const limit = Math.min(options.limit ?? 25, 100);
    const skip = (page - 1) * limit;

    const where: Record<string, unknown> = { familyId };

    const [contributions, total] = await Promise.all([
      this.prisma.userContribution.findMany({
        where,
        skip,
        take: limit,
        orderBy: { totalPoints: 'desc' },
        include: {
          user: { select: { id: true, name: true, email: true } },
        },
      }),
      this.prisma.userContribution.count({ where }),
    ]);

    // Get level info
    const { getLevel } = await import('@/lib/community/contribution-tracker');

    const leaderboard = contributions.map((c, index) => {
      const levelInfo = getLevel(c.totalPoints);
      const rank = skip + index + 1;

      return {
        rank,
        userId: c.userId,
        userName: c.user.name ?? c.user.email,
        totalPoints: c.totalPoints,
        level: levelInfo,
        stats: {
          personsAdded: c.personsAdded,
          relationshipsAdded: c.relationshipsAdded,
          photosAdded: c.photosAdded,
          eventsCreated: c.eventsCreated,
          storiesShared: c.storiesShared,
          commentsWritten: c.commentsWritten,
          invitationsSent: c.invitationsSent,
          personsEdited: c.personsEdited,
        },
      };
    });

    // Get family badge summary
    const familyBadges = await this.prisma.userBadge.findMany({
      where: { familyId },
      include: {
        badge: true,
        user: { select: { id: true, name: true } },
      },
      orderBy: { earnedAt: 'desc' },
      take: 10,
    });

    // Get family milestones
    const milestones = await this.prisma.familyMilestone.findMany({
      where: { familyId },
      orderBy: { reachedAt: 'desc' },
    });

    // Aggregate family totals
    const familyTotals = await this.prisma.userContribution.aggregate({
      where: { familyId },
      _sum: {
        totalPoints: true,
        personsAdded: true,
        relationshipsAdded: true,
        photosAdded: true,
      },
    });

    return {
      family: { id: family.id, name: family.name },
      leaderboard,
      badges: familyBadges.map((ub) => ({
        badge: {
          id: ub.badge.id,
          slug: ub.badge.slug,
          name: ub.badge.name,
          nameHi: ub.badge.nameHi,
          icon: ub.badge.icon,
          tier: ub.badge.tier,
        },
        earnedBy: ub.user.name,
        earnedAt: ub.earnedAt,
      })),
      milestones,
      totals: {
        totalPoints: familyTotals._sum.totalPoints ?? 0,
        personsAdded: familyTotals._sum.personsAdded ?? 0,
        relationshipsAdded: familyTotals._sum.relationshipsAdded ?? 0,
        photosAdded: familyTotals._sum.photosAdded ?? 0,
      },
      pagination: {
        page,
        limit,
        total,
        totalPages: Math.ceil(total / limit),
      },
    };
  }

  /**
   * GET /api/v1/families/:familyId/events — List events
   */
  async listFamilyEvents(
    familyId: string,
    options: {
      upcoming?: boolean;
      eventType?: string;
      page?: number;
      limit?: number;
    } = {},
  ) {
    const page = Math.max(1, options.page ?? 1);
    const limit = Math.min(options.limit ?? 20, 100);
    const skip = (page - 1) * limit;

    const where: Record<string, unknown> = {
      familyId,
      isCancelled: false,
    };

    if (options.upcoming) {
      where.startDate = { gte: new Date() };
    }

    if (options.eventType) {
      where.eventType = options.eventType;
    }

    const [events, total] = await Promise.all([
      this.prisma.communityEvent.findMany({
        where,
        skip,
        take: limit,
        orderBy: { startDate: 'asc' },
        include: {
          _count: { select: { rsvps: true, reminders: true } },
        },
      }),
      this.prisma.communityEvent.count({ where }),
    ]);

    return {
      events,
      pagination: {
        page,
        limit,
        total,
        totalPages: Math.ceil(total / limit),
      },
    };
  }

  /**
   * POST /api/v1/families/:familyId/events — Create event
   */
  async createFamilyEvent(familyId: string, userId: string, body: Record<string, unknown>) {
    const {
      title,
      description,
      eventType,
      startDate,
      endDate,
      isAllDay,
      isRecurring,
      recurrenceRule,
      location,
      locationUrl,
      meetingUrl,
      visibility,
      coverImageUrl,
      communityId,
      metadata,
    } = body;

    if (!title || !startDate) {
      throw new UnprocessableEntityException('Missing required fields: title, startDate');
    }

    // Verify family exists and user is a member
    const familyMember = await this.prisma.familyMember.findFirst({
      where: { familyId, userId },
    });

    if (!familyMember) {
      throw new ForbiddenException('You must be a family member to create events');
    }

    const resolvedEventType = (eventType as string) ?? 'custom';
    const resolvedVisibility = (visibility as string) ?? 'family';

    // Create event
    const event = await this.prisma.communityEvent.create({
      data: {
        familyId,
        communityId: communityId as string | undefined,
        creatorId: userId,
        title: title as string,
        description: description as string | undefined,
        eventType: resolvedEventType,
        startDate: new Date(startDate as string),
        endDate: endDate ? new Date(endDate as string) : null,
        isAllDay: (isAllDay as boolean) ?? false,
        isRecurring: (isRecurring as boolean) ?? false,
        recurrenceRule: recurrenceRule as string | undefined,
        location: location as string | undefined,
        locationUrl: locationUrl as string | undefined,
        meetingUrl: meetingUrl as string | undefined,
        visibility: resolvedVisibility,
        coverImageUrl: coverImageUrl as string | undefined,
        metadata: metadata ? JSON.stringify(metadata) : null,
      },
    });

    // Auto-RSVP the creator as attending
    await this.prisma.eventRSVP.create({
      data: {
        eventId: event.id,
        userId,
        status: 'attending',
      },
    });

    // Create reminders for all family members
    const familyMembers = await this.prisma.familyMember.findMany({
      where: { familyId },
      select: { userId: true },
    });

    const reminderOffsets = [1440, 60, 15]; // 1 day, 1 hour, 15 min before

    for (const member of familyMembers) {
      // Auto-RSVP
      if (member.userId !== userId) {
        await this.prisma.eventRSVP.create({
          data: {
            eventId: event.id,
            userId: member.userId,
            status: 'pending',
          },
        });
      }

      // Create reminders
      for (const offsetMinutes of reminderOffsets) {
        const remindAt = new Date(new Date(startDate as string).getTime() - offsetMinutes * 60 * 1000);
        if (remindAt > new Date()) {
          await this.prisma.eventReminder.create({
            data: {
              eventId: event.id,
              userId: member.userId,
              remindAt,
            },
          });
        }
      }
    }

    // Create a feed post for the event
    await this.prisma.communityPost.create({
      data: {
        familyId,
        communityId: communityId as string | undefined,
        authorId: userId,
        type: 'event',
        title: `📅 ${title}`,
        body: (description as string) ?? `New event: ${title}`,
        visibility: resolvedVisibility === 'public' ? 'public' : 'family_only',
        metadata: JSON.stringify({ eventId: event.id, eventType: resolvedEventType }),
      },
    });

    // Record contribution
    try {
      const { recordContribution } = await import('@/lib/community/contribution-tracker');
      await recordContribution(userId, familyId, 'eventCreated');
    } catch {
      // Contribution tracker might not be available; ignore silently
    }

    this.logger.log(`Event created: ${event.id} in family: ${familyId}`);
    return { event };
  }

  // ═════════════════════════════════════════════════════════════════════
  // V1 Family List (API key auth — scoped to key owner's families)
  // ═════════════════════════════════════════════════════════════════════

  /**
   * GET /api/v1/families — List families (API key auth, paginated)
   */
  async listFamiliesV1(
    userId: string,
    options: {
      page?: number;
      limit?: number;
      sort?: string;
      order?: string;
      search?: string;
    } = {},
  ) {
    const page = Math.max(1, options.page ?? 1);
    const limit = Math.min(100, Math.max(1, options.limit ?? 20));
    const sort = options.sort || 'createdAt';
    const order = options.order || 'desc';

    const where: Record<string, unknown> = {};

    if (options.search) {
      where.OR = [
        { name: { contains: options.search } },
        { description: { contains: options.search } },
      ];
    }

    // Only show families the API key owner has access to
    const familyMemberships = await this.prisma.familyMember.findMany({
      where: { userId },
      select: { familyId: true },
    });
    const familyIds = familyMemberships.map((fm) => fm.familyId);

    where.id = { in: familyIds };

    const [families, total] = await Promise.all([
      this.prisma.family.findMany({
        where,
        orderBy: { [sort]: order === 'asc' ? 'asc' : 'desc' },
        skip: (page - 1) * limit,
        take: limit,
      }),
      this.prisma.family.count({ where }),
    ]);

    return {
      data: families,
      pagination: {
        page,
        limit,
        total,
        hasMore: page * limit < total,
        totalPages: Math.ceil(total / limit),
      },
    };
  }

  /**
   * GET /api/v1/families/:familyId — Get family with optional includes
   */
  async getFamilyV1(familyId: string, userId: string, include?: string) {
    await this.requireFamilyMember(familyId, userId);

    const family = await this.prisma.family.findUnique({
      where: { id: familyId },
      include: {
        members: include?.includes('members') ? { include: { user: true } } : false,
        persons: include?.includes('members') || include?.includes('stats') ? true : false,
        _count: include?.includes('stats')
          ? { select: { persons: true, members: true } }
          : undefined,
      },
    });

    if (!family) {
      throw new NotFoundException('Family not found');
    }

    const responseData: Record<string, unknown> = { ...family };

    if (include?.includes('stats')) {
      const persons = (family as Record<string, unknown>).persons as Array<{ isDeceased: boolean }> || [];
      const living = persons.filter((p) => !p.isDeceased);
      const deceased = persons.filter((p) => p.isDeceased);

      responseData.stats = {
        totalPersons: persons.length,
        livingCount: living.length,
        deceasedCount: deceased.length,
        memberCount: ((family as Record<string, unknown>)._count as { members: number })?.members || 0,
      };
    }

    // Remove persons array if not requested
    if (!include?.includes('members') && !include?.includes('stats')) {
      delete responseData.persons;
    }

    return responseData;
  }

  // ═════════════════════════════════════════════════════════════════════
  // Idempotency Support
  // ═════════════════════════════════════════════════════════════════════

  /**
   * Check idempotency key and return cached response if exists.
   */
  async checkIdempotencyKey(key: string): Promise<{
    isDuplicate: boolean;
    response?: { body: unknown; status: number; headers?: Record<string, string> };
  }> {
    const idemKey = await this.prisma.idempotencyKey.findUnique({
      where: { key },
    });

    if (!idemKey) {
      return { isDuplicate: false };
    }

    // Check if expired
    if (new Date() > idemKey.expiresAt) {
      await this.prisma.idempotencyKey.delete({ where: { key } });
      return { isDuplicate: false };
    }

    return {
      isDuplicate: true,
      response: {
        body: JSON.parse(idemKey.responseBody),
        status: idemKey.responseStatus,
        headers: JSON.parse(idemKey.responseHeaders || '{}'),
      },
    };
  }

  /**
   * Store idempotency key response.
   */
  async storeIdempotencyResponse(
    key: string,
    body: unknown,
    status: number,
    headers: Record<string, string> = {},
  ) {
    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000); // 24 hours

    await this.prisma.idempotencyKey.create({
      data: {
        key,
        responseBody: JSON.stringify(body),
        responseStatus: status,
        responseHeaders: JSON.stringify(headers),
        expiresAt,
      },
    });
  }

  // ═════════════════════════════════════════════════════════════════════
  // Access Control Helpers
  // ═════════════════════════════════════════════════════════════════════

  /**
   * Require the user to be a member of the family. Returns the membership.
   */
  async requireFamilyMember(familyId: string, userId: string) {
    const membership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId } },
    });

    if (!membership) {
      throw new NotFoundException('Family not found or access denied');
    }

    return membership;
  }

  /**
   * Require the user to have a minimum role in the family.
   */
  async requireFamilyRole(familyId: string, userId: string, action: string) {
    const membership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId } },
    });

    if (!membership) {
      throw new NotFoundException('Family not found or access denied');
    }

    if (!hasMinRole(membership.role, action)) {
      throw new ForbiddenException(
        `Insufficient role. ${action} requires: ${MIN_ROLES[action]?.join(', ')}. Got: ${membership.role}`,
      );
    }

    return membership;
  }
}
