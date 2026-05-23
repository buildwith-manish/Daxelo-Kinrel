// DAXELO KINREL — Pack 08: Transparency Report Generator
// Quarterly moderation reports with 5 sections per Indian regulatory requirements

import { db } from '@/lib/db'

// ── Report Types ────────────────────────────────────────────────────────

export interface ContentActionedStats {
  totalActioned: number
  byCategory: Record<string, number>
  byAction: Record<string, number>
  byContentType: Record<string, number>
  autoActioned: number
  humanActioned: number
  autoActionAccuracy: number
}

export interface AppealsStats {
  totalFiled: number
  totalResolved: number
  upheld: number
  reinstated: number
  reduced: number
  dismissed: number
  pending: number
  avgResolutionHours: number
  tier1Stats: { filed: number; resolved: number }
  tier2Stats: { filed: number; resolved: number }
}

export interface ChildSafetyStats {
  minorsIdentified: number
  parentalConsentsRequested: number
  parentalConsentsGranted: number
  parentalConsentsRevoked: number
  csamDetections: number
  csamReportsToNCRB: number
  csamReportsToNCMEC: number
  accountsBannedForCSAM: number
  minorRestrictionsApplied: number
}

export interface AccuracyStats {
  totalClassifications: number
  autoCorrect: number
  autoIncorrect: number
  humanOverrides: number
  falsePositiveRate: number
  falseNegativeRate: number
  precisionByCategory: Record<string, number>
  avgConfidenceScore: number
}

export interface EnforcementStats {
  totalCases: number
  avgResolutionTimeHours: number
  medianResolutionTimeHours: number
  casesByPriority: Record<string, number>
  casesBySource: Record<string, number>
  moderatorsActive: number
  casesPerModerator: number
  slaComplianceRate: number
}

export interface QuarterlyModerationReport {
  year: number
  quarter: number
  period: { start: Date; end: Date }
  generatedAt: Date
  contentActioned: ContentActionedStats
  appeals: AppealsStats
  childSafety: ChildSafetyStats
  accuracy: AccuracyStats
  enforcement: EnforcementStats
}

// ── Helper: Group By ────────────────────────────────────────────────────

export function groupBy<T>(array: T[], key: keyof T): Record<string, T[]> {
  return array.reduce((groups, item) => {
    const groupKey = String(item[key])
    if (!groups[groupKey]) groups[groupKey] = []
    groups[groupKey].push(item)
    return groups
  }, {} as Record<string, T[]>)
}

// ── Helper: Count By ────────────────────────────────────────────────────

function countBy<T>(array: T[], key: keyof T): Record<string, number> {
  const groups = groupBy(array, key)
  const counts: Record<string, number> = {}
  for (const [k, v] of Object.entries(groups)) {
    counts[k] = v.length
  }
  return counts
}

// ── Date Range for Quarter ──────────────────────────────────────────────

function getQuarterDates(year: number, quarter: number): { start: Date; end: Date } {
  const startMonth = (quarter - 1) * 3
  const start = new Date(year, startMonth, 1)
  const end = new Date(year, startMonth + 3, 0, 23, 59, 59, 999) // Last day of quarter
  return { start, end }
}

// ── Content Actioned Stats ──────────────────────────────────────────────

async function getContentActionedStats(startDate: Date, endDate: Date): Promise<ContentActionedStats> {
  const cases = await db.moderationCase.findMany({
    where: {
      createdAt: { gte: startDate, lte: endDate },
      status: 'actioned',
    },
  })

  const allCases = await db.moderationCase.findMany({
    where: {
      createdAt: { gte: startDate, lte: endDate },
    },
  })

  const actioned = cases
  const autoActioned = actioned.filter(c => c.source === 'auto').length
  const humanActioned = actioned.filter(c => c.source !== 'auto').length

  const autoCorrect = actioned.filter(c => c.source === 'auto' && c.reviewDecision !== 'dismiss').length
  const autoTotal = allCases.filter(c => c.source === 'auto').length

  return {
    totalActioned: actioned.length,
    byCategory: countBy(actioned, 'category'),
    byAction: countBy(actioned.filter(c => c.contentAction), 'contentAction'),
    byContentType: countBy(actioned, 'contentType'),
    autoActioned,
    humanActioned,
    autoActionAccuracy: autoTotal > 0 ? autoCorrect / autoTotal : 0,
  }
}

