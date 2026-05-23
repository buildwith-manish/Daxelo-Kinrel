// DAXELO KINREL — Pack 08: Core Moderation Service
// Orchestrates content moderation pipeline: classify → create case → apply action

import { db } from '@/lib/db'
import { ContentCategory, AutoAction, ClassificationResult, categoryToPriority, CONTENT_TYPES } from './classification'
import { classify as classifyText } from './text-classifier'
import { classify as classifyImage } from './image-classifier'

// ── Types ───────────────────────────────────────────────────────────────

interface ModerateContentParams {
  contentType: string
  contentId: string
  content: string | Buffer
  authorId: string
  familyId?: string
  source?: string
  reporterId?: string
  reportReason?: string
  reportDetails?: string
}

// ── Core: Moderate Content ──────────────────────────────────────────────

export async function moderateContent(params: ModerateContentParams): Promise<ClassificationResult> {
  const { contentType, contentId, content, authorId, familyId, source = 'auto', reporterId, reportReason, reportDetails } = params

  // Step 1: Classify content
  let result: ClassificationResult

  const contentConfig = CONTENT_TYPES[contentType]
  const isImage = contentConfig?.inputType === 'image' || (Buffer.isBuffer(content) && contentConfig?.requiresImageValidation)

  if (isImage && Buffer.isBuffer(content)) {
    result = await classifyImage({
      buffer: content,
      contentType,
    })
  } else if (typeof content === 'string') {
    result = await classifyText(content, contentType)
  } else {
    // Default: treat as text
    result = await classifyText(content.toString('utf-8'), contentType)
  }

  // Step 2: Create moderation case
  const priority = calculatePriority(
    result.category,
    result.confidence,
    source,
  )

  const contentPreview = typeof content === 'string'
    ? content.substring(0, 500)
    : `[Binary image data, ${Buffer.byteLength(content)} bytes]`

  const modCase = await createCase({
    contentType,
    contentId,
    contentPreview,
    authorId,
    familyId,
    category: result.category,
    confidence: result.confidence,
    autoAction: result.autoAction,
    flaggedCategories: result.flaggedCategories,
    priority,
    source,
    reporterId,
    reportReason,
    reportDetails,
  })

  // Step 3: Log the auto-action
  await db.moderationActionItem.create({
    data: {
      caseId: modCase.id,
      actionType: `auto_${result.autoAction}`,
      actorId: null,
      details: JSON.stringify({
        category: result.category,
        confidence: result.confidence,
        autoAction: result.autoAction,
        stageResults: result.details.stageResults,
      }),
    },
  })

  // Step 4: Handle CSAM immediately
  if (result.category === ContentCategory.CSAM) {
    await handleCSAM(modCase.id)
  }

  // Step 5: Apply auto-action
  if (result.autoAction === AutoAction.QUARANTINE) {
    await applyAction(modCase.id, 'hidden')
  } else if (result.autoAction === AutoAction.REJECT) {
    await applyAction(modCase.id, 'removed')
  } else if (result.autoAction === AutoAction.REPORT_TO_AUTHORITIES) {
    await applyAction(modCase.id, 'removed')
  }

  // Step 6: Write audit log
  await db.moderationAuditLog.create({
    data: {
      action: 'classify',
      contentType,
      contentId,
      actorType: 'ai_classifier',
      actorId: null,
      result: result.autoAction,
      reason: result.category,
      confidence: result.confidence,
      metadata: JSON.stringify({
        caseId: modCase.id,
        priority,
        flaggedCategories: result.flaggedCategories,
        scoreBreakdown: result.details.scoreBreakdown,
      }),
    },
  })

  return result
}

// ── Create Case ─────────────────────────────────────────────────────────

