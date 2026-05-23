// DAXELO KINREL — Pack 08: Behavioral Anomaly Detection
// Detects suspicious user behavior patterns to prevent abuse

import { db } from '@/lib/db'

// ── Signals Configuration ───────────────────────────────────────────────

export const SIGNALS = {
  rapid_profile_viewing: {
    label: 'Rapid Profile Viewing',
    description: 'Viewing more than 50 profiles per hour',
    threshold: 50, // per hour
    weight: 15,
    category: 'stalking',
  },
  mass_invitations: {
    label: 'Mass Invitations',
    description: 'Sending more than 20 invitations per day',
    threshold: 20, // per day
    weight: 20,
    category: 'spam',
  },
  multiple_family_joins: {
    label: 'Multiple Family Joins',
    description: 'Joining more than 5 families in 24 hours',
    threshold: 5, // per 24 hours
    weight: 25,
    category: 'infiltration',
  },
  frequent_photo_changes: {
    label: 'Frequent Photo Changes',
    description: 'Changing profile photo more than 10 times per day',
    threshold: 10, // per day
    weight: 15,
    category: 'impersonation',
  },
  mass_messaging: {
    label: 'Mass Messaging',
    description: 'Sending more than 30 messages per hour to non-family',
    threshold: 30, // per hour
    weight: 15,
    category: 'spam',
  },
  multiple_login_locations: {
    label: 'Multiple Login Locations',
    description: 'Logging in from more than 3 different cities in 24 hours',
    threshold: 3, // per 24 hours
    weight: 10,
    category: 'account_compromise',
  },
} as const

// ── Risk Thresholds ─────────────────────────────────────────────────────

export const RISK_THRESHOLDS = {
  allow: { min: 0, max: 29, label: 'Allow', color: 'green', action: 'No restrictions' },
  throttle: { min: 30, max: 49, label: 'Throttle', color: 'yellow', action: 'Rate limit actions' },
  restrict: { min: 50, max: 69, label: 'Restrict', color: 'orange', action: 'Limit features, require verification' },
  suspend: { min: 70, max: 100, label: 'Suspend', color: 'red', action: 'Temporary suspension, manual review required' },
} as const

// ── Activity Metrics Interface ──────────────────────────────────────────

export interface ActivityMetrics {
  userId: string
  period: string // '1h', '24h', '7d'
  profileViews: number
  invitationsSent: number
  familiesJoined: number
  photoChanges: number
  messagesSent: number
  loginLocations: number
  // Derived
  profileViewsPerHour: number
  invitationsPerDay: number
  messagesPerHour: number
}

// ── Signal Result ───────────────────────────────────────────────────────

export interface SignalResult {
  signal: string
  triggered: boolean
  value: number
  threshold: number
  score: number // contribution to risk score
  category: string
}

// ── Analysis Result ─────────────────────────────────────────────────────

export interface AnalysisResult {
  riskScore: number
  riskLevel: 'allow' | 'throttle' | 'restrict' | 'suspend'
  signals: SignalResult[]
  recommendation: string
  autoActions: string[]
}

// ── Get Recent Activity ─────────────────────────────────────────────────

export async function getRecentActivity(userId: string): Promise<ActivityMetrics> {
  const now = new Date()
  const oneHourAgo = new Date(now.getTime() - 60 * 60 * 1000)
  const oneDayAgo = new Date(now.getTime() - 24 * 60 * 60 * 1000)

  // Count moderation audit logs as proxy for activity
  // In production, this would query dedicated activity tables
  const recentActions = await db.moderationAuditLog.findMany({
    where: {
      actorId: userId,
      createdAt: { gte: oneDayAgo },
    },
    orderBy: { createdAt: 'desc' },
  })

  // Count family memberships joined recently
  const recentFamilies = await db.familyMember.findMany({
    where: {
      userId,
      joinedAt: { gte: oneDayAgo },
    },
  })

  // Simulated metrics based on available data
  // In production, these would come from activity tracking tables
  const profileViews = Math.floor(Math.random() * 10) // Placeholder
  const invitationsSent = recentActions.filter(a => a.action === 'invite').length || 0
  const familiesJoined = recentFamilies.length
  const photoChanges = recentActions.filter(a => a.action === 'photo_change').length || 0
  const messagesSent = recentActions.filter(a => a.action === 'message').length || 0
  const loginLocations = 1 // Default single location

  // Per-hour calculations
  const hoursSinceDayStart = Math.max((now.getTime() - oneDayAgo.getTime()) / (60 * 60 * 1000), 1)
  const hoursSinceHourStart = Math.max((now.getTime() - oneHourAgo.getTime()) / (60 * 60 * 1000), 1)

  return {
    userId,
    period: '24h',
    profileViews,
    invitationsSent,
    familiesJoined,
    photoChanges,
    messagesSent,
    loginLocations,
    profileViewsPerHour: Math.round(profileViews / hoursSinceHourStart),
    invitationsPerDay: invitationsSent,
    messagesPerHour: Math.round(messagesSent / hoursSinceHourStart),
  }
}

// ── Analyze Activity ────────────────────────────────────────────────────

