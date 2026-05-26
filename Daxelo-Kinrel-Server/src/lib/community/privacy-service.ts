// DAXELO KINREL — Pack 09: Privacy Boundary Service
// Field-level privacy filtering with accessor levels and Indian family context

import { db } from '@/lib/db';

// ── Types ────────────────────────────────────────────────────────────

export type AccessorLevel =
  | 'self'
  | 'immediate_family'
  | 'extended_family'
  | 'family_admins'
  | 'nobody';

export interface PrivacyFieldRule {
  field: string;
  defaultLevel: AccessorLevel;
  label: string;
  labelHi: string;
}

// ── Privacy Hierarchy ────────────────────────────────────────────────

export const PRIVACY_HIERARCHY: AccessorLevel[] = [
  'self',
  'immediate_family',
  'extended_family',
  'family_admins',
  'nobody',
];

// ── Default Privacy Settings ─────────────────────────────────────────

export const DEFAULT_PRIVACY: Record<string, AccessorLevel> = {
  name: 'extended_family',
  dateOfBirth: 'immediate_family',
  gotra: 'extended_family',
  occupation: 'extended_family',
  city: 'extended_family',
  relationship: 'immediate_family',
  isDeceased: 'extended_family',
  phone: 'immediate_family',
  email: 'immediate_family',
  photo: 'immediate_family',
  health: 'nobody',
  financial: 'nobody',
  matrimonial: 'nobody',
  location: 'immediate_family',
  education: 'extended_family',
};

// ── Privacy Field Rules ──────────────────────────────────────────────

export const PRIVACY_FIELD_RULES: PrivacyFieldRule[] = [
  { field: 'name', defaultLevel: 'extended_family', label: 'Name', labelHi: 'नाम' },
  { field: 'dateOfBirth', defaultLevel: 'immediate_family', label: 'Date of Birth', labelHi: 'जन्मतिथि' },
  { field: 'gotra', defaultLevel: 'extended_family', label: 'Gotra', labelHi: 'गोत्र' },
  { field: 'occupation', defaultLevel: 'extended_family', label: 'Occupation', labelHi: 'व्यवसाय' },
  { field: 'city', defaultLevel: 'extended_family', label: 'City', labelHi: 'शहर' },
  { field: 'relationship', defaultLevel: 'immediate_family', label: 'Relationship', labelHi: 'रिश्ता' },
  { field: 'isDeceased', defaultLevel: 'extended_family', label: 'Deceased Status', labelHi: 'दिवंगत स्थिति' },
  { field: 'phone', defaultLevel: 'immediate_family', label: 'Phone', labelHi: 'फ़ोन' },
  { field: 'email', defaultLevel: 'immediate_family', label: 'Email', labelHi: 'ईमेल' },
  { field: 'photo', defaultLevel: 'immediate_family', label: 'Photo', labelHi: 'फ़ोटो' },
  { field: 'health', defaultLevel: 'nobody', label: 'Health Info', labelHi: 'स्वास्थ्य जानकारी' },
  { field: 'financial', defaultLevel: 'nobody', label: 'Financial Info', labelHi: 'वित्तीय जानकारी' },
  { field: 'matrimonial', defaultLevel: 'nobody', label: 'Matrimonial Info', labelHi: 'वैवाहिक जानकारी' },
  { field: 'location', defaultLevel: 'immediate_family', label: 'Location', labelHi: 'स्थान' },
  { field: 'education', defaultLevel: 'extended_family', label: 'Education', labelHi: 'शिक्षा' },
];

// ── Immediate Relationship Types ─────────────────────────────────────

const IMMEDIATE_RELATIONSHIPS = new Set([
  'father', 'mother', 'parent',
  'son', 'daughter', 'child',
  'brother', 'sister', 'sibling',
  'husband', 'wife', 'spouse',
  'father_in_law', 'mother_in_law',
  'son_in_law', 'daughter_in_law',
  'brother_in_law', 'sister_in_law',
]);

// ── Core Functions ───────────────────────────────────────────────────

/**
 * Get a person's data with field-level privacy filtering based on accessor
 */
export async function getPersonWithPrivacy(
  personId: string,
  accessorId: string
): Promise<Record<string, unknown> | null> {
  const person = await db.person.findUnique({
    where: { id: personId },
  });

  if (!person) return null;

  // Get person's family to check membership
  const familyMember = await db.familyMember.findFirst({
    where: {
      familyId: person.familyId,
      userId: accessorId,
    },
  });

  const accessorLevel = await getAccessorLevel(accessorId, personId);

  // Get privacy settings for this person
  const privacySettings = await db.personPrivacySetting.findUnique({
    where: { personId },
  });

  // Build filtered result
  const result: Record<string, unknown> = { id: person.id, familyId: person.familyId };

  // Always allow ID and familyId
  const fieldsToCheck: Record<string, unknown> = {
    name: person.name,
    dateOfBirth: person.dateOfBirth,
    gotra: person.gotra,
    occupation: person.occupation,
    city: person.city,
    relationship: person.relationship,
    isDeceased: person.isDeceased,
  };

  for (const [field, value] of Object.entries(fieldsToCheck)) {
    const requiredLevel = getEffectivePrivacyLevel(field, privacySettings);
    if (canAccess(accessorLevel, requiredLevel)) {
      result[field] = value;
    }
  }

  // Log the access
  await logDataAccess(accessorId, personId, 'person_view', 'read');

  return result;
}

