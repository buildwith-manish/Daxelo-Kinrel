// DAXELO KINREL — Ticket Router
// Pack 02: Support & Operations

import { db } from '@/lib/db'
import { getUserSupportTier, tierPriorityWeight, tierMaxResponseTime, type SupportTier } from './tier-calculator'

export interface RoutingResult {
  queue: string
  priority: number
  assignedAgentId: string | null
  estimatedResponseHours: number
}

export async function routeTicket(ticketId: string): Promise<RoutingResult> {
  const ticket = await db.supportTicket.findUnique({
    where: { id: ticketId },
    include: { user: { include: { subscription: true } } },
  })

  if (!ticket) throw new Error(`Ticket ${ticketId} not found`)

  const tier = await getUserSupportTier(ticket.userId)
  const weight = tierPriorityWeight(tier)
  const queue = categorizeQueue(ticket.category)
  const urgency = calculateUrgency(ticket.category, ticket.severity)
  const catWeight = categoryWeight(ticket.category)

  // Priority = tier weight × urgency × category weight (scale 0-100)
  const priority = Math.min(Math.round(weight * urgency * catWeight * 10), 100)

  // Find available agent
  const agent = await findAvailableAgent(queue, tier)

  // Calculate estimated response time
  const base = tierMaxResponseTime(tier)
  const estimatedResponseHours = getResponseEstimate(base, urgency)

  return {
    queue,
    priority,
    assignedAgentId: agent?.id ?? null,
    estimatedResponseHours,
  }
}

function categorizeQueue(category: string): string {
  const queueMap: Record<string, string> = {
    billing: 'billing',
    account: 'account',
    data_loss: 'critical',
    bug: 'technical',
    feature_request: 'product',
    general: 'general',
    matrimonial: 'matrimonial',
    verification: 'trust',
    privacy: 'compliance',
  }
  return queueMap[category] ?? 'general'
}

function calculateUrgency(category: string, severity: string): number {
  // Critical categories always get high urgency
  if (['data_loss', 'privacy', 'compliance'].includes(category)) return 3
  switch (severity) {
    case 'critical': return 3
    case 'high': return 2
    case 'medium': return 1
    case 'low': return 0.5
    default: return 1
  }
}

function categoryWeight(category: string): number {
  const weights: Record<string, number> = {
    data_loss: 3,
    privacy: 3,
    billing: 2,
    account: 1.5,
    bug: 1.5,
    matrimonial: 1.5,
    verification: 1.5,
    feature_request: 0.5,
    general: 1,
  }
  return weights[category] ?? 1
}

function getResponseEstimate(baseHours: number, urgency: number): number {
  if (urgency >= 3) return Math.max(baseHours / 4, 0.25)
  if (urgency >= 2) return Math.max(baseHours / 2, 0.5)
  return baseHours
}

async function findAvailableAgent(queue: string, tier: SupportTier) {
  const tierWeight = tierPriorityWeight(tier)

  // Get all online agents and filter in JS since queues is a JSON string
  const agents = await db.supportAgent.findMany({
    where: {
      status: { in: ['online', 'busy'] },
      currentLoad: { lt: 10 },
      minTier: { lte: tierWeight },
    },
    orderBy: { currentLoad: 'asc' },
  })

  // Filter by queue assignment (stored as JSON array string)
  for (const agent of agents) {
    try {
      const agentQueues: string[] = JSON.parse(agent.queues)
      if (agentQueues.includes(queue) && agent.currentLoad < agent.maxLoad) {
        return agent
      }
    } catch {
      continue
    }
  }

  return null
}

export { categorizeQueue, calculateUrgency, categoryWeight }
