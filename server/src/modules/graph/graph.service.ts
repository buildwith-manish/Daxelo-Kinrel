import { Injectable, NotFoundException, ForbiddenException, Logger, Inject, forwardRef } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../../prisma/prisma.service';
import { getInverseKey } from '../relationships/relationships.service';
import { KinshipService } from '../kinship/kinship.service';
import { GraphEngineService, ComputedRelationship } from './graph-engine.service';
import { MAX_GRAPH_NODES, DEFAULT_GRAPH_DEPTH, MAX_GRAPH_DEPTH, DEFAULT_TREE_DEPTH } from '../../common/constants';
import Redis from 'ioredis';

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

export interface FlatGraphResult {
  persons: Array<Record<string, any>>;
  relationships: Array<Record<string, any>>;
}

export interface EnrichedGraphResult {
  persons: Array<{
    id: string;
    familyId: string;
    name: string;
    gender: string | null;
    generationIndex: number;
    isAnchor: boolean;
    isDeceased: boolean;
    photoUrl: string | null;
    username: string | null;
    computedKinship: string | null;
    kinshipCategory: string | null;
    isSelf: boolean;
  }>;
  relationships: Array<{
    id: string;
    familyId: string;
    fromPersonId: string;
    toPersonId: string;
    relationshipKey: string;
    direction: string;
    isActive: boolean;
    label: string | null;
    displayLabel: string;
  }>;
  selfPersonId: string | null;
}

export interface PathResult {
  path: Array<Record<string, any>>;
  relationships: Array<Record<string, any>>;
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
  private readonly CACHE_TTL = 1800; // BUG-015 FIX: 30 minutes (was 5) — large families take 2-5s to rebuild

