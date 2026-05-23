// DAXELO KINREL — Pack 08: Auto-Moderation Rules Engine
// Default rules and rule execution for automatic content moderation

import { db } from '@/lib/db'

// ── Default Rules ───────────────────────────────────────────────────────

export interface DefaultRule {
  id: string
  name: string
  description: string
  contentType: string | null
  category: string
  condition: string
  action: string
  priority: string
  isActive: boolean
  pattern?: RegExp
}

export const DEFAULT_RULES: DefaultRule[] = [
  {
    id: 'rule_phone_exposure',
    name: 'Phone Number Exposure',
    description: 'Detects Indian phone numbers in text content',
    contentType: null, // Applies to all text content
    category: 'pii_exposure',
    condition: 'regex:(?:(?:\\+91|0)[\\s-]?)?[6-9]\\d{4}[\\s-]?\\d{5}',
    action: 'allow_with_flag',
    priority: 'high',
    isActive: true,
    pattern: /(?:(?:\+91|0)[\s-]?)?[6-9]\d{4}[\s-]?\d{5}/g,
  },
  {
    id: 'rule_email_exposure',
    name: 'Email Address Exposure',
    description: 'Detects email addresses in text content',
    contentType: null,
    category: 'pii_exposure',
    condition: 'regex:[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Z|a-z]{2,}',
    action: 'allow_with_flag',
    priority: 'normal',
    isActive: true,
    pattern: /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}/g,
  },
  {
    id: 'rule_aadhaar_exposure',
    name: 'Aadhaar Number Exposure',
    description: 'Detects 12-digit Aadhaar numbers in text content',
    contentType: null,
    category: 'pii_exposure',
    condition: 'regex:[2-9]\\d{3}\\s?\\d{4}\\s?\\d{4}',
    action: 'reject',
    priority: 'critical',
    isActive: true,
    pattern: /[2-9]\d{3}\s?\d{4}\s?\d{4}/g,
  },
  {
    id: 'rule_pan_exposure',
    name: 'PAN Card Number Exposure',
    description: 'Detects PAN card numbers (5L+4D+1L format) in text',
    contentType: null,
    category: 'pii_exposure',
    condition: 'regex:[A-Z]{5}\\d{4}[A-Z]',
    action: 'reject',
    priority: 'critical',
    isActive: true,
    pattern: /[A-Z]{5}\d{4}[A-Z]/g,
  },
  {
    id: 'rule_caste_slurs',
    name: 'Caste-Based Slurs',
    description: 'Detects caste-based derogatory language in Hindi and English',
    contentType: null,
    category: 'caste_discrimination',
    condition: 'dictionary:caste_slurs',
    action: 'reject',
    priority: 'urgent',
    isActive: true,
  },
  {
    id: 'rule_communal_hate',
    name: 'Communal Hate Speech',
    description: 'Detects communal hate speech targeting religious groups',
    contentType: null,
    category: 'communal_hate',
    condition: 'dictionary:communal_hate',
    action: 'reject',
    priority: 'urgent',
    isActive: true,
  },
  {
    id: 'rule_profile_photo_face',
    name: 'Profile Photo Must Have Face',
    description: 'Profile photos must contain exactly one visible face',
    contentType: 'profile_photo',
    category: 'borderline',
    condition: 'face_count:1',
    action: 'quarantine',
    priority: 'high',
    isActive: true,
  },
  {
    id: 'rule_multiple_faces',
    name: 'Multiple Faces in Single-Subject Photo',
    description: 'Photos for profile/matrimonial must have only one person',
    contentType: 'profile_photo',
    category: 'borderline',
    condition: 'face_count_max:1',
    action: 'quarantine',
    priority: 'high',
    isActive: true,
  },
  {
    id: 'rule_matrimonial_watermark',
    name: 'Matrimonial Site Watermark',
    description: 'Detects watermarks from competing matrimonial sites (Shaadi.com, BharatMatrimony)',
    contentType: 'matrimonial_profile',
    category: 'spam',
    condition: 'watermark:matrimonial_sites',
    action: 'allow_with_flag',
    priority: 'normal',
    isActive: true,
  },
]

// ── Run Auto-Moderation ─────────────────────────────────────────────────

export function runAutoModeration(
  content: string,
  contentType: string,
): { passed: boolean; violations: DefaultRule[] } {
  const violations: DefaultRule[] = []

  for (const rule of DEFAULT_RULES) {
    if (!rule.isActive) continue

    // Check if rule applies to this content type
    if (rule.contentType && rule.contentType !== contentType) continue

    if (matchRule(content, rule)) {
      violations.push(rule)
    }
  }

  return {
    passed: violations.length === 0,
    violations,
  }
}

