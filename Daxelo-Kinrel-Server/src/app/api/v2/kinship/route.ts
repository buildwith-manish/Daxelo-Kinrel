import { NextRequest } from 'next/server';
import {
  kinshipData, searchKinship, getByCategory, getByGender,
  getByLineage, getKinshipTermByLocale, getRelationship,
  getCategories, normalizeRelationshipKey, LANGUAGE_CODE_MAP,
  type LocaleCode, type SupportedLanguage,
} from '@/lib/kinship';
import { success, error } from '@/packages/api';

export async function GET(req: NextRequest) {
  try {
    const { searchParams } = new URL(req.url);
    const rawKey = searchParams.get('key');
    const lang = searchParams.get('lang');
    const q = searchParams.get('q');
    const category = searchParams.get('category');
    const gender = searchParams.get('gender');
    const lineage = searchParams.get('lineage');

    if (rawKey) {
      const key = normalizeRelationshipKey(rawKey);
      const rel = getRelationship(key);
      if (!rel) return error('NOT_FOUND', `Relationship "${rawKey}" not found`, 404);

      let translations: Record<string, { native: string; latin: string }> | undefined;
      if (lang) {
        const localeCode = lang as LocaleCode;
        const langName = LANGUAGE_CODE_MAP[localeCode];
        if (langName) {
          const term = kinshipData.translations[key]?.[langName as SupportedLanguage];
          translations = term ? { [lang]: term } : undefined;
        } else if (lang === 'en') {
          translations = { en: { native: rel.englishTerm, latin: rel.englishTerm.toLowerCase() } };
        }
      } else {
        translations = kinshipData.translations[key] as Record<string, { native: string; latin: string }> | undefined;
      }

      return success({ relationship: rel, translations, localizedLabel: lang ? getKinshipTermByLocale(key, lang as LocaleCode) : undefined });
    }

    if (q) {
      const results = searchKinship(q);
      return success({ results: results.slice(0, 50), total: results.length, query: q });
    }

    if (category) {
      const results = getByCategory(category);
      return success({ results, total: results.length, category });
    }

    if (gender) {
      if (gender !== 'male' && gender !== 'female' && gender !== 'neutral') {
        return error('INVALID_PARAMETER', 'Gender must be: male, female, neutral', 400);
      }
      return success({ results: getByGender(gender), total: getByGender(gender).length, gender });
    }

    if (lineage) {
      return success({ results: getByLineage(lineage), total: getByLineage(lineage).length, lineage });
    }

    return success({
      version: kinshipData.version,
      generatedAt: kinshipData.generatedAt,
      totalRelationships: kinshipData.totalRelationships,
      supportedLanguages: kinshipData.supportedLanguages,
      categories: getCategories(),
      usage: {
        lookup: '/api/v2/kinship?key=fathers_younger_brother&lang=hi',
        search: '/api/v2/kinship?q=chacha',
        category: '/api/v2/kinship?category=in_laws',
        gender: '/api/v2/kinship?gender=male',
        lineage: '/api/v2/kinship?lineage=paternal',
      },
    });
  } catch (err) {
    console.error('[Kinship GET] Error:', err);
    return error('INTERNAL_ERROR', 'Failed to query kinship data', 500);
  }
}
