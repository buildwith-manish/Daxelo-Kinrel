/**
 * DAXELO KINREL — Cultural Sensitivity Utilities
 *
 * Handles culturally sensitive data for the Indian family context:
 * - Gotra visibility rules (Hindu lineage system)
 * - Stigmatized health condition protection levels
 * - High-sensitivity relationship terminology
 * - Religious memorial guidelines
 * - Privacy-aware display names
 *
 * Pack 06: Accessibility — Cultural sensitivity
 */

// ── Gotra Visibility Rules ────────────────────────────────────────

/**
 * Gotra is a Hindu lineage system that must be handled with extreme
 * cultural sensitivity. It affects matrimonial decisions and revealing
 * it inappropriately can cause social issues.
 *
 * Rules define who can see gotra information by viewer context.
 * - false: never visible
 * - true: always visible
 * - 'consent_required': visible only with explicit consent
 * - 'restricted': visible only to authorized admins with audit
 */
export const GOTRA_VISIBILITY_RULES: Record<
  string,
  boolean | 'consent_required' | 'restricted'
> = {
  public: false,
  extended: false,
  family: 'consent_required',
  self: true,
  admin: true,
  matrimonial: 'consent_required',
  search: false,
  api: 'restricted',
} as const;

/**
 * Determine if a viewer can see gotra information.
 *
 * @param viewerRole - The viewer's relationship context
 * @param hasConsent - Whether the person has given explicit consent
 * @returns Whether gotra can be shown
 *
 * @example
 * canViewGotra('self', false)          // true
 * canViewGotra('family', true)         // true (with consent)
 * canViewGotra('family', false)        // false (no consent)
 * canViewGotra('public', true)         // false (never public)
 */
export function canViewGotra(viewerRole: string, hasConsent: boolean): boolean {
  const rule = GOTRA_VISIBILITY_RULES[viewerRole];
  if (rule === undefined) return false;
  if (rule === true) return true;
  if (rule === false) return false;
  if (rule === 'consent_required') return hasConsent;
  if (rule === 'restricted') return hasConsent; // restricted also needs consent
  return false;
}

// ── Stigmatized Health Conditions ─────────────────────────────────

/**
 * Set of health conditions that carry social stigma in Indian society.
 * These require enhanced privacy protection beyond standard health data.
 *
 * Categories:
 * - Mental health (8 conditions)
 * - Sexual health (4 conditions)
 * - Infectious diseases (3 conditions)
 * - Neurological (1 condition)
 * - Addiction (2 conditions)
 * - Reproductive (4 conditions)
 */
export const STIGMATIZED_CONDITIONS = new Set<string>([
  // Mental health
  'depression',
  'anxiety',
  'bipolar',
  'schizophrenia',
  'ocd',
  'ptsd',
  'eating_disorder',
  'suicidal_ideation',
  // Sexual health
  'hiv',
  'aids',
  'syphilis',
  'gonorrhea',
  'herpes',
  // Infectious diseases
  'leprosy',
  'tuberculosis',
  // Neurological
  'epilepsy',
  // Addiction
  'alcoholism',
  'drug_addiction',
  // Reproductive
  'infertility',
  'impotence',
  'pcod',
  'pcos',
]);

/**
 * Protection levels for stigmatized conditions.
 * Higher levels = more restrictive data handling.
 */
export interface StigmaProtectionLevel {
  /** Whether the condition is private by default */
  defaultPrivate: boolean;
  /** Whether to include in pattern/analytics sharing */
  shareInPatterns: boolean;
  /** Whether to include in aggregate insights */
  aggregateInsights: boolean;
  /** Data retention period in days (null = indefinite) */
  retentionDays: number | null;
  /** Whether to exclude from search indexing */
  excludeFromSearch: boolean;
  /** Whether to exclude from data export */
  excludeFromExport: boolean;
  /** Whether double consent is required for any sharing */
  requireDoubleConsent: boolean;
}

/**
 * Protection levels by category.
 * - standard: non-stigmatized conditions
 * - elevated: social stigma but manageable (e.g., epilepsy, PCOS)
 * - maximum: severe stigma / life impact (e.g., HIV, suicidal ideation)
 */
export const STIGMA_PROTECTION: Record<string, StigmaProtectionLevel> = {
  standard: {
    defaultPrivate: true,
    shareInPatterns: true,
    aggregateInsights: true,
    retentionDays: null,
    excludeFromSearch: false,
    excludeFromExport: false,
    requireDoubleConsent: false,
  },
  elevated: {
    defaultPrivate: true,
    shareInPatterns: false,
    aggregateInsights: true,
    retentionDays: 365,
    excludeFromSearch: true,
    excludeFromExport: true,
    requireDoubleConsent: true,
  },
  maximum: {
    defaultPrivate: true,
    shareInPatterns: false,
    aggregateInsights: false,
    retentionDays: 90,
    excludeFromSearch: true,
    excludeFromExport: true,
    requireDoubleConsent: true,
  },
} as const;

