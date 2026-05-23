// DAXELO KINREL — Create/List Support Tickets
// Pack 02: Support & Operations — API Route

import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { z } from 'zod'
import { routeTicket } from '@/lib/support/ticket-router'
import { getUserSupportTier, tierMaxResponseTime } from '@/lib/support/tier-calculator'
import { generateTicketNumber } from '@/lib/support/ticket-number'

const createTicketSchema = z.object({
  category: z.enum([
    'billing', 'account', 'data_loss', 'bug', 'feature_request',
    'general', 'matrimonial', 'verification', 'privacy',
  ]),
  subcategory: z.string().optional(),
  severity: z.enum(['critical', 'high', 'medium', 'low']).default('medium'),
  subject: z.string().min(5).max(255),
  description: z.string().min(10),
  attachments: z.array(z.string().url()).max(5).optional(),
  appVersion: z.string().optional(),
  platform: z.enum(['android', 'ios', 'web']).optional(),
  deviceInfo: z.string().optional(),
})

export async function POST(request: NextRequest) {
  try {
    const userId = request.headers.get('X-User-Id')
    if (!userId) {
      return NextResponse.json({ error: 'Unauthorized — X-User-Id header required' }, { status: 401 })
    }

    // Ensure user exists
    const user = await db.user.findUnique({ where: { id: userId } })
    if (!user) {
      return NextResponse.json({ error: 'User not found' }, { status: 404 })
    }

    const body = await request.json()
    const parsed = createTicketSchema.safeParse(body)
    if (!parsed.success) {
      return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 })
    }

    const data = parsed.data
    const tier = await getUserSupportTier(userId)
    const maxResponseHours = tierMaxResponseTime(tier)

    // Generate human-readable ticket number
    const ticketNumber = await generateTicketNumber()

    // Calculate SLA deadlines
    const now = new Date()
    const firstResponseDeadline = new Date(now.getTime() + maxResponseHours * 60 * 60 * 1000)
    const resolutionDeadline = new Date(now.getTime() + maxResponseHours * 4 * 60 * 60 * 1000)

    const ticket = await db.supportTicket.create({
      data: {
        ticketNumber,
        userId,
        category: data.category,
        subcategory: data.subcategory,
        severity: data.severity,
        subject: data.subject,
        description: data.description,
        attachments: JSON.stringify(data.attachments ?? []),
        appVersion: data.appVersion,
        platform: data.platform,
        deviceInfo: data.deviceInfo ? JSON.stringify({ info: data.deviceInfo }) : null,
        slaTier: tier,
        firstResponseDeadline,
        resolutionDeadline,
        language: user.preferredLanguage ?? 'en',
      },
    })

    // Route ticket to agent/queue
    const routing = await routeTicket(ticket.id)

    // Update ticket with routing info
    await db.supportTicket.update({
      where: { id: ticket.id },
      data: {
        assignedAgentId: routing.assignedAgentId,
        queue: routing.queue,
        priority: routing.priority,
      },
    })

    return NextResponse.json({
      ticket: {
        id: ticket.id,
        ticketNumber: ticket.ticketNumber,
        status: ticket.status,
        category: ticket.category,
        severity: ticket.severity,
        slaTier: ticket.slaTier,
        estimatedResponseHours: routing.estimatedResponseHours,
        queue: routing.queue,
        priority: routing.priority,
        firstResponseDeadline: ticket.firstResponseDeadline,
        resolutionDeadline: ticket.resolutionDeadline,
        createdAt: ticket.createdAt,
      },
    }, { status: 201 })
  } catch (error) {
    console.error('[Support Tickets POST] Error:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url)
    const status = searchParams.get('status')
    const page = parseInt(searchParams.get('page') ?? '1')
    const limit = parseInt(searchParams.get('limit') ?? '20')

    const where: Record<string, unknown> = {}
    if (status) where.status = status

    const [tickets, total] = await Promise.all([
      db.supportTicket.findMany({
        where,
        include: {
          user: { select: { id: true, name: true, email: true } },
          assignedAgent: { select: { id: true, name: true } },
          csat: { select: { rating: true } },
          messages: { take: 1, orderBy: { createdAt: 'desc' } },
        },
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * limit,
        take: limit,
      }),
      db.supportTicket.count({ where }),
    ])

    return NextResponse.json({ tickets, total, page, limit })
  } catch (error) {
    console.error('[Support Tickets GET] Error:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