  constructor(
    private prisma: PrismaService,
    private config: ConfigService,
    @Inject(forwardRef(() => KinshipService))
    private kinshipService: KinshipService,
    @Inject(forwardRef(() => GraphEngineService))
    private graphEngine: GraphEngineService,
  ) {
    const redisUrl = this.config.get<string>('REDIS_URL', '');
    if (redisUrl && redisUrl !== 'redis://localhost:6379') {
      // BUG-006 FIX: Use a strict 2-second startup connect timeout so a
      // missing Redis can never block NestJS module initialization for 30+
      // seconds. The previous connectTimeout: 5000 + retryStrategy(times > 3)
      // combo could stall the app for ~20s on DNS resolution failures.
      // BUG-044 FIX: retryStrategy no longer permanently disables caching
      // after 3 retries — it stops immediate retries but schedules a
      // background reconnect every 60s so a temporary Redis outage doesn't
      // permanently disable the cache for the lifetime of the process.
      this.redis = new Redis(redisUrl, {
        lazyConnect: true,
        maxRetriesPerRequest: 1,
        connectTimeout: 2000,
        enableReadyCheck: false,
        retryStrategy: (times) => {
          if (times > 2) {
            this.logger.warn(
              'Redis connection failed after 2 retries during startup. ' +
              'Graph caching disabled. Background reconnect scheduled in 60s.',
            );
            // Schedule a single background reconnect attempt — do NOT return
            // a number, which would keep the ioredis internal retry loop
            // running and stall the constructor.
            setTimeout(() => this.attemptRedisReconnect(redisUrl), 60_000);
            return null;
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

      // BUG-006 FIX: Race connect() against a 2s timeout so the constructor
      // can never block NestJS bootstrap for more than 2s, even on slow DNS.
      Promise.race([
        this.redis.connect(),
        new Promise<void>((_, reject) =>
          setTimeout(() => reject(new Error('Redis startup connect timeout')), 2000),
        ),
      ])
        .then(() => {
          this.logger.log('Redis connected successfully for graph caching');
        })
        .catch(() => {
          this.logger.verbose(
            'Redis connection failed during startup. ' +
            'Graph caching disabled, will retry in background.',
          );
          // Mark as null so getFlatGraph/invalidate skip the redis code path;
          // the retryStrategy will schedule a background reconnect.
          if (this.redis) {
            try { this.redis.disconnect(); } catch { /* ignore */ }
            this.redis = null;
          }
        });
    } else {
      this.logger.verbose('REDIS_URL not configured — graph caching disabled');
    }
  }

  /**
   * BUG-044 FIX: Background Redis reconnection.
   *
   * Called by retryStrategy after immediate retries are exhausted. Tries a
   * fresh connection with a 2s timeout; on success, swaps it into `this.redis`
   * so caching resumes. On failure, schedules another attempt in 120s.
   */
  private attemptRedisReconnect(redisUrl: string): void {
    if (this.redis !== null) {
      return; // Already reconnected
    }

    this.logger.verbose('Attempting background Redis reconnection...');

    const tempRedis = new Redis(redisUrl, {
      lazyConnect: true,
      maxRetriesPerRequest: 1,
      connectTimeout: 2000,
      enableReadyCheck: false,
      retryStrategy: () => null, // No internal retries for background attempt
    });

    Promise.race([
      tempRedis.connect(),
      new Promise<void>((_, reject) =>
        setTimeout(() => reject(new Error('Background reconnect timeout')), 2000),
      ),
    ])
      .then(() => {
        this.redis = tempRedis;
        this.logger.log('Redis reconnected successfully in background');
      })
      .catch(() => {
        try { tempRedis.disconnect(); } catch { /* ignore */ }
        this.logger.verbose('Background Redis reconnection failed, will retry in 120s');
        setTimeout(() => this.attemptRedisReconnect(redisUrl), 120_000);
      });
  }

  // ════════════════════════════════════════════════════════════════════
  // ENRICHED GRAPH: Computed kinship terms for graph rendering
  // ════════════════════════════════════════════════════════════════════

  /**
   * Returns the family graph enriched with computed kinship terms.
   *
   * Each person gets a `computedKinship` field showing their relationship
   * to the self/anchor person (e.g., "Uncle", "Cousin", "Grandmother").
   *
   * Each relationship gets a `displayLabel` field with proper English term.
   */
  async getEnrichedGraph(
    userId: string,
    familyId: string,
    selfPersonId?: string,
  ): Promise<EnrichedGraphResult> {
    // Verify access
    await this.requireFamilyMember(userId, familyId);

    // Get base graph data
    const { persons, relationships } = await this.getFlatGraph(familyId);

    // Determine the "self" person (whose perspective we show relationships from).
    // Cascade: explicit selfPersonId → user's anchor → family's anchorPersonId →
    // oldest person by (generationIndex, birthYear) → first person in the list.
    //
    // BUG-001 FIX: Previously, if no self/anchor could be resolved, the endpoint
    // returned the persons array with `computedKinship: null` for every row.
    // The Flutter frontend treated null kinship as "no data" and rendered a
    // blank graph even though the family had members. We now ALWAYS pick a
    // fallback self person (the oldest by generation/birthYear) so kinship can
    // be computed from someone's perspective. If the family is genuinely empty,
    // we return empty arrays rather than a populated-but-null structure.
    let resolvedSelfId: string | undefined =
      selfPersonId
      ?? (await this.findSelfPersonId(userId, familyId))
      ?? (await this.findAnchorPersonId(familyId))
      ?? undefined;

    if (!resolvedSelfId && persons.length > 0) {
      // Pick the oldest person: lowest generationIndex (oldest generation),
      // then earliest birthYear, then earliest createdAt as final tiebreaker.
      const oldest = persons.reduce((best, current) => {
        if (!best) return current;
        const bestGen = best.generationIndex ?? 999;
        const curGen = current.generationIndex ?? 999;
        if (curGen !== bestGen) return curGen < bestGen ? current : best;
        const bestYear = best.birthYear ?? 9999;
        const curYear = current.birthYear ?? 9999;
        if (curYear !== bestYear) return curYear < bestYear ? current : best;
        return best;
      }, persons[0]);
      resolvedSelfId = oldest.id;
      this.logger.warn(
        `No self/anchor person found for family ${familyId}, ` +
        `using oldest person "${oldest.name}" (${oldest.id}) as fallback self`,
      );
    }

    if (!resolvedSelfId) {
      // Empty family — return empty graph rather than null-kinship rows.
      this.logger.warn(`Family ${familyId} has no persons, returning empty graph`);
      return {
        persons: [],
        relationships: [],
        selfPersonId: null,
      };
    }

    // Use GraphEngineService to compute ALL kinship relationships from self's perspective
    let computedRelationships: ComputedRelationship[] = [];
    try {
      computedRelationships = await this.graphEngine.getAllRelationships(
        familyId,
        resolvedSelfId,
        6, // max depth
      );
    } catch (error) {
      this.logger.warn(`Failed to compute relationships: ${error}`);
    }

    // Build lookup: personId → computed kinship
    const kinshipMap = new Map<string, ComputedRelationship>();
    for (const cr of computedRelationships) {
      kinshipMap.set(cr.personId, cr);
    }

    // Enrich persons with computed kinship labels (ENGLISH ONLY)
    const enrichedPersons = persons.map((person) => {
      if (person.id === resolvedSelfId) {
        return {
          ...person,
          computedKinship: 'You',
          kinshipCategory: 'self',
          isSelf: true,
        };
      }

      const computed = kinshipMap.get(person.id);
      if (computed) {
        return {
          ...person,
          computedKinship: this.formatKinshipTerm(computed.computedTerm),
          kinshipCategory: this.categorizeKinship(computed.computedTerm),
          isSelf: false,
        };
      }

      return {
        ...person,
        computedKinship: null,
        kinshipCategory: 'extended',
        isSelf: false,
      };
    }) as EnrichedGraphResult['persons'];

    // Enrich relationships with display labels (ENGLISH ONLY)
    const enrichedRelationships = relationships.map((rel) => {
      // Try to get proper English term from KinshipService
      const kinshipTerm = this.kinshipService.getByKey(rel.relationshipKey);
      const displayLabel = kinshipTerm?.englishTerm
        ?? this.formatKey(rel.relationshipKey);

      return {
        ...rel,
        displayLabel,
      };
    }) as EnrichedGraphResult['relationships'];

    return {
      persons: enrichedPersons,
      relationships: enrichedRelationships,
      selfPersonId: resolvedSelfId,
    };
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
    const membership = await this.requireFamilyMember(userId, familyId);
    const isReadOnly = membership === null; // Non-member viewing a public family

    if (options.from && options.to) {
      return this.getPath(familyId, options.from, options.to);
    }

    const safeDepth = Math.min(options.depth ?? DEFAULT_GRAPH_DEPTH, MAX_GRAPH_DEPTH);

    let result: any;

    if (options.root && options.format === 'tree') {
      result = await this.getTree(familyId, options.root, safeDepth);
    } else if (options.format === 'tree') {
      const family = await this.prisma.family.findUnique({
        where: { id: familyId },
      });
      const rootId = family?.anchorPersonId;
      if (rootId) {
        result = await this.getTree(familyId, rootId, safeDepth);
      } else {
        result = await this.getFlatGraph(familyId);
      }
    } else {
      result = await this.getFlatGraph(familyId);
    }

    // Strip contact details for non-members (read-only access)
    if (isReadOnly) {
      result = this.stripContactDetails(result);
      if (typeof result === 'object' && !Array.isArray(result)) {
        result.readOnly = true;
        result.readOnlyBanner = 'You are viewing this family tree in read-only mode. Contact details are hidden.';
      }
    }

    return result;
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

    // BUG-008 FIX: Order by birthYear ASC first (oldest by birth is the most
    // reliable signal of "root" generation), then generationIndex ASC, then
    // createdAt ASC as a deterministic tiebreaker. Previously we ordered by
    // generationIndex alone, which is manually set and frequently wrong on
    // imported or backfilled data, causing the tree to render upside-down.
    const persons = await this.prisma.person.findMany({
      where: { familyId, deletedAt: null },
      orderBy: [
        { birthYear: 'asc' },
        { generationIndex: 'asc' },
        { createdAt: 'asc' },
      ],
      take: 1,
    });

    if (persons.length > 0) {
      return persons[0].id;
    }

    throw new NotFoundException('No persons found in this family to use as tree root');
  }

  /** Builds a hierarchical tree rooted at the given person up to the specified depth. */
  async getTree(familyId: string, rootPersonId: string, depth: number = DEFAULT_TREE_DEPTH): Promise<{ root: TreeNode | null; totalNodes: number; isTruncated: boolean }> {
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

    const personMap = new Map(persons.map((p) => [p.id, p as any]));

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
        parentToChildren.get(rel.toPersonId)!.push({ childId: rel.fromPersonId, key: getInverseKey(rel.relationshipKey, personMap.get(rel.fromPersonId)?.gender ?? null) });
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

      const person: any = personMap.get(personId);
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

    return { root, totalNodes: visited.size, isTruncated: visited.size >= MAX_GRAPH_NODES };
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

    const personMap = new Map(persons.map((p) => [p.id, p as any]));

    const fromPerson: any = personMap.get(fromPersonId);
    const toPerson: any = personMap.get(toPersonId);

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

    const adjacency = new Map<string, Array<{ neighborId: string; relationship: Record<string, any> }>>();

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

      // Reverse direction: toPerson → fromPerson (flip relationship key for correct inverse)
      if (!adjacency.has(rel.toPersonId)) {
        adjacency.set(rel.toPersonId, []);
      }
      const toPersonForInverse = personMap.get(rel.toPersonId);
      adjacency.get(rel.toPersonId)!.push({
        neighborId: rel.fromPersonId,
        relationship: {
          ...rel,
          fromPersonId: rel.toPersonId,
          toPersonId: rel.fromPersonId,
          relationshipKey: getInverseKey(rel.relationshipKey, toPersonForInverse?.gender ?? null),
        },
      });
    }

    const visited = new Set<string>();
    const queue: Array<{
      personId: string;
      pathPersonIds: string[];
      pathRelationships: Record<string, any>[];
    }> = [{
      personId: fromPersonId,
      pathPersonIds: [fromPersonId],
      pathRelationships: [],
    }];

    visited.add(fromPersonId);

    let foundPath: { pathPersonIds: string[]; pathRelationships: Record<string, any>[] } | null = null;

    while (queue.length > 0) {
      const current = queue.shift()!;

      if (current.personId === toPersonId) {
        foundPath = current;
        break;
      }

      const neighbors = adjacency.get(current.personId) || [];
      for (const neighbor of neighbors) {
        if (!visited.has(neighbor.neighborId)) {
          visited.add(neighbor.neighborId);
          queue.push({
            personId: neighbor.neighborId,
            pathPersonIds: [...current.pathPersonIds, neighbor.neighborId],
            pathRelationships: [...current.pathRelationships, neighbor.relationship],
          });
        }
      }
    }

    if (!foundPath) {
      return { path: [], relationships: [] };
    }

    const pathPersons = foundPath.pathPersonIds
      .map((id) => personMap.get(id))
      .filter(Boolean)
      .map((p) => this.formatPerson(p!));

    const pathRelationships = foundPath.pathRelationships.map((r) => ({
      id: r.id,
      familyId: r.familyId,
      fromPersonId: r.fromPersonId,
      toPersonId: r.toPersonId,
      relationshipKey: r.relationshipKey,
      direction: r.direction,
      isActive: r.isActive,
      label: r.label,
    }));

    return { path: pathPersons, relationships: pathRelationships };
  }

  /** Invalidate both the Redis flat-graph cache and the GraphEngine in-memory cache for a family. */
  async invalidateFlatGraphCache(familyId: string): Promise<void> {
    const cacheKey = `graph:flat:${familyId}`;

    // BUG-002 FIX: Invalidate the in-memory GraphEngine cache FIRST, then
    // attempt Redis. If Redis is unreachable, the in-memory cache is already
    // fresh, so the next request will rebuild the graph from the DB and
    // re-populate Redis. Previously, Redis was invalidated first — a Redis
    // failure left both caches stale because the (now-stale) in-memory
    // GraphEngine cache would still serve the request without rebuilding.
    this.graphEngine.invalidateCache(familyId);
    this.logger.debug(`Invalidated in-memory graph cache for family ${familyId}`);

    if (this.redis) {
      try {
        // Race the DEL against a 2s timeout so a slow Redis can't block the
        // caller (e.g. a relationship-creation transaction) indefinitely.
        await Promise.race([
          this.redis.del(cacheKey),
          new Promise<void>((_, reject) =>
            setTimeout(() => reject(new Error('Redis DEL timeout')), 2000),
          ),
        ]);
        this.logger.debug(`Invalidated Redis cache for ${cacheKey}`);
      } catch (err: any) {
        // In-memory cache is already invalidated, so the next read will
        // rebuild from DB and re-populate Redis. Log and move on.
        this.logger.warn(
          `Redis cache invalidation failed for ${cacheKey}: ${err?.message ?? err}. ` +
          `In-memory cache invalidated successfully; new data will be computed on next request.`,
        );
      }
    }
  }

  /** Returns the relationship path between two persons after verifying family membership. */
  async getPathWithAuth(userId: string, familyId: string, fromPersonId: string, toPersonId: string) {
    const membership = await this.requireFamilyMember(userId, familyId);
    const result = await this.getPath(familyId, fromPersonId, toPersonId);

    // Strip contact details for non-members (read-only access)
    if (membership === null) {
      result.path = result.path.map((p: any) => {
        const stripped = { ...p };
        const contactFields = ['email', 'phone', 'address', 'bloodGroup', 'anniversaryDate'];
        for (const field of contactFields) {
          if (field in stripped) stripped[field] = null;
        }
        return stripped;
      });
      (result as any).readOnly = true;
    }

    return result;
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
        displayLabel: this.resolveRelationshipLabel(r.relationshipKey),
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

  /** Compute layout positions for graph nodes based on the specified algorithm. */
  async computeLayout(
    userId: string,
    familyId: string,
    algorithm: string,
    viewportWidth: number = 1400,
    viewportHeight: number = 920,
  ): Promise<Record<string, { x: number; y: number }>> {
    await this.requireFamilyMember(userId, familyId);
    const { persons } = await this.getFlatGraph(familyId);

    // Clamp viewport to sensible bounds — the Flutter frontend sends actual
    // device pixel dimensions, which can range from 360 (small phone) to
    // 4096 (4K monitor). Hard-coded 1400×920 made the graph unusable on
    // anything smaller than a desktop (BUG-012).
    const w = Math.max(320, Math.min(4096, viewportWidth));
    const h = Math.max(240, Math.min(4096, viewportHeight));

    switch (algorithm) {
      case 'hierarchical':
        return this.hierarchicalLayout(persons, w, h);
      case 'radial':
        return this.radialLayout(persons, w, h);
      case 'force':
        return this.forceDirectedLayout(persons, w, h);
      default:
        return this.hierarchicalLayout(persons, w, h);
    }
  }

  /** Get detailed member info for the info card popup. */
  async getMemberDetails(userId: string, familyId: string, memberId: string) {
    await this.requireFamilyMember(userId, familyId);
    const person = await this.prisma.person.findFirst({
      where: { id: memberId, familyId, deletedAt: null },
      select: {
        id: true,
        familyId: true,
        name: true,
        gender: true,
        dateOfBirth: true,
        city: true,
        gotra: true,
        isDeceased: true,
        birthYear: true,
        occupation: true,
        privacyLevel: true,
        sideOfFamily: true,
        generationIndex: true,
        isAnchor: true,
        photoUrl: true,
        photoThumb: true,
        username: true,
      },
    });

    if (!person) {
      throw new NotFoundException('Person not found');
    }

    // Also fetch their relationships in this family
    const relationships = await this.prisma.relationship.findMany({
      where: {
        familyId,
        isActive: true,
        OR: [
          { fromPersonId: memberId },
          { toPersonId: memberId },
        ],
      },
      select: {
        id: true,
        fromPersonId: true,
        toPersonId: true,
        relationshipKey: true,
        direction: true,
        label: true,
      },
    });

    return {
      ...this.formatPerson(person),
      relationships,
      relationshipCount: relationships.length,
    };
  }

  /** Get all members belonging to a specific generation within a family. */
  async getMembersByGeneration(userId: string, familyId: string, generation: number) {
    await this.requireFamilyMember(userId, familyId);
    const persons = await this.prisma.person.findMany({
      where: {
        familyId,
        deletedAt: null,
        generationIndex: generation,
      },
      orderBy: { name: 'asc' },
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
        username: true,
      },
    });

    // Get relationships between these generation members
    const personIds = persons.map(p => p.id);

    const relationships = await this.prisma.relationship.findMany({
      where: {
        familyId,
        isActive: true,
        fromPersonId: { in: personIds },
        toPersonId: { in: personIds },
      },
      select: {
        id: true,
        fromPersonId: true,
        toPersonId: true,
        relationshipKey: true,
        direction: true,
        label: true,
      },
    });

    return {
      generation,
      members: persons.map(p => this.formatPerson(p)),
      relationships,
      totalMembers: persons.length,
    };
  }

  /**
   * BUG-012 / BUG-028 FIX: Hierarchical layout now accepts viewport dimensions
   * and enforces a minimum per-node spacing of 100px. If a generation has more
   * nodes than the viewport can fit at min spacing, the effective canvas width
   * is expanded so nodes never overlap (the Flutter frontend pans/zooms).
   */
  private hierarchicalLayout(
    persons: Array<Record<string, any>>,
    canvasWidth: number = 1400,
    canvasHeight: number = 920,
  ): Record<string, { x: number; y: number }> {
    const positions: Record<string, { x: number; y: number }> = {};
    const MIN_SPACING = 100;

    // Group by generation
    const genGroups = new Map<number, Array<Record<string, any>>>();
    for (const person of persons) {
      const gen = person.generationIndex ?? 0;
      const group = genGroups.get(gen) || [];
      group.push(person);
      genGroups.set(gen, group);
    }

    const maxGen = Math.max(...[...genGroups.keys()], 3);
    const genSpacing = canvasHeight / (maxGen + 2);

    for (const [gen, group] of genGroups) {
      const y = genSpacing * (gen + 1);
      const calculated = canvasWidth / (group.length + 1);
      const spacing = Math.max(MIN_SPACING, calculated);

      group.forEach((person, idx) => {
        positions[person.id] = {
          x: spacing * (idx + 1),
          y,
        };
      });
    }

    return positions;
  }

  /** BUG-029 FIX: Radial layout now centers on actual viewport dimensions. */
  private radialLayout(
    persons: Array<Record<string, any>>,
    canvasWidth: number = 1400,
    canvasHeight: number = 920,
  ): Record<string, { x: number; y: number }> {
    const positions: Record<string, { x: number; y: number }> = {};
    const centerX = canvasWidth / 2;
    const centerY = canvasHeight / 2;
    const baseRadius = Math.min(canvasWidth, canvasHeight) * 0.15;

    const genGroups = new Map<number, Array<Record<string, any>>>();
    for (const person of persons) {
      const gen = person.generationIndex ?? 0;
      const group = genGroups.get(gen) || [];
      group.push(person);
      genGroups.set(gen, group);
    }

    for (const [gen, group] of genGroups) {
      const radius = baseRadius + gen * (Math.min(canvasWidth, canvasHeight) * 0.12);
      const angleStep = (2 * Math.PI) / Math.max(group.length, 1);

      group.forEach((person, idx) => {
        const angle = angleStep * idx - Math.PI / 2;
        positions[person.id] = {
          x: centerX + radius * Math.cos(angle),
          y: centerY + radius * Math.sin(angle),
        };
      });
    }

    return positions;
  }

  /** BUG-030 FIX: Force-directed layout accepts viewport dimensions. */
  private forceDirectedLayout(
    persons: Array<Record<string, any>>,
    canvasWidth: number = 1400,
    canvasHeight: number = 920,
  ): Record<string, { x: number; y: number }> {
    // Simple force-directed: start with hierarchical then add jitter
    const positions = this.hierarchicalLayout(persons, canvasWidth, canvasHeight);

    const rng = (seed: number) => {
      let x = Math.sin(seed) * 10000;
      return x - Math.floor(x);
    };

    for (const [id, pos] of Object.entries(positions)) {
      const hash = id.split('').reduce((acc, c) => acc + c.charCodeAt(0), 0);
      positions[id] = {
        x: pos.x + (rng(hash) - 0.5) * 40,
        y: pos.y + (rng(hash + 1) - 0.5) * 20,
      };
    }

    return positions;
  }

  private async requireFamilyMember(userId: string, familyId: string) {
    const membership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId } },
    });

