// DAXELO KINREL — Ticket Messages
// Pack 02: Support & Operations — API Route

import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { z } from 'zod'

const messageSchema = z.object({
  content: z.string().min(1).max(5000),
  attachments: z.array(z.string()).max(5).optional(),
  channel: z.enum(['in_app', 'email', 'whatsapp', 'phone']).default('in_app'),
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

    const body = await request.json()
    const parsed = messageSchema.safeParse(body)
    if (!parsed.success) {
      return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 })
    }

    const data = parsed.data

    // Reopen if ticket was resolved
    if (ticket.status === 'resolved' || ticket.status === 'closed') {
      await db.supportTicket.update({
        where: { id: ticketId },
        data: { status: 'open', resolvedAt: null },
      })
    }

    const user = await db.user.findUnique({ where: { id: userId } })

    const message = await db.supportMessage.create({
      data: {
        ticketId,
        senderType: 'user',
        senderId: userId,
        senderName: user?.name ?? 'User',
        content: data.content,
        attachments: JSON.stringify(data.attachments ?? []),
        channel: data.channel,
      },
    })

    return NextResponse.json({ message }, { status: 201 })
  } catch (error) {
    console.error('[Ticket Messages POST] Error:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}

export async function GET(
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

    const messages = await db.supportMessage.findMany({
      where: { ticketId, isInternal: false },
      orderBy: { createdAt: 'asc' },
    })

    return NextResponse.json({ messages })
  } catch (error) {
    console.error('[Ticket Messages GET] Error:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
