// DAXELO KINREL — Pack 08: Text Classification Pipeline
// 3-stage text classification: Regex PII → Custom Dictionary → Rule-based Scoring

import {
  ContentCategory,
  AutoAction,
  ClassificationResult,
  ClassificationDetails,
  StageResult,
  lookupDecision,
  CONTENT_TYPES,
  categoryToPriority,
} from './classification'

// ── PII Detection Patterns ──────────────────────────────────────────────

const PII_PATTERNS: Record<string, RegExp> = {
  aadhaar: /\b[2-9]\d{3}\s?\d{4}\s?\d{4}\b/g,              // 12-digit Aadhaar (starts 2-9)
  pan: /\b[A-Z]{5}\d{4}[A-Z]\b/g,                             // PAN: 5L+4D+1L
  indian_phone: /(?:(?:\+91|0)[\s-]?)?[6-9]\d{4}[\s-]?\d{5}\b/g, // Indian mobile
  email: /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/g,
  bank_account: /\b\d{9,18}\b/g,                               // Indian bank account (9-18 digits)
  driving_license: /\b[A-Z]{2}[-\s]?\d{2}[-\s]?\d{4}[-\s]?\d{7}\b/g, // Indian DL
  passport: /\b[A-Z][1-9]\d\s?\d{4}[1-9]\b/g,                // Indian passport
  ifsc: /\b[A-Z]{4}0[A-Z0-9]{6}\b/g,                          // IFSC code
  upi_id: /\b[\w.-]+@[\w.-]+\b/g,                              // UPI ID (simplified)
}

// ── Indian Profanity Patterns (Hindi + English) ────────────────────────

export const INDIAN_PROFANITY_PATTERNS: { pattern: RegExp; severity: number; label: string }[] = [
  // Hindi profanity (transliterated)
  { pattern: /\b(bhenchod|bhen?ch?od|bc|b\.c\.|beh?nch?od)\b/gi, severity: 0.9, label: 'hindi_profanity_severe' },
  { pattern: /\b(maderchod|mader?ch?od|mc|m\.c\.|madarchod)\b/gi, severity: 0.9, label: 'hindi_profanity_severe' },
  { pattern: /\b(chutiya|chutiya|chootiya|ch?utiya)\b/gi, severity: 0.7, label: 'hindi_profanity_moderate' },
  { pattern: /\b(gaand|gand|gaa?nd)\b/gi, severity: 0.6, label: 'hindi_profanity_moderate' },
  { pattern: /\b(lauda|lavda|lawda|lauda)\b/gi, severity: 0.8, label: 'hindi_profanity_severe' },
  { pattern: /\b(bhosda|bhosdike|bhosdiwala)\b/gi, severity: 0.8, label: 'hindi_profanity_severe' },
  { pattern: /\b(randi|raandi|rundi)\b/gi, severity: 0.7, label: 'hindi_profanity_moderate' },
  { pattern: /\b(kutta|kaminey|kamina|kamini)\b/gi, severity: 0.5, label: 'hindi_profanity_mild' },
  { pattern: /\b(saal?aa|sale|sala|sali|saali)\b/gi, severity: 0.5, label: 'hindi_profanity_mild' },
  { pattern: /\b(haraami|harami|haramee)\b/gi, severity: 0.6, label: 'hindi_profanity_moderate' },
  { pattern: /\b(jhaatu|jhaatu)\b/gi, severity: 0.6, label: 'hindi_profanity_moderate' },
  { pattern: /\b(tatte|tatt?e)\b/gi, severity: 0.7, label: 'hindi_profanity_moderate' },
  { pattern: /\b(chhakka|chakka)\b/gi, severity: 0.4, label: 'hindi_profanity_mild' },

  // English profanity (common)
  { pattern: /\b(fuck|fucking|fucked|fucker)\b/gi, severity: 0.8, label: 'english_profanity_severe' },
  { pattern: /\b(shit|bullshit|shitty)\b/gi, severity: 0.5, label: 'english_profanity_moderate' },
  { pattern: /\b(bitch|bitches|bitchy)\b/gi, severity: 0.6, label: 'english_profanity_moderate' },
  { pattern: /\b(asshole|arsehole)\b/gi, severity: 0.6, label: 'english_profanity_moderate' },
  { pattern: /\b(dick|dickhead)\b/gi, severity: 0.6, label: 'english_profanity_moderate' },
  { pattern: /\b(bastard)\b/gi, severity: 0.5, label: 'english_profanity_moderate' },
  { pattern: /\b(damn|goddamn)\b/gi, severity: 0.3, label: 'english_profanity_mild' },
  { pattern: /\b(whore|slut|hooker)\b/gi, severity: 0.7, label: 'english_profanity_severe' },
]

