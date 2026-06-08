import { Injectable, NotFoundException, ForbiddenException, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { getInverseKey } from '../relationships/relationships.service';
import { MAX_GRAPH_NODES, DEFAULT_GRAPH_DEPTH, MAX_GRAPH_DEPTH } from '../../common/constants';
import Redis from 'ioredis';

// ── Typed payloads matching Prisma select clauses ────────────────────

type TreePerson = Prisma.PersonGetPayload<{
  select: {
    id: true; familyId: true; name: true; gender: true;
    dateOfBirth: true; isDeceased: true; birthYear: true;
    isAnchor: true; photoUrl: true; photoThumb: true;
    sideOfFamily: true; generationIndex: true;
  };
}>;

type GraphPerson = Prisma.PersonGetPayload<{
  select: {
    id: true; familyId: true; name: true; gender: true;
    dateOfBirth: true; city: true; gotra: true; isDeceased: true;
    deletedAt: true; birthYear: true; occupation: true;
    privacyLevel: true; notes: true; sideOfFamily: true;
    generationIndex: true; isAnchor: true; photoUrl: true;
    photoThumb: true; username: true;
  };
}>;

type GraphRelationship = Prisma.RelationshipGetPayload<{
  select: {
    id: true; familyId: true; fromPersonId: true;
    toPersonId: true; relationshipKey: true; direction: true;
    isActive: true; label: true;
  };
}>;

type TreeRelationship = Prisma.RelationshipGetPayload<{
  select: {
    id: true; fromPersonId: true; toPersonId: true;
    relationshipKey: true; direction: true; label: true;
  };
}>;

export interface TreeNode {
  person: {
    id: string;
    familyId: string;
    name: string;
    gender: string | null;
    dateOfBirth: Date | null;
    isDeceased: boolean;
    birthYear: number | null;
    isAnchor: boolean;
    photoUrl: string | null;
    photoThumb: string | null;
    sideOfFamily: string | null;
    generationIndex: number;
  };
  relationships: Array<{
    id: string;
    toPersonId: string;
    relationshipKey: string;
    direction: string;
    label: string | null;
  }>;
  children: TreeNode[];
}

export interface FormattedPerson {
  id: string;
  familyId: string;
  name: string;
  gender: string | null;
  dateOfBirth: Date | null;
  city: string | null;
  gotra: string | null;
  isDeceased: boolean;
  deletedAt: Date | null;
  birthYear: number | null;
  occupation: string | null;
  privacyLevel: string;
  notes: string | null;
  sideOfFamily: string | null;
  generationIndex: number;
  isAnchor: boolean;
  photoUrl: string | null;
  photoThumb: string | null;
  username: string | null;
}

export interface FormattedRelationship {
  id: string;
  familyId: string;
  fromPersonId: string;
  toPersonId: string;
  relationshipKey: string;
  direction: string;
  isActive: boolean;
  label: string | null;
}

export interface FlatGraphResult {
  persons: FormattedPerson[];
  relationships: FormattedRelationship[];
}

export interface PathResult {
  path: FormattedPerson[];
  relationships: FormattedRelationship[];
}

const PARENT_KEYS = new Set([
  'father', 'mother',
  'paternal_grandfather', 'paternal_grandmother',
  'maternal_grandfather', 'maternal_grandmother',
  'grandfather', 'grandmother',
]);

const CHILD_KEYS = new Set([
  'son', 'daughter',
  'grandson', 'granddaughter',
]);

const SPOUSE_KEYS = new Set(['husband', 'wife']);

@Injectable()
export class GraphService {
  private redis: Redis | null = null;
  private readonly logger = new Logger(GraphService.name);
  private readonly CACHE_TTL = 300; // 5 minutes (increased from 60s — BUG-17 fix)

  constructor(
    private prisma: PrismaService,
    private config: ConfigService,
  ) {
    const redisUrl = this.config.get<string>('REDIS_URL', '');
    if (redisUrl && redisUrl !== 'redis://localhost:6379') {
      this.redis = new Redis(redisUrl, {
        lazyConnect: true,
        maxRetriesPerRequest: 1,
        connectTimeout: 5000,
        retryStrategy: (times) => {
          if (times > 3) {
            this.logger.warn('Redis connection failed after 3 retries — graph caching disabled');
            this.redis = null;
            return null; // Stop retrying
          }
          return Math.min(times * 200, 1000);
        },
      });

      this.redis.on('error', (err) => {
        // Suppress ECONNREFUSED spam — log once, then stop retrying
        if (err.message?.includes('ECONNREFUSED') || err.message?.includes('AggregateError')) {
          this.logger.verbose(`Redis unavailable for graph caching: ${err.message}`);
          if (this.redis) {
            this.redis.disconnect();
            this.redis = null;
          }
        }
      });

      this.redis.connect().catch(() => {
        this.logger.verbose('Redis connection failed — graph caching disabled');
        this.redis = null;
      });
    } else {
      this.logger.verbose('REDIS_URL not configured — graph caching disabled');
    }
  }

  /** Returns the family graph in flat, tree, or path format based on options. */
  async getGraph(
    userId: string,
    familyId: string,
    options: {
      root?: string;
      depth?: number;
      format?: 'flat' | 'tree';
      from?: string;
      to?: string;
      locale?: string;
    } = {},
  ) {
    // Check if the user is a member of the family
    const membership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId } },
    });

    if (membership) {
      // Full access for members
      if (options.from && options.to) {
        return this.getPath(familyId, options.from, options.to);
      }

      const safeDepth = Math.min(options.depth ?? DEFAULT_GRAPH_DEPTH, MAX_GRAPH_DEPTH);

      if (options.root && options.format === 'tree') {
        return this.getTree(familyId, options.root, safeDepth);
      }

      if (options.format === 'tree') {
        const family = await this.prisma.family.findUnique({
          where: { id: familyId },
        });
        const rootId = family?.anchorPersonId;
        if (rootId) {
          return this.getTree(familyId, rootId, safeDepth);
        }
        return this.getFlatGraph(familyId);
      }

      return this.getFlatGraph(familyId);
    }

    // Non-member access: check family privacy
    const family = await this.prisma.family.findUnique({
      where: { id: familyId },
      select: { isPublic: true, deletedAt: true },
    });

    if (!family || family.deletedAt) {
      throw new NotFoundException('Family not found');
    }

    if (!family.isPublic) {
      throw new ForbiddenException({ error: 'FAMILY_PRIVATE' });
    }

    // Public family: return tree nodes only (strip contact details)
    if (options.from && options.to) {
      throw new ForbiddenException('Path finding is only available to family members');
    }

    const safeDepth = Math.min(options.depth ?? DEFAULT_GRAPH_DEPTH, MAX_GRAPH_DEPTH);

    if (options.root && options.format === 'tree') {
      const result = await this.getTree(familyId, options.root, safeDepth);
      return this.stripContactDetails(result);
    }

    if (options.format === 'tree') {
      const fam = await this.prisma.family.findUnique({
        where: { id: familyId },
      });
      const rootId = fam?.anchorPersonId;
      if (rootId) {
        const result = await this.getTree(familyId, rootId, safeDepth);
        return this.stripContactDetails(result);
      }
      const result = await this.getFlatGraph(familyId);
      return this.stripContactDetailsFromFlat(result);
    }

    const result = await this.getFlatGraph(familyId);
    return this.stripContactDetailsFromFlat(result);
  }

  /** Resolves the root person ID for tree rendering, falling back to anchor or oldest person. */
  async resolveRootPersonId(userId: string, familyId: string, root?: string): Promise<string> {
    if (root) {
      return root;
    }

    const family = await this.prisma.family.findUnique({
      where: { id: familyId },
      select: { anchorPersonId: true },
    });

    if (family?.anchorPersonId) {
      return family.anchorPersonId;
    }

    const persons = await this.prisma.person.findMany({
      where: { familyId, deletedAt: null },
      orderBy: [{ generationIndex: 'asc' }, { createdAt: 'asc' }],
      take: 1,
    });

    if (persons.length > 0) {
      return persons[0].id;
    }

    throw new NotFoundException('No persons found in this family to use as tree root');
  }

  /** Builds a hierarchical tree rooted at the given person up to the specified depth. */
  async getTree(familyId: string, rootPersonId: string, depth: number = DEFAULT_GRAPH_DEPTH): Promise<{ root: TreeNode | null; totalNodes: number }> {
    // Select only fields used by TreeNode — skips large photo fields (photoCard, photoFull),
    // notes, occupation, city, gotra, privacyLevel, etc. reducing DB row size
    const persons = await this.prisma.person.findMany({
      where: { familyId, deletedAt: null },
      select: {
        id: true,
        familyId: true,
        name: true,
        gender: true,
        dateOfBirth: true,
        isDeceased: true,
        birthYear: true,
        isAnchor: true,
        photoUrl: true,
        photoThumb: true,
        sideOfFamily: true,
        generationIndex: true,
      },
    });

    // Select only fields used by tree building and relationship output
    const relationships = await this.prisma.relationship.findMany({
      where: { familyId, isActive: true },
      select: {
        id: true,
        fromPersonId: true,
        toPersonId: true,
        relationshipKey: true,
        direction: true,
        label: true,
      },
    });

    const personMap = new Map<string, TreePerson>(
      persons.map((p) => [p.id, p]),
    );

    if (!personMap.has(rootPersonId)) {
      throw new NotFoundException('Root person not found');
    }

    const parentToChildren = new Map<string, Array<{ childId: string; key: string }>>();
    const spouseMap = new Map<string, string>();

    for (const rel of relationships) {
      if (!personMap.has(rel.fromPersonId) || !personMap.has(rel.toPersonId)) continue;

      if (PARENT_KEYS.has(rel.relationshipKey)) {
        if (!parentToChildren.has(rel.fromPersonId)) {
          parentToChildren.set(rel.fromPersonId, []);
        }
        parentToChildren.get(rel.fromPersonId)!.push({ childId: rel.toPersonId, key: rel.relationshipKey });
      } else if (CHILD_KEYS.has(rel.relationshipKey)) {
        if (!parentToChildren.has(rel.toPersonId)) {
          parentToChildren.set(rel.toPersonId, []);
        }
        parentToChildren.get(rel.toPersonId)!.push({ childId: rel.fromPersonId, key: getInverseKey(rel.relationshipKey) });
      } else if (SPOUSE_KEYS.has(rel.relationshipKey)) {
        spouseMap.set(rel.fromPersonId, rel.toPersonId);
      }
    }

    const personRelationships = new Map<string, Array<{
      id: string;
      toPersonId: string;
      relationshipKey: string;
      direction: string;
      label: string | null;
    }>>();

    for (const rel of relationships) {
      if (!personMap.has(rel.fromPersonId) || !personMap.has(rel.toPersonId)) continue;

      if (!personRelationships.has(rel.fromPersonId)) {
        personRelationships.set(rel.fromPersonId, []);
      }
      personRelationships.get(rel.fromPersonId)!.push({
        id: rel.id,
        toPersonId: rel.toPersonId,
        relationshipKey: rel.relationshipKey,
        direction: rel.direction,
        label: rel.label,
      });
    }

    const visited = new Set<string>();

    const buildNode = (personId: string, currentDepth: number): TreeNode | null => {
      if (visited.size >= MAX_GRAPH_NODES || visited.has(personId) || currentDepth > depth) return null;
      visited.add(personId);

      const person = personMap.get(personId);
      if (!person) return null;

      const spouseId = spouseMap.get(personId);
      const directChildren = parentToChildren.get(personId) || [];
      const spouseChildren = spouseId ? (parentToChildren.get(spouseId) || []) : [];
      const allChildIds = new Set<string>();

      for (const c of directChildren) allChildIds.add(c.childId);
      for (const c of spouseChildren) allChildIds.add(c.childId);

      const children: TreeNode[] = [];
      for (const childId of allChildIds) {
        const childNode = buildNode(childId, currentDepth + 1);
        if (childNode) children.push(childNode);
      }

      return {
        person: {
          id: person.id,
          familyId: person.familyId,
          name: person.name,
          gender: person.gender,
          dateOfBirth: person.dateOfBirth,
          isDeceased: person.isDeceased,
          birthYear: person.birthYear,
          isAnchor: person.isAnchor,
          photoUrl: person.photoThumb ?? person.photoUrl ?? null,
          photoThumb: person.photoThumb,
          sideOfFamily: person.sideOfFamily,
          generationIndex: person.generationIndex,
        },
        relationships: personRelationships.get(personId) || [],
        children,
      };
    };

    const root = buildNode(rootPersonId, 0);

    return { root, totalNodes: visited.size };
  }

  /** Finds the shortest relationship path between two persons using BFS. */
  async getPath(familyId: string, fromPersonId: string, toPersonId: string): Promise<PathResult> {
    // Select only fields used by formatPerson and path building
    const persons = await this.prisma.person.findMany({
      where: { familyId, deletedAt: null },
      select: {
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
        photoThumb: true,
        username: true,
      },
    });

    // Select only fields used by path building and relationship output
    const relationships = await this.prisma.relationship.findMany({
      where: { familyId, isActive: true },
      select: {
        id: true,
        familyId: true,
        fromPersonId: true,
        toPersonId: true,
        relationshipKey: true,
        direction: true,
        isActive: true,
        label: true,
      },
    });

    const personMap = new Map<string, GraphPerson>(
      persons.map((p) => [p.id, p]),
    );

    const fromPerson = personMap.get(fromPersonId);
    const toPerson = personMap.get(toPersonId);

    if (!fromPerson) {
      throw new NotFoundException('Source person not found');
    }
    if (!toPerson) {
      throw new NotFoundException('Target person not found');
    }

    if (fromPersonId === toPersonId) {
      return {
        path: [this.formatPerson(fromPerson)],
        relationships: [],
      };
    }

    const adjacency = new Map<string, Array<{ neighborId: string; relationship: GraphRelationship }>>();

    for (const rel of relationships) {
      if (!personMap.has(rel.fromPersonId) || !personMap.has(rel.toPersonId)) continue;

      // Forward direction: fromPerson → toPerson
      if (!adjacency.has(rel.fromPersonId)) {
        adjacency.set(rel.fromPersonId, []);
      }
      adjacency.get(rel.fromPersonId)!.push({
        neighborId: rel.toPersonId,
        relationship: rel,
      });

      // Reverse direction: toPerson → fromPerson
      if (!adjacency.has(rel.toPersonId)) {
        adjacency.set(rel.toPersonId, []);
      }
      adjacency.get(rel.toPersonId)!.push({
        neighborId: rel.fromPersonId,
        relationship: rel,
      });
    }

    const visited = new Set<string>();
    const parentMap = new Map<string, string>();          // child → parent
    const relMap = new Map<string, GraphRelationship>(); // child → relationship to parent
    const queue: string[] = [fromPersonId];
    let head = 0;

    visited.add(fromPersonId);

    let found = false;

    while (head < queue.length) {
      const currentId = queue[head++];

      if (currentId === toPersonId) {
        found = true;
        break;
      }

      const neighbors = adjacency.get(currentId) || [];
      for (const neighbor of neighbors) {
        if (!visited.has(neighbor.neighborId)) {
          visited.add(neighbor.neighborId);
          parentMap.set(neighbor.neighborId, currentId);
          relMap.set(neighbor.neighborId, neighbor.relationship);
          queue.push(neighbor.neighborId);
        }
      }
    }

    if (!found) {
      return { path: [], relationships: [] };
    }

    // Reconstruct path from destination back to source using parent pointers
    const pathPersonIds: string[] = [];
    const pathRelationships: GraphRelationship[] = [];
    let cur: string | undefined = toPersonId;
    while (cur !== undefined) {
      pathPersonIds.push(cur);
      const rel = relMap.get(cur);
      if (rel) pathRelationships.push(rel);
      cur = parentMap.get(cur);
    }
    pathPersonIds.reverse();
    pathRelationships.reverse();

    const pathPersons = pathPersonIds
      .map((id) => personMap.get(id))
      .filter(Boolean)
      .map((p) => this.formatPerson(p!));

    const pathRels = pathRelationships.map((r) => ({
      id: r.id,
      familyId: r.familyId,
      fromPersonId: r.fromPersonId,
      toPersonId: r.toPersonId,
      relationshipKey: r.relationshipKey,
      direction: r.direction,
      isActive: r.isActive,
      label: r.label,
    }));

    return { path: pathPersons, relationships: pathRels };
  }

  /** Returns the relationship path between two persons after verifying family membership. */
  async getPathWithAuth(userId: string, familyId: string, fromPersonId: string, toPersonId: string) {
    await this.requireFamilyMember(userId, familyId);
    return this.getPath(familyId, fromPersonId, toPersonId);
  }

  /** Returns all persons and relationships for a family as flat lists, with Redis caching. */
  async getFlatGraph(familyId: string): Promise<FlatGraphResult> {
    // ── Check Redis cache first ──────────────────────────────────────
    const cacheKey = `graph:flat:${familyId}`;
    try {
      if (this.redis) {
        const cached = await this.redis.get(cacheKey);
        if (cached) {
          return JSON.parse(cached);
        }
      }
    } catch (err) {
      this.logger.warn(`Redis cache read failed for ${cacheKey}`, err);
    }

    // Select only fields used by formatPerson — skips large photo fields (photoCard, photoFull)
    const [persons, relationships] = await Promise.all([
      this.prisma.person.findMany({
        where: { familyId, deletedAt: null },
        orderBy: { name: 'asc' },
        select: {
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
          photoThumb: true,
          username: true,
        },
      }),
      this.prisma.relationship.findMany({
        where: { familyId, isActive: true },
        orderBy: { createdAt: 'desc' },
        select: {
          id: true,
          familyId: true,
          fromPersonId: true,
          toPersonId: true,
          relationshipKey: true,
          direction: true,
          isActive: true,
          label: true,
        },
      }),
    ]);

    const activePersonIds = new Set(persons.map((p) => p.id));
    const validRelationships = relationships.filter(
      (r) => activePersonIds.has(r.fromPersonId) && activePersonIds.has(r.toPersonId),
    );

    const result = {
      persons: persons.map((p) => this.formatPerson(p)),
      relationships: validRelationships.map((r) => ({
        id: r.id,
        familyId: r.familyId,
        fromPersonId: r.fromPersonId,
        toPersonId: r.toPersonId,
        relationshipKey: r.relationshipKey,
        direction: r.direction,
        isActive: r.isActive,
        label: r.label,
      })),
    };

    // ── Store in Redis cache ─────────────────────────────────────────
    try {
      if (this.redis) {
        await this.redis.setex(cacheKey, this.CACHE_TTL, JSON.stringify(result));
      }
    } catch (err) {
      this.logger.warn(`Redis cache write failed for ${cacheKey}`, err);
    }

    return result;
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

  /**
   * Strips contact details (phone, email, address) from Person nodes
   * for non-member access to public families.
   * Used for flat graph results.
   */
  private stripContactDetailsFromFlat(result: FlatGraphResult): FlatGraphResult {
    return {
      persons: result.persons.map((person) => ({
        ...person,
        // Strip contact-sensitive fields — Person model has phone, email, address
        // but our FormattedPerson doesn't include them directly.
        // However, we should strip notes and occupation which may contain personal info.
        notes: null,
        occupation: null,
      })),
      relationships: result.relationships,
    };
  }

  /**
   * Strips contact details from tree nodes for non-member access to public families.
   */
  private stripContactDetails(result: { root: TreeNode | null; totalNodes: number }): {
    root: TreeNode | null;
    totalNodes: number;
  } {
    if (!result.root) return result;

    const stripNode = (node: TreeNode): TreeNode => ({
      ...node,
      person: {
        ...node.person,
        // Tree nodes already don't include notes/occupation, but ensure consistency
      },
      children: node.children.map(stripNode),
    });

    return {
      root: stripNode(result.root),
      totalNodes: result.totalNodes,
    };
  }

  private formatPerson(person: GraphPerson | TreePerson): FormattedPerson {
    return {
      id: person.id,
      familyId: person.familyId,
      name: person.name,
      gender: person.gender ?? null,
      dateOfBirth: person.dateOfBirth ?? null,
      city: 'city' in person ? (person as GraphPerson).city ?? null : null,
      gotra: 'gotra' in person ? (person as GraphPerson).gotra ?? null : null,
      isDeceased: person.isDeceased ?? false,
      deletedAt: 'deletedAt' in person ? (person as GraphPerson).deletedAt ?? null : null,
      birthYear: person.birthYear ?? null,
      occupation: 'occupation' in person ? (person as GraphPerson).occupation ?? null : null,
      privacyLevel: 'privacyLevel' in person ? (person as GraphPerson).privacyLevel ?? 'family' : 'family',
      notes: 'notes' in person ? (person as GraphPerson).notes ?? null : null,
      sideOfFamily: person.sideOfFamily ?? null,
      generationIndex: person.generationIndex ?? 0,
      isAnchor: person.isAnchor ?? false,
      // Graph endpoints return thumb URL for performance
      photoUrl: person.photoThumb ?? person.photoUrl ?? null,
      photoThumb: person.photoThumb ?? null,
      username: 'username' in person ? (person as GraphPerson).username ?? null : null,
    };
  }
}
