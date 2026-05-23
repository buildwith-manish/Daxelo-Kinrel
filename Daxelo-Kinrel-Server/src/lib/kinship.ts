/**
 * KINREL — Kinship Module
 *
 * Single source of truth for all Indian kinship term lookups.
 * Backed by indian-kinship.json (5,359 relationships, 15 languages, v4.1.0).
 *
 * IMPORTANT: This module is SERVER-ONLY. Never import the JSON directly
 * in a 'use client' component — use /api/v1/kinship fetches instead.
 */

import kinshipData from './data/indian-kinship.json'

// ── Types ────────────────────────────────────────────────────────────

export type SupportedLanguage =
  | 'hindi' | 'bengali' | 'telugu' | 'marathi' | 'tamil'
  | 'urdu' | 'gujarati' | 'kannada' | 'malayalam' | 'odia'
  | 'punjabi' | 'assamese' | 'sanskrit' | 'sindhi' | 'english'

/** Locale codes used in the app's LocaleProvider (e.g. 'hi', 'ta') */
export type LocaleCode = 'hi' | 'bn' | 'te' | 'mr' | 'ta' | 'ur' | 'gu' | 'kn' | 'ml' | 'or' | 'pa' | 'as' | 'sa' | 'sd' | 'en'

export interface KinshipTranslation {
  native: string
  latin: string
}

export interface KinshipRelationship {
  id: number
  relationshipKey: string
  englishTerm: string
  gender: 'male' | 'female' | 'neutral'
  lineage: string
  generation: number
  relationType: string
  elderYounger: string | null
  relationshipCategory: string
  cousinType: string | null
  relationshipPath: string[]
  notes: string
  searchKeywords: string[]
}

// ── Internal typed data ──────────────────────────────────────────────

interface KinshipDataFile {
  version: string
  generatedAt: string
  totalRelationships: number
  supportedLanguages: SupportedLanguage[]
  translations: Record<string, Record<SupportedLanguage, KinshipTranslation>>
  relationships: KinshipRelationship[]
}

const data = kinshipData as KinshipDataFile

// ── Language Code Map ────────────────────────────────────────────────
// Maps app locale codes (hi, ta, etc.) to JSON language names (hindi, tamil, etc.)

export const LANGUAGE_CODE_MAP: Record<LocaleCode, SupportedLanguage | null> = {
  hi: 'hindi',
  bn: 'bengali',
  te: 'telugu',
  mr: 'marathi',
  ta: 'tamil',
  ur: 'urdu',
  gu: 'gujarati',
  kn: 'kannada',
  ml: 'malayalam',
  or: 'odia',
  pa: 'punjabi',
  as: 'assamese',
  sa: 'sanskrit',
  sd: 'sindhi',
  en: 'english',
}

/** Reverse map: JSON language name → app locale code */
export const LANGUAGE_NAME_TO_CODE: Record<SupportedLanguage, LocaleCode> = {
  hindi: 'hi',
  bengali: 'bn',
  telugu: 'te',
  marathi: 'mr',
  tamil: 'ta',
  urdu: 'ur',
  gujarati: 'gu',
  kannada: 'kn',
  malayalam: 'ml',
  odia: 'or',
  punjabi: 'pa',
  assamese: 'as',
  sanskrit: 'sa',
  sindhi: 'sd',
  english: 'en',
}

// ── Legacy Key Map ───────────────────────────────────────────────────
// Maps old short keys (bua, chacha, etc.) to new relationshipKey values

const LEGACY_KEY_MAP: Record<string, string> = {
  bua: 'fathers_sister',
  chacha: 'fathers_younger_brother',
  mama: 'mothers_brother',
  mami: 'mothers_brothers_wife',
  bhaiya: 'elder_brother',
  didi: 'elder_sister',
  jeth: 'husbands_elder_brother',
  jethani: 'husbands_elder_brothers_wife',
  devar: 'husbands_younger_brother',
  devrani: 'husbands_younger_brothers_wife',
  nanad: 'husbands_sister',
  sarhaj: 'husbands_elder_brothers_wife',
  sala: 'wifes_brother',
  sali: 'wifes_sister',
  behnoi: 'sisters_husband',
  samdhi: 'co_father_in_law_paternal',
  samdhan: 'co_mother_in_law_paternal',
  tau: 'fathers_elder_brother',
  tai: 'fathers_elder_brothers_wife',
  grandfather: 'paternal_grandfather',
  grandmother: 'paternal_grandmother',
  uncle: 'fathers_younger_brother',
  aunt: 'fathers_younger_brothers_wife',
  nephew: 'brothers_son',
  niece: 'brothers_daughter',
  cousin: 'paternal_cousins_son',
  pota: 'sons_son',
  poti: 'sons_daughter',
  bhatija: 'brothers_son',
  bhatiji: 'brothers_daughter',
  // Directional mappings
  grandfather_paternal: 'paternal_grandfather',
  grandmother_paternal: 'paternal_grandmother',
  grandfather_maternal: 'maternal_grandfather',
  grandmother_maternal: 'maternal_grandmother',
  uncle_paternal: 'fathers_younger_brother',
  aunt_paternal: 'fathers_younger_brothers_wife',
  uncle_maternal: 'mothers_brother',
  aunt_maternal: 'mothers_brothers_wife',
  father_in_law: 'husbands_father',
  mother_in_law: 'husbands_mother',
  brother_in_law: 'husbands_younger_brother',
  sister_in_law: 'husbands_sister',
  son_in_law: 'daughters_husband',
  daughter_in_law: 'sons_wife',
}

