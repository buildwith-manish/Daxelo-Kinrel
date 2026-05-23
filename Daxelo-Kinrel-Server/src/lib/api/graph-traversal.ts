import { db } from '@/lib/db'
import { getKinshipTermByLocale, getRelationship, normalizeRelationshipKey, type LocaleCode } from '@/lib/kinship'

// ── Types ────────────────────────────────────────────────────────────

export interface TreeNode {
  person: {
    id: string
    name: string
    relationship: string | null
    dateOfBirth: Date | null
    isDeceased: boolean
    privacyLevel: string
    occupation: string | null
    city: string | null
    gotra: string | null
  }
  spouse?: TreeNode['person']
  children: TreeNode[]
}

export interface PathStep {
  relationshipId: string
  type: string
  direction: 'from' | 'to'
}

export interface PathResult {
  path: PathStep[]
  length: number
  relationshipDescription: string
  localizedDescription: string
}

// ── Localized Relation Label ───────────────────────────────────────
// Replaces the old hardcoded RELATIONSHIP_DESCRIPTIONS.
// Now powered by the kinship module with 523 terms × 13 languages.

function getLocalizedRelationLabel(
  relationshipKey: string,
  language: LocaleCode = 'hi'
): string {
  return getKinshipTermByLocale(relationshipKey, language)
}

// Build English description from relationship metadata
function getEnglishRelationLabel(relationshipKey: string): string {
  const key = normalizeRelationshipKey(relationshipKey)
  const rel = getRelationship(key)
  if (rel) {
    return `${rel.englishTerm} of`
  }
  return `${relationshipKey} of`
}

// ── Inverse Relationship Types ───────────────────────────────────────

export function inverseType(type: string): string {
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
  }
  return inverses[type] || 'related'
}

// ── Build Family Tree ────────────────────────────────────────────────

export async function buildTree(familyId: string, depth: number = 5): Promise<TreeNode> {
  const family = await db.family.findUnique({
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
  })

  if (!family) {
    throw new Error('Family not found')
  }

  // Build adjacency from relationships
  const personMap = new Map<string, TreeNode['person'] & { childrenIds: string[]; spouseId?: string }>()
  const visited = new Set<string>()

  // Initialize person map
  for (const person of family.persons) {
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
    })
  }

  // Populate relationships
  for (const person of family.persons) {
    const entry = personMap.get(person.id)!
    for (const rel of person.relationshipsFrom) {
      if (rel.type === 'spouse') {
        entry.spouseId = rel.toPersonId
      } else if (['father', 'mother', 'parent'].includes(rel.type)) {
        // person is parent of toPerson
        const childEntry = personMap.get(rel.toPersonId)
        if (childEntry) {
          entry.childrenIds.push(rel.toPersonId)
        }
      } else if (['child', 'son', 'daughter'].includes(rel.type)) {
        // person is child of toPerson (toPerson is parent)
        // Don't add to childrenIds; the parent adds the child
      }
    }

    for (const rel of person.relationshipsTo) {
      if (rel.type === 'spouse') {
        entry.spouseId = rel.fromPersonId
      } else if (['child', 'son', 'daughter'].includes(rel.type)) {
        // fromPerson is child of person (person is parent)
        entry.childrenIds.push(rel.fromPersonId)
      }
    }
  }

  // Find root: a person who is not a child of anyone else
  const childIds = new Set<string>()
  for (const [, entry] of personMap) {
    for (const cid of entry.childrenIds) {
      childIds.add(cid)
    }
  }

  let rootId: string | null = null
  for (const person of family.persons) {
    if (!childIds.has(person.id)) {
      rootId = person.id
      break
    }
  }

  // If no root found, pick the first person
  if (!rootId && family.persons.length > 0) {
    rootId = family.persons[0].id
  }

  if (!rootId) {
    // Empty family
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
    }
  }

  // Recursively build tree
  function buildNode(personId: string, currentDepth: number): TreeNode {
    visited.add(personId)
    const entry = personMap.get(personId)!

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
    }

    // Add spouse
    if (entry.spouseId && personMap.has(entry.spouseId)) {
      const spouseEntry = personMap.get(entry.spouseId)!
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
      }
    }

    // Add children (deduplicate)
    if (currentDepth < depth) {
      const uniqueChildren = [...new Set(entry.childrenIds)]
      for (const childId of uniqueChildren) {
        if (!visited.has(childId) && personMap.has(childId)) {
          node.children.push(buildNode(childId, currentDepth + 1))
        }
      }
    }

    return node
  }

  return buildNode(rootId, 0)
}

// ── Find Shortest Path (BFS) ─────────────────────────────────────────

