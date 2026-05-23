// DAXELO KINREL — SLA Credits Calculator
// Pack 02: Support & Operations

import { db } from '@/lib/db'

export interface SLACredit {
  userId: string
  creditType: string // refund or extension
  creditValue: number // INR for refund, days for extension
  reason: string
}

/**
 * Calculate SLA credits for a given month.
 * VIP: 10% of lifetime fee per incident (₹500)
 * Premium: 30-day extension
 * Standard: 7-day extension
 * Basic: no credit
 */
export async function calculateSLACredits(month: string): Promise<SLACredit[]> {
  const credits: SLACredit[] = []

  const monthStart = new Date(`${month}-01T00:00:00.000Z`)
  const monthEnd = new Date(monthStart)
  monthEnd.setMonth(monthEnd.getMonth() + 1)

  const breaches = await db.supportTicket.findMany({
    where: {
      slaBreached: true,
      resolvedAt: { not: null },
      createdAt: {
        gte: monthStart,
        lt: monthEnd,
      },
    },
    include: { user: { include: { subscription: true } } },
  })

  for (const ticket of breaches) {
    const tier = ticket.slaTier as 'basic' | 'standard' | 'premium' | 'vip'
    const sub = ticket.user.subscription

    if (!sub || sub.plan === 'free') continue

    switch (tier) {
      case 'vip':
        credits.push({
          userId: ticket.userId,
          creditType: 'refund',
          creditValue: 4999 * 0.10, // ₹500 per incident
          reason: `SLA breach on ticket ${ticket.ticketNumber}`,
        })
        break

      case 'premium':
        credits.push({
          userId: ticket.userId,
          creditType: 'extension',
          creditValue: 30, // days
          reason: `SLA breach on ticket ${ticket.ticketNumber}`,
        })
        break

      case 'standard':
        credits.push({
          userId: ticket.userId,
          creditType: 'extension',
          creditValue: 7, // days
          reason: `SLA breach on ticket ${ticket.ticketNumber}`,
        })
        break
    }
  }

  return credits
}

/**
 * Get SLA compliance report for a given month.
 */
export async function getSLAReport(month: string) {
  const monthStart = new Date(`${month}-01T00:00:00.000Z`)
  const monthEnd = new Date(monthStart)
  monthEnd.setMonth(monthEnd.getMonth() + 1)

  const tickets = await db.supportTicket.findMany({
    where: {
      status: { in: ['resolved', 'closed'] },
      createdAt: { gte: monthStart, lt: monthEnd },
    },
    select: {
      slaTier: true,
      slaBreached: true,
      firstResponseAt: true,
      createdAt: true,
      resolvedAt: true,
    },
  })

  // Group by tier
  const tiers = ['basic', 'standard', 'premium', 'vip'] as const
  const report = tiers.map(tier => {
    const tierTickets = tickets.filter(t => t.slaTier === tier)
    const metSla = tierTickets.filter(t => !t.slaBreached).length
    const total = tierTickets.length

    // Calculate average response and resolution times
    const responseTimes = tierTickets
      .filter(t => t.firstResponseAt)
      .map(t => (t.firstResponseAt!.getTime() - t.createdAt.getTime()) / 60_000) // minutes

    const resolutionTimes = tierTickets
      .filter(t => t.resolvedAt)
      .map(t => (t.resolvedAt!.getTime() - t.createdAt.getTime()) / 3_600_000) // hours

    return {
      tier,
      totalTickets: total,
      metSla,
      compliancePct: total > 0 ? Math.round((metSla / total) * 100 * 100) / 100 : 0,
      avgFirstResponseMin: responseTimes.length > 0
        ? Math.round(responseTimes.reduce((a, b) => a + b, 0) / responseTimes.length)
        : null,
      avgResolutionHours: resolutionTimes.length > 0
        ? Math.round(resolutionTimes.reduce((a, b) => a + b, 0) / resolutionTimes.length * 100) / 100
        : null,
      breaches: total - metSla,
    }
  })

  return { month, report }
}
