// DAXELO KINREL — Pack 10: Admin Users API
// GET /api/admin/users — List all users (admin only)

import { NextRequest, NextResponse } from 'next/server'
import { getServerSession } from 'next-auth'
import { authOptions } from '@/lib/auth'
import { db } from '@/lib/db'

export async function GET(request: NextRequest) {
  const session = await getServerSession(authOptions)
  if (!session?.user?.id) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  if ((session.user as Record<string, unknown>).role !== 'admin') {
    return NextResponse.json({ error: 'Forbidden — admin access required' }, { status: 403 })
  }

  const url = new URL(request.url)
  const page = Math.max(1, parseInt(url.searchParams.get('page') || '1'))
  const limit = Math.min(100, Math.max(1, parseInt(url.searchParams.get('limit') || '20')))
  const search = url.searchParams.get('search') || ''
  const role = url.searchParams.get('role')

  // Build where clause
  const where: Record<string, unknown> = {}

  if (search) {
    where.OR = [
      { name: { contains: search } },
      { email: { contains: search } },
      { phone: { contains: search } },
    ]
  }

  if (role) {
    where.role = role
  }

  const [users, total] = await Promise.all([
    db.user.findMany({
      where,
      select: {
        id: true,
        email: true,
        name: true,
        phone: true,
        role: true,
        preferredLanguage: true,
        createdAt: true,
        updatedAt: true,
        subscription: {
          select: { plan: true, status: true },
        },
        families: {
          select: { familyId: true, role: true },
        },
      },
      orderBy: { createdAt: 'desc' },
      skip: (page - 1) * limit,
      take: limit,
    }),
    db.user.count({ where }),
  ])

  return NextResponse.json({
    users,
    pagination: {
      page,
      limit,
      total,
      hasMore: page * limit < total,
      totalPages: Math.ceil(total / limit),
    },
  })
}
