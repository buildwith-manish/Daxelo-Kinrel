// DAXELO KINREL — Pack 08: Content Moderation Classification Types
// Defines all enums, interfaces, and decision matrices for content classification

// ── Content Category Enum ──────────────────────────────────────────────

export enum ContentCategory {
  SAFE = 'safe',
  BORDERLINE = 'borderline',
  HARASSMENT = 'harassment',
  HATE_SPEECH = 'hate_speech',
  VIOLENCE = 'violence',
  SEXUAL_CONTENT = 'sexual_content',
  CSAM = 'csam',
  PII_EXPOSURE = 'pii_exposure',
  SPAM = 'spam',
  CASTE_DISCRIMINATION = 'caste_discrimination',
  RELIGIOUS_OFFENSE = 'religious_offense',
  COMMUNAL_HATE = 'communal_hate',
  DOWRY_REFERENCE = 'dowry_reference',
  COLORISM = 'colorism',
  MISINFORMATION = 'misinformation',
  IMPERSONATION = 'impersonation',
}

// ── Auto-Action Enum ────────────────────────────────────────────────────

export enum AutoAction {
  ALLOW = 'allow',
  ALLOW_WITH_FLAG = 'allow_with_flag',
  QUARANTINE = 'quarantine',
  REJECT = 'reject',
  ESCALATE = 'escalate',
  REPORT_TO_AUTHORITIES = 'report_to_authorities',
}

// ── Classification Result Interface ─────────────────────────────────────

export interface ClassificationResult {
  category: ContentCategory
  confidence: number // 0.0 to 1.0
  autoAction: AutoAction
  flaggedCategories: ContentCategory[]
  details: ClassificationDetails
}

export interface ClassificationDetails {
  piiTypes: string[]
  matchedPatterns: string[]
  scoreBreakdown: Record<string, number>
  stageResults: StageResult[]
  recommendedAction: string
  humanReviewRequired: boolean
  humanReviewSLA?: string // e.g. "4h", "24h"
  notificationLevel?: 'none' | 'info' | 'warning' | 'critical'
}

export interface StageResult {
  stage: string
  passed: boolean
  score: number
  findings: string[]
}

// ── Decision Matrix ─────────────────────────────────────────────────────
// Maps (category × confidence) → auto-action + human review SLA + notification

export interface DecisionMatrixEntry {
  autoAction: AutoAction
  humanReviewSLA: string
  notificationLevel: 'none' | 'info' | 'warning' | 'critical'
  humanReviewRequired: boolean
}

type ConfidenceLevel = 'low' | 'medium' | 'high' | 'very_high'

function getConfidenceLevel(confidence: number): ConfidenceLevel {
  if (confidence < 0.3) return 'low'
  if (confidence < 0.6) return 'medium'
  if (confidence < 0.85) return 'high'
  return 'very_high'
}

