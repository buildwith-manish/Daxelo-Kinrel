// DAXELO KINREL — Pack 08: Image Classification Pipeline
// Image validation, face detection simulation, and content rules checking

import {
  ContentCategory,
  AutoAction,
  ClassificationResult,
  ClassificationDetails,
  StageResult,
  lookupDecision,
} from './classification'

// ── Magic Bytes / File Signatures ───────────────────────────────────────

export const MAGIC_BYTES: Record<string, { bytes: number[]; offset: number; format: string }> = {
  png: { bytes: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a], offset: 0, format: 'PNG' },
  jpeg_start: { bytes: [0xff, 0xd8, 0xff], offset: 0, format: 'JPEG' },
  jpeg_end: { bytes: [0xff, 0xd9], offset: -2, format: 'JPEG' },
  gif87: { bytes: [0x47, 0x49, 0x46, 0x38, 0x37, 0x61], offset: 0, format: 'GIF' },
  gif89: { bytes: [0x47, 0x49, 0x46, 0x38, 0x39, 0x61], offset: 0, format: 'GIF' },
  webp: { bytes: [0x52, 0x49, 0x46, 0x46], offset: 0, format: 'WebP' }, // RIFF header, then WEBP at offset 8
}

// ── Constants ───────────────────────────────────────────────────────────

export const MAX_IMAGE_SIZE = 25 * 1024 * 1024 // 25MB

const ALLOWED_MIME_TYPES = ['image/jpeg', 'image/png', 'image/gif', 'image/webp']

// ── Image Rules by Content Type ─────────────────────────────────────────

export interface ImageRule {
  contentType: string
  minFaces: number
  maxFaces: number
  allowGroupPhotos: boolean
  requireSingleSubject: boolean
  maxFileSizeKB: number
  allowedFormats: string[]
  description: string
}

export const IMAGE_RULES: Record<string, ImageRule> = {
  profile_photo: {
    contentType: 'profile_photo',
    minFaces: 1,
    maxFaces: 1,
    allowGroupPhotos: false,
    requireSingleSubject: true,
    maxFileSizeKB: 5120,
    allowedFormats: ['JPEG', 'PNG', 'WebP'],
    description: 'Profile photo must have exactly 1 face, no group photos',
  },
  photo: {
    contentType: 'photo',
    minFaces: 0,
    maxFaces: 50,
    allowGroupPhotos: true,
    requireSingleSubject: false,
    maxFileSizeKB: 25600,
    allowedFormats: ['JPEG', 'PNG', 'WebP'],
    description: 'General photo with no strict face requirements',
  },
  community_post: {
    contentType: 'community_post',
    minFaces: 0,
    maxFaces: 50,
    allowGroupPhotos: true,
    requireSingleSubject: false,
    maxFileSizeKB: 10240,
    allowedFormats: ['JPEG', 'PNG', 'WebP', 'GIF'],
    description: 'Community post images allow group photos',
  },
  matrimonial_profile: {
    contentType: 'matrimonial_profile',
    minFaces: 1,
    maxFaces: 1,
    allowGroupPhotos: false,
    requireSingleSubject: true,
    maxFileSizeKB: 10240,
    allowedFormats: ['JPEG', 'PNG', 'WebP'],
    description: 'Matrimonial profile must have exactly 1 face',
  },
}

// ── Image Validation ────────────────────────────────────────────────────

export function validateImage(buffer: Buffer): {
  valid: boolean
  format?: string
  size?: number
  error?: string
} {
  if (!buffer || buffer.length === 0) {
    return { valid: false, error: 'Empty image buffer' }
  }

  if (buffer.length > MAX_IMAGE_SIZE) {
    return {
      valid: false,
      size: buffer.length,
      error: `Image size ${buffer.length} bytes exceeds maximum ${MAX_IMAGE_SIZE} bytes (25MB)`,
    }
  }

  // Check PNG
  if (
    buffer[0] === 0x89 && buffer[1] === 0x50 &&
    buffer[2] === 0x4e && buffer[3] === 0x47 &&
    buffer[4] === 0x0d && buffer[5] === 0x0a &&
    buffer[6] === 0x1a && buffer[7] === 0x0a
  ) {
    return { valid: true, format: 'PNG', size: buffer.length }
  }

  // Check JPEG
  if (buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) {
    return { valid: true, format: 'JPEG', size: buffer.length }
  }

  // Check GIF87a
  if (
    buffer[0] === 0x47 && buffer[1] === 0x49 &&
    buffer[2] === 0x46 && buffer[3] === 0x38 &&
    buffer[4] === 0x37 && buffer[5] === 0x61
  ) {
    return { valid: true, format: 'GIF', size: buffer.length }
  }

  // Check GIF89a
  if (
    buffer[0] === 0x47 && buffer[1] === 0x49 &&
    buffer[2] === 0x46 && buffer[3] === 0x38 &&
    buffer[4] === 0x39 && buffer[5] === 0x61
  ) {
    return { valid: true, format: 'GIF', size: buffer.length }
  }

  // Check WebP (RIFF + WEBP)
  if (
    buffer[0] === 0x52 && buffer[1] === 0x49 &&
    buffer[2] === 0x46 && buffer[3] === 0x46 &&
    buffer.length > 11 &&
    buffer[8] === 0x57 && buffer[9] === 0x45 &&
    buffer[10] === 0x42 && buffer[11] === 0x50
  ) {
    return { valid: true, format: 'WebP', size: buffer.length }
  }

  return { valid: false, size: buffer.length, error: 'Unrecognized image format' }
}

