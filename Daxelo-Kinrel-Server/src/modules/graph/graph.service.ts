import {
  Injectable,
  NotFoundException,
  BadRequestException,
  InternalServerErrorException,
  Logger,
} from '@nestjs/common';
import { PrismaService } from '@/common/prisma/prisma.service';
import { KinshipService } from '@/modules/kinship/kinship.service';
import {
  getKinshipTermByLocale,
  getRelationship,
  normalizeRelationshipKey,
  type LocaleCode,
} from '@/lib/kinship';

// ── Types ────────────────────────────────────────────────────────────

export interface TreeNode {
  person: {
    id: string;
    name: string;
    relationship: string | null;
    dateOfBirth: Date | null;
    isDeceased: boolean;
    privacyLevel: string;
    occupation: string | null;
    city: string | null;
    gotra: string | null;
  };
  spouse?: TreeNode['person'];
  children: TreeNode[];
}

export interface PathStep {
  relationshipId: string;
  type: string;
  direction: 'from' | 'to';
}

export interface PathResult {
  path: PathStep[];
  length: number;
  relationshipDescription: string;
  localizedDescription: string;
}

export interface EnrichedPathStep extends PathStep {
  localizedType?: string;
  fromPerson: { id: string; name: string };
  toPerson: { id: string; name: string };
}

// ── Inverse Relationship Types ───────────────────────────────────────

function inverseType(type: string): string {
  const inverses: Record<string, string> = {
    father: 'child',
    mother: 'child',
    son: 'parent',
    daughter: 'parent',
    spouse: 'spouse',
    brother: 'sibling',
    sister: 'sibling',
    grandfather: 'grandchild',
    grandmother: 'grandchild',
    grandchild: 'grandparent',
    uncle: 'nephew_or_niece',
    aunt: 'nephew_or_niece',
    nephew: 'uncle_or_aunt',
    niece: 'uncle_or_aunt',
    cousin: 'cousin',
    child: 'parent',
    parent: 'child',
    sibling: 'sibling',
    bua: 'nephew_or_niece',
    chacha: 'nephew_or_niece',
    mama: 'nephew_or_niece',
    bhaiya: 'sibling',
    didi: 'sibling',
    jeth: 'spouse_brother',
    devrani: 'spouse_brother_wife',
    nanad: 'spouse_sister',
    samdhi: 'samdhi',
  };
  return inverses[type] || 'related';
}

// ═════════════════════════════════════════════════════════════════════
// GraphService
// ═════════════════════════════════════════════════════════════════════

@Injectable()
export class GraphService {
  private readonly logger = new Logger(GraphService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly kinshipService: KinshipService,
  ) {}

  // ── Family Access Check ────────────────────────────────────────────