/**
 * Maximum-stigma conditions that get the highest protection.
 * These include conditions with severe social consequences
 * in Indian society (marriage prospects, social exclusion).
 */
const MAXIMUM_STIGMA_CONDITIONS = new Set<string>([
  'hiv',
  'aids',
  'suicidal_ideation',
  'schizophrenia',
  'leprosy',
  'syphilis',
  'gonorrhea',
  'herpes',
  'drug_addiction',
  'infertility',
  'impotence',
]);

/**
 * Elevated-stigma conditions that get moderate protection.
 * These carry social stigma but are more commonly discussed.
 */
const ELEVATED_STIGMA_CONDITIONS = new Set<string>([
  'depression',
  'anxiety',
  'bipolar',
  'ocd',
  'ptsd',
  'eating_disorder',
  'alcoholism',
  'epilepsy',
  'tuberculosis',
  'pcod',
  'pcos',
]);

/**
 * Get the stigma protection level for a condition.
 *
 * @param condition - The health condition key
 * @returns Protection level: 'standard', 'elevated', or 'maximum'
 *
 * @example
 * getStigmaProtectionLevel('diabetes')    // 'standard'
 * getStigmaProtectionLevel('depression')  // 'elevated'
 * getStigmaProtectionLevel('hiv')         // 'maximum'
 */
export function getStigmaProtectionLevel(
  condition: string
): 'standard' | 'elevated' | 'maximum' {
  if (MAXIMUM_STIGMA_CONDITIONS.has(condition)) return 'maximum';
  if (ELEVATED_STIGMA_CONDITIONS.has(condition)) return 'elevated';
  return 'standard';
}

/**
 * Check if a condition is in the stigmatized set.
 *
 * @param condition - The health condition key
 * @returns Whether the condition requires stigma protection
 */
export function isStigmatizedCondition(condition: string): boolean {
  return STIGMATIZED_CONDITIONS.has(condition);
}

// ── High-Sensitivity Relationships ────────────────────────────────

/**
 * Relationship terms that are culturally sensitive in Indian context.
 * Some in-law relationship terms (like sala, sali) can be used
 * pejoratively and require confirmation before displaying.
 *
 * These terms should always show with a confirmation step
 * and prefer the respectful alternative.
 */
export const HIGH_SENSITIVITY_RELATIONSHIPS = new Set<string>([
  'sala',      // Wife's brother — often used pejoratively
  'sali',      // Wife's sister — often used pejoratively
  'jeth',      // Husband's elder brother — respectful but formal
  'devrani',   // Husband's younger brother's wife
  'jethani',   // Husband's elder brother's wife
]);

/**
 * Safe display name mappings for sensitive relationship terms.
 * Maps from the Hindi/colloquial key to a respectful alternative.
 */
const SENSITIVE_RELATIONSHIP_NAMES: Record<string, { english: string; respectful: string }> = {
  sala: { english: "Wife's Brother", respectful: "Spouse's Brother" },
  sali: { english: "Wife's Sister", respectful: "Spouse's Sister" },
  jeth: { english: "Husband's Elder Brother", respectful: "Elder Brother-in-law" },
  devrani: { english: "Husband's Younger Brother's Wife", respectful: "Younger Co-sister-in-law" },
  jethani: { english: "Husband's Elder Brother's Wife", respectful: "Elder Co-sister-in-law" },
};

/**
 * Check if a relationship key requires confirmation before display.
 *
 * @param relationshipKey - The relationship type key
 * @returns Whether the term needs a confirmation step
 *
 * @example
 * requiresConfirmation('sala')     // true
 * requiresConfirmation('father')   // false
 */
export function requiresConfirmation(relationshipKey: string): boolean {
  return HIGH_SENSITIVITY_RELATIONSHIPS.has(relationshipKey);
}

/**
 * Get a safe display name for a relationship term.
 * Returns the English or respectful form, never the potentially
 * offensive colloquial term.
 *
 * @param relationshipKey - The relationship type key
 * @param preferEnglish - Whether to prefer the English form (default: true)
 * @returns Safe display name
 *
 * @example
 * safeDisplayName('sala', true)      // "Wife's Brother"
 * safeDisplayName('sala', false)     // "Spouse's Brother"
 * safeDisplayName('father', true)    // "Father"
 */
export function safeDisplayName(
  relationshipKey: string,
  preferEnglish: boolean = true
): string {
  const sensitive = SENSITIVE_RELATIONSHIP_NAMES[relationshipKey];
  if (sensitive) {
    return preferEnglish ? sensitive.english : sensitive.respectful;
  }
  // For non-sensitive terms, capitalize and return
  return relationshipKey
    .split('_')
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ');
}