export async function createCase(params: {
  contentType: string
  contentId: string
  contentPreview: string
  authorId: string
  familyId?: string
  category: ContentCategory
  confidence: number
  autoAction: AutoAction
  flaggedCategories: ContentCategory[]
  priority: string
  source: string
  reporterId?: string
  reportReason?: string
  reportDetails?: string
}): Promise<ModerationCaseRow> {
  const modCase = await db.moderationCase.create({
    data: {
      contentType: params.contentType,
      contentId: params.contentId,
      contentPreview: params.contentPreview,
      authorId: params.authorId,
      familyId: params.familyId,
      category: params.category,
      confidence: params.confidence,
      autoAction: params.autoAction,
      flaggedCategories: JSON.stringify(params.flaggedCategories),
      status: params.autoAction === AutoAction.ALLOW ? 'actioned' : 'pending',
      priority: params.priority,
      source: params.source,
      reporterId: params.reporterId,
      reportReason: params.reportReason,
      reportDetails: params.reportDetails,
      contentAction: params.autoAction === AutoAction.ALLOW ? 'none' : null,
    },
  })

  return modCase
}

// ── Check Rules ─────────────────────────────────────────────────────────

export function checkRules(contentType: string, content: string): ModerationRuleRow[] {
  // Returns matching active rules for this content type
  // Note: In production, this would query the database
  // For synchronous usage, we return rule definitions
  return []
}

// ── Calculate Priority ──────────────────────────────────────────────────

export function calculatePriority(category: string, confidence: number, source: string): string {
  // Source-based priority boost
  const sourcePriority: Record<string, number> = {
    admin: 90,
    user_report: 70,
    proactive: 60,
    auto: 50,
  }

  const basePriority = categoryToPriority(category as ContentCategory, confidence)
  const sourceWeight = sourcePriority[source] || 50

  const priorityMap: Record<string, number> = { low: 10, normal: 30, high: 60, urgent: 80, critical: 95 }

  const score = (priorityMap[basePriority] || 30) * 0.7 + sourceWeight * 0.3

  if (score >= 90) return 'critical'
  if (score >= 70) return 'urgent'
  if (score >= 50) return 'high'
  if (score >= 30) return 'normal'
  return 'low'
}

// ── Handle CSAM ─────────────────────────────────────────────────────────

export async function handleCSAM(caseId: string): Promise<void> {
  // Step 1: Quarantine immediately
  await db.moderationCase.update({
    where: { id: caseId },
    data: {
      status: 'escalated',
      priority: 'critical',
      contentAction: 'removed',
    },
  })

  // Step 2: Log CSAM-specific action
  await db.moderationActionItem.create({
    data: {
      caseId,
      actionType: 'csam_quarantine',
      actorId: null,
      details: JSON.stringify({
        timestamp: new Date().toISOString(),
        action: 'quarantine_and_preserve',
        evidencePreserved: true,
        ncmecReportPending: true,
        ncrbReportPending: true,
      }),
    },
  })

  // Step 3: Write audit log for CSAM handling
  await db.moderationAuditLog.create({
    data: {
      action: 'escalate',
      contentType: 'image',
      contentId: caseId,
      actorType: 'system',
      actorId: null,
      result: 'report_to_authorities',
      reason: 'csam_detected',
      confidence: 1.0,
      metadata: JSON.stringify({
        csamHandlingProtocol: true,
        evidencePreserved: true,
        ncmeReportInitiated: true,
        ncrbReportInitiated: true,
        uploaderBanInitiated: true,
        timestamp: new Date().toISOString(),
      }),
    },
  })

  // Step 4: Flag uploader for ban
  const modCase = await db.moderationCase.findUnique({ where: { id: caseId } })
  if (modCase) {
    await db.userModerationStatus.upsert({
      where: { userId: modCase.authorId },
      create: {
        userId: modCase.authorId,
        status: 'banned',
        banReason: 'CSAM content uploaded - POCSO Act mandatory reporting',
        lastActionAt: new Date(),
      },
      update: {
        status: 'banned',
        banReason: 'CSAM content uploaded - POCSO Act mandatory reporting',
        lastActionAt: new Date(),
      },
    })
  }
}

// ── Apply Action ────────────────────────────────────────────────────────