// ── Face Detection (Simplified for Production) ─────────────────────────
// In production, this would call a face detection API (e.g., AWS Rekognition, Google Vision)
// For now, we simulate based on image metadata and heuristics

export async function detectFaces(buffer: Buffer): Promise<{
  count: number
  hasMinor: boolean
  confidence: number
  details: string[]
}> {
  const details: string[] = []

  // Simulated face detection — in production, integrate with:
  // - AWS Rekognition DetectFaces
  // - Google Cloud Vision API face detection
  // - Azure Face API

  // For now, we return a default result that assumes 1 adult face
  // Real implementation would analyze the image buffer
  const format = validateImage(buffer)
  if (!format.valid) {
    details.push('Invalid image format for face detection')
    return { count: 0, hasMinor: false, confidence: 0, details }
  }

  // Simulated: return 1 face for valid images
  // This is a placeholder that should be replaced with actual face detection
  details.push(`Image format: ${format.format}`)
  details.push('Face detection: simulated (production needs API integration)')

  return {
    count: 1,
    hasMinor: false,
    confidence: 0.8,
    details,
  }
}

// ── Image Rules Checker ─────────────────────────────────────────────────

export function checkImageRules(
  contentType: string,
  faceCount: number,
): { passed: boolean; violations: string[] } {
  const violations: string[] = []
  const rules = IMAGE_RULES[contentType]

  if (!rules) {
    // No specific rules for this content type — allow
    return { passed: true, violations: [] }
  }

  if (faceCount < rules.minFaces) {
    violations.push(
      `Expected at least ${rules.minFaces} face(s), found ${faceCount}`,
    )
  }

  if (faceCount > rules.maxFaces) {
    violations.push(
      `Expected at most ${rules.maxFaces} face(s), found ${faceCount}`,
    )
  }

  if (rules.requireSingleSubject && faceCount !== 1) {
    violations.push(
      `This content type requires exactly 1 subject, found ${faceCount} face(s)`,
    )
  }

  return { passed: violations.length === 0, violations }
}

// ── NSFW Detection (Simplified) ─────────────────────────────────────────
// In production, integrate with a dedicated NSFW detection service

function estimateNSFWScore(buffer: Buffer): { score: number; flags: string[] } {
  const flags: string[] = []

  // Simplified heuristic checks
  const format = validateImage(buffer)

  if (!format.valid) {
    return { score: 0, flags: ['invalid_format'] }
  }

  // Check for very small images (potential inappropriate content indicators)
  if (buffer.length < 1024) {
    flags.push('very_small_image')
  }

  // In production, use:
  // - AWS Rekognition DetectModerationLabels
  // - Google Cloud Vision Safe Search
  // - NSFWJS (open-source)
  // - Clarifai NSFW model

  return { score: 0, flags }
}

// ── Watermark Detection ─────────────────────────────────────────────────

function detectWatermarks(buffer: Buffer): { hasWatermark: boolean; type?: string } {
  // Simplified watermark detection
  // In production, use OCR + pattern matching for:
  // - "Shaadi.com" / "BharatMatrimony" / "Jeevansathi" watermarks on matrimonial photos
  // - Stock photo watermarks (Shutterstock, Getty, etc.)

  return { hasWatermark: false }
}

// ── Main Image Classification ───────────────────────────────────────────