export const DECISION_MATRIX: Record<ContentCategory, Record<ConfidenceLevel, DecisionMatrixEntry>> = {
  [ContentCategory.SAFE]: {
    low: { autoAction: AutoAction.ALLOW, humanReviewSLA: 'none', notificationLevel: 'none', humanReviewRequired: false },
    medium: { autoAction: AutoAction.ALLOW, humanReviewSLA: 'none', notificationLevel: 'none', humanReviewRequired: false },
    high: { autoAction: AutoAction.ALLOW, humanReviewSLA: 'none', notificationLevel: 'none', humanReviewRequired: false },
    very_high: { autoAction: AutoAction.ALLOW, humanReviewSLA: 'none', notificationLevel: 'none', humanReviewRequired: false },
  },
  [ContentCategory.BORDERLINE]: {
    low: { autoAction: AutoAction.ALLOW_WITH_FLAG, humanReviewSLA: '72h', notificationLevel: 'info', humanReviewRequired: false },
    medium: { autoAction: AutoAction.ALLOW_WITH_FLAG, humanReviewSLA: '48h', notificationLevel: 'info', humanReviewRequired: true },
    high: { autoAction: AutoAction.QUARANTINE, humanReviewSLA: '24h', notificationLevel: 'warning', humanReviewRequired: true },
    very_high: { autoAction: AutoAction.QUARANTINE, humanReviewSLA: '24h', notificationLevel: 'warning', humanReviewRequired: true },
  },
  [ContentCategory.HARASSMENT]: {
    low: { autoAction: AutoAction.ALLOW_WITH_FLAG, humanReviewSLA: '48h', notificationLevel: 'info', humanReviewRequired: true },
    medium: { autoAction: AutoAction.QUARANTINE, humanReviewSLA: '24h', notificationLevel: 'warning', humanReviewRequired: true },
    high: { autoAction: AutoAction.REJECT, humanReviewSLA: '12h', notificationLevel: 'warning', humanReviewRequired: true },
    very_high: { autoAction: AutoAction.REJECT, humanReviewSLA: '4h', notificationLevel: 'critical', humanReviewRequired: true },
  },
  [ContentCategory.HATE_SPEECH]: {
    low: { autoAction: AutoAction.QUARANTINE, humanReviewSLA: '24h', notificationLevel: 'warning', humanReviewRequired: true },
    medium: { autoAction: AutoAction.REJECT, humanReviewSLA: '12h', notificationLevel: 'warning', humanReviewRequired: true },
    high: { autoAction: AutoAction.REJECT, humanReviewSLA: '4h', notificationLevel: 'critical', humanReviewRequired: true },
    very_high: { autoAction: AutoAction.ESCALATE, humanReviewSLA: '2h', notificationLevel: 'critical', humanReviewRequired: true },
  },
  [ContentCategory.VIOLENCE]: {
    low: { autoAction: AutoAction.QUARANTINE, humanReviewSLA: '24h', notificationLevel: 'warning', humanReviewRequired: true },
    medium: { autoAction: AutoAction.REJECT, humanReviewSLA: '12h', notificationLevel: 'critical', humanReviewRequired: true },
    high: { autoAction: AutoAction.ESCALATE, humanReviewSLA: '4h', notificationLevel: 'critical', humanReviewRequired: true },
    very_high: { autoAction: AutoAction.ESCALATE, humanReviewSLA: '1h', notificationLevel: 'critical', humanReviewRequired: true },
  },
  [ContentCategory.SEXUAL_CONTENT]: {
    low: { autoAction: AutoAction.QUARANTINE, humanReviewSLA: '24h', notificationLevel: 'warning', humanReviewRequired: true },
    medium: { autoAction: AutoAction.REJECT, humanReviewSLA: '12h', notificationLevel: 'critical', humanReviewRequired: true },
    high: { autoAction: AutoAction.REJECT, humanReviewSLA: '4h', notificationLevel: 'critical', humanReviewRequired: true },
    very_high: { autoAction: AutoAction.ESCALATE, humanReviewSLA: '1h', notificationLevel: 'critical', humanReviewRequired: true },
  },
  [ContentCategory.CSAM]: {
    low: { autoAction: AutoAction.REJECT, humanReviewSLA: '1h', notificationLevel: 'critical', humanReviewRequired: true },
    medium: { autoAction: AutoAction.REPORT_TO_AUTHORITIES, humanReviewSLA: '30min', notificationLevel: 'critical', humanReviewRequired: true },
    high: { autoAction: AutoAction.REPORT_TO_AUTHORITIES, humanReviewSLA: '15min', notificationLevel: 'critical', humanReviewRequired: true },
    very_high: { autoAction: AutoAction.REPORT_TO_AUTHORITIES, humanReviewSLA: 'immediate', notificationLevel: 'critical', humanReviewRequired: true },
  },
  [ContentCategory.PII_EXPOSURE]: {
    low: { autoAction: AutoAction.ALLOW_WITH_FLAG, humanReviewSLA: '48h', notificationLevel: 'info', humanReviewRequired: false },
    medium: { autoAction: AutoAction.QUARANTINE, humanReviewSLA: '24h', notificationLevel: 'warning', humanReviewRequired: true },
    high: { autoAction: AutoAction.QUARANTINE, humanReviewSLA: '12h', notificationLevel: 'warning', humanReviewRequired: true },
    very_high: { autoAction: AutoAction.REJECT, humanReviewSLA: '4h', notificationLevel: 'critical', humanReviewRequired: true },
  },
  [ContentCategory.SPAM]: {
    low: { autoAction: AutoAction.ALLOW_WITH_FLAG, humanReviewSLA: '72h', notificationLevel: 'none', humanReviewRequired: false },
    medium: { autoAction: AutoAction.QUARANTINE, humanReviewSLA: '48h', notificationLevel: 'info', humanReviewRequired: false },
    high: { autoAction: AutoAction.REJECT, humanReviewSLA: '24h', notificationLevel: 'warning', humanReviewRequired: true },
    very_high: { autoAction: AutoAction.REJECT, humanReviewSLA: '12h', notificationLevel: 'warning', humanReviewRequired: true },
  },
  [ContentCategory.CASTE_DISCRIMINATION]: {
    low: { autoAction: AutoAction.QUARANTINE, humanReviewSLA: '24h', notificationLevel: 'warning', humanReviewRequired: true },
    medium: { autoAction: AutoAction.REJECT, humanReviewSLA: '12h', notificationLevel: 'critical', humanReviewRequired: true },
    high: { autoAction: AutoAction.ESCALATE, humanReviewSLA: '4h', notificationLevel: 'critical', humanReviewRequired: true },
    very_high: { autoAction: AutoAction.REPORT_TO_AUTHORITIES, humanReviewSLA: '2h', notificationLevel: 'critical', humanReviewRequired: true },
  },
  [ContentCategory.RELIGIOUS_OFFENSE]: {
    low: { autoAction: AutoAction.QUARANTINE, humanReviewSLA: '24h', notificationLevel: 'warning', humanReviewRequired: true },
    medium: { autoAction: AutoAction.REJECT, humanReviewSLA: '12h', notificationLevel: 'critical', humanReviewRequired: true },
    high: { autoAction: AutoAction.ESCALATE, humanReviewSLA: '4h', notificationLevel: 'critical', humanReviewRequired: true },
    very_high: { autoAction: AutoAction.REPORT_TO_AUTHORITIES, humanReviewSLA: '2h', notificationLevel: 'critical', humanReviewRequired: true },
  },
  [ContentCategory.COMMUNAL_HATE]: {
    low: { autoAction: AutoAction.QUARANTINE, humanReviewSLA: '24h', notificationLevel: 'warning', humanReviewRequired: true },
    medium: { autoAction: AutoAction.REJECT, humanReviewSLA: '12h', notificationLevel: 'critical', humanReviewRequired: true },
    high: { autoAction: AutoAction.ESCALATE, humanReviewSLA: '4h', notificationLevel: 'critical', humanReviewRequired: true },
    very_high: { autoAction: AutoAction.REPORT_TO_AUTHORITIES, humanReviewSLA: '1h', notificationLevel: 'critical', humanReviewRequired: true },
  },
  [ContentCategory.DOWRY_REFERENCE]: {
    low: { autoAction: AutoAction.QUARANTINE, humanReviewSLA: '24h', notificationLevel: 'warning', humanReviewRequired: true },
    medium: { autoAction: AutoAction.REJECT, humanReviewSLA: '12h', notificationLevel: 'critical', humanReviewRequired: true },
    high: { autoAction: AutoAction.ESCALATE, humanReviewSLA: '4h', notificationLevel: 'critical', humanReviewRequired: true },
    very_high: { autoAction: AutoAction.REPORT_TO_AUTHORITIES, humanReviewSLA: '2h', notificationLevel: 'critical', humanReviewRequired: true },
  },
  [ContentCategory.COLORISM]: {
    low: { autoAction: AutoAction.ALLOW_WITH_FLAG, humanReviewSLA: '48h', notificationLevel: 'info', humanReviewRequired: true },
    medium: { autoAction: AutoAction.QUARANTINE, humanReviewSLA: '24h', notificationLevel: 'warning', humanReviewRequired: true },
    high: { autoAction: AutoAction.REJECT, humanReviewSLA: '12h', notificationLevel: 'warning', humanReviewRequired: true },
    very_high: { autoAction: AutoAction.ESCALATE, humanReviewSLA: '4h', notificationLevel: 'critical', humanReviewRequired: true },
  },
  [ContentCategory.MISINFORMATION]: {
    low: { autoAction: AutoAction.ALLOW_WITH_FLAG, humanReviewSLA: '48h', notificationLevel: 'info', humanReviewRequired: false },
    medium: { autoAction: AutoAction.QUARANTINE, humanReviewSLA: '24h', notificationLevel: 'warning', humanReviewRequired: true },
    high: { autoAction: AutoAction.REJECT, humanReviewSLA: '12h', notificationLevel: 'warning', humanReviewRequired: true },
    very_high: { autoAction: AutoAction.ESCALATE, humanReviewSLA: '4h', notificationLevel: 'critical', humanReviewRequired: true },
  },
  [ContentCategory.IMPERSONATION]: {
    low: { autoAction: AutoAction.ALLOW_WITH_FLAG, humanReviewSLA: '48h', notificationLevel: 'info', humanReviewRequired: true },
    medium: { autoAction: AutoAction.QUARANTINE, humanReviewSLA: '24h', notificationLevel: 'warning', humanReviewRequired: true },
    high: { autoAction: AutoAction.REJECT, humanReviewSLA: '12h', notificationLevel: 'critical', humanReviewRequired: true },
    very_high: { autoAction: AutoAction.ESCALATE, humanReviewSLA: '4h', notificationLevel: 'critical', humanReviewRequired: true },
  },
}

