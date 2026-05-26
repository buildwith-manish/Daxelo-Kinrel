// DAXELO KINREL — CSAT Rating
// Pack 02: Support & Operations — API Route

import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { z } from 'zod'

const csatSchema = z.object({
  rating: z.number().int().min(1).max(5),
  comment: z.string().max(1000).optional(),
})

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ ticketId: string }> }
) {
  try {
    const userId = request.headers.get('X-User-Id')
    if (!userId) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }

    const { ticketId } = await params
    const ticket = await db.supportTicket.findUnique({ where: { id: ticketId } })

    if (!ticket || ticket.userId !== userId) {
      return NextResponse.json({ error: 'Not found' }, { status: 404 })
    }

    if (ticket.status !== 'resolved' && ticket.status !== 'closed') {
      return NextResponse.json({ error: 'CSAT can only be submitted for resolved tickets' }, { status: 400 })
    }

    // Check if CSAT already exists
    const existing = await db.supportCSAT.findUnique({ where: { ticketId } })
    if (existing) {
      return NextResponse.json({ error: 'CSAT already submitted for this ticket' }, { status: 409 })
    }

    const body = await request.json()
    const parsed = csatSchema.safeParse(body)
    if (!parsed.success) {
      return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 })
    }

    const csat = await db.supportCSAT.create({
      data: {
        ticketId,
        rating: parsed.data.rating,
        comment: parsed.data.comment,
      },
    })

    return NextResponse.json({ csat }, { status: 201 })
  } catch (error) {
    console.error('[CSAT POST] Error:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
