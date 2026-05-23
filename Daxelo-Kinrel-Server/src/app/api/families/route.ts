import { NextRequest, NextResponse } from 'next/server'
import { getServerSession } from 'next-auth'
import { authOptions } from '@/lib/auth'
import { db } from '@/lib/db'

// ── GET /api/families — List user's families ────────────────────────────

export async function GET() {
  const session = await getServerSession(authOptions)

  if (!session?.user?.id) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const memberships = await db.familyMember.findMany({
    where: { userId: session.user.id },
    include: {
      family: {
        include: {
          _count: {
            select: { members: true, persons: true },
          },
        },
      },
    },
    orderBy: { joinedAt: 'desc' },
  })

  const families = memberships.map((m) => ({
    id: m.family.id,
    name: m.family.name,
    description: m.family.description,
    primaryLanguage: m.family.primaryLanguage,
    gotra: m.family.gotra,
    originVillage: m.family.originVillage,
    role: m.role,
    memberCount: m.family._count.members,
    personCount: m.family._count.persons,
    createdAt: m.family.createdAt,
    updatedAt: m.family.updatedAt,
  }))

  return NextResponse.json({ families })
}

// ── POST /api/families — Create family ─────────────────────────────────

export async function POST(request: NextRequest) {
  const session = await getServerSession(authOptions)

  if (!session?.user?.id) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const body = await request.json().catch(() => null)
  if (!body) {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 })
  }

  const { name, description, primaryLanguage, gotra, originVillage } = body

  if (!name || typeof name !== 'string' || name.trim().length === 0) {
    return NextResponse.json(
      { error: 'Family name is required' },
      { status: 400 }
    )
  }

  // Create family
  const family = await db.family.create({
    data: {
      name: name.trim(),
      description: description?.trim() || null,
      primaryLanguage: primaryLanguage || 'en',
      gotra: gotra?.trim() || null,
      originVillage: originVillage?.trim() || null,
    },
  })

  // Add creator as admin
  await db.familyMember.create({
    data: {
      familyId: family.id,
      userId: session.user.id,
      role: 'admin',
    },
  })

  // Audit log
  await db.auditLog.create({
    data: {
      userId: session.user.id,
      action: 'FAMILY_CREATED',
      resource: 'Family',
      resourceId: family.id,
      details: JSON.stringify({ name: family.name }),
    },
  })

  return NextResponse.json(
    {
      family: {
        id: family.id,
        name: family.name,
        description: family.description,
        primaryLanguage: family.primaryLanguage,
        gotra: family.gotra,
        originVillage: family.originVillage,
        memberCount: 1,
        personCount: 0,
        role: 'admin',
        createdAt: family.createdAt,
        updatedAt: family.updatedAt,
      },
    },
    { status: 201 }
  )
}