// ── Caste Reference Patterns ────────────────────────────────────────────

export const CASTE_REFERENCE_PATTERNS: { pattern: RegExp; severity: number; label: string }[] = [
  // Caste slurs and derogatory references (Hindi + English)
  { pattern: /\b(chamar|chamaar|chambhar)\b/gi, severity: 0.8, label: 'caste_slur_dalit' },
  { pattern: /\b(bhangi|bhanghi|valmiki)\b/gi, severity: 0.8, label: 'caste_slur_scavenger' },
  { pattern: /\b(neech|neechi|neecha)\b/gi, severity: 0.7, label: 'caste_slur_low' },
  { pattern: /\b(shudra|sudra|shoodra)\b/gi, severity: 0.7, label: 'caste_reference_hierarchical' },
  { pattern: /\b(achhut|achhoot|asprishya)\b/gi, severity: 0.9, label: 'caste_slur_untouchable' },
  { pattern: /\b(untouchable|outcaste)\b/gi, severity: 0.9, label: 'caste_slur_untouchable_en' },
  { pattern: /\b(dalit\s*(slur|abuse|hate|joke))\b/gi, severity: 0.85, label: 'caste_hate_dalit' },
  { pattern: /\b(reservation\s*(wala|wali|people|crowd))\b/gi, severity: 0.5, label: 'caste_reference_reservation' },
  { pattern: /\b(jaati\s*(bhed|vikriti|discrimination))\b/gi, severity: 0.8, label: 'caste_discrimination_hindi' },
  { pattern: /\b(caste\s*(discrimination|slur|abuse|system|hate))\b/gi, severity: 0.7, label: 'caste_discrimination_en' },
]

// ── Communal Hate Patterns ──────────────────────────────────────────────

const COMMUNAL_HATE_PATTERNS: { pattern: RegExp; severity: number; label: string }[] = [
  { pattern: /\b(anti[\s-]?national)\b/gi, severity: 0.6, label: 'communal_antinational' },
  { pattern: /\b(terorist|terrorist)\b/gi, severity: 0.7, label: 'communal_terrorist_slur' },
  { pattern: /\b(paki|paki\s)/gi, severity: 0.7, label: 'communal_paki_slur' },
  { pattern: /\b(gaumutra|gomutra\s*(jokes?|taunt))\b/gi, severity: 0.6, label: 'communal_religious_mockery' },
  { pattern: /\b(halal\s*(jihad|politics))\b/gi, severity: 0.7, label: 'communal_halal_conspiracy' },
  { pattern: /\b(love\s*jihad|love\s*je?had)\b/gi, severity: 0.7, label: 'communal_love_jihad' },
  { pattern: /\b(ghar\s*wapsi)\b/gi, severity: 0.5, label: 'communal_ghar_wapsi' },
  { pattern: /\b(communal\s*(riot|violence|attack|tension))\b/gi, severity: 0.8, label: 'communal_violence_reference' },
]

// ── Religious Offense Patterns ──────────────────────────────────────────

const RELIGIOUS_OFFENSE_PATTERNS: { pattern: RegExp; severity: number; label: string }[] = [
  { pattern: /\b(blasp?hem(y|ous))\b/gi, severity: 0.6, label: 'religious_blasphemy' },
  { pattern: /\b(idol\s*worship\s*(joke|mock|taunt))\b/gi, severity: 0.6, label: 'religious_idol_mockery' },
  { pattern: /\b(murti\s*(todo|tor|break))\b/gi, severity: 0.8, label: 'religious_idol_violence' },
  { pattern: /\b(gau\s*hatya|gau\s*maans)\b/gi, severity: 0.7, label: 'religious_cow_reference' },
  { pattern: /\b(prophet\s*(insult|mock|cartoon))\b/gi, severity: 0.8, label: 'religious_prophet_insult' },
  { pattern: /\b(quran\s*(burn|desecrate|insult))\b/gi, severity: 0.8, label: 'religious_quran_insult' },
  { pattern: /\b(gita\s*(burn|insult|mock))\b/gi, severity: 0.8, label: 'religious_gita_insult' },
  { pattern: /\b(ram\s*(mock|insult|joke))\b/gi, severity: 0.7, label: 'religious_deity_insult' },
]

// ── Dowry Reference Patterns ────────────────────────────────────────────