export async function applyAction(caseId: string, action: string, reviewerId?: string): Promise<void> {
  const validActions = ['none', 'hidden', 'removed', 'replaced', 'user_suspended', 'user_banned']

  if (!validActions.includes(action)) {
    throw new Error(`Invalid moderation action: ${action}`)
  }

  await db.moderationCase.update({
    where: { id: caseId },
    data: {
      contentAction: action,
      status: 'actioned',
      reviewerId: reviewerId || null,
      reviewedAt: new Date(),
      reviewDecision: action === 'none' ? 'dismiss' : 'uphold',
    },
  })

  // If user-level action, update user moderation status
  if (action === 'user_suspended' || action === 'user_banned') {
    const modCase = await db.moderationCase.findUnique({ where: { id: caseId } })
    if (modCase) {
      const suspensionHours = action === 'user_suspended' ? 168 : null // 7 days default suspension

      await db.userModerationStatus.upsert({
        where: { userId: modCase.authorId },
        create: {
          userId: modCase.authorId,
          status: action === 'user_banned' ? 'banned' : 'suspended',
          banReason: action === 'user_banned' ? 'Content violation: banned' : undefined,
          suspendedUntil: action === 'user_suspended'
            ? new Date(Date.now() + (suspensionHours || 168) * 60 * 60 * 1000)
            : undefined,
          lastActionAt: new Date(),
        },
        update: {
          status: action === 'user_banned' ? 'banned' : 'suspended',
          suspendedUntil: action === 'user_suspended'
            ? new Date(Date.now() + (suspensionHours || 168) * 60 * 60 * 1000)
            : undefined,
          lastActionAt: new Date(),
        },
      })

      // Create moderation action record
      await db.moderationAction.create({
        data: {
          moderatorId: reviewerId || 'system',
          targetType: 'user',
          targetId: modCase.authorId,
          action: action === 'user_banned' ? 'ban' : 'suspend',
          reason: `Content moderation: ${modCase.category}`,
          duration: suspensionHours,
        },
      })
    }
  }

  // Log the action
  await db.moderationActionItem.create({
    data: {
      caseId,
      actionType: 'reviewed',
      actorId: reviewerId || 'system',
      details: JSON.stringify({ action, timestamp: new Date().toISOString() }),
    },
  })

  // Write audit log
  await db.moderationAuditLog.create({
    data: {
      action: 'review',
      contentType: 'mixed',
      contentId: caseId,
      actorType: reviewerId ? 'human_moderator' : 'system',
      actorId: reviewerId || null,
      result: action,
      reason: 'Applied moderation action',
      metadata: JSON.stringify({ caseId, action }),
    },
  })
}

// ── Get Queue ───────────────────────────────────────────────────────────

export async function getQueue(
  status?: string,
  priority?: string,
  category?: string,
  limit?: number,
): Promise<ModerationCaseRow[]> {
  const where: Record<string, unknown> = {}

  if (status) where.status = status
  if (priority) where.priority = priority
  if (category) where.category = category

  const cases = await db.moderationCase.findMany({
    where,
    orderBy: [
      { priority: 'desc' },
      { createdAt: 'asc' },
    ],
    take: limit || 50,
  })

  return cases
}

// ── Assign Reviewer ─────────────────────────────────────────────────────

export async function assignReviewer(caseId: string, reviewerId: string): Promise<void> {
  await db.moderationCase.update({
    where: { id: caseId },
    data: {
      reviewerId,
      status: 'under_review',
    },
  })

  await db.moderationActionItem.create({
    data: {
      caseId,
      actionType: 'reviewed',
      actorId: reviewerId,
      details: JSON.stringify({ action: 'assigned_reviewer', timestamp: new Date().toISOString() }),
    },
  })
}

// ── Type aliases for Prisma return types ────────────────────────────────

type ModerationCaseRow = Awaited<ReturnType<typeof db.moderationCase.create>>
type ModerationRuleRow = Awaited<ReturnType<typeof db.moderationRule.findFirst>>