export function analyzeActivity(metrics: ActivityMetrics): AnalysisResult {
  const signals: SignalResult[] = []
  let riskScore = 0

  // Check each signal
  const signalChecks: Array<{
    key: string
    value: number
    threshold: number
    weight: number
    category: string
  }> = [
    { key: 'rapid_profile_viewing', value: metrics.profileViewsPerHour, threshold: SIGNALS.rapid_profile_viewing.threshold, weight: SIGNALS.rapid_profile_viewing.weight, category: SIGNALS.rapid_profile_viewing.category },
    { key: 'mass_invitations', value: metrics.invitationsPerDay, threshold: SIGNALS.mass_invitations.threshold, weight: SIGNALS.mass_invitations.weight, category: SIGNALS.mass_invitations.category },
    { key: 'multiple_family_joins', value: metrics.familiesJoined, threshold: SIGNALS.multiple_family_joins.threshold, weight: SIGNALS.multiple_family_joins.weight, category: SIGNALS.multiple_family_joins.category },
    { key: 'frequent_photo_changes', value: metrics.photoChanges, threshold: SIGNALS.frequent_photo_changes.threshold, weight: SIGNALS.frequent_photo_changes.weight, category: SIGNALS.frequent_photo_changes.category },
    { key: 'mass_messaging', value: metrics.messagesPerHour, threshold: SIGNALS.mass_messaging.threshold, weight: SIGNALS.mass_messaging.weight, category: SIGNALS.mass_messaging.category },
    { key: 'multiple_login_locations', value: metrics.loginLocations, threshold: SIGNALS.multiple_login_locations.threshold, weight: SIGNALS.multiple_login_locations.weight, category: SIGNALS.multiple_login_locations.category },
  ]

  for (const check of signalChecks) {
    const triggered = check.value > check.threshold
    const overageRatio = triggered ? (check.value - check.threshold) / check.threshold : 0
    const score = triggered ? Math.min(check.weight * (1 + overageRatio), check.weight * 2) : 0

    signals.push({
      signal: check.key,
      triggered,
      value: check.value,
      threshold: check.threshold,
      score: Math.round(score * 10) / 10,
      category: check.category,
    })

    riskScore += score
  }

  // Cap at 100
  riskScore = Math.min(Math.round(riskScore), 100)

  // Determine risk level
  let riskLevel: 'allow' | 'throttle' | 'restrict' | 'suspend'
  if (riskScore >= RISK_THRESHOLDS.suspend.min) {
    riskLevel = 'suspend'
  } else if (riskScore >= RISK_THRESHOLDS.restrict.min) {
    riskLevel = 'restrict'
  } else if (riskScore >= RISK_THRESHOLDS.throttle.min) {
    riskLevel = 'throttle'
  } else {
    riskLevel = 'allow'
  }

  // Generate recommendation
  const recommendation = generateRecommendation(riskLevel, signals)
  const autoActions = generateAutoActions(riskLevel, signals)

  return { riskScore, riskLevel, signals, recommendation, autoActions }
}

// ── Risk Score ──────────────────────────────────────────────────────────

export async function riskScore(userId: string): Promise<number> {
  const metrics = await getRecentActivity(userId)
  const analysis = analyzeActivity(metrics)
  return analysis.riskScore
}

// ── Recommendation Generator ────────────────────────────────────────────

function generateRecommendation(riskLevel: string, signals: SignalResult[]): string {
  const triggeredSignals = signals.filter(s => s.triggered)

  if (triggeredSignals.length === 0) {
    return 'User activity is within normal parameters. No action needed.'
  }

  const categories = [...new Set(triggeredSignals.map(s => s.category))]

  switch (riskLevel) {
    case 'suspend':
      return `URGENT: User showing ${categories.join(', ')} behavior patterns. Immediate suspension recommended pending manual review. Triggered signals: ${triggeredSignals.map(s => s.signal).join(', ')}.`
    case 'restrict':
      return `User showing ${categories.join(', ')} behavior patterns. Restrict sensitive features and require additional verification. Triggered signals: ${triggeredSignals.map(s => s.signal).join(', ')}.`
    case 'throttle':
      return `User approaching behavioral thresholds in ${categories.join(', ')}. Apply rate limiting and monitor closely. Triggered signals: ${triggeredSignals.map(s => s.signal).join(', ')}.`
    default:
      return 'User activity slightly elevated but within acceptable bounds. Continue monitoring.'
  }
}

// ── Auto Actions Generator ──────────────────────────────────────────────

function generateAutoActions(riskLevel: string, signals: SignalResult[]): string[] {
  const actions: string[] = []

  switch (riskLevel) {
    case 'suspend':
      actions.push('suspend_account')
      actions.push('require_manual_review')
      actions.push('notify_admin')
      break
    case 'restrict':
      actions.push('restrict_matrimonial_access')
      actions.push('restrict_community_posting')
      actions.push('require_phone_verification')
      break
    case 'throttle':
      actions.push('rate_limit_invitations')
      actions.push('rate_limit_messaging')
      actions.push('add_captcha_to_actions')
      break
    default:
      // No auto actions
      break
  }

  // Add category-specific actions
  const triggeredCategories = new Set(signals.filter(s => s.triggered).map(s => s.category))
  if (triggeredCategories.has('stalking')) {
    actions.push('hide_profile_from_search')
  }
  if (triggeredCategories.has('impersonation')) {
    actions.push('require_photo_verification')
  }
  if (triggeredCategories.has('account_compromise')) {
    actions.push('force_password_reset')
    actions.push('terminate_other_sessions')
  }

  return actions
}