// ── Religious Memorial Rules ──────────────────────────────────────

/**
 * Memorial and death-related customs vary significantly across
 * Indian religions. These rules guide respectful handling
 * of deceased person information and memorial features.
 */
export const RELIGIOUS_MEMORIAL_RULES: Record<string, {
  guidelines: string[];
  memorialPeriod: string;
  restrictions: string[];
}> = {
  hindu: {
    guidelines: [
      'Display "Late" prefix before name',
      'Show memorial period (13 days Shraddh)',
      'Annual Shraddh date reminder',
      'Avoid displaying during auspicious periods',
    ],
    memorialPeriod: '13 days (Shraddh), then annual',
    restrictions: [
      'Do not suggest gift ideas for deceased person\'s birthday',
      'Mark as "Immortal" only with family consent',
    ],
  },
  muslim: {
    guidelines: [
      'Use "Marhoom/Marhooma" prefix',
      'Show 40-day mourning period (Chehlum)',
      'Annual memorial (Khatam)',
      'Respect Janazah prayer notification',
    ],
    memorialPeriod: '40 days (Chehlum), then annual',
    restrictions: [
      'No photograph display after death without consent',
      'No celebration suggestions for deceased birthdays',
    ],
  },
  sikh: {
    guidelines: [
      'Use "Bhala Chala" reference',
      'Show Akhand Path notification period',
      'Annual Bhog ceremony reminder',
    ],
    memorialPeriod: '10 days to annual Bhog',
    restrictions: [
      'No elaborate memorial suggestions',
      'Simple remembrance only',
    ],
  },
  jain: {
    guidelines: [
      'Reference "Salutations to liberated souls"',
      'Show 12-day mourning period',
      'Annual Uthvana memorial',
    ],
    memorialPeriod: '12 days, then annual',
    restrictions: [
      'No celebration on death anniversary',
      'Emphasize spiritual liberation',
    ],
  },
  christian: {
    guidelines: [
      'Use "Late" or "Departed" prefix',
      'Show memorial mass date',
      'Annual death anniversary mass reminder',
    ],
    memorialPeriod: '30 days, then annual',
    restrictions: [
      'Respect denomination-specific customs',
      'No Halloween-themed suggestions near death date',
    ],
  },
  parsi: {
    guidelines: [
      'Handle with utmost sensitivity — Muktad period',
      'Show 10-day Muktad observance',
      'Annual Muktad reminder',
    ],
    memorialPeriod: '10 days (Muktad), then annual',
    restrictions: [
      'Extremely sensitive — consult family before any display',
      'No photography of death-related items',
    ],
  },
} as const;

// ── Privacy-Aware Display Names ───────────────────────────────────

/**
 * Anonymize a person's name for public display.
 * Returns only the first initial followed by a period.
 *
 * @param name - Full name to anonymize
 * @returns Anonymized name (first initial only)
 *
 * @example
 * anonymizeForPublic('Rajesh Kumar')  // "R."
 * anonymizeForPublic('Priya')         // "P."
 */
export function anonymizeForPublic(name: string): string {
  if (!name || name.trim().length === 0) return '';
  return name.trim().charAt(0).toUpperCase() + '.';
}

/**
 * Determine the appropriate display name based on viewer role
 * and person's privacy level.
 *
 * @param viewerRole - The viewer's relationship context
 * @param person - Person object with name, optional nickname, and privacy level
 * @returns Appropriate display name
 *
 * @example
 * displayName('self', { name: 'Rajesh Kumar', nickname: 'Raju', privacyLevel: 'private' })
 * // "Rajesh Kumar (Raju)"
 *
 * displayName('public', { name: 'Rajesh Kumar', privacyLevel: 'private' })
 * // "R."
 */
export function displayName(
  viewerRole: string,
  person: {
    name: string;
    nickname?: string;
    privacyLevel: string;
  }
): string {
  const { name, nickname, privacyLevel } = person;

  // Self always sees full name
  if (viewerRole === 'self' || viewerRole === 'admin') {
    return nickname ? `${name} (${nickname})` : name;
  }

  // Public context — anonymize unless explicitly public
  if (viewerRole === 'public' || viewerRole === 'search') {
    if (privacyLevel === 'public') {
      return name;
    }
    return anonymizeForPublic(name);
  }

  // Family context — show name based on privacy level
  if (viewerRole === 'family' || viewerRole === 'extended') {
    if (privacyLevel === 'private' && viewerRole === 'extended') {
      return anonymizeForPublic(name);
    }
    return nickname ? `${name} (${nickname})` : name;
  }

  // Default: anonymize
  return anonymizeForPublic(name);
}