// ── Match Rule ──────────────────────────────────────────────────────────

export function matchRule(content: string, rule: DefaultRule): boolean {
  if (!rule.isActive) return false

  // Regex-based rules
  if (rule.pattern) {
    const patternCopy = new RegExp(rule.pattern.source, rule.pattern.flags)
    return patternCopy.test(content)
  }

  // Condition-based rules
  if (rule.condition.startsWith('regex:')) {
    const regexStr = rule.condition.substring(6)
    try {
      const regex = new RegExp(regexStr, 'gi')
      return regex.test(content)
    } catch {
      return false
    }
  }

  if (rule.condition.startsWith('dictionary:')) {
    // Dictionary-based rules are handled by the text-classifier
    // This is a simplified check
    return false
  }

  if (rule.condition.startsWith('face_count:')) {
    // Face count rules are handled by image-classifier
    return false
  }

  if (rule.condition.startsWith('face_count_max:')) {
    // Face count rules are handled by image-classifier
    return false
  }

  if (rule.condition.startsWith('watermark:')) {
    // Watermark rules are handled by image-classifier
    return false
  }

  return false
}

// ── Is User Moderator ───────────────────────────────────────────────────

export async function isUserModerator(userId: string): Promise<boolean> {
  const user = await db.user.findUnique({
    where: { id: userId },
  })

  if (!user) return false

  // Check if user has admin or agent role
  return user.role === 'admin' || user.role === 'agent'
}

// ── Apply User Action ───────────────────────────────────────────────────

export async function applyUserAction(
  userId: string,
  action: string,
  duration?: number,
): Promise<void> {
  const validActions = ['warn', 'suspend', 'ban', 'restrict']

  if (!validActions.includes(action)) {
    throw new Error(`Invalid user action: ${action}`)
  }

  const statusMap: Record<string, string> = {
    warn: 'warned',
    suspend: 'suspended',
    ban: 'banned',
    restrict: 'restricted',
  }

  const now = new Date()
  const suspendedUntil = action === 'suspend' && duration
    ? new Date(now.getTime() + duration * 60 * 60 * 1000)
    : undefined

  await db.userModerationStatus.upsert({
    where: { userId },
    create: {
      userId,
      status: statusMap[action],
      warningCount: action === 'warn' ? 1 : 0,
      suspendedUntil,
      lastWarnedAt: action === 'warn' ? now : undefined,
      lastActionAt: now,
    },
    update: {
      status: statusMap[action],
      warningCount: action === 'warn' ? { increment: 1 } : undefined,
      suspendedUntil,
      lastWarnedAt: action === 'warn' ? now : undefined,
      lastActionAt: now,
      banReason: action === 'ban' ? 'Moderation action applied' : undefined,
    },
  })

  // Create moderation action record
  await db.moderationAction.create({
    data: {
      moderatorId: 'system',
      targetType: 'user',
      targetId: userId,
      action,
      reason: `Auto-moderation: ${action}`,
      duration: duration || null,
    },
  })
}

// ── Auto Hide Content ───────────────────────────────────────────────────

export async function autoHideContent(
  targetType: string,
  targetId: string,
  reason: string,
): Promise<void> {
  // Hide content based on target type
  if (targetType === 'community_post') {
    await db.communityPost.update({
      where: { id: targetId },
      data: {
        isHidden: true,
        hiddenReason: reason,
      },
    })
  } else if (targetType === 'comment') {
    await db.comment.update({
      where: { id: targetId },
      data: {
        isHidden: true,
        hiddenReason: reason,
      },
    })
  }

  // Create moderation action record
  await db.moderationAction.create({
    data: {
      moderatorId: 'system',
      targetType,
      targetId,
      action: 'hide',
      reason,
    },
  })
}

// ── Seed Default Rules to Database ──────────────────────────────────────

export async function seedDefaultRules(): Promise<void> {
  for (const rule of DEFAULT_RULES) {
    const existing = await db.moderationRule.findFirst({
      where: { name: rule.name },
    })

    if (!existing) {
      await db.moderationRule.create({
        data: {
          name: rule.name,
          description: rule.description,
          contentType: rule.contentType,
          category: rule.category,
          condition: rule.condition,
          action: rule.action,
          priority: rule.priority,
          isActive: rule.isActive,
          createdBy: null,
        },
      })
    }
  }
}