const DOWRY_PATTERNS: { pattern: RegExp; severity: number; label: string }[] = [
  { pattern: /\b(dahej|dahaej)\b/gi, severity: 0.7, label: 'dowry_reference_hindi' },
  { pattern: /\b(dowry)\b/gi, severity: 0.6, label: 'dowry_reference_en' },
  { pattern: /\b(dowry\s*(demand|harassment|death|torture|case))\b/gi, severity: 0.9, label: 'dowry_criminal_reference' },
  { pattern: /\b(dahej\s*(mangna|demand|mang|lutna))\b/gi, severity: 0.9, label: 'dowry_demand_hindi' },
  { pattern: /\b(gift\s*(for\s*marriage|from\s*bride|from\s*girl\s*side))\b/gi, severity: 0.5, label: 'dowry_euphemism' },
  { pattern: /\b(stridhan|stree\s*dhan)\b/gi, severity: 0.4, label: 'dowry_stridhan_reference' },
]

// ── Colorism Patterns ───────────────────────────────────────────────────

const COLORISM_PATTERNS: { pattern: RegExp; severity: number; label: string }[] = [
  { pattern: /\b(gori|gora)\b/gi, severity: 0.4, label: 'colorism_gori' },
  { pattern: /\b(kali|kala)\s*(ladki|ladka|aurat| admi|chehra|rang)\b/gi, severity: 0.6, label: 'colorism_kali_reference' },
  { pattern: /\b(fair\s*(skin|complexion|bride|girl|boy)\b)/gi, severity: 0.5, label: 'colorism_fair_preference' },
  { pattern: /\b(dark\s*(skin|complexion)\s*(problem|issue|ugly|bad))\b/gi, severity: 0.7, label: 'colorism_dark_shaming' },
  { pattern: /\b(fair\s*and\s*lovely|fair\s*and\s*handsome)\b/gi, severity: 0.5, label: 'colorism_product_reference' },
  { pattern: /\b(whitening|bleaching\s*(cream|face|skin))\b/gi, severity: 0.5, label: 'colorism_bleaching' },
  { pattern: /\b(saawli|sawli|sanwli)\s*(ladki|chehra|rang)\b/gi, severity: 0.5, label: 'colorism_sawli' },
]

// ── Regional Slurs ──────────────────────────────────────────────────────

const REGIONAL_SLUR_PATTERNS: { pattern: RegExp; severity: number; label: string }[] = [
  { pattern: /\b(madrasi)\b/gi, severity: 0.6, label: 'regional_slur_south' },
  { pattern: /\b(bihari)\b/gi, severity: 0.3, label: 'regional_reference_bihar' },
  { pattern: /\b(bhaiya)\b/gi, severity: 0.3, label: 'regional_reference_up' },
  { pattern: /\b(gorkha|gurkha)\s*(slur|joke|taunt)\b/gi, severity: 0.6, label: 'regional_slur_gorkha' },
  { pattern: /\b(chinki|chinky)\b/gi, severity: 0.7, label: 'regional_slur_ne' },
  { pattern: /\b(north\s*east\s*(slur|joke|taunt|mock))\b/gi, severity: 0.7, label: 'regional_slur_ne_reference' },
]

// ── All Dictionary Patterns Combined ────────────────────────────────────

interface DictionaryEntry {
  pattern: RegExp
  severity: number
  label: string
  category: ContentCategory
}

const ALL_DICTIONARY: DictionaryEntry[] = [
  ...INDIAN_PROFANITY_PATTERNS.map(p => ({ ...p, category: ContentCategory.HARASSMENT })),
  ...CASTE_REFERENCE_PATTERNS.map(p => ({ ...p, category: ContentCategory.CASTE_DISCRIMINATION })),
  ...COMMUNAL_HATE_PATTERNS.map(p => ({ ...p, category: ContentCategory.COMMUNAL_HATE })),
  ...RELIGIOUS_OFFENSE_PATTERNS.map(p => ({ ...p, category: ContentCategory.RELIGIOUS_OFFENSE })),
  ...DOWRY_PATTERNS.map(p => ({ ...p, category: ContentCategory.DOWRY_REFERENCE })),
  ...COLORISM_PATTERNS.map(p => ({ ...p, category: ContentCategory.COLORISM })),
  ...REGIONAL_SLUR_PATTERNS.map(p => ({ ...p, category: ContentCategory.HARASSMENT })),
]

// ── Stage 1: PII Detection ──────────────────────────────────────────────

