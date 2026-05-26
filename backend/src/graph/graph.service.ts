/**
 * DAXELO KINREL — Graph Service
 *
 * Provides family tree building and path-finding between persons.
 * Ported from graph-traversal.ts logic.
 */

import { Injectable, NotFoundException, ForbiddenException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { KinshipService, LocaleCode } from '../kinship/kinship.service';
import { INVERSE_RELATIONSHIP_MAP } from '../relationships/relationships.service';

// ── Types ────────────────────────────────────────────────────────────

export interface TreeNode {
  person: {
    id: string;
    name: string;
    relationship: string | null;
    isDeceased: boolean;
    dateOfBirth: Date | null;
  };
  spouse: TreeNode['person'] | null;
  children: TreeNode[];
}

export interface FlatNode {
  id: string;
  name: string;
  relationship: string | null;
  isDeceased: boolean;
  dateOfBirth: Date | null;
  parentId: string | null;
  spouseId: string | null;
  level: number;
}

export interface PathStep {
  personId: string;
  personName: string;
  relationshipToNext: string | null;
}

export interface PathResult {
  from: { id: string; name: string };
  to: { id: string; name: string };
  path: PathStep[];
  length: number;
  relationshipDescription: string;
  localizedDescription: string;
  locale: string;
}

@Injectable()
export class GraphService {
  constructor(
    private prisma: PrismaService,
    private kinshipService: KinshipService,
  ) {}

  /**
   * Build a family tree (nested or flat format)
   * - Find root (person who is not a child of anyone in the family)
   * - Recursively build: person + spouse + children
   */
  async buildTree(
    familyId: string,
    userId: string,
    options: {
      format?: 'nested' | 'flat';
      depth?: number;
    } = {},
  ) {
    // Check family membership
    await this.checkMembership(familyId, userId);

    const maxDepth = options.depth || 10;
    const format = options.format || 'nested';

    // Get all non-deleted persons in the family
    const persons = await this.prisma.person.findMany({
      where: { familyId, deletedAt: null },
    });

    // Get all relationships in the family
    const relationships = await this.prisma.relationship.findMany({
      where: { familyId },
    });

    if (persons.length === 0) {
      return {
        familyId,
        format,
        depth: 0,
        tree: null,
        nodes: [],
        totalNodes: 0,
      };
    }

    // Build adjacency structures
    const personMap = new Map(persons.map((p) => [p.id, p]));

    // childId → parentId mapping (from parent-child relationships)
    const childToParents = new Map<string, Array<{ parentId: string; type: string }>>();
    // parentId → children mapping
    const parentToChildren = new Map<string, Array<{ childId: string; type: string }>>();
    // personId → spouseId mapping (spouse relationships)
    const spouseMap = new Map<string, string>();

    // Determine parent-child relationship types
    const parentTypes = new Set([
      'father', 'mother',
      'paternal_grandfather', 'paternal_grandmother',
      'maternal_grandfather', 'maternal_grandmother',
    ]);

    const childTypes = new Set([
      'son', 'daughter',
      'grandson', 'granddaughter',
    ]);

    const spouseTypes = new Set(['husband', 'wife']);

    for (const rel of relationships) {
      const fromPerson = personMap.get(rel.fromPersonId);
      const toPerson = personMap.get(rel.toPersonId);
      if (!fromPerson || !toPerson) continue; // skip soft-deleted

      const relType = rel.type;

      if (parentTypes.has(relType)) {
        // fromPerson is parent of toPerson
        if (!childToParents.has(rel.toPersonId)) {
          childToParents.set(rel.toPersonId, []);
        }
        childToParents.get(rel.toPersonId)!.push({ parentId: rel.fromPersonId, type: relType });

        if (!parentToChildren.has(rel.fromPersonId)) {
          parentToChildren.set(rel.fromPersonId, []);
        }
        parentToChildren.get(rel.fromPersonId)!.push({ childId: rel.toPersonId, type: relType });
      } else if (childTypes.has(relType)) {
        // fromPerson is child of toPerson
        if (!childToParents.has(rel.fromPersonId)) {
          childToParents.set(rel.fromPersonId, []);
        }
        childToParents.get(rel.fromPersonId)!.push({ parentId: rel.toPersonId, type: INVERSE_RELATIONSHIP_MAP[relType] || relType });

        if (!parentToChildren.has(rel.toPersonId)) {
          parentToChildren.set(rel.toPersonId, []);
        }
        parentToChildren.get(rel.toPersonId)!.push({ childId: rel.fromPersonId, type: relType });
      } else if (spouseTypes.has(relType)) {
        spouseMap.set(rel.fromPersonId, rel.toPersonId);
      }
    }

    // Find root: person who is not a child of anyone
    let root = persons.find((p) => !childToParents.has(p.id));
    if (!root) {
      // If everyone is a child, pick the first person
      root = persons[0];
    }

    // Build tree recursively
    const visited = new Set<string>();

    const buildPersonNode = (personId: string, currentDepth: number): TreeNode | null => {
      if (visited.has(personId) || currentDepth > maxDepth) return null;
      visited.add(personId);

      const person = personMap.get(personId);
      if (!person) return null;

      const spouseId = spouseMap.get(personId);
      const spouse = spouseId ? personMap.get(spouseId) : null;

      // Get children: either from parentToChildren or via spouse
      const directChildren = parentToChildren.get(personId) || [];
      const spouseChildren = spouseId ? (parentToChildren.get(spouseId) || []) : [];
      const allChildIds = new Set<string>();

      for (const c of directChildren) allChildIds.add(c.childId);
      for (const c of spouseChildren) allChildIds.add(c.childId);

      const children: TreeNode[] = [];
      for (const childId of allChildIds) {
        const childNode = buildPersonNode(childId, currentDepth + 1);
        if (childNode) children.push(childNode);
      }

      return {
        person: {
          id: person.id,
          name: person.name,
          relationship: person.relationship,
          isDeceased: person.isDeceased,
          dateOfBirth: person.dateOfBirth,
        },
        spouse: spouse
          ? {
              id: spouse.id,
              name: spouse.name,
              relationship: spouse.relationship,
              isDeceased: spouse.isDeceased,
              dateOfBirth: spouse.dateOfBirth,
            }
          : null,
        children,
      };
    };

    const tree = buildPersonNode(root.id, 0);

    if (format === 'flat') {
      const nodes: FlatNode[] = [];
      const flatten = (
        node: TreeNode | null,
        parentId: string | null,
        level: number,
      ) => {
        if (!node) return;
        nodes.push({
          id: node.person.id,
          name: node.person.name,
          relationship: node.person.relationship,
          isDeceased: node.person.isDeceased,
          dateOfBirth: node.person.dateOfBirth,
          parentId,
          spouseId: node.spouse?.id || null,
          level,
        });
        if (node.spouse) {
          nodes.push({
            id: node.spouse.id,
            name: node.spouse.name,
            relationship: node.spouse.relationship,
            isDeceased: node.spouse.isDeceased,
            dateOfBirth: node.spouse.dateOfBirth,
            parentId: parentId,
            spouseId: node.person.id,
            level,
          });
        }
        for (const child of node.children) {
          flatten(child, node.person.id, level + 1);
        }
      };
      flatten(tree, null, 0);

      return {
        familyId,
        format: 'flat' as const,
        depth: maxDepth,
        nodes,
        totalNodes: nodes.length,
      };
    }

    return {
      familyId,
      format: 'nested' as const,
      depth: maxDepth,
      tree,
      totalNodes: visited.size,
    };
  }

  /**
   * Find shortest path between two persons using BFS
   * - Build adjacency from relationships
   * - BFS with path tracking
   * - Return PathResult with localized descriptions
   */
  async findPath(
    familyId: string,
    userId: string,
    fromPersonId: string,
    toPersonId: string,
    locale: string = 'en',
  ) {
    // Check family membership
    await this.checkMembership(familyId, userId);

    // Verify both persons exist
    const [fromPerson, toPerson] = await Promise.all([
      this.prisma.person.findFirst({
        where: { id: fromPersonId, familyId, deletedAt: null },
      }),
      this.prisma.person.findFirst({
        where: { id: toPersonId, familyId, deletedAt: null },
      }),
    ]);

    if (!fromPerson) {
      throw new NotFoundException('Source person not found');
    }
    if (!toPerson) {
      throw new NotFoundException('Target person not found');
    }

    if (fromPersonId === toPersonId) {
      return {
        from: { id: fromPerson.id, name: fromPerson.name },
        to: { id: toPerson.id, name: toPerson.name },
        path: [
          {
            personId: fromPerson.id,
            personName: fromPerson.name,
            relationshipToNext: null,
          },
        ],
        length: 0,
        relationshipDescription: 'Same person',
        localizedDescription: 'Same person',
        locale,
      };
    }

    // Get all non-deleted persons and relationships
    const persons = await this.prisma.person.findMany({
      where: { familyId, deletedAt: null },
    });
    const relationships = await this.prisma.relationship.findMany({
      where: { familyId },
    });

    const personMap = new Map(persons.map((p) => [p.id, p]));

    // Build adjacency list: personId → [{ neighborId, relationshipType }]
    const adjacency = new Map<string, Array<{ neighborId: string; relType: string }>>();

    for (const rel of relationships) {
      const fromExists = personMap.has(rel.fromPersonId);
      const toExists = personMap.has(rel.toPersonId);
      if (!fromExists || !toExists) continue;

      if (!adjacency.has(rel.fromPersonId)) {
        adjacency.set(rel.fromPersonId, []);
      }
      adjacency.get(rel.fromPersonId)!.push({
        neighborId: rel.toPersonId,
        relType: rel.type,
      });
    }

    // BFS — each entry tracks the person and the relationship edges traversed
    const visited = new Set<string>();
    const queue: Array<{
      personId: string;
      path: Array<{ personId: string; relType: string | null }>;
    }> = [{ personId: fromPersonId, path: [{ personId: fromPersonId, relType: null }] }];

    visited.add(fromPersonId);

    let foundPath: Array<{ personId: string; relType: string | null }> | null = null;

    while (queue.length > 0) {
      const current = queue.shift()!;

      if (current.personId === toPersonId) {
        foundPath = current.path;
        break;
      }

      const neighbors = adjacency.get(current.personId) || [];
      for (const neighbor of neighbors) {
        if (!visited.has(neighbor.neighborId)) {
          visited.add(neighbor.neighborId);
          queue.push({
            personId: neighbor.neighborId,
            path: [
              ...current.path,
              { personId: neighbor.neighborId, relType: neighbor.relType },
            ],
          });
        }
      }
    }

    if (!foundPath) {
      return {
        from: { id: fromPerson.id, name: fromPerson.name },
        to: { id: toPerson.id, name: toPerson.name },
        path: [],
        length: -1,
        relationshipDescription: 'No path found',
        localizedDescription: 'No path found',
        locale,
      };
    }

    // Build path steps — relType on step[i] = relationship from step[i-1] to step[i]
    const pathSteps: PathStep[] = foundPath.map((step) => {
      const person = personMap.get(step.personId)!;
      return {
        personId: step.personId,
        personName: person.name,
        // The relationship leading TO this person (null for the starting person)
        relationshipToNext: null, // will be filled below
      };
    });

    // Fill in relationshipToNext: the relationship from step[i] to step[i+1]
    // foundPath[i+1].relType = the edge traversed from step[i] to step[i+1]
    for (let i = 0; i < pathSteps.length - 1; i++) {
      pathSteps[i].relationshipToNext = foundPath[i + 1].relType;
    }

    // Build relationship description
    const descriptionParts: string[] = [];
    const localizedParts: string[] = [];
    const localeCode = locale as LocaleCode;

    for (let i = 0; i < pathSteps.length - 1; i++) {
      const step = pathSteps[i];
      const nextStep = pathSteps[i + 1];
      const relType = step.relationshipToNext;

      if (relType) {
        const rel = this.kinshipService.getRelationship(relType);
        const englishTerm = rel?.englishTerm || relType;
        const localizedTerm = this.kinshipService.getKinshipTermByLocale(relType, localeCode);

        descriptionParts.push(`${englishTerm} of ${nextStep.personName}`);
        localizedParts.push(`${localizedTerm} ${localeCode === 'en' ? 'of' : ''} ${nextStep.personName}`);
      }
    }

    const relationshipDescription =
      descriptionParts.length > 0
        ? `${fromPerson.name} is ${descriptionParts.join(', ')}`
        : 'Direct connection';

    const localizedDescription =
      localizedParts.length > 0
        ? `${fromPerson.name} — ${localizedParts.join(' → ')}`
        : relationshipDescription;

    return {
      from: { id: fromPerson.id, name: fromPerson.name },
      to: { id: toPerson.id, name: toPerson.name },
      path: pathSteps,
      length: pathSteps.length - 1,
      relationshipDescription,
      localizedDescription,
      locale,
    };
  }

  /**
   * Get inverse type for traversal
   */
  private inverseType(type: string): string {
    return INVERSE_RELATIONSHIP_MAP[type] || type;
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
}
