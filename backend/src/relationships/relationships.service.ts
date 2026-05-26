import {
  Injectable,
  BadRequestException,
  NotFoundException,
  ForbiddenException,
  ConflictException,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { KinshipValidatorService } from '../kinship/kinship-validator.service';
import { CreateRelationshipDto } from './dto/create-relationship.dto';

/**
 * Inverse relationship map.
 * Maps a relationship type to its inverse type.
 * When creating "father" from A→B, auto-creates "son" from B→A.
 */
export const INVERSE_RELATIONSHIP_MAP: Record<string, string> = {
  father: 'son',
  mother: 'son',
  son: 'father',
  daughter: 'mother',
  husband: 'wife',
  wife: 'husband',
  elder_brother: 'younger_brother',
  younger_brother: 'elder_brother',
  elder_sister: 'younger_sister',
  younger_sister: 'elder_sister',
  brother: 'brother',
  sister: 'sister',
  paternal_grandfather: 'grandson',
  paternal_grandmother: 'grandson',
  maternal_grandfather: 'grandson',
  maternal_grandmother: 'grandson',
  husbands_father: 'sons_wife',
  husbands_mother: 'sons_wife',
  wives_father: 'daughters_husband',
  wives_mother: 'daughters_husband',
  sons_wife: 'husbands_father',
  daughters_husband: 'wives_father',
};

@Injectable()
export class RelationshipsService {
  constructor(
    private prisma: PrismaService,
    private kinshipValidator: KinshipValidatorService,
  ) {}

  /**
   * List relationships for a family
   * - Filter by personId (optional)
   * - Include fromPerson/toPerson (not soft-deleted)
   * - Paginated
   */
  async listRelationships(
    familyId: string,
    userId: string,
    query: {
      page?: number;
      limit?: number;
      personId?: string;
    },
  ) {
    // Check family membership
    await this.checkMembership(familyId, userId);

    const page = Math.max(1, query.page || 1);
    const limit = Math.min(100, Math.max(1, query.limit || 20));
    const skip = (page - 1) * limit;

    // Build where clause
    const where: Record<string, unknown> = {
      familyId,
      fromPerson: { deletedAt: null },
      toPerson: { deletedAt: null },
    };

    if (query.personId) {
      where.OR = [
        { fromPersonId: query.personId },
        { toPersonId: query.personId },
      ];
      // Remove the default filter since OR will handle it
      delete where.fromPerson;
      delete where.toPerson;
      // Add soft-delete check within OR conditions
      where.OR = [
        { fromPersonId: query.personId, fromPerson: { deletedAt: null }, toPerson: { deletedAt: null } },
        { toPersonId: query.personId, fromPerson: { deletedAt: null }, toPerson: { deletedAt: null } },
      ];
    }

    const [relationships, total] = await Promise.all([
      this.prisma.relationship.findMany({
        where,
        skip,
        take: limit,
        orderBy: { createdAt: 'desc' },
        include: {
          fromPerson: true,
          toPerson: true,
        },
      }),
      this.prisma.relationship.count({ where }),
    ]);

    const totalPages = Math.ceil(total / limit);

    return {
      items: relationships,
      pagination: {
        page,
        limit,
        total,
        hasMore: page < totalPages,
        totalPages,
      },
    };
  }

  /**
   * Create a relationship
   * - Member+ role required
   * - Validate kinship type
   * - No self-relationship
   * - Both persons must exist and not be soft-deleted
   * - No duplicate
   * - Auto-create inverse relationship in transaction
   * - Audit log
   */
  async createRelationship(
    familyId: string,
    userId: string,
    dto: CreateRelationshipDto,
  ) {
    // Check membership with minimum role
    const membership = await this.checkMembershipWithRole(familyId, userId, 'member');

    // No self-relationship
    if (dto.fromPersonId === dto.toPersonId) {
      throw new BadRequestException('Cannot create a self-relationship');
    }

    // Validate kinship type
    const normalizedType = this.kinshipValidator.validateAndNormalizeKey(dto.type);
    if (!normalizedType) {
      throw new BadRequestException(
        `Invalid relationship type: "${dto.type}". Please provide a valid kinship term.`,
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
      throw new NotFoundException('Source person not found in this family');
    }
    if (!toPerson) {
      throw new NotFoundException('Target person not found in this family');
    }

    // Check no duplicate
    const existing = await this.prisma.relationship.findFirst({
      where: {
        familyId,
        fromPersonId: dto.fromPersonId,
        toPersonId: dto.toPersonId,
        type: normalizedType,
      },
    });

    if (existing) {
      throw new ConflictException('This relationship already exists');
    }

    // Get inverse type
    const inverseType = INVERSE_RELATIONSHIP_MAP[normalizedType] || normalizedType;

    // Create primary and inverse relationships in a transaction
    const result = await this.prisma.$transaction(async (tx) => {
      // Primary relationship
      const primary = await tx.relationship.create({
        data: {
          familyId,
          fromPersonId: dto.fromPersonId,
          toPersonId: dto.toPersonId,
          type: normalizedType,
          direction: 'from',
        },
        include: {
          fromPerson: true,
          toPerson: true,
        },
      });

      // Inverse relationship
      await tx.relationship.create({
        data: {
          familyId,
          fromPersonId: dto.toPersonId,
          toPersonId: dto.fromPersonId,
          type: inverseType,
          direction: 'from',
        },
      });

      return primary;
    });

    // Audit log
    await this.prisma.auditLog.create({
      data: {
        userId,
        action: 'RELATIONSHIP_CREATED',
        resource: 'Relationship',
        resourceId: result.id,
        details: JSON.stringify({
          fromPersonId: dto.fromPersonId,
          toPersonId: dto.toPersonId,
          type: normalizedType,
          inverseType,
          familyId,
          role: membership.role,
        }),
      },
    });

    return result;
  }

  /**
   * Delete a relationship and its inverse
   * - Editor+ role required
   * - Deletes both primary and inverse in a transaction
   * - Audit log
   */
  async deleteRelationship(
    familyId: string,
    relationshipId: string,
    userId: string,
  ) {
    // Check membership with editor+ role
    const membership = await this.checkMembershipWithRole(familyId, userId, 'editor');

    // Find the relationship
    const relationship = await this.prisma.relationship.findFirst({
      where: { id: relationshipId, familyId },
    });

    if (!relationship) {
      throw new NotFoundException('Relationship not found');
    }

    // Find the inverse relationship
    const inverse = await this.prisma.relationship.findFirst({
      where: {
        familyId,
        fromPersonId: relationship.toPersonId,
        toPersonId: relationship.fromPersonId,
        type: INVERSE_RELATIONSHIP_MAP[relationship.type] || relationship.type,
      },
    });

    // Delete both in a transaction
    await this.prisma.$transaction(async (tx) => {
      await tx.relationship.delete({ where: { id: relationshipId } });

      if (inverse) {
        await tx.relationship.delete({ where: { id: inverse.id } });
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
          fromPersonId: relationship.fromPersonId,
          toPersonId: relationship.toPersonId,
          type: relationship.type,
          inverseId: inverse?.id || null,
          familyId,
          role: membership.role,
        }),
      },
    });
  }

  /**
   * Check that user is a member of the family
   */
  private async checkMembership(familyId: string, userId: string) {
    const membership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId } },
    });

    if (!membership) {
      throw new ForbiddenException('You are not a member of this family');
    }

    return membership;
  }

  /**
   * Check membership and enforce minimum role
   * Role hierarchy: admin > editor > member > viewer
   */
  private async checkMembershipWithRole(
    familyId: string,
    userId: string,
    minRole: string,
  ) {
    const membership = await this.checkMembership(familyId, userId);

    const roleHierarchy: Record<string, number> = {
      viewer: 1,
      member: 2,
      editor: 3,
      admin: 4,
    };

    const userLevel = roleHierarchy[membership.role] || 0;
    const requiredLevel = roleHierarchy[minRole] || 0;

    if (userLevel < requiredLevel) {
      throw new ForbiddenException(
        `Insufficient permissions. Required: ${minRole}, current: ${membership.role}`,
      );
    }

    return membership;
  }
}