export function detectPII(text: string): string[] {
  const found: string[] = []
  for (const [piiType, pattern] of Object.entries(PII_PATTERNS)) {
    const matches = text.match(pattern)
    if (matches && matches.length > 0) {
      found.push(piiType)
    }
  }
  // Deduplicate bank account false positives — only flag if it looks like a real account
  if (found.includes('bank_account')) {
    const bankMatches = text.match(PII_PATTERNS.bank_account) || []
    const hasOtherPII = found.some(f => f !== 'bank_account')
    if (bankMatches.length > 0 && !hasOtherPII && bankMatches.every(m => m.length < 11)) {
      // Short numbers without context are likely not bank accounts
      const idx = found.indexOf('bank_account')
      if (idx !== -1) found.splice(idx, 1)
    }
  }
  return found
}

// ── Stage 2: Dictionary Matching ────────────────────────────────────────

function matchDictionary(text: string): { matches: DictionaryEntry[], maxSeverity: number, categories: Set<ContentCategory> } {
  const matches: DictionaryEntry[] = []
  const categories = new Set<ContentCategory>()
  let maxSeverity = 0

  for (const entry of ALL_DICTIONARY) {
    const patternCopy = new RegExp(entry.pattern.source, entry.pattern.flags)
    const found = text.match(patternCopy)
    if (found && found.length > 0) {
      matches.push(entry)
      categories.add(entry.category)
      maxSeverity = Math.max(maxSeverity, entry.severity)
    }
  }
  return { matches, maxSeverity, categories }
}

// ── Stage 3: Rule-Based Scoring ─────────────────────────────────────────

function ruleBasedScore(
  text: string,
  piiTypes: string[],
  dictionaryMatches: DictionaryEntry[],
  dictMaxSeverity: number,
  dictCategories: Set<ContentCategory>,
): { category: ContentCategory; confidence: number; scoreBreakdown: Record<string, number> } {
  const scoreBreakdown: Record<string, number> = {}
  let totalScore = 0

  // PII scoring
  if (piiTypes.length > 0) {
    const piiScore = Math.min(piiTypes.length * 0.2, 0.8)
    scoreBreakdown['pii_exposure'] = piiScore
    totalScore += piiScore * 0.4
  }

  // Dictionary scoring
  if (dictMaxSeverity > 0) {
    scoreBreakdown['dictionary_match'] = dictMaxSeverity
    totalScore += dictMaxSeverity * 0.4
  }

  // Length-based spam heuristic
  if (text.length > 500 && /(.)\1{10,}/.test(text)) {
    scoreBreakdown['spam_repetition'] = 0.6
    totalScore += 0.6 * 0.1
  }

  // URL-heavy content (spam indicator)
  const urlCount = (text.match(/https?:\/\/\S+/g) || []).length
  if (urlCount > 3) {
    scoreBreakdown['spam_urls'] = Math.min(urlCount * 0.1, 0.5)
    totalScore += Math.min(urlCount * 0.1, 0.5) * 0.1
  }

  // ALL CAPS ratio (shouting/spam)
  const upperRatio = text.replace(/[^A-Z]/g, '').length / Math.max(text.replace(/[^a-zA-Z]/g, '').length, 1)
  if (upperRatio > 0.7 && text.length > 50) {
    scoreBreakdown['all_caps_ratio'] = 0.3
    totalScore += 0.3 * 0.05
  }

  // Determine primary category
  let category: ContentCategory = ContentCategory.SAFE
  if (dictCategories.has(ContentCategory.CASTE_DISCRIMINATION)) {
    category = ContentCategory.CASTE_DISCRIMINATION
  } else if (dictCategories.has(ContentCategory.COMMUNAL_HATE)) {
    category = ContentCategory.COMMUNAL_HATE
  } else if (dictCategories.has(ContentCategory.RELIGIOUS_OFFENSE)) {
    category = ContentCategory.RELIGIOUS_OFFENSE
  } else if (dictCategories.has(ContentCategory.DOWRY_REFERENCE)) {
    category = ContentCategory.DOWRY_REFERENCE
  } else if (dictCategories.has(ContentCategory.COLORISM)) {
    category = ContentCategory.COLORISM
  } else if (dictCategories.has(ContentCategory.HARASSMENT)) {
    category = ContentCategory.HARASSMENT
  } else if (piiTypes.length > 0) {
    category = ContentCategory.PII_EXPOSURE
  } else if (totalScore > 0.3) {
    category = ContentCategory.BORDERLINE
  }

  const confidence = Math.min(totalScore, 1.0)

  return { category, confidence, scoreBreakdown }
}

