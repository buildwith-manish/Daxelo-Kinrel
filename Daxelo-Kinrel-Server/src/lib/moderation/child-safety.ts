// DAXELO KINREL — Pack 08: Child Safety Service
// Minor detection, parental consent, and CSAM handling protocols for Indian law (POCSO Act)

import { db } from '@/lib/db'

// ── Minor Detection ─────────────────────────────────────────────────────

export function isMinor(dateOfBirth: Date): boolean {
  return calculateAge(dateOfBirth) < 18
}

export function calculateAge(dateOfBirth: Date): number {
  const today = new Date()
  let age = today.getFullYear() - dateOfBirth.getFullYear()
  const monthDiff = today.getMonth() - dateOfBirth.getMonth()

  if (monthDiff < 0 || (monthDiff === 0 && today.getDate() < dateOfBirth.getDate())) {
    age--
  }

  return age
}

// ── Minor Restrictions ──────────────────────────────────────────────────

export const MINOR_RESTRICTIONS = {
  visibility: 'family_only',         // Only family members can see minor's profile
  searchability: false,               // Minors cannot appear in search results
  matrimonial: false,                 // No access to matrimonial features
  community: false,                   // No community posting
  directMessaging: false,             // No direct messaging with non-family
  photoUpload: 'requires_consent',   // Photo upload requires parental consent
  healthData: 'requires_consent',    // Health data requires parental consent
  educationData: 'requires_consent', // Education data requires parental consent
  profileEditing: 'limited',         // Limited profile editing
  shareableLinks: false,             // Cannot create shareable links
  publicProfile: false,              // Profile never public
  locationSharing: false,            // No location sharing
  dataExport: 'requires_consent',    // Data export requires parental consent
} as const

// ── CSAM Handling Protocol ──────────────────────────────────────────────

export const CSAM_HANDLING_PROTOCOL = {
  quarantine: {
    immediate: true,
    description: 'Immediately quarantine content and prevent any further access',
    retentionDays: 90, // Retain for law enforcement
  },
  preserveEvidence: {
    enabled: true,
    description: 'Preserve original content with full metadata for law enforcement',
    includes: ['original_file', 'upload_timestamp', 'uploader_ip', 'user_agent', 'device_info'],
    hashAlgorithm: 'SHA-256',
  },
  reportNCMEC: {
    enabled: true,
    description: 'Report to National Center for Missing & Exploited Children (US-hosted content)',
    endpoint: 'https://report.cybertip.org/ispc/',
    mandatoryForUS: true,
    timeline: 'Within 24 hours of detection',
  },
  reportNCRB: {
    enabled: true,
    description: 'Report to National Crime Records Bureau (India)',
    endpoint: 'https://ncrb.gov.in/',
    mandatoryForIndia: true,
    timeline: 'Immediately upon detection',
    legalBasis: 'POCSO Act 2012, Section 19-21',
  },
  banUploader: {
    immediate: true,
    description: 'Immediately ban the uploader account',
    notifyLawEnforcement: true,
    retainAccountData: true, // For investigation
  },
} as const

// ── Apply Minor Restrictions ────────────────────────────────────────────

export async function applyMinorRestrictions(personId: string): Promise<void> {
  // Find the person to verify they are a minor
  const person = await db.person.findUnique({
    where: { id: personId },
  })

  if (!person || !person.dateOfBirth || !isMinor(person.dateOfBirth)) {
    return // Not a minor, no restrictions needed
  }

  // Update person privacy level to family-only
  await db.person.update({
    where: { id: personId },
    data: {
      privacyLevel: 'family',
    },
  })

  // Note: Additional restrictions (search, matrimonial, community) would be enforced
  // at the application layer by checking the person's age before allowing access
  // These are documented in MINOR_RESTRICTIONS above
}

// ── Check Parental Consent ──────────────────────────────────────────────

export async function checkParentalConsent(
  childPersonId: string,
  consentType: string,
): Promise<boolean> {
  const consent = await db.parentalConsent.findFirst({
    where: {
      childPersonId,
      consentType,
      consented: true,
      revokedAt: null,
    },
  })

  return consent !== null
}

// ── Require Parental Consent ────────────────────────────────────────────

export async function requireConsent(
  childPersonId: string,
  guardianUserId: string,
  consentType: string,
): Promise<ParentalConsentRow> {
  // Check if consent already exists
  const existing = await db.parentalConsent.findFirst({
    where: {
      childPersonId,
      guardianUserId,
      consentType,
      revokedAt: null,
    },
  })

  if (existing) {
    return existing
  }

  // Create new consent request (not yet consented)
  const consent = await db.parentalConsent.create({
    data: {
      childPersonId,
      guardianUserId,
      consentType,
      consented: false,
      consentMethod: 'in_app', // Default method
    },
  })

  return consent
}

// ── Grant Parental Consent ──────────────────────────────────────────────

export async function grantConsent(
  consentId: string,
  method: string,
  ipAddress?: string,
  userAgent?: string,
): Promise<void> {
  await db.parentalConsent.update({
    where: { id: consentId },
    data: {
      consented: true,
      consentGivenAt: new Date(),
      consentMethod: method,
      ipAddress: ipAddress || null,
      userAgent: userAgent || null,
    },
  })
}

// ── Revoke Parental Consent ─────────────────────────────────────────────

export async function revokeConsent(consentId: string): Promise<void> {
  await db.parentalConsent.update({
    where: { id: consentId },
    data: {
      consented: false,
      revokedAt: new Date(),
    },
  })

  // Apply restrictions immediately upon revocation
  const consent = await db.parentalConsent.findUnique({ where: { id: consentId } })
  if (consent) {
    await applyMinorRestrictions(consent.childPersonId)
  }
}

// ── Get All Consents for a Child ────────────────────────────────────────

export async function getChildConsents(childPersonId: string): Promise<ParentalConsentRow[]> {
  return db.parentalConsent.findMany({
    where: { childPersonId },
    orderBy: { createdAt: 'desc' },
  })
}

// ── Type Aliases ────────────────────────────────────────────────────────

type ParentalConsentRow = Awaited<ReturnType<typeof db.parentalConsent.create>>