export async function findPath(
  familyId: string,
  fromPersonId: string,
  toPersonId: string
): Promise<PathResult | null> {
  if (fromPersonId === toPersonId) {
    return {
      path: [],
      length: 0,
      relationshipDescription: 'self',
      localizedDescription: getKinshipTermByLocale('self', 'hi'),
    }
  }

  // Get all relationships for this family
  const relationships = await db.relationship.findMany({
    where: { familyId },
  })

  // Build adjacency list
  const adjacency = new Map<string, Array<{ personId: string; relationshipId: string; type: string; direction: 'from' | 'to' }>>()

  for (const rel of relationships) {
    if (!adjacency.has(rel.fromPersonId)) {
      adjacency.set(rel.fromPersonId, [])
    }
    if (!adjacency.has(rel.toPersonId)) {
      adjacency.set(rel.toPersonId, [])
    }

    // fromPerson -> toPerson
    adjacency.get(rel.fromPersonId)!.push({
      personId: rel.toPersonId,
      relationshipId: rel.id,
      type: rel.type,
      direction: 'from',
    })

    // toPerson -> fromPerson (inverse)
    adjacency.get(rel.toPersonId)!.push({
      personId: rel.fromPersonId,
      relationshipId: rel.id,
      type: inverseType(rel.type),
      direction: 'to',
    })
  }

  // BFS
  const queue: Array<{ personId: string; path: PathStep[] }> = [
    { personId: fromPersonId, path: [] },
  ]
  const visited = new Set<string>([fromPersonId])

  while (queue.length > 0) {
    const current = queue.shift()!

    const neighbors = adjacency.get(current.personId) || []
    for (const neighbor of neighbors) {
      if (visited.has(neighbor.personId)) continue
      visited.add(neighbor.personId)

      const newPath: PathStep[] = [
        ...current.path,
        {
          relationshipId: neighbor.relationshipId,
          type: neighbor.type,
          direction: neighbor.direction,
        },
      ]

      if (neighbor.personId === toPersonId) {
        // Build description using kinship module
        const pathDescription = buildPathDescription(newPath)
        return {
          path: newPath,
          length: newPath.length,
          relationshipDescription: pathDescription.en,
          localizedDescription: pathDescription.localized,
        }
      }

      queue.push({ personId: neighbor.personId, path: newPath })
    }
  }

  return null // No path found
}

// ── Build Path Description ───────────────────────────────────────────

function buildPathDescription(path: PathStep[]): { en: string; localized: string } {
  if (path.length === 0) return { en: 'self', localized: 'स्वयं' }

  const enParts: string[] = []
  const localizedParts: string[] = []

  for (const step of path) {
    const enLabel = getEnglishRelationLabel(step.type)
    const hiLabel = getLocalizedRelationLabel(step.type, 'hi')
    enParts.push(enLabel)
    localizedParts.push(hiLabel)
  }

  return {
    en: enParts.join(' → '),
    localized: localizedParts.join(' → '),
  }
}

// ── Get Ancestors ────────────────────────────────────────────────────

