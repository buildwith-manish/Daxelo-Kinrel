// DAXELO KINREL — Support Tier Calculator
// Pack 02: Support & Operations

import { db } from '@/lib/db'

export type SupportTier = 'basic' | 'standard' | 'premium' | 'vip'

const PLAN_TIER_MAP: Record<string, SupportTier> = {
  free: 'basic',
  pro_monthly: 'standard',
  pro_annual: 'standard',
  family_annual: 'premium',
  lifetime: 'vip',
}

export function tierForPlan(plan: string): SupportTier {
  return PLAN_TIER_MAP[plan] ?? 'basic'
}

export async function getUserSupportTier(userId: string): Promise<SupportTier> {
  const subscription = await db.subscription.findUnique({
    where: { userId },
    select: { plan: true, status: true },
  })

  if (!subscription || subscription.status !== 'active') {
    return 'basic'
  }

  return tierForPlan(subscription.plan)
}

export function tierPriorityWeight(tier: SupportTier): number {
  switch (tier) {
    case 'vip': return 4
    case 'premium': return 3
    case 'standard': return 2
    case 'basic': return 1
  }
}

export function tierMaxResponseTime(tier: SupportTier): number {
  // Returns max response time in hours
  switch (tier) {
    case 'vip': return 1
    case 'premium': return 4
    case 'standard': return 24
    case 'basic': return 72
  }
}

export function tierLabel(tier: SupportTier): string {
  switch (tier) {
    case 'vip': return 'VIP Support'
    case 'premium': return 'Premium Support'
    case 'standard': return 'Standard Support'
    case 'basic': return 'Basic Support'
  }
}

export function tierChannels(tier: SupportTier): string[] {
  switch (tier) {
    case 'vip':
      return ['in_app', 'email', 'whatsapp', 'phone', 'dedicated_agent']
    case 'premium':
      return ['in_app', 'email', 'whatsapp', 'phone']
    case 'standard':
      return ['in_app', 'email', 'whatsapp']
    case 'basic':
      return ['in_app', 'email']
  }
}

export function tierResponseTimeLabel(tier: SupportTier): string {
  switch (tier) {
    case 'vip': return '≤ 1 hour response'
    case 'premium': return '≤ 4 hour response'
    case 'standard': return '≤ 24 hour response'
    case 'basic': return '≤ 72 hour response'
  }
}

export const SEVERITY_RESPONSE_MATRIX: Record<SupportTier, Record<string, number>> = {
  vip: { critical: 0.25, high: 1, medium: 4, low: 24 },
  premium: { critical: 0.5, high: 4, medium: 8, low: 48 },
  standard: { critical: 1, high: 8, medium: 24, low: 72 },
  basic: { critical: 4, high: 24, medium: 72, low: -1 }, // -1 = best effort
}