// ── Score to Action Mapping ─────────────────────────────────────────────

export function mapScoreToAction(score: number): AutoAction {
  if (score >= 0.85) return AutoAction.REJECT
  if (score >= 0.7) return AutoAction.ESCALATE
  if (score >= 0.5) return AutoAction.QUARANTINE
  if (score >= 0.3) return AutoAction.ALLOW_WITH_FLAG
  return AutoAction.ALLOW
}

// ── Main Classification Function ────────────────────────────────────────

export async function classify(text: string, contentType: string): Promise<ClassificationResult> {
  const config = CONTENT_TYPES[contentType]
  const stageResults: StageResult[] = []
  const allFlaggedCategories: ContentCategory[] = []
  const allMatchedPatterns: string[] = []

  // Stage 1: PII Detection
  let piiTypes: string[] = []
  if (config?.enablePIIDetection !== false) {
    piiTypes = detectPII(text)
    const piiPassed = piiTypes.length === 0
    stageResults.push({
      stage: 'pii_detection',
      passed: piiPassed,
      score: piiTypes.length > 0 ? Math.min(piiTypes.length * 0.3, 0.9) : 0,
      findings: piiTypes,
    })
    if (piiTypes.length > 0) {
      allFlaggedCategories.push(ContentCategory.PII_EXPOSURE)
    }
  } else {
    stageResults.push({ stage: 'pii_detection', passed: true, score: 0, findings: [] })
  }

  // Stage 2: Dictionary Matching
  let dictMatches: DictionaryEntry[] = []
  let dictMaxSeverity = 0
  let dictCategories = new Set<ContentCategory>()

  if (config?.enableProfanityDetection || config?.enableIndiaSpecificDetection) {
    const dictResult = matchDictionary(text)
    dictMatches = dictResult.matches
    dictMaxSeverity = dictResult.maxSeverity
    dictCategories = dictResult.categories
    stageResults.push({
      stage: 'dictionary_matching',
      passed: dictMatches.length === 0,
      score: dictMaxSeverity,
      findings: dictMatches.map(m => m.label),
    })
    dictCategories.forEach(c => allFlaggedCategories.push(c))
    dictMatches.forEach(m => allMatchedPatterns.push(m.label))
  } else {
    stageResults.push({ stage: 'dictionary_matching', passed: true, score: 0, findings: [] })
  }

  // Stage 3: Rule-Based Scoring
  const ruleResult = ruleBasedScore(text, piiTypes, dictMatches, dictMaxSeverity, dictCategories)
  stageResults.push({
    stage: 'rule_based_scoring',
    passed: ruleResult.confidence < 0.3,
    score: ruleResult.confidence,
    findings: Object.entries(ruleResult.scoreBreakdown)
      .filter(([, v]) => v > 0.1)
      .map(([k, v]) => `${k}: ${(v * 100).toFixed(0)}%`),
  })

  // Determine final category and confidence
  const finalCategory = ruleResult.category
  const finalConfidence = ruleResult.confidence

  // Look up decision from matrix
  const decision = lookupDecision(finalCategory, finalConfidence)

  // Deduplicate flagged categories
  const uniqueFlagged = [...new Set(allFlaggedCategories)]

  const details: ClassificationDetails = {
    piiTypes,
    matchedPatterns: allMatchedPatterns,
    scoreBreakdown: ruleResult.scoreBreakdown,
    stageResults,
    recommendedAction: decision.autoAction,
    humanReviewRequired: decision.humanReviewRequired,
    humanReviewSLA: decision.humanReviewSLA !== 'none' ? decision.humanReviewSLA : undefined,
    notificationLevel: decision.notificationLevel,
  }

  return {
    category: finalCategory,
    confidence: finalConfidence,
    autoAction: decision.autoAction,
    flaggedCategories: uniqueFlagged,
    details,
  }
}

// ── Utility: Quick Check ────────────────────────────────────────────────

export function quickProfanityCheck(text: string): boolean {
  for (const entry of INDIAN_PROFANITY_PATTERNS) {
    const patternCopy = new RegExp(entry.pattern.source, entry.pattern.flags)
    if (patternCopy.test(text)) return true
  }
  return false
}

export function quickCasteCheck(text: string): boolean {
  for (const entry of CASTE_REFERENCE_PATTERNS) {
    const patternCopy = new RegExp(entry.pattern.source, entry.pattern.flags)
    if (patternCopy.test(text)) return true
  }
  return false
}