export async function getAncestors(personId: string, depth: number = 5): Promise<TreeNode> {
  // Get all relationships involving this person
  const person = await db.person.findUnique({
    where: { id: personId },
    include: {
      relationshipsTo: {
        include: { fromPerson: true },
      },
      relationshipsFrom: {
        include: { toPerson: true },
      },
    },
  })

  if (!person) {
    throw new Error('Person not found')
  }

  const visited = new Set<string>([personId])

  function buildAncestorNode(currentPersonId: string, currentDepth: number): TreeNode {
    visited.add(currentPersonId)

    const currentPerson = currentPersonId === personId ? person : null
    // Fetch person if not the root
    // For simplicity, we'll build from the initial data

    const node: TreeNode = {
      person: currentPerson
        ? {
            id: currentPerson.id,
            name: currentPerson.name,
            relationship: currentPerson.relationship,
            dateOfBirth: currentPerson.dateOfBirth,
            isDeceased: currentPerson.isDeceased,
            privacyLevel: currentPerson.privacyLevel,
            occupation: currentPerson.occupation,
            city: currentPerson.city,
            gotra: currentPerson.gotra,
          }
        : {
            id: currentPersonId,
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
    }

    return node
  }

  // Use a different approach: traverse upward via relationships
  const root = await buildAncestorTree(person.familyId, personId, depth, visited)

  return root
}

async function buildAncestorTree(
  familyId: string,
  personId: string,
  depth: number,
  visited: Set<string>
): Promise<TreeNode> {
  const person = await db.person.findUnique({
    where: { id: personId },
  })

  if (!person) {
    throw new Error('Person not found')
  }

  const node: TreeNode = {
    person: {
      id: person.id,
      name: person.name,
      relationship: person.relationship,
      dateOfBirth: person.dateOfBirth,
      isDeceased: person.isDeceased,
      privacyLevel: person.privacyLevel,
      occupation: person.occupation,
      city: person.city,
      gotra: person.gotra,
    },
    children: [],
  }

  if (depth <= 0) return node

  // Find parent relationships: where this person is a child
  const parentRels = await db.relationship.findMany({
    where: {
      familyId,
      toPersonId: personId,
      type: { in: ['child', 'son', 'daughter'] },
    },
    include: { fromPerson: true },
  })

  // Also find where this person is the toPerson with father/mother type
  const parentRels2 = await db.relationship.findMany({
    where: {
      familyId,
      fromPersonId: { not: personId },
      toPersonId: personId,
      type: { in: ['father', 'mother', 'parent'] },
    },
    include: { fromPerson: true },
  })

  // Combine: person is child, fromPerson is parent
  // OR fromPerson is father/mother of person (toPerson)
  const allParentRels = [...parentRels, ...parentRels2]

  for (const rel of allParentRels) {
    const parentId = rel.fromPersonId
    if (!visited.has(parentId)) {
      visited.add(parentId)
      const ancestorNode = await buildAncestorTree(familyId, parentId, depth - 1, visited)
      node.children.push(ancestorNode)
    }
  }

  return node
}

// ── Get Descendants ──────────────────────────────────────────────────

export async function getDescendants(personId: string, depth: number = 5): Promise<TreeNode> {
  const person = await db.person.findUnique({
    where: { id: personId },
  })

  if (!person) {
    throw new Error('Person not found')
  }

  const visited = new Set<string>([personId])

  async function buildDescendantNode(currentId: string, currentDepth: number): Promise<TreeNode> {
    const currentPerson = await db.person.findUnique({
      where: { id: currentId },
    })

    if (!currentPerson) {
      throw new Error('Person not found')
    }

    const node: TreeNode = {
      person: {
        id: currentPerson.id,
        name: currentPerson.name,
        relationship: currentPerson.relationship,
        dateOfBirth: currentPerson.dateOfBirth,
        isDeceased: currentPerson.isDeceased,
        privacyLevel: currentPerson.privacyLevel,
        occupation: currentPerson.occupation,
        city: currentPerson.city,
        gotra: currentPerson.gotra,
      },
      children: [],
    }

    if (currentDepth <= 0) return node

    // Find children: where this person is a parent
    const childRels = await db.relationship.findMany({
      where: {
        familyId: currentPerson.familyId,
        fromPersonId: currentId,
        type: { in: ['father', 'mother', 'parent'] },
      },
      include: { toPerson: true },
    })

    // Also find where someone is child/son/daughter of this person
    const childRels2 = await db.relationship.findMany({
      where: {
        familyId: currentPerson.familyId,
        toPersonId: currentId,
        type: { in: ['child', 'son', 'daughter'] },
      },
      include: { fromPerson: true },
    })

    const allChildRels = [...childRels, ...childRels2]

    for (const rel of allChildRels) {
      const childId = rel.type === 'father' || rel.type === 'mother' || rel.type === 'parent'
        ? rel.toPersonId
        : rel.fromPersonId
      if (!visited.has(childId)) {
        visited.add(childId)
        const childNode = await buildDescendantTree(currentPerson.familyId, childId, currentDepth - 1, visited)
        node.children.push(childNode)
      }
    }

    // Add spouse
    const spouseRel = await db.relationship.findFirst({
      where: {
        familyId: currentPerson.familyId,
        type: 'spouse',
        OR: [
          { fromPersonId: currentId },
          { toPersonId: currentId },
        ],
      },
      include: { fromPerson: true, toPerson: true },
    })

    if (spouseRel) {
      const spousePerson = spouseRel.fromPersonId === currentId ? spouseRel.toPerson : spouseRel.fromPerson
      node.spouse = {
        id: spousePerson.id,
        name: spousePerson.name,
        relationship: spousePerson.relationship,
        dateOfBirth: spousePerson.dateOfBirth,
        isDeceased: spousePerson.isDeceased,
        privacyLevel: spousePerson.privacyLevel,
        occupation: spousePerson.occupation,
        city: spousePerson.city,
        gotra: spousePerson.gotra,
      }
    }

    return node
  }

  return buildDescendantNode(personId, depth)
}

async function buildDescendantTree(
  familyId: string,
  personId: string,
  depth: number,
  visited: Set<string>
): Promise<TreeNode> {
  const person = await db.person.findUnique({
    where: { id: personId },
  })

  if (!person) {
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
    }
  }

  const node: TreeNode = {
    person: {
      id: person.id,
      name: person.name,
      relationship: person.relationship,
      dateOfBirth: person.dateOfBirth,
      isDeceased: person.isDeceased,
      privacyLevel: person.privacyLevel,
      occupation: person.occupation,
      city: person.city,
      gotra: person.gotra,
    },
    children: [],
  }

  if (depth <= 0) return node

  // Find children
  const childRels = await db.relationship.findMany({
    where: {
      familyId,
      fromPersonId: personId,
      type: { in: ['father', 'mother', 'parent'] },
    },
  })

  const childRels2 = await db.relationship.findMany({
    where: {
      familyId,
      toPersonId: personId,
      type: { in: ['child', 'son', 'daughter'] },
    },
  })

  const childIds = new Set<string>()
  for (const rel of childRels) childIds.add(rel.toPersonId)
  for (const rel of childRels2) childIds.add(rel.fromPersonId)

  for (const childId of childIds) {
    if (!visited.has(childId)) {
      visited.add(childId)
      const childNode = await buildDescendantTree(familyId, childId, depth - 1, visited)
      node.children.push(childNode)
    }
  }

  return node
}
