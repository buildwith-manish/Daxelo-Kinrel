// DAXELO KINREL — Pack 02: Relationships API (Internal, Session Auth)
// GET/POST/DELETE /api/families/:familyId/relationships

import { getServerSession } from 'next-auth'
import { authOptions } from '@/lib/auth'
import { db } from '@/lib/db'
import { NextRequest, NextResponse } from 'next/server'
import { z } from 'zod'
import { validateAndNormalizeKey } from '@/lib/kinship-validator'

// ── Auth Helpers ────────────────────────────────────────────────────

async function requireAuth() {
  const session = await getServerSession(authOptions)
  if (!session?.user?.id) return null
  return session
}

async function requireFamilyMember(familyId: string, userId: string, minRole?: string[]) {
  const membership = await db.familyMember.findUnique({
    where: { familyId_userId: { familyId, userId } },
  })
  if (!membership) return null
  if (minRole && !minRole.includes(membership.role)) return null
  return membership
}

// ── Inverse Relationship Map ────────────────────────────────────────

const INVERSE_RELATIONSHIP_MAP: Record<string, string> = {
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
}

function getInverseRelationship(type: string): string {
  return INVERSE_RELATIONSHIP_MAP[type] || 'related_to'
}

// ── GET /api/families/:familyId/relationships ───────────────────────

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ familyId: string }> }
) {
  const session = await requireAuth()
  if (!session) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const { familyId } = await params

  const membership = await requireFamilyMember(familyId, session.user.id)
  if (!membership) {
    return NextResponse.json({ error: 'Family not found or access denied' }, { status: 404 })
  }

  const url = new URL(request.url)
  const personId = url.searchParams.get('personId') || undefined
  const page = Math.max(1, parseInt(url.searchParams.get('page') || '1'))
  const limit = Math.min(100, Math.max(1, parseInt(url.searchParams.get('limit') || '20')))

  const where: any = { familyId }

  if (personId) {
    where.OR = [
      { fromPersonId: personId },
      { toPersonId: personId },
    ]
  }

  const [relationships, total] = await Promise.all([
    db.relationship.findMany({
      where,
      include: {
        fromPerson: { where: { deletedAt: null } },
        toPerson: { where: { deletedAt: null } },
      },
      orderBy: { createdAt: 'desc' },
      skip: (page - 1) * limit,
      take: limit,
    }),
    db.relationship.count({ where }),
  ])

  // Filter out relationships where either person is soft-deleted
  const filteredRelationships = relationships.filter(
    (r) => r.fromPerson !== null && r.toPerson !== null
  )

  return NextResponse.json({
    data: filteredRelationships,
    pagination: {
      page,
      limit,
      total,
      hasMore: page * limit < total,
      totalPages: Math.ceil(total / limit),
    },
  })
}

// ── POST /api/families/:familyId/relationships ──────────────────────

