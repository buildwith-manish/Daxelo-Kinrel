// DAXELO KINREL — SLA Monitor
// Pack 02: Support & Operations

import { db } from '@/lib/db'

/**
 * Check for SLA breaches and approaching deadlines.
 * Should be called periodically (e.g., every 5 minutes via cron).
 */
export async function checkSLABreaches(): Promise<void> {
  const now = new Date()

  // ── First Response SLA ────────────────────────────────────────
  const approachingResponse = await db.supportTicket.findMany({
    where: {
      status: { in: ['open', 'in_progress', 'waiting_customer', 'waiting_third_party'] },
      firstResponseDeadline: { lte: new Date(now.getTime() + 30 * 60 * 1000) }, // Within 30 min
      firstResponseAt: null,
      slaBreached: false,
    },
    include: { assignedAgent: true },
  })

  for (const ticket of approachingResponse) {
    if (!ticket.firstResponseDeadline) continue

    const minutesLeft = Math.round(
      (ticket.firstResponseDeadline.getTime() - now.getTime()) / 60_000
    )

    if (minutesLeft <= 0) {
      // SLA BREACHED
      await db.supportTicket.update({
        where: { id: ticket.id },
        data: { slaBreached: true },
      })

      await db.sLATracking.create({
        data: {
          ticketId: ticket.id,
          type: 'first_response',
          tier: ticket.slaTier,
          deadline: ticket.firstResponseDeadline,
          breached: true,
          breachDuration: Math.abs(minutesLeft),
        },
      })

      await escalateSLABreach(ticket.id, ticket.ticketNumber, ticket.slaTier, ticket.category, ticket.assignedAgent?.name ?? 'Unassigned')
    } else if (minutesLeft <= 30) {
      await notifyAgentSLAWarning(ticket.id, ticket.ticketNumber, minutesLeft, ticket.assignedAgentId)
    }
  }

  // ── Resolution SLA ────────────────────────────────────────────
  const approachingResolution = await db.supportTicket.findMany({
    where: {
      status: { in: ['open', 'in_progress', 'waiting_third_party'] },
      resolutionDeadline: { lte: new Date(now.getTime() + 60 * 60 * 1000) },
      resolvedAt: null,
      slaBreached: false,
    },
  })

  for (const ticket of approachingResolution) {
    if (!ticket.resolutionDeadline) continue

    const minutesLeft = Math.round(
      (ticket.resolutionDeadline.getTime() - now.getTime()) / 60_000
    )

    if (minutesLeft <= 0) {
      await db.supportTicket.update({
        where: { id: ticket.id },
        data: { slaBreached: true },
      })

      await db.sLATracking.create({
        data: {
          ticketId: ticket.id,
          type: 'resolution',
          tier: ticket.slaTier,
          deadline: ticket.resolutionDeadline,
          breached: true,
          breachDuration: Math.abs(minutesLeft),
        },
      })

      await escalateSLABreach(ticket.id, ticket.ticketNumber, ticket.slaTier, ticket.category, ticket.assignedAgentId ? 'Assigned' : 'Unassigned')
    }
  }
}

async function escalateSLABreach(
  ticketId: string,
  ticketNumber: string,
  tier: string,
  category: string,
  assignedAgent: string
): Promise<void> {
  // Log the escalation (in production, this would send PagerDuty alert)
  console.error(`[SLA BREACH] Ticket ${ticketNumber} (${tier}) — Category: ${category}, Agent: ${assignedAgent}`)

  // Create escalation record
  await db.supportEscalation.create({
    data: {
      ticketId,
      reason: 'sla_breach',
      notes: `SLA breach for ${tier} tier ticket. Category: ${category}. Agent: ${assignedAgent}.`,
    },
  })
}

async function notifyAgentSLAWarning(
  ticketId: string,
  ticketNumber: string,
  minutesLeft: number,
  agentId: string | null
): Promise<void> {
  if (!agentId) return

  console.warn(`[SLA WARNING] Ticket ${ticketNumber} — ${minutesLeft} minutes until breach. Agent: ${agentId}`)

  // In production, this would send Socket.io notification to agent
  // io.to(`agent:${agentId}`).emit('sla:warning', { ticketId, ticketNumber, minutesLeft })
}
