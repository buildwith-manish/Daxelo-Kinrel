import {
  Injectable,
  BadRequestException,
  NotFoundException,
  ForbiddenException,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { KinshipValidatorService } from '../kinship/kinship-validator.service';
import { CreatePersonDto } from './dto/create-person.dto';
import { UpdatePersonDto } from './dto/update-person.dto';

@Injectable()
export class PersonsService {
  constructor(
    private prisma: PrismaService,
    private kinshipValidator: KinshipValidatorService,
  ) {}

  /**
   * List persons for a family (paginated, filterable)
   * - Any family member can view
   * - Filters out soft-deleted persons
   * - Optional includeRelationships
   */
  async listPersons(
    familyId: string,
    userId: string,
    query: {
      page?: number;
      limit?: number;
      deceased?: string;
      search?: string;
      sort?: string;
      order?: string;
      includeRelationships?: string;
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
      deletedAt: null, // filter out soft-deleted
    };

    if (query.deceased === 'true') {
      where.isDeceased = true;
    } else if (query.deceased === 'false') {
      where.isDeceased = false;
    }

    if (query.search) {
      where.name = { contains: query.search };
    }

    // Sorting
    const sortField = query.sort || 'createdAt';
    const sortOrder = query.order?.toLowerCase() === 'asc' ? 'asc' : 'desc';
    const orderBy: Record<string, string> = { [sortField]: sortOrder };

    // Include relationships?
    const includeRelationships = query.includeRelationships === 'true';
    const include = includeRelationships
      ? {
          relationshipsFrom: {
            include: {
              toPerson: true,
            },
          },
          relationshipsTo: {
            include: {
              fromPerson: true,
            },
          },
        }
      : undefined;

    const [persons, total] = await Promise.all([
      this.prisma.person.findMany({
        where,
        skip,
        take: limit,
        orderBy,
        include,
      }),
      this.prisma.person.count({ where }),
    ]);

    const totalPages = Math.ceil(total / limit);

    return {
      items: persons,
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
   * Create a person in a family
   * - Admin, editor, or member role required
   * - Kinship key validation and normalization
   * - Audit log
   */
  async createPerson(
    familyId: string,
    userId: string,
    dto: CreatePersonDto,
  ) {
    // Check membership with minimum role
    const membership = await this.checkMembershipWithRole(familyId, userId, 'member');

    // Validate and normalize kinship key
    const normalizedKey = this.kinshipValidator.validateAndNormalizeKey(dto.relationship);
    if (!normalizedKey) {
      throw new BadRequestException(
        `Invalid relationship key: "${dto.relationship}". Please provide a valid kinship term.`,
      );
    }

    const person = await this.prisma.person.create({
      data: {
        familyId,
        name: dto.name.trim(),
        relationship: normalizedKey,
        dateOfBirth: dto.dateOfBirth ? new Date(dto.dateOfBirth) : null,
        gotra: dto.gotra?.trim() || null,
        occupation: dto.occupation?.trim() || null,
        city: dto.city?.trim() || null,
        isDeceased: dto.isDeceased ?? false,
        privacyLevel: dto.privacyLevel || 'family',
      },
    });

    // Audit log
    await this.prisma.auditLog.create({
      data: {
        userId,
        action: 'PERSON_CREATED',
        resource: 'Person',
        resourceId: person.id,
        details: JSON.stringify({
          name: person.name,
          relationship: normalizedKey,
          familyId,
          role: membership.role,
        }),
      },
    });

    return person;
  }

  /**
   * Get a single person with relationships
   * - Any family member can view
   * - Includes relationships
   * - Checks not soft-deleted
   */
  async getPerson(familyId: string, personId: string, userId: string) {
    await this.checkMembership(familyId, userId);

    const person = await this.prisma.person.findFirst({
      where: { id: personId, familyId, deletedAt: null },
      include: {
        relationshipsFrom: {
          include: {
            toPerson: true,
          },
        },
        relationshipsTo: {
          include: {
            fromPerson: true,
          },
        },
      },
    });

    if (!person) {
      throw new NotFoundException('Person not found');
    }

    return person;
  }

  /**
   * Update a person
   * - Admin or editor role required
   * - Validates kinship key if changed
   * - Audit log
   */
  async updatePerson(
    familyId: string,
    personId: string,
    userId: string,
    dto: UpdatePersonDto,
  ) {
    // Check membership with editor+ role
    const membership = await this.checkMembershipWithRole(familyId, userId, 'editor');

    // Verify person exists and not soft-deleted
    const existing = await this.prisma.person.findFirst({
      where: { id: personId, familyId, deletedAt: null },
    });

    if (!existing) {
      throw new NotFoundException('Person not found');
    }

    // Build update data
    const updateData: Record<string, unknown> = {};

    if (dto.name !== undefined) {
      updateData.name = dto.name.trim();
    }
    if (dto.relationship !== undefined) {
      const normalizedKey = this.kinshipValidator.validateAndNormalizeKey(dto.relationship);
      if (!normalizedKey) {
        throw new BadRequestException(
          `Invalid relationship key: "${dto.relationship}". Please provide a valid kinship term.`,
        );
      }
      updateData.relationship = normalizedKey;
    }
    if (dto.dateOfBirth !== undefined) {
      updateData.dateOfBirth = dto.dateOfBirth ? new Date(dto.dateOfBirth) : null;
    }
    if (dto.gotra !== undefined) {
      updateData.gotra = dto.gotra?.trim() || null;
    }
    if (dto.occupation !== undefined) {
      updateData.occupation = dto.occupation?.trim() || null;
    }
    if (dto.city !== undefined) {
      updateData.city = dto.city?.trim() || null;
    }
    if (dto.isDeceased !== undefined) {
      updateData.isDeceased = dto.isDeceased;
    }
    if (dto.privacyLevel !== undefined) {
      updateData.privacyLevel = dto.privacyLevel;
    }

    const updated = await this.prisma.person.update({
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
        details: JSON.stringify({
          updatedFields: Object.keys(updateData),
          familyId,
          role: membership.role,
        }),
      },
    });

    return updated;
  }

  /**
   * Soft delete a person
   * - Admin only
   * - Sets deletedAt timestamp
   * - Audit log
   */
  async deletePerson(familyId: string, personId: string, userId: string) {
    // Check membership with admin role
    const membership = await this.checkMembershipWithRole(familyId, userId, 'admin');

    // Verify person exists and not already soft-deleted
    const existing = await this.prisma.person.findFirst({
      where: { id: personId, familyId, deletedAt: null },
    });

    if (!existing) {
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
        details: JSON.stringify({
          name: existing.name,
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