// ── Decision Matrix Lookup ──────────────────────────────────────────────

export function lookupDecision(category: ContentCategory, confidence: number): DecisionMatrixEntry {
  const level = getConfidenceLevel(confidence)
  const categoryMatrix = DECISION_MATRIX[category]
  if (!categoryMatrix) {
    return { autoAction: AutoAction.ALLOW_WITH_FLAG, humanReviewSLA: '48h', notificationLevel: 'info', humanReviewRequired: true }
  }
  return categoryMatrix[level]
}

// ── Content Types ───────────────────────────────────────────────────────
// 11 content types with their moderation strategies

export interface ContentTypeConfig {
  id: string
  label: string
  inputType: 'text' | 'image' | 'both'
  maxLength?: number
  requiresImageValidation?: boolean
  maxFaces?: number
  minFaces?: number
  enablePIIDetection: boolean
  enableProfanityDetection: boolean
  enableIndiaSpecificDetection: boolean
  allowedFileTypes?: string[]
  maxFileSizeKB?: number
}

export const CONTENT_TYPES: Record<string, ContentTypeConfig> = {
  person_biography: {
    id: 'person_biography',
    label: 'Person Biography',
    inputType: 'text',
    maxLength: 5000,
    enablePIIDetection: true,
    enableProfanityDetection: true,
    enableIndiaSpecificDetection: true,
  },
  family_story: {
    id: 'family_story',
    label: 'Family Story',
    inputType: 'text',
    maxLength: 10000,
    enablePIIDetection: true,
    enableProfanityDetection: true,
    enableIndiaSpecificDetection: true,
  },
  photo: {
    id: 'photo',
    label: 'Photo',
    inputType: 'image',
    requiresImageValidation: true,
    allowedFileTypes: ['image/jpeg', 'image/png', 'image/webp'],
    maxFileSizeKB: 25600,
    enablePIIDetection: false,
    enableProfanityDetection: false,
    enableIndiaSpecificDetection: false,
  },
  profile_photo: {
    id: 'profile_photo',
    label: 'Profile Photo',
    inputType: 'image',
    requiresImageValidation: true,
    minFaces: 1,
    maxFaces: 1,
    allowedFileTypes: ['image/jpeg', 'image/png', 'image/webp'],
    maxFileSizeKB: 5120,
    enablePIIDetection: false,
    enableProfanityDetection: false,
    enableIndiaSpecificDetection: false,
  },
  community_post: {
    id: 'community_post',
    label: 'Community Post',
    inputType: 'both',
    maxLength: 2000,
    requiresImageValidation: true,
    allowedFileTypes: ['image/jpeg', 'image/png', 'image/webp', 'image/gif'],
    maxFileSizeKB: 10240,
    enablePIIDetection: true,
    enableProfanityDetection: true,
    enableIndiaSpecificDetection: true,
  },
  comment: {
    id: 'comment',
    label: 'Comment',
    inputType: 'text',
    maxLength: 1000,
    enablePIIDetection: true,
    enableProfanityDetection: true,
    enableIndiaSpecificDetection: true,
  },
  person_name: {
    id: 'person_name',
    label: 'Person Name',
    inputType: 'text',
    maxLength: 200,
    enablePIIDetection: false,
    enableProfanityDetection: true,
    enableIndiaSpecificDetection: true,
  },
  community_description: {
    id: 'community_description',
    label: 'Community Description',
    inputType: 'text',
    maxLength: 2000,
    enablePIIDetection: true,
    enableProfanityDetection: true,
    enableIndiaSpecificDetection: true,
  },
  event_description: {
    id: 'event_description',
    label: 'Event Description',
    inputType: 'text',
    maxLength: 5000,
    enablePIIDetection: true,
    enableProfanityDetection: true,
    enableIndiaSpecificDetection: true,
  },
  matrimonial_profile: {
    id: 'matrimonial_profile',
    label: 'Matrimonial Profile',
    inputType: 'both',
    maxLength: 5000,
    requiresImageValidation: true,
    allowedFileTypes: ['image/jpeg', 'image/png', 'image/webp'],
    maxFileSizeKB: 10240,
    enablePIIDetection: true,
    enableProfanityDetection: true,
    enableIndiaSpecificDetection: true,
  },
  invitation_message: {
    id: 'invitation_message',
    label: 'Invitation Message',
    inputType: 'text',
    maxLength: 500,
    enablePIIDetection: true,
    enableProfanityDetection: true,
    enableIndiaSpecificDetection: false,
  },
}

// ── Priority Mapping ────────────────────────────────────────────────────

export function categoryToPriority(category: ContentCategory, confidence: number): string {
  const criticalCategories: ContentCategory[] = [
    ContentCategory.CSAM,
    ContentCategory.HATE_SPEECH,
    ContentCategory.COMMUNAL_HATE,
    ContentCategory.CASTE_DISCRIMINATION,
    ContentCategory.VIOLENCE,
  ]

  const highCategories: ContentCategory[] = [
    ContentCategory.HARASSMENT,
    ContentCategory.SEXUAL_CONTENT,
    ContentCategory.RELIGIOUS_OFFENSE,
    ContentCategory.DOWRY_REFERENCE,
  ]

  if (criticalCategories.includes(category) && confidence >= 0.6) return 'critical'
  if (criticalCategories.includes(category)) return 'urgent'
  if (highCategories.includes(category) && confidence >= 0.7) return 'urgent'
  if (highCategories.includes(category)) return 'high'
  if (category === ContentCategory.PII_EXPOSURE && confidence >= 0.7) return 'high'
  if (category === ContentCategory.BORDERLINE) return 'normal'
  if (category === ContentCategory.SAFE) return 'low'
  return 'normal'
}