/**
 * Determine the accessor level for a user viewing a person
 */
export async function getAccessorLevel(
  accessorId: string,
  personId: string
): Promise<AccessorLevel> {
  // Check if accessor is the person themselves (via linked user)
  const person = await db.person.findUnique({
    where: { id: personId },
  });

  if (!person) return 'nobody';

  // Check if accessor is a family admin
  const accessorFamilyMember = await db.familyMember.findFirst({
    where: {
      familyId: person.familyId,
      userId: accessorId,
      role: 'admin',
    },
  });

  if (accessorFamilyMember) return 'family_admins';

  // Check if accessor is in immediate family
  const isImmediate = await isInImmediateFamily(accessorId, personId);
  if (isImmediate) return 'immediate_family';

  // Check if accessor is in same family
  const isInFamily = await db.familyMember.findFirst({
    where: {
      familyId: person.familyId,
      userId: accessorId,
    },
  });

  if (isInFamily) return 'extended_family';

  return 'nobody';
}

/**
 * Check if an accessor level can access a field with the required level
 */
export function canAccess(accessorLevel: AccessorLevel, requiredLevel: AccessorLevel): boolean {
  const accessorIdx = PRIVACY_HIERARCHY.indexOf(accessorLevel);
  const requiredIdx = PRIVACY_HIERARCHY.indexOf(requiredLevel);

  // Lower index = higher access
  // self (0) can see everything except nobody (4)
  // immediate_family (1) can see immediate_family and below
  return accessorIdx <= requiredIdx;
}

/**
 * Get IDs of immediate family members for a person
 */
export async function getImmediateFamilyMemberIds(personId: string): Promise<string[]> {
  const person = await db.person.findUnique({
    where: { id: personId },
  });

  if (!person) return [];

  // Find all persons in same family with immediate relationship types
  const immediateMembers = await db.person.findMany({
    where: {
      familyId: person.familyId,
      relationship: { in: [...IMMEDIATE_RELATIONSHIPS] },
    },
    select: { id: true },
  });

  return immediateMembers.map((p) => p.id);
}

/**
 * Check if a relationship type is considered "immediate family"
 */
export function isImmediateRelationship(type: string): boolean {
  return IMMEDIATE_RELATIONSHIPS.has(type.toLowerCase().replace(/\s+/g, '_'));
}

/**
 * Check if a viewer can see a specific post
 */
export async function canViewPost(
  post: { visibility: string; familyId?: string | null; communityId?: string | null; authorId: string },
  viewerId: string
): Promise<boolean> {
  // Public posts are visible to everyone
  if (post.visibility === 'public') return true;

  // Author can always see their own posts
  if (post.authorId === viewerId) return true;

  // Members-only posts: check community membership
  if (post.visibility === 'members' && post.communityId) {
    const membership = await db.communityMember.findFirst({
      where: { communityId: post.communityId, userId: viewerId },
    });
    return !!membership;
  }

  // Family-only posts: check family membership
  if (post.visibility === 'family_only' && post.familyId) {
    const membership = await db.familyMember.findFirst({
      where: { familyId: post.familyId, userId: viewerId },
    });
    return !!membership;
  }

  return false;
}

/**
 * Log a data access event
 */
export async function logDataAccess(
  accessorId: string,
  personId: string,
  field: string,
  accessType: string
): Promise<void> {
  try {
    await db.dataAccessLog.create({
      data: {
        personId,
        viewerId: accessorId,
        viewerRole: 'member',
        fieldAccessed: field,
        granted: true,
        reason: accessType,
      },
    });
  } catch {
    // Don't fail the main operation if logging fails
  }
}

// ── Helpers ──────────────────────────────────────────────────────────

async function isInImmediateFamily(
  accessorId: string,
  personId: string
): Promise<boolean> {
  const person = await db.person.findUnique({ where: { id: personId } });
  if (!person) return false;

  // Check if the accessor is a family member of the same family
  // and their linked person has an immediate relationship
  const accessorFamilyMember = await db.familyMember.findFirst({
    where: { userId: accessorId, familyId: person.familyId },
  });

  if (!accessorFamilyMember) return false;

  // For now, consider all same-family members as extended family
  // unless they have a specific immediate relationship
  // In a full implementation, this would trace the relationship graph
  return false; // Conservative: require explicit relationship check
}

function getEffectivePrivacyLevel(
  field: string,
  privacySettings: { visibility?: string; gotraVisibility?: string } | null
): AccessorLevel {
  if (!privacySettings) {
    return DEFAULT_PRIVACY[field] ?? 'extended_family';
  }

  // Check gotra-specific visibility
  if (field === 'gotra' && privacySettings.gotraVisibility) {
    return mapVisibilityToAccessorLevel(privacySettings.gotraVisibility);
  }

  // Check general visibility for other fields
  if (privacySettings.visibility) {
    // Map the general visibility to field-specific levels
    return mapVisibilityToAccessorLevel(privacySettings.visibility);
  }

  return DEFAULT_PRIVACY[field] ?? 'extended_family';
}

function mapVisibilityToAccessorLevel(visibility: string): AccessorLevel {
  switch (visibility) {
    case 'public':
      return 'extended_family';
    case 'extended':
      return 'extended_family';
    case 'family_only':
      return 'immediate_family';
    case 'admin':
      return 'family_admins';
    case 'self':
      return 'self';
    case 'hidden':
      return 'nobody';
    default:
      return 'extended_family';
  }
}
