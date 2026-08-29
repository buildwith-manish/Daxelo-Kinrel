import {
  Injectable,
  BadRequestException,
  NotFoundException,
  ForbiddenException,
  ConflictException,
  Logger,
  Inject,
  forwardRef,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { KinrelGateway } from '../gateway/kinrel.gateway';
import { CreateRelationshipDto } from './dto/create-relationship.dto';
import { GraphService } from '../graph/graph.service';
import { GraphEngineService } from '../graph/graph-engine.service';
import { Prisma } from '@prisma/client';

const ROLE_HIERARCHY: Record<string, number> = {
  viewer: 1,
  member: 2,
  editor: 3,
  admin: 4,
};

// Core relationship types — only these should be stored in the database
// Extended types are computed dynamically by GraphEngineService
const ALLOWED_CORE_KEYS = new Set([
  'father', 'mother', 'son', 'daughter',
  'brother', 'sister', 'husband', 'wife',
]);

const INVERSE_RELATIONSHIP_MAP: Record<string, (toGender?: string | null) => string> = {
  father: (toGender) => toGender === 'female' ? 'daughter' : 'son',
  mother: (toGender) => toGender === 'female' ? 'daughter' : 'son',
  // son/daughter inverse depends on the PARENT's gender (toGender = the person being linked to)
  son: (toGender) => toGender === 'female' ? 'mother' : 'father',
  daughter: (toGender) => toGender === 'female' ? 'mother' : 'father',
  husband: () => 'wife',
  wife: () => 'husband',
  brother: (toGender) => toGender === 'female' ? 'sister' : 'brother',
  sister: (toGender) => toGender === 'female' ? 'sister' : 'brother',
  grandfather: (toGender) => toGender === 'female' ? 'granddaughter' : 'grandson',
  grandmother: (toGender) => toGender === 'female' ? 'granddaughter' : 'grandson',
  grandson: () => 'grandfather',
  granddaughter: () => 'grandmother',
  uncle: (toGender) => toGender === 'female' ? 'niece' : 'nephew',
  aunt: (toGender) => toGender === 'female' ? 'niece' : 'nephew',
  nephew: () => 'uncle',
  niece: () => 'aunt',
  paternal_grandfather: (toGender) => toGender === 'female' ? 'granddaughter' : 'grandson',
  paternal_grandmother: (toGender) => toGender === 'female' ? 'granddaughter' : 'grandson',
  maternal_grandfather: (toGender) => toGender === 'female' ? 'granddaughter' : 'grandson',
  maternal_grandmother: (toGender) => toGender === 'female' ? 'granddaughter' : 'grandson',
  husbands_father: () => 'sons_wife',
  husbands_mother: () => 'sons_wife',
  wives_father: () => 'daughters_husband',
  wives_mother: () => 'daughters_husband',
  sons_wife: () => 'husbands_father',
  daughters_husband: () => 'wives_father',
  elder_brother: () => 'younger_brother',
  younger_brother: () => 'elder_brother',
  elder_sister: () => 'younger_sister',
  younger_sister: () => 'elder_sister',
  cousin: () => 'cousin',
  father_in_law: (toGender) => toGender === 'female' ? 'daughters_husband' : 'sons_wife',
  mother_in_law: (toGender) => toGender === 'female' ? 'daughters_husband' : 'sons_wife',
  brother_in_law: () => 'brother_in_law',
  sister_in_law: () => 'sister_in_law',
};

export function getInverseKey(forwardKey: string, toGender?: string | null): string {
  const mapper = INVERSE_RELATIONSHIP_MAP[forwardKey];
  if (mapper) {
    return mapper(toGender);
  }
  return forwardKey;
}

@Injectable()
export class RelationshipsService {
  private readonly logger = new Logger(RelationshipsService.name);

  constructor(
    private prisma: PrismaService,
    private gateway: KinrelGateway,
    @Inject(forwardRef(() => GraphService))
    private graphService: GraphService,
    @Inject(forwardRef(() => GraphEngineService))
    private graphEngineService: GraphEngineService,
  ) {}

  /** Creates a bidirectional relationship between two persons in the family. */
  async create(userId: string, familyId: string, dto: CreateRelationshipDto) {
    await this.requireFamilyRole(userId, familyId, 'editor');

    if (dto.fromPersonId === dto.toPersonId) {
      throw new BadRequestException('Cannot create a self-relationship');
    }

    // Validate: only core relationship types are allowed for new relationships
    // Extended types (grandfather, uncle, etc.) are computed dynamically by GraphEngineService
    if (!ALLOWED_CORE_KEYS.has(dto.relationshipKey)) {
      throw new BadRequestException(
        `Only core relationship types are allowed. Use: ${[...ALLOWED_CORE_KEYS].join(', ')}. ` +
        `Extended types like "${dto.relationshipKey}" are computed automatically from core relationships.`,
      );
    }

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

    const existingForward = await this.prisma.relationship.findFirst({
      where: {
        familyId,
        fromPersonId: dto.fromPersonId,
        toPersonId: dto.toPersonId,
        relationshipKey: dto.relationshipKey,
      },
    });

    if (existingForward) {
      throw new ConflictException('This relationship already exists');
    }

    const inverseKey = getInverseKey(dto.relationshipKey, toPerson.gender);

    const result = await this.prisma.$transaction(async (tx) => {
      const forward = await tx.relationship.create({
        data: {
          familyId,
          fromPersonId: dto.fromPersonId,
          toPersonId: dto.toPersonId,
          relationshipKey: dto.relationshipKey,
          direction: 'from',
          isActive: true,
        },
      });

      await tx.relationship.create({
        data: {
          familyId,
          fromPersonId: dto.toPersonId,
          toPersonId: dto.fromPersonId,
          relationshipKey: inverseKey,
          direction: 'from',
          isActive: true,
        },
      });

      await tx.family.update({
        where: { id: familyId },
        data: { lastActivityAt: new Date() },
      });

      // Auto-update generationIndex to maintain consistent hierarchy
      const key = dto.relationshipKey;
      if (key === 'father' || key === 'mother') {
        // fromPerson IS the parent → toPerson is the child (one generation down)
        // BUG-009 FIX: Also update parent's generationIndex if it's at default 0
        // and we're adding a child — the parent should be at gen -1 (above child)
        if (fromPerson.generationIndex === 0 && toPerson.generationIndex === 0) {
          // Both at default — set parent to -1, child to 0
          await tx.person.update({
            where: { id: dto.fromPersonId },
            data: { generationIndex: -1 },
          });
          await tx.person.update({
            where: { id: dto.toPersonId },
            data: { generationIndex: 0 },
          });
        } else {
          await tx.person.update({
            where: { id: dto.toPersonId },
            data: { generationIndex: fromPerson.generationIndex + 1 },
          });
        }
      } else if (key === 'son' || key === 'daughter') {
        // fromPerson IS the child → toPerson is the parent (one generation up)
        // child gets parent's generationIndex + 1
        await tx.person.update({
          where: { id: dto.fromPersonId },
          data: { generationIndex: toPerson.generationIndex + 1 },
        });
      } else if (key === 'brother' || key === 'sister') {
        // v5.129 Sibling Backfill (§1.2): when a sibling edge is added,
        // backfill the SHARED PARENT so neither sibling is left
        // parentless in the graph (which would cause the Tree layout
        // engine's root-finder to float them to the top row, disconnected
        // from where they actually belong).
        //
        // Three branches, in priority order:
        //   1. One sibling has recorded parents → link the other under
        //      those same real parents.
        //   2. Neither sibling has recorded parents → auto-create ONE
        //      placeholder parent (isPlaceholder: true) and link BOTH
        //      siblings to it.
        //   3. Both siblings already have DIFFERENT recorded parents →
        //      flag for human review (§3). Don't auto-merge.
        //
        // All edges created here are marked isInferred: true so downstream
        // code can distinguish user-added vs system-backfilled edges.
        await this.backfillSharedParentForSibling(
          tx,
          familyId,
          fromPerson,
          toPerson,
          forward.id,
        );

        // Sync sibling to same generation if one is still at default 0.
        // (Original behavior preserved as a fallback — the backfill above
        // also sets generationIndex when it creates a placeholder parent,
        // but this catches any edge case where the backfill was a no-op
        // because both siblings already had parents.)
        if (toPerson.generationIndex === 0 && fromPerson.generationIndex !== 0) {
          await tx.person.update({
            where: { id: dto.toPersonId },
            data: { generationIndex: fromPerson.generationIndex },
          });
        } else if (fromPerson.generationIndex === 0 && toPerson.generationIndex !== 0) {
          await tx.person.update({
            where: { id: dto.fromPersonId },
            data: { generationIndex: toPerson.generationIndex },
          });
        }
      } else if (key === 'husband' || key === 'wife') {
        // Sync spouse to same generation if unset
        if (toPerson.generationIndex === 0 && fromPerson.generationIndex !== 0) {
          await tx.person.update({
            where: { id: dto.toPersonId },
            data: { generationIndex: fromPerson.generationIndex },
          });
        } else if (fromPerson.generationIndex === 0 && toPerson.generationIndex !== 0) {
          await tx.person.update({
            where: { id: dto.fromPersonId },
            data: { generationIndex: toPerson.generationIndex },
          });
        }
      }

      return forward;
    });

    // Emit MINIMAL payload — Flutter fetches full data from Isar/API if needed
    this.gateway.emitToFamily(familyId, 'relationship:created', {
      id: result.id,
      updatedAt: (result.updatedAt ?? new Date()).toISOString(),
      type: 'relationship:created',
      familyId,
    });

    this.gateway.emitToFamily(familyId, 'graph:updated', {
      id: familyId,
      updatedAt: new Date().toISOString(),
      type: 'graph:updated',
      familyId,
    });

    // Invalidate Redis flat graph cache so next fetch reflects new relationship
    await this.graphService.invalidateFlatGraphCache(familyId);

    return this.formatRelationship(result);
  }

  /** Returns all active relationships in a family, optionally filtered by person, with pagination. */
  async findAll(
    userId: string,
    familyId: string,
    query: { personId?: string },
    pagination?: { page?: number; limit?: number },
  ) {
    await this.requireFamilyMember(userId, familyId);

    const where: Record<string, unknown> = {
      familyId,
      isActive: true,
      fromPerson: { deletedAt: null },
      toPerson: { deletedAt: null },
    };

    if (query.personId) {
      delete where.fromPerson;
      delete where.toPerson;
      where.OR = [
        { fromPersonId: query.personId, fromPerson: { deletedAt: null }, toPerson: { deletedAt: null }, isActive: true },
        { toPersonId: query.personId, fromPerson: { deletedAt: null }, toPerson: { deletedAt: null }, isActive: true },
      ];
    }

    const page = pagination?.page ?? 1;
    const limit = pagination?.limit ?? 20;
    const skip = (page - 1) * limit;

    const [relationships, total] = await this.prisma.$transaction([
      this.prisma.relationship.findMany({
        where,
        skip,
        take: limit,
        orderBy: { createdAt: 'desc' },
        include: {
          fromPerson: { select: { id: true, deletedAt: true } },
          toPerson: { select: { id: true, deletedAt: true } },
        },
      }),
      this.prisma.relationship.count({ where }),
    ]);

    return {
      items: relationships
        .filter((r) => r.fromPerson && r.toPerson)
        .map((r) => this.formatRelationship(r)),
      total,
      page,
      limit,
    };
  }

  /** Deletes a relationship and its inverse pair. */
  async remove(userId: string, familyId: string, relationshipId: string) {
    await this.requireFamilyRole(userId, familyId, 'editor');

    const relationship = await this.prisma.relationship.findFirst({
      where: { id: relationshipId, familyId },
    });

    if (!relationship) {
      throw new NotFoundException('Relationship not found');
    }

    // BUG-010 FIX: Pass toPerson's gender to getInverseKey for correct inverse lookup
    const toPerson = await this.prisma.person.findUnique({
      where: { id: relationship.toPersonId },
      select: { gender: true },
    });
    const inverseKey = getInverseKey(relationship.relationshipKey, toPerson?.gender ?? null);
    const inverse = await this.prisma.relationship.findFirst({
      where: {
        familyId,
        fromPersonId: relationship.toPersonId,
        toPersonId: relationship.fromPersonId,
        relationshipKey: inverseKey,
        isActive: true,
      },
    });

    await this.prisma.$transaction(async (tx) => {
      await tx.relationship.delete({ where: { id: relationshipId } });

      if (inverse) {
        await tx.relationship.delete({ where: { id: inverse.id } });
      }

      await tx.family.update({
        where: { id: familyId },
        data: { lastActivityAt: new Date() },
      });
    });

    // Emit MINIMAL payload — Flutter fetches full data from Isar/API if needed
    this.gateway.emitToFamily(familyId, 'relationship:deleted', {
      id: relationshipId,
      updatedAt: new Date().toISOString(),
      type: 'relationship:deleted',
      familyId,
    });

    this.gateway.emitToFamily(familyId, 'graph:updated', {
      id: familyId,
      updatedAt: new Date().toISOString(),
      type: 'graph:updated',
      familyId,
    });

    // Invalidate Redis flat graph cache so next fetch reflects deleted relationship
    await this.graphService.invalidateFlatGraphCache(familyId);

    return { deleted: true, relationshipId };
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

  private formatRelationship(rel: Record<string, any>) {
    return {
      id: rel.id,
      familyId: rel.familyId,
      fromPersonId: rel.fromPersonId,
      toPersonId: rel.toPersonId,
      relationshipKey: rel.relationshipKey,
      direction: rel.direction,
      isActive: rel.isActive,
      label: rel.label ?? null,
    };
  }

  /**
   * GET /families/:familyId/relationship-path?from=...&to=...
   *
   * v2.2 — Returns the cached relationship path between two persons in a family.
   * Uses the existing `RelationshipPathCache` table (architecture §16).
   * Falls through to `GraphEngineService.findPath` when no cache hit,
   * then persists the result for future reads.
   *
   * Privacy: hidden / private persons are represented as anonymous nodes
   * — they are NOT skipped, as skipping would produce incorrect kinship
   * paths (architecture §14).
   */
  async getRelationshipPath(
    userId: string,
    familyId: string,
    fromPersonId: string,
    toPersonId: string,
  ): Promise<{
    familyId: string;
    fromPersonId: string;
    toPersonId: string;
    found: boolean;
    path: Array<{
      personId: string;
      personName: string;
      relationshipType?: string;
      direction?: string;
    }>;
    distance: number;
    kinshipTerm: string | null;
    kinshipTermHindi: string | null;
    cached: boolean;
  }> {
    await this.requireFamilyMember(userId, familyId);

    if (fromPersonId === toPersonId) {
      return {
        familyId,
        fromPersonId,
        toPersonId,
        found: true,
        path: [],
        distance: 0,
        kinshipTerm: 'self',
        kinshipTermHindi: 'स्वयं',
        cached: false,
      };
    }

    // 1. Try cache first.
    const cacheTtlMs = 30 * 60 * 1000; // 30 min
    const now = new Date();
    const cached = await this.prisma.relationshipPathCache.findUnique({
      where: {
        familyId_fromPersonId_toPersonId: {
          familyId,
          fromPersonId,
          toPersonId,
        },
      },
    });

    if (cached && cached.expiresAt && cached.expiresAt > now) {
      let parsedPath: any[] = [];
      try {
        parsedPath = JSON.parse(cached.path);
      } catch {
        parsedPath = [];
      }
      return {
        familyId,
        fromPersonId,
        toPersonId,
        found: parsedPath.length > 0,
        path: parsedPath,
        distance: cached.distance,
        kinshipTerm: cached.kinshipTerm,
        kinshipTermHindi: cached.kinshipTermHi,
        cached: true,
      };
    }

    // 2. Compute fresh using GraphEngineService.findPath
    const fresh = await this.graphEngineService.findPath(
      familyId,
      fromPersonId,
      toPersonId,
    );

    // 3. Persist to cache (upsert). Non-fatal on failure.
    const pathJson = JSON.stringify(fresh.path);
    const expiresAt = new Date(now.getTime() + cacheTtlMs);
    try {
      await this.prisma.relationshipPathCache.upsert({
        where: {
          familyId_fromPersonId_toPersonId: {
            familyId,
            fromPersonId,
            toPersonId,
          },
        },
        create: {
          familyId,
          fromPersonId,
          toPersonId,
          path: pathJson,
          kinshipTerm: fresh.kinshipTerm ?? null,
          kinshipTermHi: fresh.kinshipTermHindi ?? null,
          distance: fresh.distance,
          expiresAt,
        },
        update: {
          path: pathJson,
          kinshipTerm: fresh.kinshipTerm ?? null,
          kinshipTermHi: fresh.kinshipTermHindi ?? null,
          distance: fresh.distance,
          computedAt: now,
          expiresAt,
        },
      });
    } catch (err) {
      this.logger.warn(
        `Failed to persist RelationshipPathCache: ${(err as Error).message}`,
      );
    }

    return {
      familyId,
      fromPersonId,
      toPersonId,
      found: fresh.found,
      path: fresh.path,
      distance: fresh.distance,
      kinshipTerm: fresh.kinshipTerm ?? null,
      kinshipTermHindi: fresh.kinshipTermHindi ?? null,
      cached: false,
    };
  }

  // ════════════════════════════════════════════════════════════════════
  // v5.129 Sibling Backfill (§1.2 + §3)
  // ════════════════════════════════════════════════════════════════════

  /**
   * Backfill a shared parent for a sibling edge so neither sibling is
   * left parentless in the graph.
   *
   * Three branches (§1.2):
   *   1. One sibling has recorded parents → link the other under those
   *      same real parents.
   *   2. Neither sibling has parents → create ONE placeholder parent
   *      (isPlaceholder: true, gender: null) and link BOTH siblings.
   *   3. Both siblings already have DIFFERENT parents → flag for review
   *      (§3), don't auto-merge.
   *
   * All edges created here are marked isInferred: true so downstream code
   * can distinguish user-added vs system-backfilled edges.
   */
  private async backfillSharedParentForSibling(
    tx: Prisma.TransactionClient,
    familyId: string,
    fromPerson: { id: string; gender: string | null; generationIndex: number },
    toPerson: { id: string; gender: string | null; generationIndex: number },
    forwardRelationshipId: string,
  ): Promise<void> {
    // Find existing parents of both siblings.
    const fromParents = await this.findParentsOf(tx, fromPerson.id);
    const toParents = await this.findParentsOf(tx, toPerson.id);

    const fromHasParents = fromParents.length > 0;
    const toHasParents = toParents.length > 0;

    if (fromHasParents && !toHasParents) {
      // Case 1: fromPerson has parents → link toPerson under them.
      for (const parent of fromParents) {
        await this.createParentChildEdgePair(
          tx, familyId, parent, toPerson,
        );
      }
    } else if (toHasParents && !fromHasParents) {
      // Case 1 mirror: toPerson has parents → link fromPerson under them.
      for (const parent of toParents) {
        await this.createParentChildEdgePair(
          tx, familyId, parent, fromPerson,
        );
      }
    } else if (!fromHasParents && !toHasParents) {
      // Case 2: neither has parents → create placeholder parent.
      const minGen = Math.min(
        fromPerson.generationIndex,
        toPerson.generationIndex,
      );
      const placeholder = await tx.person.create({
        data: {
          familyId,
          name: 'Unknown parent',
          isPlaceholder: true,
          gender: null, // §1.3: unknown, not guessed
          generationIndex: minGen - 1,
        },
      });
      // Link both siblings to the placeholder.
      // Use 'father' as the relationshipKey convention — the UI can
      // relabel to 'mother' later when the user fills in details.
      await this.createParentChildEdgePair(
        tx, familyId,
        { id: placeholder.id, relationshipKey: 'father' },
        fromPerson,
      );
      await this.createParentChildEdgePair(
        tx, familyId,
        { id: placeholder.id, relationshipKey: 'father' },
        toPerson,
      );
    } else {
      // Case 3: both have parents → check if they share any.
      const fromParentIds = new Set(fromParents.map(p => p.id));
      const sharedCount = toParents.filter(p => fromParentIds.has(p.id)).length;

      if (sharedCount === 0) {
        // Different parents → flag for review (§3).
        // Pick the first parent from each side for the flag's display.
        const parentA = fromParents[0];
        const parentB = toParents[0];
        try {
          await tx.relationshipReviewFlag.create({
            data: {
              familyId,
              sourceRelationshipId: forwardRelationshipId,
              parentAPersonId: parentA.id,
              parentBPersonId: parentB.id,
              reason: 'sibling_parent_mismatch',
              status: 'pending',
            },
          });
          this.logger.warn(
            `Sibling edge ${forwardRelationshipId} flagged for review: ` +
            `both siblings have different recorded parents ` +
            `(${parentA.id} vs ${parentB.id}).`,
          );
        } catch (err) {
          // Unique constraint violation = flag already exists. Non-fatal.
          this.logger.debug(
            `Review flag already exists for edge ${forwardRelationshipId}: ${(err as Error).message}`,
          );
        }
      }
      // If they share parents, no action needed — they're already linked
      // under the same real parents.
    }
  }

  /**
   * Find all parents of [personId] — persons connected via a father/mother
   * edge (either direction: person→parent "father"/"mother", or
   * parent→person "son"/"daughter").
   *
   * Returns an array of { id, relationshipKey } where relationshipKey
   * is 'father' or 'mother' (the key describing the parent's relationship
   * to the child).
   */
  private async findParentsOf(
    tx: Prisma.TransactionClient,
    personId: string,
  ): Promise<Array<{ id: string; relationshipKey: string }>> {
    // Direction 1: person → parent, key = 'father' or 'mother'
    // (person is fromPersonId, parent is toPersonId)
    const forwardParentEdges = await tx.relationship.findMany({
      where: {
        fromPersonId: personId,
        relationshipKey: { in: ['father', 'mother'] },
        isActive: true,
      },
      select: {
        toPersonId: true,
        relationshipKey: true,
      },
    });

    // Direction 2: parent → person, key = 'son' or 'daughter'
    // (parent is fromPersonId, person is toPersonId)
    const inverseParentEdges = await tx.relationship.findMany({
      where: {
        toPersonId: personId,
        relationshipKey: { in: ['son', 'daughter'] },
        isActive: true,
      },
      select: {
        fromPersonId: true,
        relationshipKey: true,
      },
    });

    // Merge + dedupe by parent ID.
    // For inverse edges, the relationshipKey is 'son'/'daughter' (the
    // child's relationship to the parent). We need the PARENT's key
    // ('father'/'mother'). We can't recover it from the inverse key alone
    // without knowing the parent's gender — but we can look it up.
    // For simplicity, we store the FORWARD key ('father'/'mother') when
    // available, and 'father' as a fallback for inverse-only edges.
    const parentsMap = new Map<string, { id: string; relationshipKey: string }>();

    for (const edge of forwardParentEdges) {
      if (!parentsMap.has(edge.toPersonId)) {
        parentsMap.set(edge.toPersonId, {
          id: edge.toPersonId,
          relationshipKey: edge.relationshipKey,
        });
      }
    }

    for (const edge of inverseParentEdges) {
      if (!parentsMap.has(edge.fromPersonId)) {
        // Inverse edge: key is 'son'/'daughter'. We don't know if the
        // parent is father or mother without querying their gender.
        // Use 'father' as a fallback — the createParentChildEdgePair
        // method will use this key for the new edge. If the parent is
        // actually female, the user can correct it later via the UI.
        parentsMap.set(edge.fromPersonId, {
          id: edge.fromPersonId,
          relationshipKey: 'father',
        });
      }
    }

    return Array.from(parentsMap.values());
  }

  /**
   * Create a bidirectional parent-child edge pair between [parent] and
   * [child], mirroring the pattern used in members.service.ts:138-158.
   *
   * Forward: from=child, to=parent, key=parent.relationshipKey ('father'/'mother')
   * Inverse: from=parent, to=child, key=getInverseKey(parent.relationshipKey, child.gender)
   *
   * Both edges are marked isInferred: true (system-backfilled, not user-added).
   * Idempotent — checks for existing edge before creating.
   */
  private async createParentChildEdgePair(
    tx: Prisma.TransactionClient,
    familyId: string,
    parent: { id: string; relationshipKey: string },
    child: { id: string; gender: string | null },
  ): Promise<void> {
    const forwardKey = parent.relationshipKey; // 'father' or 'mother'
    const inverseKey = getInverseKey(forwardKey, child.gender); // 'son' or 'daughter'

    // Check for existing forward edge (child → parent).
    const existingForward = await tx.relationship.findFirst({
      where: {
        familyId,
        fromPersonId: child.id,
        toPersonId: parent.id,
        relationshipKey: forwardKey,
      },
    });
    if (!existingForward) {
      await tx.relationship.create({
        data: {
          familyId,
          fromPersonId: child.id,
          toPersonId: parent.id,
          relationshipKey: forwardKey,
          direction: 'from',
          isActive: true,
          isInferred: true, // §1.2: mark as system-backfilled
        },
      });
    }

    // Check for existing inverse edge (parent → child).
    const existingInverse = await tx.relationship.findFirst({
      where: {
        familyId,
        fromPersonId: parent.id,
        toPersonId: child.id,
        relationshipKey: inverseKey,
      },
    });
    if (!existingInverse) {
      await tx.relationship.create({
        data: {
          familyId,
          fromPersonId: parent.id,
          toPersonId: child.id,
          relationshipKey: inverseKey,
          direction: 'from',
          isActive: true,
          isInferred: true,
        },
      });
    }
  }
}
