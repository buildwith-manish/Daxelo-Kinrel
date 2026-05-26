// DAXELO KINREL — Pack 02: Persons API (Internal, Session Auth)
// GET/POST /api/families/:familyId/persons

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

// ── GET /api/families/:familyId/persons ─────────────────────────────

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
  const page = Math.max(1, parseInt(url.searchParams.get('page') || '1'))
  const limit = Math.min(100, Math.max(1, parseInt(url.searchParams.get('limit') || '20')))
  const includeRelationships = url.searchParams.get('includeRelationships') === 'true'

  // Filtering
  const deceased = url.searchParams.get('deceased')
  const search = url.searchParams.get('search') || ''
  const sort = url.searchParams.get('sort') || 'createdAt'
  const order = url.searchParams.get('order') || 'desc'

  const where: any = {
    familyId,
    deletedAt: null, // Always filter out soft-deleted persons
  }

  if (deceased === 'true') where.isDeceased = true
  if (deceased === 'false') where.isDeceased = false
  if (search) {
    where.OR = [
      { name: { contains: search } },
      { relationship: { contains: search } },
      { occupation: { contains: search } },
      { city: { contains: search } },
    ]
  }

  const include = includeRelationships
    ? {
        relationshipsFrom: true,
        relationshipsTo: true,
      }
    : {}

  const [persons, total] = await Promise.all([
    db.person.findMany({
      where,
      include,
      orderBy: { [sort]: order === 'asc' ? 'asc' : 'desc' },
      skip: (page - 1) * limit,
      take: limit,
    }),
    db.person.count({ where }),
  ])

  return NextResponse.json({
    data: persons,
    pagination: {
      page,
      limit,
      total,
      hasMore: page * limit < total,
      totalPages: Math.ceil(total / limit),
    },
  })
}

// ── POST /api/families/:familyId/persons ────────────────────────────

const createPersonSchema = z.object({
  name: z.string().min(1).max(200),
  relationship: z.string().min(1).max(100),
  dateOfBirth: z.string().optional(),
  gotra: z.string().max(100).optional(),
  occupation: z.string().max(200).optional(),
  city: z.string().max(200).optional(),
  isDeceased: z.boolean().default(false),
  privacyLevel: z.enum(['family', 'extended', 'public']).default('family'),
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
    return NextResponse.json({ error: 'Member role or above required to add persons' }, { status: 403 })
  }

  // Parse body
  const body = await request.json().catch(() => null)
  if (!body) {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 })
  }

  const parsed = createPersonSchema.safeParse(body)
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

  // Validate and normalize relationship key
  const normalizedKey = validateAndNormalizeKey(data.relationship)
  if (!normalizedKey) {
    return NextResponse.json({
      error: `Invalid relationship key: "${data.relationship}". Please provide a valid kinship term.`,
    }, { status: 422 })
  }

  // Verify family exists
  const family = await db.family.findUnique({ where: { id: familyId } })
  if (!family) {
    return NextResponse.json({ error: 'Family not found' }, { status: 404 })
  }

  // Create person with normalized relationship
  const person = await db.person.create({
    data: {
      familyId,
      name: data.name,
      relationship: normalizedKey,
      dateOfBirth: data.dateOfBirth ? new Date(data.dateOfBirth) : null,
      gotra: data.gotra,
      occupation: data.occupation,
      city: data.city,
      isDeceased: data.isDeceased,
      privacyLevel: data.privacyLevel,
    },
  })

  // Audit log
  await db.auditLog.create({
    data: {
      userId: session.user.id,
      action: 'PERSON_CREATED',
      resource: 'Person',
      resourceId: person.id,
      details: JSON.stringify({ name: data.name, familyId, relationship: normalizedKey }),
    },
  })

  return NextResponse.json({ data: person }, { status: 201 })
}