const createRelationshipSchema = z.object({
  fromPersonId: z.string().min(1),
  toPersonId: z.string().min(1),
  type: z.string().min(1).max(100),
})

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ familyId: string }> }
) {
  const session = await requireAuth()
  if (!session) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const { familyId } = await params

  // Member or above required
  const membership = await requireFamilyMember(familyId, session.user.id, ['admin', 'editor', 'member'])
  if (!membership) {
    const baseMembership = await requireFamilyMember(familyId, session.user.id)
    if (!baseMembership) {
      return NextResponse.json({ error: 'Family not found or access denied' }, { status: 404 })
    }
    return NextResponse.json({ error: 'Member role or above required to create relationships' }, { status: 403 })
  }

  // Parse body
  const body = await request.json().catch(() => null)
  if (!body) {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 })
  }

  const parsed = createRelationshipSchema.safeParse(body)
  if (!parsed.success) {
    return NextResponse.json({
      error: 'Validation failed',
      details: parsed.error.issues.map(issue => ({
        path: issue.path.join('.'),
        message: issue.message,
      })),
    }, { status: 400 })
  }

  const data = parsed.data

  // Validate and normalize relationship type
  const normalizedType = validateAndNormalizeKey(data.type)
  if (!normalizedType) {
    return NextResponse.json({
      error: `Invalid relationship type: "${data.type}". Please provide a valid kinship term.`,
    }, { status: 422 })
  }

  // Cannot relate person to themselves
  if (data.fromPersonId === data.toPersonId) {
    return NextResponse.json({
      error: 'Cannot create a relationship from a person to themselves',
    }, { status: 422 })
  }

  // Check both persons exist, belong to the family, and are not soft-deleted
  const [fromPerson, toPerson] = await Promise.all([
    db.person.findFirst({
      where: { id: data.fromPersonId, familyId, deletedAt: null },
    }),
    db.person.findFirst({
      where: { id: data.toPersonId, familyId, deletedAt: null },
    }),
  ])

  if (!fromPerson) {
    return NextResponse.json({ error: 'From person not found in this family or is deleted' }, { status: 404 })
  }

  if (!toPerson) {
    return NextResponse.json({ error: 'To person not found in this family or is deleted' }, { status: 404 })
  }

  // Check for duplicate relationship
  const existing = await db.relationship.findFirst({
    where: {
      familyId,
      fromPersonId: data.fromPersonId,
      toPersonId: data.toPersonId,
      type: normalizedType,
    },
  })

  if (existing) {
    return NextResponse.json({
      error: `Relationship of type "${normalizedType}" already exists between these persons`,
    }, { status: 409 })
  }

  // Calculate inverse type
  const inverseType = getInverseRelationship(normalizedType)

  // Create relationship and inverse in a transaction
  const relationship = await db.$transaction(async (tx) => {
    const rel = await tx.relationship.create({
      data: {
        familyId,
        fromPersonId: data.fromPersonId,
        toPersonId: data.toPersonId,
        type: normalizedType,
        direction: 'from',
      },
      include: {
        fromPerson: true,
        toPerson: true,
      },
    })

    // Check if inverse already exists before creating
    const existingInverse = await tx.relationship.findFirst({
      where: {
        familyId,
        fromPersonId: data.toPersonId,
        toPersonId: data.fromPersonId,
        type: inverseType,
      },
    })

    if (!existingInverse) {
      await tx.relationship.create({
        data: {
          familyId,
          fromPersonId: data.toPersonId,
          toPersonId: data.fromPersonId,
          type: inverseType,
          direction: 'from',
        },
      })
    }

    return rel
  })

  // Audit log
  await db.auditLog.create({
    data: {
      userId: session.user.id,
      action: 'RELATIONSHIP_CREATED',
      resource: 'Relationship',
      resourceId: relationship.id,
      details: JSON.stringify({
        familyId,
        fromPersonId: data.fromPersonId,
        toPersonId: data.toPersonId,
        type: normalizedType,
        inverseType,
      }),
    },
  })

  return NextResponse.json({ data: relationship }, { status: 201 })
}

// ── DELETE /api/families/:familyId/relationships ────────────────────

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ familyId: string }> }
) {
  const session = await requireAuth()
  if (!session) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const { familyId } = await params

  // Editor or above required
  const membership = await requireFamilyMember(familyId, session.user.id, ['admin', 'editor'])
  if (!membership) {
    const baseMembership = await requireFamilyMember(familyId, session.user.id)
    if (!baseMembership) {
      return NextResponse.json({ error: 'Family not found or access denied' }, { status: 404 })
    }
    return NextResponse.json({ error: 'Editor role or above required to delete relationships' }, { status: 403 })
  }

  // Get relationship ID from query params
  const url = new URL(request.url)
  const relationshipId = url.searchParams.get('id')

  if (!relationshipId) {
    return NextResponse.json({
      error: 'Relationship ID is required as query parameter "?id=xxx"',
    }, { status: 400 })
  }

  // Find the relationship
  const relationship = await db.relationship.findFirst({
    where: { id: relationshipId, familyId },
  })

  if (!relationship) {
    return NextResponse.json({ error: 'Relationship not found' }, { status: 404 })
  }

  // Delete the relationship and its inverse in a transaction
  await db.$transaction(async (tx) => {
    // Delete the primary relationship
    await tx.relationship.delete({
      where: { id: relationshipId },
    })

    // Find and delete the inverse relationship
    const inverseType = getInverseRelationship(relationship.type)

    const inverse = await tx.relationship.findFirst({
      where: {
        familyId,
        fromPersonId: relationship.toPersonId,
        toPersonId: relationship.fromPersonId,
        type: inverseType,
      },
    })

    if (inverse) {
      await tx.relationship.delete({
        where: { id: inverse.id },
      })
    }
  })

  // Audit log
  await db.auditLog.create({
    data: {
      userId: session.user.id,
      action: 'RELATIONSHIP_DELETED',
      resource: 'Relationship',
      resourceId: relationshipId,
      details: JSON.stringify({
        familyId,
        fromPersonId: relationship.fromPersonId,
        toPersonId: relationship.toPersonId,
        type: relationship.type,
      }),
    },
  })

  return new NextResponse(null, { status: 204 })
}
