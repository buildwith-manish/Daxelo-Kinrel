import { Injectable, NotFoundException, ForbiddenException } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { getInverseKey } from '../relationships/relationships.service';

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
  constructor(private prisma: PrismaService) {}

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
    await this.requireFamilyMember(userId, familyId);

    if (options.from && options.to) {
      return this.getPath(familyId, options.from, options.to);
    }

    if (options.root && options.format === 'tree') {
      return this.getTree(familyId, options.root, options.depth || 10);
    }

    if (options.format === 'tree') {
      const family = await this.prisma.family.findUnique({
        where: { id: familyId },
      });
      const rootId = family?.anchorPersonId;
      if (rootId) {
        return this.getTree(familyId, rootId, options.depth || 10);
      }
      return this.getFlatGraph(familyId);
    }

    return this.getFlatGraph(familyId);
  }

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

  async getTree(familyId: string, rootPersonId: string, depth: number = 10): Promise<{ root: TreeNode | null; totalNodes: number }> {
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
      if (visited.has(personId) || currentDepth > depth) return null;
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

    return { root, totalNodes: visited.size };
  }

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

      if (!adjacency.has(rel.fromPersonId)) {
        adjacency.set(rel.fromPersonId, []);
      }
      adjacency.get(rel.fromPersonId)!.push({
        neighborId: rel.toPersonId,
        relationship: rel,
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

  async getPathWithAuth(userId: string, familyId: string, fromPersonId: string, toPersonId: string) {
    await this.requireFamilyMember(userId, familyId);
    return this.getPath(familyId, fromPersonId, toPersonId);
  }

  async getFlatGraph(familyId: string): Promise<FlatGraphResult> {
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

    return {
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
}