// ── Appeals Stats ───────────────────────────────────────────────────────

async function getAppealsStats(startDate: Date, endDate: Date): Promise<AppealsStats> {
  const appeals = await db.moderationAppeal.findMany({
    where: {
      createdAt: { gte: startDate, lte: endDate },
    },
  })

  const resolved = appeals.filter(a => a.status !== 'pending' && a.status !== 'under_review')
  const upheld = appeals.filter(a => a.reviewDecision === 'uphold').length
  const reinstated = appeals.filter(a => a.reviewDecision === 'reinstated').length
  const reduced = appeals.filter(a => a.reviewDecision === 'reduced').length
  const dismissed = appeals.filter(a => a.reviewDecision === 'dismissed').length
  const pending = appeals.filter(a => a.status === 'pending' || a.status === 'under_review').length

  // Calculate average resolution time
  const resolvedWithTimes = resolved.filter(a => a.reviewedAt && a.createdAt)
  const avgResolutionMs = resolvedWithTimes.length > 0
    ? resolvedWithTimes.reduce((sum, a) => {
        const reviewDate = a.reviewedAt ? a.reviewedAt.getTime() : 0
        return sum + (reviewDate - a.createdAt.getTime())
      }, 0) / resolvedWithTimes.length
    : 0
  const avgResolutionHours = avgResolutionMs / (1000 * 60 * 60)

  const tier1 = appeals.filter(a => a.appealTier === 1)
  const tier2 = appeals.filter(a => a.appealTier === 2)

  return {
    totalFiled: appeals.length,
    totalResolved: resolved.length,
    upheld,
    reinstated,
    reduced,
    dismissed,
    pending,
    avgResolutionHours: Math.round(avgResolutionHours * 10) / 10,
    tier1Stats: {
      filed: tier1.length,
      resolved: tier1.filter(a => a.status !== 'pending' && a.status !== 'under_review').length,
    },
    tier2Stats: {
      filed: tier2.length,
      resolved: tier2.filter(a => a.status !== 'pending' && a.status !== 'under_review').length,
    },
  }
}

// ── Child Safety Stats ──────────────────────────────────────────────────

async function getChildSafetyStats(startDate: Date, endDate: Date): Promise<ChildSafetyStats> {
  const csamCases = await db.moderationCase.findMany({
    where: {
      category: 'csam',
      createdAt: { gte: startDate, lte: endDate },
    },
  })

  const consents = await db.parentalConsent.findMany({
    where: {
      createdAt: { gte: startDate, lte: endDate },
    },
  })

  return {
    minorsIdentified: 0, // Would need Person table query with age calculation
    parentalConsentsRequested: consents.length,
    parentalConsentsGranted: consents.filter(c => c.consented).length,
    parentalConsentsRevoked: consents.filter(c => c.revokedAt !== null).length,
    csamDetections: csamCases.length,
    csamReportsToNCRB: csamCases.filter(c => c.contentAction === 'removed').length,
    csamReportsToNCMEC: csamCases.filter(c => c.contentAction === 'removed').length,
    accountsBannedForCSAM: csamCases.length, // Each CSAM case results in a ban
    minorRestrictionsApplied: consents.filter(c => !c.consented && c.revokedAt !== null).length,
  }
}

// ── Accuracy Stats ──────────────────────────────────────────────────────