  async requireFamilyAccess(familyId: string, userId: string): Promise<void> {
    const membership = await this.prisma.familyMember.findFirst({
      where: { familyId, userId },
    });
    if (!membership) {
      throw new NotFoundException('Family not found or access denied');
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Unified Graph Endpoint
  // ═══════════════════════════════════════════════════════════════════

  /**
   * GET /api/v1/graph/:familyId — Unified graph endpoint
   * Supports path mode (from+to) and tree mode (root, depth, format, locale)
   */
  async getGraph(
    familyId: string,
    userId: string,
    options: {
      from?: string;
      to?: string;
      root?: string;
      depth?: number;
      format?: 'nested' | 'flat';
      locale?: string;
    },
  ) {
    await this.requireFamilyAccess(familyId, userId);

    const locale = (options.locale || 'en') as LocaleCode;

    // ── Path mode: from + to query params ──────────────────────────
    if (options.from && options.to) {
      return this.getPathMode(familyId, options.from, options.to, locale);
    }

    // ── Tree mode ──────────────────────────────────────────────────
    const depth = Math.min(10, Math.max(1, options.depth ?? 5));
    const format = options.format || 'nested';
    return this.getTreeMode(familyId, depth, format, locale, options.root);
  }

  // ═══════════════════════════════════════════════════════════════════
  // Tree View
  // ═══════════════════════════════════════════════════════════════════

  /**
   * GET /api/v1/graph/:familyId/tree — Tree view (API key auth, scope: graph:read)
   */
  async getTree(
    familyId: string,
    userId: string,
    options: {
      depth?: number;
      includeDeceased?: boolean;
      format?: 'nested' | 'flat';
    },
  ) {
    await this.requireFamilyAccess(familyId, userId);

    const depth = Math.min(10, Math.max(1, options.depth ?? 5));
    const includeDeceased = options.includeDeceased ?? true;
    const format = options.format || 'nested';

    try {
      const tree = await this.buildTree(familyId, depth);

      // Filter deceased if requested
      const filteredTree = includeDeceased
        ? tree
        : this.filterDeceased(tree) || tree;

      // Format: flat representation
      if (format === 'flat') {
        const flat = this.flattenTree(filteredTree);
        return {
          familyId,
          format: 'flat' as const,
          depth,
          nodes: flat,
          totalNodes: flat.length,
        };
      }

      // Default: nested format
      return {
        familyId,
        format: 'nested' as const,
        depth,
        tree: filteredTree,
      };
    } catch (err) {
      if (err instanceof Error && err.message === 'Family not found') {
        throw new NotFoundException('Family not found');
      }
      throw err;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Path Finder
  // ═══════════════════════════════════════════════════════════════════

  /**
   * GET /api/v1/graph/:familyId/path — Path finder (API key auth, scope: graph:read)
   * Uses BFS to find shortest path between two persons.
   */
  async getPath(
    familyId: string,
    userId: string,
    fromPersonId: string,
    toPersonId: string,
  ) {
    await this.requireFamilyAccess(familyId, userId);

    if (!fromPersonId || !toPersonId) {
      throw new BadRequestException(
        'Both "from" and "to" person IDs are required',
      );
    }

    // Verify both persons exist in this family
    const [fromPerson, toPerson] = await Promise.all([
      this.prisma.person.findFirst({
        where: { id: fromPersonId, familyId, deletedAt: null },
      }),
      this.prisma.person.findFirst({
        where: { id: toPersonId, familyId, deletedAt: null },
      }),
    ]);

    if (!fromPerson) {
      throw new NotFoundException(
        `Person "${fromPersonId}" not found in this family`,
      );
    }
    if (!toPerson) {
      throw new NotFoundException(
        `Person "${toPersonId}" not found in this family`,
      );
    }

    try {
      const pathResult = await this.findPath(
        familyId,
        fromPersonId,
        toPersonId,
      );

      if (!pathResult) {
        return {
          from: { id: fromPersonId, name: fromPerson.name },
          to: { id: toPersonId, name: toPerson.name },
          path: null,
          length: -1,
          message: 'No path found between these persons',
        };
      }

      // Enrich path steps with person names
      const enrichedPath = await this.enrichPathSteps(pathResult.path);

      return {
        from: { id: fromPersonId, name: fromPerson.name },
        to: { id: toPersonId, name: toPerson.name },
        path: enrichedPath,
        length: pathResult.length,
        relationshipDescription: pathResult.relationshipDescription,
        localizedDescription: pathResult.localizedDescription,
      };
    } catch (error) {
      throw new InternalServerErrorException('Failed to find path', {
        cause: error,
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Private: Build Family Tree
  // ═══════════════════════════════════════════════════════════════════

  private async buildTree(familyId: string, depth: number): Promise<TreeNode> {
    const family = await this.prisma.family.findUnique({
      where: { id: familyId },
      include: {
        persons: {
          include: {
            relationshipsFrom: {
              include: { toPerson: true },
            },
            relationshipsTo: {
              include: { fromPerson: true },
            },
          },
        },
      },
    });

    if (!family) {
      throw new Error('Family not found');
    }

    // Build adjacency from relationships
    const personMap = new Map<
      string,
      TreeNode['person'] & {
        childrenIds: string[];
        spouseId?: string;
      }
    >();
    const visited = new Set<string>();

    // Initialize person map
    for (const person of family.persons) {
      if (person.deletedAt) continue; // Skip soft-deleted
      personMap.set(person.id, {
        id: person.id,
        name: person.name,
        relationship: person.relationship,
        dateOfBirth: person.dateOfBirth,
        isDeceased: person.isDeceased,
        privacyLevel: person.privacyLevel,
        occupation: person.occupation,
        city: person.city,
        gotra: person.gotra,
        childrenIds: [],
        spouseId: undefined,
      });
    }

    // Populate relationships
    for (const person of family.persons) {
      if (person.deletedAt) continue;
      const entry = personMap.get(person.id);
      if (!entry) continue;

      for (const rel of person.relationshipsFrom) {
        if (rel.toPerson?.deletedAt) continue;
        if (rel.type === 'spouse') {
          entry.spouseId = rel.toPersonId;
        } else if (['father', 'mother', 'parent'].includes(rel.type)) {
          // person is parent of toPerson
          const childEntry = personMap.get(rel.toPersonId);
          if (childEntry) {
            entry.childrenIds.push(rel.toPersonId);
          }
        }
      }

      for (const rel of person.relationshipsTo) {
        if (rel.fromPerson?.deletedAt) continue;
        if (rel.type === 'spouse') {
          entry.spouseId = rel.fromPersonId;
        } else if (['child', 'son', 'daughter'].includes(rel.type)) {
          // fromPerson is child of person (person is parent)
          entry.childrenIds.push(rel.fromPersonId);
        }
      }
    }

    // Find root: a person who is not a child of anyone else
    const childIds = new Set<string>();
    for (const [, entry] of personMap) {
      for (const cid of entry.childrenIds) {
        childIds.add(cid);
      }
    }

    let rootId: string | null = null;
    for (const person of family.persons) {
      if (person.deletedAt) continue;
      if (!childIds.has(person.id)) {
        rootId = person.id;
        break;
      }
    }

    // If no root found, pick the first person
    if (!rootId && family.persons.length > 0) {
      const firstActive = family.persons.find((p) => !p.deletedAt);
      rootId = firstActive?.id ?? null;
    }

    if (!rootId) {
      return {
        person: {
          id: '',
          name: 'Empty Family',
          relationship: null,
          dateOfBirth: null,
          isDeceased: false,
          privacyLevel: 'family',
          occupation: null,
          city: null,
          gotra: null,
        },
        children: [],
      };
    }

    // Recursively build tree
    const buildNode = (personId: string, currentDepth: number): TreeNode => {
      visited.add(personId);
      const entry = personMap.get(personId);
      if (!entry) {
        return {
          person: {
            id: personId,
            name: 'Unknown',
            relationship: null,
            dateOfBirth: null,
            isDeceased: false,
            privacyLevel: 'family',
            occupation: null,
            city: null,
            gotra: null,
          },
          children: [],
        };
      }

      const node: TreeNode = {
        person: {
          id: entry.id,
          name: entry.name,
          relationship: entry.relationship,
          dateOfBirth: entry.dateOfBirth,
          isDeceased: entry.isDeceased,
          privacyLevel: entry.privacyLevel,
          occupation: entry.occupation,
          city: entry.city,
          gotra: entry.gotra,
        },
        children: [],
      };

      // Add spouse
      if (entry.spouseId && personMap.has(entry.spouseId)) {
        const spouseEntry = personMap.get(entry.spouseId)!;
        node.spouse = {
          id: spouseEntry.id,
          name: spouseEntry.name,
          relationship: spouseEntry.relationship,
          dateOfBirth: spouseEntry.dateOfBirth,
          isDeceased: spouseEntry.isDeceased,
          privacyLevel: spouseEntry.privacyLevel,
          occupation: spouseEntry.occupation,
          city: spouseEntry.city,
          gotra: spouseEntry.gotra,
        };
      }

      // Add children (deduplicate)
      if (currentDepth < depth) {
        const uniqueChildren = [...new Set(entry.childrenIds)];
        for (const childId of uniqueChildren) {
          if (!visited.has(childId) && personMap.has(childId)) {
            node.children.push(buildNode(childId, currentDepth + 1));
          }
        }
      }

      return node;
    };

    return buildNode(rootId, 0);
  }

  // ═══════════════════════════════════════════════════════════════════
  // Private: BFS Path Finding
  // ═══════════════════════════════════════════════════════════════════

  private async findPath(
    familyId: string,
    fromPersonId: string,
    toPersonId: string,
  ): Promise<PathResult | null> {
    if (fromPersonId === toPersonId) {
      return {
        path: [],
        length: 0,
        relationshipDescription: 'self',
        localizedDescription: getKinshipTermByLocale('self', 'hi'),
      };
    }

    // Get all relationships for this family
    const relationships = await this.prisma.relationship.findMany({
      where: { familyId },
    });

    // Build adjacency list
    const adjacency = new Map<
      string,
      Array<{
        personId: string;
        relationshipId: string;
        type: string;
        direction: 'from' | 'to';
      }>
    >();

    for (const rel of relationships) {
      if (!adjacency.has(rel.fromPersonId)) {
        adjacency.set(rel.fromPersonId, []);
      }
      if (!adjacency.has(rel.toPersonId)) {
        adjacency.set(rel.toPersonId, []);
      }

      // fromPerson -> toPerson
      adjacency.get(rel.fromPersonId)!.push({
        personId: rel.toPersonId,
        relationshipId: rel.id,
        type: rel.type,
        direction: 'from',
      });

      // toPerson -> fromPerson (inverse)
      adjacency.get(rel.toPersonId)!.push({
        personId: rel.fromPersonId,
        relationshipId: rel.id,
        type: inverseType(rel.type),
        direction: 'to',
      });
    }

    // BFS
    const queue: Array<{ personId: string; path: PathStep[] }> = [
      { personId: fromPersonId, path: [] },
    ];
    const visited = new Set<string>([fromPersonId]);

    while (queue.length > 0) {
      const current = queue.shift()!;

      const neighbors = adjacency.get(current.personId) || [];
      for (const neighbor of neighbors) {
        if (visited.has(neighbor.personId)) continue;
        visited.add(neighbor.personId);

        const newPath: PathStep[] = [
          ...current.path,
          {
            relationshipId: neighbor.relationshipId,
            type: neighbor.type,
            direction: neighbor.direction,
          },
        ];

        if (neighbor.personId === toPersonId) {
          // Build description using kinship module
          const pathDescription = this.buildPathDescription(newPath);
          return {
            path: newPath,
            length: newPath.length,
            relationshipDescription: pathDescription.en,
            localizedDescription: pathDescription.localized,
          };
        }

        queue.push({ personId: neighbor.personId, path: newPath });
      }
    }

    return null; // No path found
  }

  // ── Build Path Description ──────────────────────────────────────────

  private buildPathDescription(path: PathStep[]): {
    en: string;
    localized: string;
  } {
    if (path.length === 0) return { en: 'self', localized: 'स्वयं' };

    const enParts: string[] = [];
    const localizedParts: string[] = [];

    for (const step of path) {
      const enLabel = this.getEnglishRelationLabel(step.type);
      const hiLabel = getKinshipTermByLocale(step.type, 'hi');
      enParts.push(enLabel);
      localizedParts.push(hiLabel);
    }

    return {
      en: enParts.join(' → '),
      localized: localizedParts.join(' → '),
    };
  }

  private getEnglishRelationLabel(relationshipKey: string): string {
    const key = normalizeRelationshipKey(relationshipKey);
    const rel = getRelationship(key);
    if (rel) {
      return `${rel.englishTerm} of`;
    }
    return `${relationshipKey} of`;
  }

  // ── Path Mode Helper ────────────────────────────────────────────────

  private async getPathMode(
    familyId: string,
    fromPersonId: string,
    toPersonId: string,
    locale: LocaleCode,
  ) {
    // Verify persons exist
    const [fromPerson, toPerson] = await Promise.all([
      this.prisma.person.findFirst({
        where: { id: fromPersonId, familyId, deletedAt: null },
      }),
      this.prisma.person.findFirst({
        where: { id: toPersonId, familyId, deletedAt: null },
      }),
    ]);

    if (!fromPerson) {
      throw new NotFoundException(`Person "${fromPersonId}" not found`);
    }
    if (!toPerson) {
      throw new NotFoundException(`Person "${toPersonId}" not found`);
    }

    try {
      const pathResult = await this.findPath(familyId, fromPersonId, toPersonId);

      if (!pathResult) {
        return {
          from: { id: fromPersonId, name: fromPerson.name },
          to: { id: toPersonId, name: toPerson.name },
          path: null,
          length: -1,
          message: 'No path found between these persons',
        };
      }

      // Get localized description
      const localizedDesc =
        locale !== 'en'
          ? getKinshipTermByLocale(
              pathResult.relationshipDescription,
              locale,
            )
          : pathResult.relationshipDescription;

      // Enrich path steps with person names
      const enrichedPath = await this.enrichPathSteps(
        pathResult.path,
        locale,
      );

      return {
        from: { id: fromPersonId, name: fromPerson.name },
        to: { id: toPersonId, name: toPerson.name },
        path: enrichedPath,
        length: pathResult.length,
        relationshipDescription: pathResult.relationshipDescription,
        localizedDescription: localizedDesc || pathResult.localizedDescription,
        locale,
      };
    } catch (error) {
      throw new InternalServerErrorException('Failed to find path', {
        cause: error,
      });
    }
  }

  // ── Tree Mode Helper ────────────────────────────────────────────────

  private async getTreeMode(
    familyId: string,
    depth: number,
    format: 'nested' | 'flat',
    locale: LocaleCode,
    rootPersonId?: string,
  ) {
    try {
      const tree = await this.buildTree(familyId, depth);

      // If root is specified, find that node in the tree
      let resultTree = tree;
      if (rootPersonId) {
        const rootNode = this.findNodeInTree(tree, rootPersonId);
        if (rootNode) {
          resultTree = rootNode;
        }
      }

      // Localize relationship labels if non-English locale
      if (locale !== 'en') {
        resultTree = this.localizeTree(resultTree, locale);
      }

      // Format: flat
      if (format === 'flat') {
        const flat = this.flattenTree(resultTree);
        return {
          familyId,
          format: 'flat' as const,
          depth,
          locale,
          nodes: flat,
          totalNodes: flat.length,
        };
      }

      // Default: nested
      return {
        familyId,
        format: 'nested' as const,
        depth,
        locale,
        tree: resultTree,
      };
    } catch (err) {
      if (err instanceof Error && err.message === 'Family not found') {
        throw new NotFoundException('Family not found');
      }
      throw err;
    }
  }

  // ── Tree Helpers ────────────────────────────────────────────────────

  private findNodeInTree(
    node: TreeNode,
    targetId: string,
  ): TreeNode | null {
    if (node.person.id === targetId) return node;
    for (const child of node.children) {
      const found = this.findNodeInTree(child, targetId);
      if (found) return found;
    }
    return null;
  }

  private localizeTree(node: TreeNode, locale: LocaleCode): TreeNode {
    return {
      ...node,
      person: {
        ...node.person,
        relationship: node.person.relationship
          ? getKinshipTermByLocale(node.person.relationship, locale)
          : null,
      },
      spouse: node.spouse
        ? {
            ...node.spouse,
            relationship: node.spouse.relationship
              ? getKinshipTermByLocale(node.spouse.relationship, locale)
              : null,
          }
        : undefined,
      children: node.children.map((child) => this.localizeTree(child, locale)),
    };
  }

  private flattenTree(
    node: TreeNode,
    currentDepth: number = 0,
    parentIds: string[] = [],
  ): Array<Record<string, unknown>> {
    const flat: Array<Record<string, unknown>> = [];

    flat.push({
      id: node.person.id,
      name: node.person.name,
      relationship: node.person.relationship,
      isDeceased: node.person.isDeceased,
      spouseId: node.spouse?.id,
      parentIds,
      depth: currentDepth,
    });

    for (const child of node.children) {
      flat.push(
        ...this.flattenTree(
          child,
          currentDepth + 1,
          [
            node.person.id,
            ...(node.spouse ? [node.spouse.id] : []),
          ],
        ),
      );
    }

    return flat;
  }

  private filterDeceased(node: TreeNode): TreeNode | null {
    if (
      node.person.isDeceased &&
      node.children.length === 0
    ) {
      return null;
    }

    return {
      ...node,
      spouse:
        node.spouse && !node.spouse.isDeceased ? node.spouse : undefined,
      children: node.children
        .map((child) => this.filterDeceased(child))
        .filter((child): child is TreeNode => child !== null),
    };
  }

  // ── Enrich Path Steps ───────────────────────────────────────────────

  private async enrichPathSteps(
    path: PathStep[],
    locale?: LocaleCode,
  ): Promise<EnrichedPathStep[]> {
    return Promise.all(
      path.map(async (step) => {
        const rel = await this.prisma.relationship.findUnique({
          where: { id: step.relationshipId },
          include: {
            fromPerson: { select: { id: true, name: true } },
            toPerson: { select: { id: true, name: true } },
          },
        });

        const localType =
          locale && locale !== 'en'
            ? getKinshipTermByLocale(step.type, locale)
            : step.type;

        return {
          ...step,
          localizedType: localType,
          fromPerson: rel?.fromPerson || { id: '', name: 'Unknown' },
          toPerson: rel?.toPerson || { id: '', name: 'Unknown' },
        };
      }),
    );
  }
}