    if (membership) {
      return membership;
    }

    // Not a member — check family privacy
    const family = await this.prisma.family.findUnique({
      where: { id: familyId },
      select: { isPublic: true },
    });

    if (!family) {
      throw new NotFoundException('Family not found');
    }

    if (family.isPublic) {
      // Allow read-only access for non-members on public families
      // Return null to indicate read-only access (no membership)
      return null;
    }

    // Private family — deny access
    throw new ForbiddenException('This family tree is private. You must be a member to view it.');
  }

  /** Check if user has full (member) access to the family graph */
  private async isFamilyMember(userId: string, familyId: string): Promise<boolean> {
    const membership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId } },
    });
    return !!membership;
  }

  /** BUG-031 FIX: Strip contact details for non-member (read-only) access.
   *  Returns a shallow-cloned result so the caller's original object is not
   *  mutated (prevents accidental data leak through cached references). */
  private stripContactDetails(result: any): any {
    const contactFields = ['email', 'phone', 'address', 'bloodGroup', 'anniversaryDate'];
    if (result && result.persons && Array.isArray(result.persons)) {
      return {
        ...result,
        persons: result.persons.map((p: any) => {
          const stripped = { ...p };
          for (const field of contactFields) {
            if (field in stripped) stripped[field] = null;
          }
          return stripped;
        }),
      };
    }
    return result;
  }

  private formatPerson(person: Record<string, any>) {
    return {
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
      // Graph endpoints return thumb URL for performance
      photoUrl: person.photoThumb ?? person.photoUrl ?? null,
      photoThumb: person.photoThumb ?? null,
      username: person.username ?? null,
    };
  }

  /**
   * Resolves a relationshipKey to a human-readable English display label.
   * Uses KinshipService for known terms, falls back to key formatting.
   */
  private resolveRelationshipLabel(relationshipKey: string): string {
    try {
      const term = this.kinshipService.getByKey(relationshipKey);
      if (term && term.englishTerm) {
        return term.englishTerm;
      }
    } catch {
      // KinshipService lookup failed — fall through to formatting
    }

    // Fallback: format the key (e.g. "fathers_brother" → "Fathers Brother")
    return this.formatKey(relationshipKey);
  }

  /** Find the "self" person for the current user in this family. */
  private async findSelfPersonId(userId: string, familyId: string): Promise<string | null> {
    // Strategy: find the anchor person in the family, since that's the
    // primary person from whose perspective kinship is computed.
    // FamilyMember doesn't have a personId column, and Person doesn't
    // have a userId column, so we use the anchor as the "self" proxy.
    const anchor = await this.prisma.person.findFirst({
      where: { familyId, isAnchor: true, deletedAt: null },
      select: { id: true },
    });

    if (anchor) {
      return anchor.id;
    }

    // Fallback: return the first person in the family
    const firstPerson = await this.prisma.person.findFirst({
      where: { familyId, deletedAt: null },
      select: { id: true },
    });

    return firstPerson?.id ?? null;
  }

  /** Find the anchor person ID for the family. */
  private async findAnchorPersonId(familyId: string): Promise<string | null> {
    const family = await this.prisma.family.findUnique({
      where: { id: familyId },
      select: { anchorPersonId: true },
    });
    return family?.anchorPersonId ?? null;
  }

  /** Format a kinship term from snake_case to Title Case (English only). */
  private formatKinshipTerm(term: string): string {
    // BUG-093 FIX: Use hyphen for in-law terms (Father-in-Law, not Father In Law)
    if (term.includes('in_law')) {
      const parts = term.split('_in_law');
      const main = parts[0];
      const mainFormatted = main.charAt(0).toUpperCase() + main.slice(1).toLowerCase();
      return `${mainFormatted}-in-Law`;
    }
    return term
      .split('_')
      .map(word => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
      .join(' ');
  }

  /**
   * Format a raw key to Title Case.
   * BUG-027 FIX: For compound kinship keys (e.g. `fathers_brother`),
   * produce the possessive form "Father's Brother" instead of "Fathers Brother".
   * Handles both `fathers_brother` (segment already has trailing 's') and
   * `wife_father` (segment without trailing 's') conventions.
   */
  private formatKey(key: string): string {
    const parts = key.split('_').filter(Boolean);
    if (parts.length <= 1) {
      return key
        .split('_')
        .map(word => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
        .join(' ');
    }
    // Possessive: "Father's Brother", "Mother's Sister", "Wife's Father"
    // The kinship vocabulary uses a small set of singular/plural possessive
    // prefixes — handle them explicitly to avoid the "wives" → "wive's"
    // problem that a generic trailing-'s' strip would cause.
    const POSSESSIVE_SINGULAR: Record<string, string> = {
      fathers: "Father's",
      mothers: "Mother's",
      wives: "Wife's",
      husbands: "Husband's",
      sons: "Son's",
      daughters: "Daughter's",
      parents: "Parent's",
      brother: "Brother's",
      sister: "Sister's",
      wife: "Wife's",
      husband: "Husband's",
      father: "Father's",
      mother: "Mother's",
      son: "Son's",
      daughter: "Daughter's",
      parent: "Parent's",
    };
    const firstLower = parts[0].toLowerCase();
    const firstFormatted = POSSESSIVE_SINGULAR[firstLower]
      ?? `${parts[0].charAt(0).toUpperCase()}${parts[0].slice(1).toLowerCase()}'s`;
    const rest = parts.slice(1).map(word => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase());
    return [firstFormatted, ...rest].join(' ');
  }

  /** Categorize a kinship term for node coloring. */
  private categorizeKinship(term: string): string {
    const t = term.toLowerCase();

    if (t === 'self') return 'self';
    if (t === 'father' || t === 'mother') return 'parent';
    if (t === 'husband' || t === 'wife' || t === 'spouse') return 'spouse';
    if (t === 'brother' || t === 'sister' || t.includes('sibling')) return 'sibling';
    if (t === 'son' || t === 'daughter' || t === 'child') return 'child';
    if (t.includes('grandfather') || t.includes('grandmother') || t.includes('grandparent')) return 'grandparent';
    if (t.includes('uncle') || t.includes('aunt')) return 'aunt_uncle';
    if (t.includes('cousin')) return 'cousin';
    if (t.includes('in_law') || t.includes('in-law')) return 'in_law';
    if (t.includes('nephew') || t.includes('niece') || t.includes('grandson') || t.includes('granddaughter')) return 'extended';

    return 'extended';
  }
}