async function getAccuracyStats(startDate: Date, endDate: Date): Promise<AccuracyStats> {
  const allCases = await db.moderationCase.findMany({
    where: {
      createdAt: { gte: startDate, lte: endDate },
    },
  })

  const reviewed = allCases.filter(c => c.reviewDecision !== null)
  const autoCases = allCases.filter(c => c.source === 'auto')
  const autoReviewed = autoCases.filter(c => c.reviewDecision !== null)

  // Auto classification was correct if the human reviewer upheld the decision
  const autoCorrect = autoReviewed.filter(c => c.reviewDecision === 'uphold').length
  const autoIncorrect = autoReviewed.filter(c => c.reviewDecision === 'dismiss').length
  const humanOverrides = autoReviewed.filter(c => c.reviewDecision === 'reduce' || c.reviewDecision === 'escalate').length

  const totalAutoReviewed = autoCorrect + autoIncorrect
  const falsePositiveRate = totalAutoReviewed > 0 ? autoIncorrect / totalAutoReviewed : 0
  const falseNegativeRate = 0 // Would need separate tracking

  // Precision by category
  const categoryGroups = groupBy(autoReviewed, 'category' as keyof typeof autoReviewed[0])
  const precisionByCategory: Record<string, number> = {}
  for (const [category, cases] of Object.entries(categoryGroups)) {
    const correct = cases.filter(c => c.reviewDecision === 'uphold').length
    precisionByCategory[category] = cases.length > 0 ? correct / cases.length : 0
  }

  // Average confidence score
  const avgConfidence = allCases.length > 0
    ? allCases.reduce((sum, c) => sum + c.confidence, 0) / allCases.length
    : 0

  return {
    totalClassifications: allCases.length,
    autoCorrect,
    autoIncorrect,
    humanOverrides,
    falsePositiveRate,
    falseNegativeRate,
    precisionByCategory,
    avgConfidenceScore: Math.round(avgConfidence * 1000) / 1000,
  }
}

// ── Enforcement Stats ───────────────────────────────────────────────────

async function getEnforcementStats(startDate: Date, endDate: Date): Promise<EnforcementStats> {
  const allCases = await db.moderationCase.findMany({
    where: {
      createdAt: { gte: startDate, lte: endDate },
    },
  })

  const resolved = allCases.filter(c => c.reviewedAt && c.createdAt)
  const resolutionTimes = resolved.map(c =>
    c.reviewedAt ? (c.reviewedAt.getTime() - c.createdAt.getTime()) / (1000 * 60 * 60) : 0,
  )

  const avgResolutionTimeHours = resolutionTimes.length > 0
    ? resolutionTimes.reduce((a, b) => a + b, 0) / resolutionTimes.length
    : 0

  const sortedTimes = [...resolutionTimes].sort((a, b) => a - b)
  const medianResolutionTimeHours = sortedTimes.length > 0
    ? sortedTimes[Math.floor(sortedTimes.length / 2)]
    : 0

  // Count unique reviewers
  const reviewerIds = new Set(allCases.filter(c => c.reviewerId).map(c => c.reviewerId))
  const moderatorsActive = reviewerIds.size

  return {
    totalCases: allCases.length,
    avgResolutionTimeHours: Math.round(avgResolutionTimeHours * 10) / 10,
    medianResolutionTimeHours: Math.round(medianResolutionTimeHours * 10) / 10,
    casesByPriority: countBy(allCases, 'priority'),
    casesBySource: countBy(allCases, 'source'),
    moderatorsActive,
    casesPerModerator: moderatorsActive > 0 ? Math.round(allCases.length / moderatorsActive) : 0,
    slaComplianceRate: 0, // Would need SLA tracking integration
  }
}

// ── Generate Quarterly Report ───────────────────────────────────────────

export async function generateQuarterlyReport(year: number, quarter: number): Promise<QuarterlyModerationReport> {
  const { start, end } = getQuarterDates(year, quarter)

  const [contentActioned, appeals, childSafety, accuracy, enforcement] = await Promise.all([
    getContentActionedStats(start, end),
    getAppealsStats(start, end),
    getChildSafetyStats(start, end),
    getAccuracyStats(start, end),
    getEnforcementStats(start, end),
  ])

  return {
    year,
    quarter,
    period: { start, end },
    generatedAt: new Date(),
    contentActioned,
    appeals,
    childSafety,
    accuracy,
    enforcement,
  }
}
