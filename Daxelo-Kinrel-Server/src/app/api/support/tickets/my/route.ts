// DAXELO KINREL — User's Tickets
// Pack 02: Support & Operations — API Route

import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'

export async function GET(request: NextRequest) {
  try {
    const userId = request.headers.get('X-User-Id')
    if (!userId) {
      return NextResponse.json({ error: 'Unauthorized — X-User-Id header required' }, { status: 401 })
    }

    const { searchParams } = new URL(request.url)
    const status = searchParams.get('status')
    const page = parseInt(searchParams.get('page') ?? '1')
    const limit = parseInt(searchParams.get('limit') ?? '20')

    const where: Record<string, unknown> = { userId }
    if (status) where.status = status

    const [tickets, total] = await Promise.all([
      db.supportTicket.findMany({
        where,
        include: {
          messages: { take: 1, orderBy: { createdAt: 'desc' } },
          assignedAgent: { select: { name: true } },
          csat: { select: { rating: true } },
        },
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * limit,
        take: limit,
      }),
      db.supportTicket.count({ where }),
    ])

    return NextResponse.json({ tickets, total, page, limit })
  } catch (error) {
    console.error('[My Tickets GET] Error:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
