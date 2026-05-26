// DAXELO KINREL — Invite Conversion Tracking
// Pack 04: WhatsApp Platform
//
// Tracks the full conversion funnel for WhatsApp invitations:
// share → link_tapped → app_opened → registered → person_linked → first_graph_view
//
// Uses the WhatsAppAnalytics model to record each step, and provides
// aggregate conversion statistics for dashboard reporting.

import { db } from '@/lib/db'

// ── Event Type Definitions ─────────────────────────────────────────────

export const INVITE_EVENT_TYPES = {
  WHATSAPP_SHARE: 'invite:whatsapp_share',
  LINK_TAPPED: 'invite:link_tapped',
  APP_OPENED: 'invite:app_opened',
  REGISTERED: 'invite:registered',
  PERSON_LINKED: 'invite:person_linked',
  FIRST_GRAPH_VIEW: 'invite:first_graph_view',
} as const

export type InviteEventType = (typeof INVITE_EVENT_TYPES)[keyof typeof INVITE_EVENT_TYPES]

export interface TrackInviteEventParams {
  event: InviteEventType
  userId?: string
  familyId?: string
  invitationId?: string
  metadata?: Record<string, unknown>
}

/**
 * Records an analytics event for the invitation conversion funnel.
 * Each event creates a WhatsAppAnalytics record with the event name,
 * associated user/family, and any additional metadata.
 *
 * @param params - Event tracking parameters
 * @returns The created analytics record ID
 */
export async function trackInviteEvent(
  params: TrackInviteEventParams
): Promise<string> {
  const { event, userId, familyId, invitationId, metadata } = params

  const enrichedMetadata: Record<string, unknown> = {
    ...metadata,
    invitationId,
    timestamp: new Date().toISOString(),
  }

  const record = await db.whatsAppAnalytics.create({
    data: {
      event,
      userId: userId ?? null,
      familyId: familyId ?? null,
      metadata: JSON.stringify(enrichedMetadata),
    },
  })

  return record.id
}

// ── Conversion Stats ───────────────────────────────────────────────────

export interface InviteConversionStats {
  /** Number of WhatsApp invitation shares */
  shares: number
  /** Number of deep link taps from WhatsApp */
  linkTaps: number
  /** Number of app opens from the link */
  appOpens: number
  /** Number of completed registrations */
  registrations: number
  /** Number of users linked to a person in the family tree */
  personLinked: number
  /** Number of users who viewed their first graph */
  firstGraphView: number
  /** Conversion rate: linkTaps / shares */
  linkTapRate: number
  /** Conversion rate: appOpens / linkTaps */
  appOpenRate: number
  /** Conversion rate: registrations / appOpens */
  registrationRate: number
  /** Conversion rate: personLinked / registrations */
  personLinkRate: number
  /** Conversion rate: firstGraphView / personLinked */
  firstGraphViewRate: number
  /** Overall conversion rate: firstGraphView / shares */
  overallConversionRate: number
  /** Date range of the data */
  startDate: Date | null
  endDate: Date | null
}

export interface GetInviteConversionStatsParams {
  familyId?: string
  startDate?: Date
  endDate?: Date
}

/**
 * Calculates aggregate conversion statistics for the invitation funnel.
 *
 * Returns counts for each funnel step and derived conversion rates
 * between consecutive steps. If a familyId is provided, stats are
 * scoped to that family only.
 *
 * @param params - Optional filters (familyId, date range)
 * @returns Full funnel metrics with conversion rates
 */
export async function getInviteConversionStats(
  params?: GetInviteConversionStatsParams
): Promise<InviteConversionStats> {
  const { familyId, startDate, endDate } = params ?? {}

  // Build the shared where clause for date and family filters
  const baseWhere: Record<string, unknown> = {}

  if (familyId) {
    baseWhere.familyId = familyId
  }

  if (startDate || endDate) {
    const createdAtFilter: Record<string, Date> = {}
    if (startDate) createdAtFilter.gte = startDate
    if (endDate) createdAtFilter.lte = endDate
    baseWhere.createdAt = createdAtFilter
  }

  // Query counts for each funnel step in parallel
  const [
    shares,
    linkTaps,
    appOpens,
    registrations,
    personLinked,
    firstGraphView,
  ] = await Promise.all([
    db.whatsAppAnalytics.count({
      where: { ...baseWhere, event: INVITE_EVENT_TYPES.WHATSAPP_SHARE },
    }),
    db.whatsAppAnalytics.count({
      where: { ...baseWhere, event: INVITE_EVENT_TYPES.LINK_TAPPED },
    }),
    db.whatsAppAnalytics.count({
      where: { ...baseWhere, event: INVITE_EVENT_TYPES.APP_OPENED },
    }),
    db.whatsAppAnalytics.count({
      where: { ...baseWhere, event: INVITE_EVENT_TYPES.REGISTERED },
    }),
    db.whatsAppAnalytics.count({
      where: { ...baseWhere, event: INVITE_EVENT_TYPES.PERSON_LINKED },
    }),
    db.whatsAppAnalytics.count({
      where: { ...baseWhere, event: INVITE_EVENT_TYPES.FIRST_GRAPH_VIEW },
    }),
  ])

  // Calculate conversion rates between funnel steps
  const safeRate = (numerator: number, denominator: number): number => {
    if (denominator === 0) return 0
    return Math.round((numerator / denominator) * 10000) / 100 // percentage with 2 decimal places
  }

  const linkTapRate = safeRate(linkTaps, shares)
  const appOpenRate = safeRate(appOpens, linkTaps)
  const registrationRate = safeRate(registrations, appOpens)
  const personLinkRate = safeRate(personLinked, registrations)
  const firstGraphViewRate = safeRate(firstGraphView, personLinked)
  const overallConversionRate = safeRate(firstGraphView, shares)

  return {
    shares,
    linkTaps,
    appOpens,
    registrations,
    personLinked,
    firstGraphView,
    linkTapRate,
    appOpenRate,
    registrationRate,
    personLinkRate,
    firstGraphViewRate,
    overallConversionRate,
    startDate: startDate ?? null,
    endDate: endDate ?? null,
  }
}