/**
 * Normalize a legacy short key to the new relationshipKey format.
 * If the key is already in the new format, it passes through unchanged.
 */
export function normalizeRelationshipKey(raw: string): string {
  return LEGACY_KEY_MAP[raw] ?? raw
}

// ── Lookup Functions ─────────────────────────────────────────────────

/**
 * Get the native + latin translation for a relationship in a given language.
 * @param relationshipKey - e.g. 'fathers_younger_brother' or legacy 'chacha'
 * @param language - e.g. 'hindi'
 */
export function getKinshipTerm(
  relationshipKey: string,
  language: SupportedLanguage
): KinshipTranslation | null {
  const key = normalizeRelationshipKey(relationshipKey)
  return data.translations[key]?.[language] ?? null
}

/**
 * Get kinship term using an app locale code (hi, ta, etc.)
 * Falls back to englishTerm if locale is 'en' or not found.
 */
export function getKinshipTermByLocale(
  relationshipKey: string,
  locale: LocaleCode
): string {
  const key = normalizeRelationshipKey(relationshipKey)

  // English: return the englishTerm from relationships
  if (locale === 'en') {
    const rel = getRelationship(key)
    return rel?.englishTerm ?? key
  }

  const langName = LANGUAGE_CODE_MAP[locale]
  if (!langName) {
    const rel = getRelationship(key)
    return rel?.englishTerm ?? key
  }

  const term = data.translations[key]?.[langName]
  return term?.native ?? getRelationship(key)?.englishTerm ?? key
}

/**
 * Get English metadata for a relationship key.
 */
export function getRelationship(key: string): KinshipRelationship | undefined {
  const normalizedKey = normalizeRelationshipKey(key)
  return data.relationships.find(r => r.relationshipKey === normalizedKey)
}

/**
 * Get all relationships for a given category.
 */
export function getByCategory(category: string): KinshipRelationship[] {
  return data.relationships.filter(r => r.relationshipCategory === category)
}

/**
 * Search relationships by keyword (English term, native script, or search keywords).
 */
export function searchKinship(query: string): KinshipRelationship[] {
  const q = query.toLowerCase()
  return data.relationships.filter(r =>
    r.englishTerm.toLowerCase().includes(q) ||
    r.searchKeywords.some(k => k.toLowerCase().includes(q)) ||
    r.relationshipKey.toLowerCase().includes(q)
  )
}

/**
 * Get all unique relationship categories.
 */
export function getCategories(): string[] {
  return [...new Set(data.relationships.map(r => r.relationshipCategory))]
}

/**
 * Get all relationships for a specific lineage.
 */
export function getByLineage(lineage: string): KinshipRelationship[] {
  return data.relationships.filter(r => r.lineage === lineage)
}

/**
 * Get all relationships of a specific gender.
 */
export function getByGender(gender: 'male' | 'female' | 'neutral'): KinshipRelationship[] {
  return data.relationships.filter(r => r.gender === gender)
}

/**
 * Get all relationships at a specific generation level.
 */
export function getByGeneration(generation: number): KinshipRelationship[] {
  return data.relationships.filter(r => r.generation === generation)
}

/**
 * Get translations for a relationship in ALL supported languages.
 */
export function getAllTranslations(relationshipKey: string): Record<SupportedLanguage, KinshipTranslation> | null {
  const key = normalizeRelationshipKey(relationshipKey)
  return data.translations[key] ?? null
}

/**
 * Resolve a relationship path (array of relationshipKeys) to a compound kinship term.
 * For example, ['self', 'father', 'fathers_younger_brother'] → finds the composed term.
 */
export function resolvePathToKey(path: string[]): KinshipRelationship | undefined {
  // Try to find a relationship whose path matches
  const pathStr = path.join('_')
  return data.relationships.find(r => r.relationshipPath.join('_') === pathStr)
}

// ── Exports ──────────────────────────────────────────────────────────

/** All 15 supported languages from the JSON */
export const SUPPORTED_LANGUAGES = data.supportedLanguages

/** All 5,359 relationship keys */
export const ALL_RELATIONSHIP_KEYS = data.relationships.map(r => r.relationshipKey)

/** Total number of relationships */
export const TOTAL_RELATIONSHIPS = data.totalRelationships

/** Data version */
export const DATA_VERSION = data.version

/** The raw data (use sparingly — prefer lookup functions) */
export { data as kinshipData }
