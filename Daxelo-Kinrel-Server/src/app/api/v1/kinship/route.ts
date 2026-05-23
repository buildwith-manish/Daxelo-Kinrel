/**
 * GET /api/v1/kinship
 *
 * Kinship lookup API — server-side only, powered by indian-kinship.json.
 * Supports: single key lookup, search, category filter, meta info.
 *
 * Query params:
 *   key      - Single relationship key (e.g. 'fathers_younger_brother')
 *   lang     - Language code: hi, bn, te, mr, ta, ur, gu, kn, ml, or, pa, as, sa, en
 *   q        - Search query (matches englishTerm, searchKeywords, relationshipKey)
 *   category - Filter by category (core_family, in_laws, grandparents, etc.)
 *   gender   - Filter by gender (male, female, neutral)
 *   lineage  - Filter by lineage (paternal, maternal, bilateral, marital)
 */

import { NextRequest, NextResponse } from 'next/server'
import {
  kinshipData,
  searchKinship,
  getByCategory,
  getByGender,
  getByLineage,
  getKinshipTermByLocale,
  getRelationship,
  getCategories,
  normalizeRelationshipKey,
  LANGUAGE_CODE_MAP,
  type LocaleCode,
  type SupportedLanguage,
} from '@/lib/kinship'

export async function GET(req: NextRequest) {
  const { searchParams } = new URL(req.url)
  const rawKey = searchParams.get('key')
  const lang = searchParams.get('lang')
  const q = searchParams.get('q')
  const category = searchParams.get('category')
  const gender = searchParams.get('gender')
  const lineage = searchParams.get('lineage')

  // ── Single key lookup ──────────────────────────────────────────
  if (rawKey) {
    const key = normalizeRelationshipKey(rawKey)
    const rel = getRelationship(key)

    if (!rel) {
      return NextResponse.json(
        { error: 'Not found', key: rawKey, normalizedKey: key },
        { status: 404 }
      )
    }

    // Get translations for requested language (or all)
    let translations: Record<string, { native: string; latin: string }> | undefined
    if (lang) {
      const localeCode = lang as LocaleCode
      const langName = LANGUAGE_CODE_MAP[localeCode]
      if (langName) {
        const term = kinshipData.translations[key]?.[langName as SupportedLanguage]
        translations = term ? { [lang]: term } : undefined
      } else if (lang === 'en') {
        translations = { en: { native: rel.englishTerm, latin: rel.englishTerm.toLowerCase() } }
      }
    } else {
      translations = kinshipData.translations[key] as Record<string, { native: string; latin: string }> | undefined
    }

    return NextResponse.json({
      relationship: rel,
      translations,
      localizedLabel: lang ? getKinshipTermByLocale(key, lang as LocaleCode) : undefined,
    })
  }

  // ── Search ─────────────────────────────────────────────────────
  if (q) {
    const results = searchKinship(q)
    // Limit results to 50 for performance
    const limited = results.slice(0, 50)
    return NextResponse.json({
      results: limited,
      total: results.length,
      showing: limited.length,
      query: q,
    })
  }

  // ── Category filter ────────────────────────────────────────────
  if (category) {
    const results = getByCategory(category)
    return NextResponse.json({
      results,
      total: results.length,
      category,
    })
  }

  // ── Gender filter ──────────────────────────────────────────────
  if (gender) {
    if (gender !== 'male' && gender !== 'female' && gender !== 'neutral') {
      return NextResponse.json(
        { error: 'Invalid gender. Use: male, female, neutral' },
        { status: 400 }
      )
    }
    const results = getByGender(gender)
    return NextResponse.json({
      results,
      total: results.length,
      gender,
    })
  }

  // ── Lineage filter ─────────────────────────────────────────────
  if (lineage) {
    const results = getByLineage(lineage)
    return NextResponse.json({
      results,
      total: results.length,
      lineage,
    })
  }

  // ── Meta info (default — don't return all 523 records) ─────────
  return NextResponse.json({
    version: kinshipData.version,
    generatedAt: kinshipData.generatedAt,
    totalRelationships: kinshipData.totalRelationships,
    supportedLanguages: kinshipData.supportedLanguages,
    categories: getCategories(),
    sampleQuery: '/api/v1/kinship?key=fathers_younger_brother&lang=hi',
    searchQuery: '/api/v1/kinship?q=chacha',
    categoryQuery: '/api/v1/kinship?category=in_laws',
  })
}
