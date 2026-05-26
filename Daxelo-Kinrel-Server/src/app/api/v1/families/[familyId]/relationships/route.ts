// DAXELO KINREL — Pack 02: Relationships API
// GET/POST/DELETE /v1/families/:familyId/relationships (API Key auth)

import { NextRequest, NextResponse } from 'next/server'
import { z } from 'zod'
import { db } from '@/lib/db'
import { apiMiddleware } from '@/lib/api/middleware'
import { success, collection, error } from '@/lib/api/response'
import { handleIdempotency, storeResponse } from '@/lib/api/idempotency'
import { emit } from '@/lib/api/webhook-delivery'
import { apiVersionHeaders } from '@/lib/api/middleware'
import { validateAndNormalizeKey } from '@/lib/kinship-validator'

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

// ── GET /v1/families/:familyId/relationships ────────────────────────

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ familyId: string }> }
) {
  const { familyId } = await params
  const result = await apiMiddleware(request, {
    requiredScope: 'persons:read',
    endpoint: 'GET /v1/families/*/relationships',
  })

  if (result instanceof NextResponse) return result

  const { apiKey, rateLimitHeaders } = result

  // Check access
  const membership = await db.familyMember.findUnique({
    where: { familyId_userId: { familyId, userId: apiKey.userId } },
  })

  if (!membership) {
    return error('NOT_FOUND', 'Family not found or access denied', 404)
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

  const response = collection(filteredRelationships, {
    page,
    limit,
    total,
    hasMore: page * limit < total,
  })

  return new NextResponse(response.body, {
    status: response.status,
    headers: {
      ...Object.fromEntries(response.headers.entries()),
      ...rateLimitHeaders,
      ...apiVersionHeaders('1.0.0'),
    },
  })
}

// ── POST /v1/families/:familyId/relationships ───────────────────────

const createRelationshipSchema = z.object({
  fromPersonId: z.string().min(1),
  toPersonId: z.string().min(1),
  type: z.string().min(1).max(100),
})

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ familyId: string }> }
) {
  const { familyId } = await params
  const result = await apiMiddleware(request, {
    requiredScope: 'persons:write',
    endpoint: 'POST /v1/families/*/relationships',
  })

  if (result instanceof NextResponse) return result

  const { apiKey, rateLimitHeaders } = result

  // Check access — member or above
  const membership = await db.familyMember.findUnique({
    where: { familyId_userId: { familyId, userId: apiKey.userId } },
  })

  if (!membership) {
    return error('NOT_FOUND', 'Family not found or access denied', 404)
  }

  if (!['admin', 'editor', 'member'].includes(membership.role)) {
    return error('INSUFFICIENT_SCOPE', 'Member role or above required to create relationships', 403)
  }

  // Check idempotency
  const idempotencyKey = request.headers.get('Idempotency-Key')
  if (idempotencyKey) {
    const idemResult = await handleIdempotency(idempotencyKey)
    if (idemResult.isDuplicate && idemResult.response) {
      return new NextResponse(JSON.stringify(idemResult.response.body), {
        status: idemResult.response.status,
        headers: {
          ...rateLimitHeaders,
          ...apiVersionHeaders('1.0.0'),
          ...idemResult.response.headers,
          'X-Idempotent-Replayed': 'true',
        },
      })
    }
  }

  // Parse body
  const body = await request.json().catch(() => null)
  if (!body) {
    return error('INVALID_PARAMETER', 'Invalid JSON body', 400)
  }

  const parsed = createRelationshipSchema.safeParse(body)
  if (!parsed.success) {
    const details = parsed.error.issues.map(issue => ({
      path: issue.path.join('.'),
      message: issue.message,
    }))
    return error('VALIDATION_ERROR', 'Request validation failed', 400, details)
  }

  const data = parsed.data

  // Validate and normalize relationship type
  const normalizedType = validateAndNormalizeKey(data.type)
  if (!normalizedType) {
    return error('VALIDATION_ERROR', `Invalid relationship type: "${data.type}". Please provide a valid kinship term.`, 422)
  }

  // Cannot relate person to themselves
  if (data.fromPersonId === data.toPersonId) {
    return error('VALIDATION_ERROR', 'Cannot create a relationship from a person to themselves', 422)
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
    return error('NOT_FOUND', 'From person not found in this family or is deleted', 404)
  }

  if (!toPerson) {
    return error('NOT_FOUND', 'To person not found in this family or is deleted', 404)
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
    return error('ALREADY_EXISTS', `Relationship of type "${normalizedType}" already exists between these persons`, 409)
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

  // Emit webhook event
  await emit('relationship.created', {
    relationshipId: relationship.id,
    familyId,
    fromPersonId: data.fromPersonId,
    toPersonId: data.toPersonId,
    type: normalizedType,
  }, familyId)

  // Audit log
  await db.auditLog.create({
    data: {
      userId: apiKey.userId,
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

  const response = success(relationship)

  // Store idempotency response
  if (idempotencyKey) {
    await storeResponse(idempotencyKey, await response.json(), response.status, {})
  }

  return new NextResponse(response.body, {
    status: 201,
    headers: {
      ...Object.fromEntries(response.headers.entries()),
      ...rateLimitHeaders,
      ...apiVersionHeaders('1.0.0'),
    },
  })
}

// ── DELETE /v1/families/:familyId/relationships ─────────────────────

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ familyId: string }> }
) {
  const { familyId } = await params
  const result = await apiMiddleware(request, {
    requiredScope: 'persons:write',
    endpoint: 'DELETE /v1/families/*/relationships',
  })

  if (result instanceof NextResponse) return result

  const { apiKey, rateLimitHeaders } = result

  // Check access — editor or above
  const membership = await db.familyMember.findUnique({
    where: { familyId_userId: { familyId, userId: apiKey.userId } },
  })

  if (!membership) {
    return error('NOT_FOUND', 'Family not found or access denied', 404)
  }

  if (!['admin', 'editor'].includes(membership.role)) {
    return error('INSUFFICIENT_SCOPE', 'Editor role or above required to delete relationships', 403)
  }

  // Get relationship ID from query params
  const url = new URL(request.url)
  const relationshipId = url.searchParams.get('id')

  if (!relationshipId) {
    return error('MISSING_REQUIRED_FIELD', 'Relationship ID is required as query parameter "?id=xxx"', 400)
  }

  // Find the relationship
  const relationship = await db.relationship.findFirst({
    where: { id: relationshipId, familyId },
  })

  if (!relationship) {
    return error('NOT_FOUND', 'Relationship not found', 404)
  }

  // Delete the relationship and its inverse in a transaction
  await db.$transaction(async (tx) => {
    // Delete the primary relationship
    await tx.relationship.delete({
      where: { id: relationshipId },
    })

    // Find and delete the inverse relationship
    // The inverse would have swapped fromPersonId/toPersonId and the inverse type
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

  // Emit webhook event
  await emit('relationship.deleted', {
    relationshipId,
    familyId,
  }, familyId)

  // Audit log
  await db.auditLog.create({
    data: {
      userId: apiKey.userId,
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

  return new NextResponse(null, {
    status: 204,
    headers: {
      ...rateLimitHeaders,
      ...apiVersionHeaders('1.0.0'),
    },
  })
}
