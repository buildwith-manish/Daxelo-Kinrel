import { Injectable, NotFoundException, Logger } from '@nestjs/common';
import {
  KINSHIP_TERMS,
  LANGUAGE_MAP,
  ALL_CATEGORIES,
  ALL_LINEAGES,
  SUPPORTED_LANGUAGES,
  KINSHIP_DATA_VERSION,
  type KinshipTerm,
  type KinshipTranslation,
} from './data/kinship-terms';

// Also import the comprehensive 523-term dataset from the existing lib
import {
  kinshipData,
  normalizeRelationshipKey as libNormalizeKey,
  getRelationship,
  searchKinship as libSearchKinship,
  getByCategory as libGetByCategory,
  getByGender as libGetByGender,
  getByLineage as libGetByLineage,
  getCategories as libGetCategories,
  getKinshipTermByLocale,
  ALL_RELATIONSHIP_KEYS as LIB_ALL_KEYS,
  TOTAL_RELATIONSHIPS as LIB_TOTAL,
  DATA_VERSION as LIB_VERSION,
  LANGUAGE_CODE_MAP,
  type SupportedLanguage,
  type LocaleCode,
} from '@/lib/kinship';

// ── Legacy Key Map ────────────────────────────────────────────────────

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
};

// Build lookup maps from our local data
const LOCAL_TERM_MAP = new Map<string, KinshipTerm>();
for (const term of KINSHIP_TERMS) {
  LOCAL_TERM_MAP.set(term.relationshipKey, term);
}

@Injectable()
export class KinshipService {
  private readonly logger = new Logger(KinshipService.name);

  /**
   * Normalize a legacy short key to the new relationshipKey format.
   * Uses the comprehensive lib normalizer which covers more legacy keys.
   */
  normalizeRelationshipKey(raw: string): string {
    return LEGACY_KEY_MAP[raw] ?? libNormalizeKey(raw);
  }

  /**
   * Validate and normalize — returns the normalized key or null if invalid.
   * Uses the comprehensive 523-term dataset for validation.
   */
  validateAndNormalizeKey(key: string): string | null {
    const normalized = this.normalizeRelationshipKey(key);
    return LIB_ALL_KEYS.includes(normalized) ? normalized : null;
  }

  /**
   * Single key lookup — returns relationship details and translations.
   * Uses the comprehensive 523-term dataset from the existing lib.
   */
  lookupKey(rawKey: string, lang?: string) {
    const key = this.normalizeRelationshipKey(rawKey);

    // Try the comprehensive lib dataset first (523 terms)
    const rel = getRelationship(key);

    if (!rel) {
      throw new NotFoundException({
        error: 'Not found',
        key: rawKey,
        normalizedKey: key,
      });
    }

    // Get translations for requested language (or all)
    let translations: Record<string, { native: string; latin: string }> | undefined;

    if (lang) {
      const localeCode = lang as LocaleCode;
      const langName = LANGUAGE_CODE_MAP[localeCode];
      if (langName) {
        const term = kinshipData.translations[key]?.[langName as SupportedLanguage];
        translations = term ? { [lang]: term } : undefined;
      } else if (lang === 'en') {
        translations = {
          en: { native: rel.englishTerm, latin: rel.englishTerm.toLowerCase() },
        };
      }
    } else {
      translations = kinshipData.translations[key] as
        | Record<string, { native: string; latin: string }>
        | undefined;
    }

    // Get localized label
    const localizedLabel = lang ? getKinshipTermByLocale(key, lang as LocaleCode) : undefined;

    return {
      relationship: {
        id: rel.relationshipKey,
        relationshipKey: rel.relationshipKey,
        englishTerm: rel.englishTerm,
        gender: rel.gender,
        lineage: rel.lineage,
        generation: rel.generation,
        relationType: rel.relationType,
        elderYounger: rel.elderYounger,
        relationshipCategory: rel.relationshipCategory,
        cousinType: rel.cousinType,
        relationshipPath: rel.relationshipPath,
        notes: rel.notes,
        searchKeywords: rel.searchKeywords,
      },
      translations,
      localizedLabel,
    };
  }

  /**
   * Search kinship terms by query string.
   * Uses the comprehensive 523-term dataset.
   */
  searchKinship(query: string) {
    const results = libSearchKinship(query);

    // Limit results to 50 for performance
    const limited = results.slice(0, 50);

    return {
      results: limited.map((r) => ({
        relationshipKey: r.relationshipKey,
        englishTerm: r.englishTerm,
        gender: r.gender,
        lineage: r.lineage,
        generation: r.generation,
        relationshipCategory: r.relationshipCategory,
        searchKeywords: r.searchKeywords,
        translations: kinshipData.translations[r.relationshipKey] ?? {},
      })),
      total: results.length,
      showing: limited.length,
      query,
    };
  }

  /**
   * Get kinship terms filtered by category.
   */
  getByCategory(category: string) {
    const results = libGetByCategory(category);
    return {
      results,
      total: results.length,
      category,
    };
  }

  /**
   * Get kinship terms filtered by gender.
   */
  getByGender(gender: 'male' | 'female' | 'neutral') {
    const results = libGetByGender(gender);
    return {
      results,
      total: results.length,
      gender,
    };
  }

  /**
   * Get kinship terms filtered by lineage.
   */
  getByLineage(lineage: string) {
    const results = libGetByLineage(lineage);
    return {
      results,
      total: results.length,
      lineage,
    };
  }

  /**
   * Get meta information about the kinship dataset.
   */
  getMetaInfo() {
    return {
      version: LIB_VERSION,
      generatedAt: kinshipData.generatedAt,
      totalRelationships: LIB_TOTAL,
      supportedLanguages: kinshipData.supportedLanguages,
      categories: libGetCategories(),
      sampleQuery: '/api/v1/kinship?key=fathers_younger_brother&lang=hi',
      searchQuery: '/api/v1/kinship?q=chacha',
      categoryQuery: '/api/v1/kinship?category=in_laws',
    };
  }
}
