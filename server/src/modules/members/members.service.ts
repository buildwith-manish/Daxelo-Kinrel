import {
  Injectable,
  BadRequestException,
  NotFoundException,
  ForbiddenException,
  Inject,
  forwardRef,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { KinrelGateway, MinimalPayload } from '../gateway/kinrel.gateway';
import { CreateMemberDto } from './dto/create-member.dto';
import { UpdateMemberDto } from './dto/update-member.dto';
import { getInverseKey } from '../relationships/relationships.service';
import { GraphService } from '../graph/graph.service';

const ROLE_HIERARCHY: Record<string, number> = {
  viewer: 1,
  member: 2,
  editor: 3,
  admin: 4,
};

const CORE_RELATIONSHIP_KEYS = new Set([
  'father', 'mother', 'son', 'daughter',
  'brother', 'sister', 'husband', 'wife',
]);

@Injectable()
export class MembersService {
  constructor(
    private prisma: PrismaService,
    private gateway: KinrelGateway,
    @Inject(forwardRef(() => GraphService))
    private graphService: GraphService,
  ) {}

  /** Creates a new person in the family and increments the member count.
   *
   * When relativePersonId + initialRelationshipKey are provided, also creates
   * a bidirectional relationship linking the new member to the existing person,
   * and auto-computes the new member's generationIndex from the hierarchy.
   */
  async create(userId: string, familyId: string, dto: CreateMemberDto) {
    await this.requireFamilyRole(userId, familyId, 'member');

    if (!dto.name || typeof dto.name !== 'string' || dto.name.trim().length === 0) {
      throw new BadRequestException('Person name is required');
    }

    // Validate kinship linking params up-front
    if (dto.relativePersonId && !dto.initialRelationshipKey) {
      throw new BadRequestException('initialRelationshipKey is required when relativePersonId is provided');
    }
    if (dto.initialRelationshipKey && !dto.relativePersonId) {
      throw new BadRequestException('relativePersonId is required when initialRelationshipKey is provided');
    }
    if (dto.initialRelationshipKey && !CORE_RELATIONSHIP_KEYS.has(dto.initialRelationshipKey)) {
      throw new BadRequestException(
        `Only core relationship types are allowed: ${[...CORE_RELATIONSHIP_KEYS].join(', ')}`,
      );
    }

    const person = await this.prisma.$transaction(async (tx) => {
      // Resolve relative if kinship linking is requested
      let relativeRecord: { id: string; gender: string | null; generationIndex: number } | null = null;
      if (dto.relativePersonId && dto.initialRelationshipKey) {
        relativeRecord = await tx.person.findFirst({
          where: { id: dto.relativePersonId, familyId, deletedAt: null },
          select: { id: true, gender: true, generationIndex: true },
        });
        if (!relativeRecord) {
          throw new BadRequestException('Relative person not found in this family');
        }
      }

      // Compute generationIndex from relationship if not explicitly provided
      let computedGenIndex = dto.generationIndex ?? 0;
      if (relativeRecord && dto.initialRelationshipKey && (dto.generationIndex === undefined || dto.generationIndex === 0)) {
        const key = dto.initialRelationshipKey;
        if (key === 'father' || key === 'mother') {
          // New member IS parent → relative is the child → new member is one gen ABOVE relative
          computedGenIndex = Math.max(0, relativeRecord.generationIndex - 1);
        } else if (key === 'son' || key === 'daughter') {
          // New member IS child → relative is the parent → new member is one gen BELOW relative
          computedGenIndex = relativeRecord.generationIndex + 1;
        } else {
          // Sibling, spouse — same generation as relative
          computedGenIndex = relativeRecord.generationIndex;
        }
      }

      const created = await tx.person.create({
        data: {
          familyId,
          name: dto.name.trim(),
          gender: dto.gender || null,
          dateOfBirth: dto.dateOfBirth ? new Date(dto.dateOfBirth) : null,
          city: dto.city?.trim() || null,
          gotra: dto.gotra?.trim() || null,
          birthYear: dto.birthYear || null,
          isAnchor: dto.isAnchor ?? false,
          sideOfFamily: dto.sideOfFamily || null,
          generationIndex: computedGenIndex,
          privacyLevel: 'family',
        },
      });

      await tx.family.update({
        where: { id: familyId },
        data: {
          memberCount: { increment: 1 },
          lastActivityAt: new Date(),
        },
      });

      if (dto.isAnchor) {
        await tx.family.update({
          where: { id: familyId },
          data: { anchorPersonId: created.id },
        });
      }

      // Create bidirectional kinship relationship if requested
      if (relativeRecord && dto.initialRelationshipKey) {
        // Check for duplicate relationship
        const existing = await tx.relationship.findFirst({
          where: {
            familyId,
            fromPersonId: created.id,
            toPersonId: relativeRecord.id,
            relationshipKey: dto.initialRelationshipKey,
          },
        });

        if (!existing) {
          const inverseKey = getInverseKey(dto.initialRelationshipKey, relativeRecord.gender);

          await tx.relationship.create({
            data: {
              familyId,
              fromPersonId: created.id,
              toPersonId: relativeRecord.id,
              relationshipKey: dto.initialRelationshipKey,
              direction: 'from',
              isActive: true,
            },
          });

          await tx.relationship.create({
            data: {
              familyId,
              fromPersonId: relativeRecord.id,
              toPersonId: created.id,
              relationshipKey: inverseKey,
              direction: 'from',
              isActive: true,
            },
          });
        }
      }

      return created;
    });

    // Emit person:created event
    this.gateway.emitToFamily(familyId, 'person:created', {
      id: person.id,
      updatedAt: (person.updatedAt ?? new Date()).toISOString(),
      type: 'person:created',
      familyId,
    });

    // v39 BUG-1 FIX: ALWAYS invalidate graph cache when a member is added,
    // not just when a relationship is created. Previously, adding a
    // standalone member (no relationship) left the stale empty graph
    // cached in Redis for 30 minutes — every subsequent API call returned
    // the empty cached data, so the new member was invisible.
    this.gateway.emitToFamily(familyId, 'graph:updated', {
      id: familyId,
      updatedAt: new Date().toISOString(),
      type: 'graph:updated',
      familyId,
    });
    await this.graphService.invalidateFlatGraphCache(familyId);

    // If relationship was also created, emit the relationship:created event
    if (dto.relativePersonId && dto.initialRelationshipKey) {
      this.gateway.emitToFamily(familyId, 'relationship:created', {
        id: person.id,
        updatedAt: new Date().toISOString(),
        type: 'relationship:created',
        familyId,
      });
    }

    return this.formatPerson(person);
  }

  /** Returns a paginated list of persons in the family with optional search and relationships. */
  async findAll(
    userId: string,
    familyId: string,
    query: {
      cursor?: string;
      limit?: number;
      search?: string;
      sort?: string;
      order?: string;
      includeRelationships?: string;
    },
  ) {
    await this.requireFamilyMember(userId, familyId);

    const limit = Math.min(100, Math.max(1, query.limit || 50));

    const where: Record<string, unknown> = {
      familyId,
      deletedAt: null,
    };

    if (query.search) {
      where.name = { contains: query.search };
    }

    const sortField = query.sort || 'createdAt';
    const sortOrder = query.order?.toLowerCase() === 'asc' ? 'asc' : 'desc';
    const orderBy: Record<string, string> = { [sortField]: sortOrder };

    const includeRelationships = query.includeRelationships === 'true';

    // Select only fields needed by formatPerson — skips large photo fields (photoThumb, photoCard, photoFull)
    // that are not used in list view, reducing DB row size by 70%+
    const listSelect = {
      id: true,
      familyId: true,
      name: true,
      gender: true,
      dateOfBirth: true,
      city: true,
      gotra: true,
      isDeceased: true,
      deletedAt: true,
      birthYear: true,
      occupation: true,
      privacyLevel: true,
      notes: true,
      sideOfFamily: true,
      generationIndex: true,
      isAnchor: true,
      photoUrl: true,
      username: true,
      updatedAt: true,
    };

    // When includeRelationships is true, we must use include (not select),
    // but we add nested select to toPerson/fromPerson to avoid fetching full Person rows.
    // When includeRelationships is false, we use select to only fetch needed fields.
    const persons = includeRelationships
      ? await this.prisma.person.findMany({
          where,
          take: limit + 1,
          skip: query.cursor ? 1 : 0,
          cursor: query.cursor ? { id: query.cursor } : undefined,
          orderBy,
          include: {
            relationshipsFrom: {
              where: { isActive: true, toPerson: { deletedAt: null } },
              include: { toPerson: { select: { id: true } } },
            },
            relationshipsTo: {
              where: { isActive: true, fromPerson: { deletedAt: null } },
              include: { fromPerson: { select: { id: true } } },
            },
          },
        })
      : await this.prisma.person.findMany({
          where,
          take: limit + 1,
          skip: query.cursor ? 1 : 0,
          cursor: query.cursor ? { id: query.cursor } : undefined,
          orderBy,
          select: listSelect,
        });

    const hasNextPage = persons.length > limit;
    const data = hasNextPage ? persons.slice(0, -1) : persons;
    const nextCursor = hasNextPage ? data[data.length - 1].id : null;

    return {
      data: data.map((p) => this.formatPerson(p)),
      nextCursor,
    };
  }

  /** Returns a single person with their relationships by ID. */
  async findOne(userId: string, familyId: string, personId: string) {
    await this.requireFamilyMember(userId, familyId);

    const person = await this.prisma.person.findFirst({
      where: { id: personId, familyId, deletedAt: null },
      include: {
        relationshipsFrom: {
          where: { isActive: true, toPerson: { deletedAt: null } },
          include: { toPerson: { select: { id: true } } },
        },
        relationshipsTo: {
          where: { isActive: true, fromPerson: { deletedAt: null } },
          include: { fromPerson: { select: { id: true } } },
        },
      },
    });

    if (!person) {
      throw new NotFoundException('Person not found');
    }

    return this.formatPerson(person);
  }

  /** Updates a person's details and emits a WebSocket update event. */
  async update(userId: string, familyId: string, personId: string, dto: UpdateMemberDto) {
    await this.requireFamilyRole(userId, familyId, 'editor');

    const existing = await this.prisma.person.findFirst({
      where: { id: personId, familyId, deletedAt: null },
    });

    if (!existing) {
      throw new NotFoundException('Person not found');
    }

    const updateData: Record<string, unknown> = {};

    if (dto.name !== undefined) updateData.name = dto.name.trim();
    if (dto.gender !== undefined) updateData.gender = dto.gender || null;
    if (dto.dateOfBirth !== undefined) updateData.dateOfBirth = dto.dateOfBirth ? new Date(dto.dateOfBirth) : null;
    if (dto.city !== undefined) updateData.city = dto.city?.trim() || null;
    if (dto.gotra !== undefined) updateData.gotra = dto.gotra?.trim() || null;
    if (dto.birthYear !== undefined) updateData.birthYear = dto.birthYear || null;
    if (dto.isDeceased !== undefined) updateData.isDeceased = dto.isDeceased;
    if (dto.occupation !== undefined) updateData.occupation = dto.occupation?.trim() || null;
    if (dto.privacyLevel !== undefined) updateData.privacyLevel = dto.privacyLevel;
    if (dto.notes !== undefined) updateData.notes = dto.notes?.trim() || null;
    if (dto.sideOfFamily !== undefined) updateData.sideOfFamily = dto.sideOfFamily || null;
    if (dto.generationIndex !== undefined) updateData.generationIndex = dto.generationIndex;
    if (dto.isAnchor !== undefined) updateData.isAnchor = dto.isAnchor;
    if (dto.photoUrl !== undefined) updateData.photoUrl = dto.photoUrl;
    if (dto.username !== undefined) updateData.username = dto.username?.trim() || null;

    const updated = await this.prisma.person.update({
      where: { id: personId },
      data: updateData,
    });

    if (dto.isAnchor === true) {
      await this.prisma.family.update({
        where: { id: familyId },
        data: { anchorPersonId: personId, lastActivityAt: new Date() },
      });
    }

    // Emit MINIMAL payload — Flutter fetches full data from Isar/API if needed
    this.gateway.emitToFamily(familyId, 'person:updated', {
      id: personId,
      updatedAt: (updated.updatedAt ?? new Date()).toISOString(),
      type: 'person:updated',
      familyId,
    });

    return this.formatPerson(updated);
  }

  /** Soft-deletes a person and deactivates their relationships. */
  async remove(userId: string, familyId: string, personId: string) {
    await this.requireFamilyRole(userId, familyId, 'editor');

    const existing = await this.prisma.person.findFirst({
      where: { id: personId, familyId, deletedAt: null },
    });

    if (!existing) {
      throw new NotFoundException('Person not found');
    }

    await this.prisma.$transaction(async (tx) => {
      await tx.person.update({
        where: { id: personId },
        data: { deletedAt: new Date() },
      });

      await tx.relationship.updateMany({
        where: {
          OR: [{ fromPersonId: personId }, { toPersonId: personId }],
        },
        data: { isActive: false },
      });

      await tx.family.update({
        where: { id: familyId },
        data: {
          memberCount: { decrement: 1 },
          lastActivityAt: new Date(),
        },
      });
    });

    // Emit MINIMAL payload for person deletion
    this.gateway.emitToFamily(familyId, 'person:deleted', {
      id: personId,
      updatedAt: new Date().toISOString(),
      type: 'person:deleted',
      familyId,
    });

    // Emit MINIMAL payload for graph update (debounced by gateway)
    this.gateway.emitToFamily(familyId, 'graph:updated', {
      id: familyId,
      updatedAt: new Date().toISOString(),
      type: 'graph:updated',
      familyId,
    });

    return { deleted: true, personId };
  }

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

  private formatPerson(person: Record<string, any>) {
    const result: Record<string, any> = {
      id: person.id,
      familyId: person.familyId,
      name: person.name,
      gender: person.gender ?? null,
      dateOfBirth: person.dateOfBirth ?? null,
      city: person.city ?? null,
      gotra: person.gotra ?? null,
      isDeceased: person.isDeceased ?? false,
      deletedAt: person.deletedAt ?? null,
      birthYear: person.birthYear ?? null,
      occupation: person.occupation ?? null,
      privacyLevel: person.privacyLevel ?? 'family',
      notes: person.notes ?? null,
      sideOfFamily: person.sideOfFamily ?? null,
      generationIndex: person.generationIndex ?? 0,
      isAnchor: person.isAnchor ?? false,
      photoUrl: person.photoUrl ?? null,
      username: person.username ?? null,
    };

    if (person.relationshipsFrom || person.relationshipsTo) {
      const relationships: Record<string, any>[] = [];

      if (person.relationshipsFrom) {
        for (const rel of person.relationshipsFrom) {
          if (rel.toPerson) {
            relationships.push({
              id: rel.id,
              familyId: rel.familyId,
              fromPersonId: rel.fromPersonId,
              toPersonId: rel.toPersonId,
              relationshipKey: rel.relationshipKey,
              direction: rel.direction,
              isActive: rel.isActive,
              label: rel.label ?? null,
            });
          }
        }
      }

      if (person.relationshipsTo) {
        for (const rel of person.relationshipsTo) {
          if (rel.fromPerson) {
            relationships.push({
              id: rel.id,
              familyId: rel.familyId,
              fromPersonId: rel.fromPersonId,
              toPersonId: rel.toPersonId,
              relationshipKey: rel.relationshipKey,
              direction: rel.direction,
              isActive: rel.isActive,
              label: rel.label ?? null,
            });
          }
        }
      }

      result.relationships = relationships;
    }

    return result;
  }
}