export async function classify(imageData: {
  url?: string
  buffer?: Buffer
  contentType: string
}): Promise<ClassificationResult> {
  const stageResults: StageResult[] = []
  const flaggedCategories: ContentCategory[] = []
  const matchedPatterns: string[] = []
  const scoreBreakdown: Record<string, number> = {}
  let overallScore = 0

  // Stage 1: Image Validation
  if (imageData.buffer) {
    const validation = validateImage(imageData.buffer)
    stageResults.push({
      stage: 'image_validation',
      passed: validation.valid,
      score: validation.valid ? 0 : 0.5,
      findings: validation.valid
        ? [`Format: ${validation.format}, Size: ${validation.size} bytes`]
        : [validation.error || 'Invalid image'],
    })
    if (!validation.valid) {
      flaggedCategories.push(ContentCategory.BORDERLINE)
      overallScore += 0.3
      scoreBreakdown['invalid_format'] = 0.3
    }
  } else {
    stageResults.push({
      stage: 'image_validation',
      passed: false,
      score: 0.5,
      findings: ['No image buffer provided'],
    })
  }

  // Stage 2: Face Detection
  let faceCount = 0
  let hasMinor = false
  if (imageData.buffer) {
    const faceResult = await detectFaces(imageData.buffer)
    faceCount = faceResult.count
    hasMinor = faceResult.hasMinor

    stageResults.push({
      stage: 'face_detection',
      passed: true,
      score: faceResult.confidence,
      findings: faceResult.details,
    })

    if (hasMinor) {
      flaggedCategories.push(ContentCategory.CSAM)
      overallScore += 0.8
      scoreBreakdown['minor_detected'] = 0.8
    }
  } else {
    stageResults.push({
      stage: 'face_detection',
      passed: true,
      score: 0,
      findings: ['Skipped: no buffer'],
    })
  }

  // Stage 3: Image Rules Check
  const rulesResult = checkImageRules(imageData.contentType, faceCount)
  stageResults.push({
    stage: 'image_rules',
    passed: rulesResult.passed,
    score: rulesResult.violations.length * 0.3,
    findings: rulesResult.violations,
  })
  if (!rulesResult.passed) {
    flaggedCategories.push(ContentCategory.BORDERLINE)
    overallScore += rulesResult.violations.length * 0.2
    scoreBreakdown['rule_violations'] = rulesResult.violations.length * 0.2
  }

  // Stage 4: NSFW Detection
  if (imageData.buffer) {
    const nsfwResult = estimateNSFWScore(imageData.buffer)
    stageResults.push({
      stage: 'nsfw_detection',
      passed: nsfwResult.score < 0.5,
      score: nsfwResult.score,
      findings: nsfwResult.flags,
    })
    if (nsfwResult.score >= 0.5) {
      flaggedCategories.push(ContentCategory.SEXUAL_CONTENT)
      overallScore += nsfwResult.score
      scoreBreakdown['nsfw_score'] = nsfwResult.score
    }
  }

  // Stage 5: Watermark Detection
  if (imageData.buffer && imageData.contentType === 'matrimonial_profile') {
    const watermarkResult = detectWatermarks(imageData.buffer)
    stageResults.push({
      stage: 'watermark_detection',
      passed: !watermarkResult.hasWatermark,
      score: watermarkResult.hasWatermark ? 0.4 : 0,
      findings: watermarkResult.hasWatermark
        ? [`Watermark detected: ${watermarkResult.type}`]
        : [],
    })
    if (watermarkResult.hasWatermark) {
      matchedPatterns.push('matrimonial_watermark')
      overallScore += 0.3
      scoreBreakdown['watermark'] = 0.3
    }
  }

  // Determine final category
  let category: ContentCategory = ContentCategory.SAFE
  if (flaggedCategories.includes(ContentCategory.CSAM)) {
    category = ContentCategory.CSAM
  } else if (flaggedCategories.includes(ContentCategory.SEXUAL_CONTENT)) {
    category = ContentCategory.SEXUAL_CONTENT
  } else if (flaggedCategories.includes(ContentCategory.BORDERLINE)) {
    category = ContentCategory.BORDERLINE
  }

  const confidence = Math.min(overallScore, 1.0)
  const decision = lookupDecision(category, confidence)

  const details: ClassificationDetails = {
    piiTypes: [],
    matchedPatterns,
    scoreBreakdown,
    stageResults,
    recommendedAction: decision.autoAction,
    humanReviewRequired: decision.humanReviewRequired,
    humanReviewSLA: decision.humanReviewSLA !== 'none' ? decision.humanReviewSLA : undefined,
    notificationLevel: decision.notificationLevel,
  }

  return {
    category,
    confidence,
    autoAction: decision.autoAction,
    flaggedCategories: [...new Set(flaggedCategories)],
    details,
  }
}
