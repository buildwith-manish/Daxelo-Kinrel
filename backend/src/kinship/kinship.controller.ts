import { Controller, Get, Query } from '@nestjs/common';
import { KinshipService } from './kinship.service';

@Controller('v1/kinship')
export class KinshipController {
  constructor(private kinshipService: KinshipService) {}

  /**
   * GET /api/v1/kinship
   *
   * Multi-purpose endpoint:
   * - No params → Meta info
   * - ?key=xxx&lang=hi → Single key lookup
   * - ?q=xxx → Search
   * - ?category=xxx → Category filter
   * - ?gender=xxx → Gender filter
   * - ?lineage=xxx → Lineage filter
   */
  @Get()
  async query(@Query() query: Record<string, string>) {
    // Search by query
    if (query.q) {
      const results = this.kinshipService.searchKinship(query.q);
      return { results, total: results.length, query: query.q };
    }

    // Single key lookup
    if (query.key) {
      const key = query.key;
      const relationship = this.kinshipService.getRelationship(key);
      if (!relationship) {
        return { error: 'Relationship not found', key };
      }

      // If a language is specified, include the translation
      const lang = query.lang as any;
      if (lang && lang !== 'en') {
        const translation = this.kinshipService.getKinshipTerm(key, lang);
        return { relationship, translation, key, language: lang };
      }

      // If locale code is specified
      if (lang === 'en') {
        return { relationship, key, language: 'en' };
      }

      // Return all translations for this key
      const allTranslations = this.kinshipService.getAllTranslations(key);
      return { relationship, translations: allTranslations, key };
    }

    // Category filter
    if (query.category) {
      const results = this.kinshipService.getByCategory(query.category);
      return { results, total: results.length, category: query.category };
    }

    // Gender filter
    if (query.gender) {
      const gender = query.gender as 'male' | 'female' | 'neutral';
      const results = this.kinshipService.getByGender(gender);
      return { results, total: results.length, gender };
    }

    // Lineage filter
    if (query.lineage) {
      const results = this.kinshipService.getByLineage(query.lineage);
      return { results, total: results.length, lineage: query.lineage };
    }

    // Generation filter
    if (query.generation) {
      const generation = parseInt(query.generation, 10);
      if (isNaN(generation)) {
        return { error: 'Invalid generation parameter', generation: query.generation };
      }
      const results = this.kinshipService.getByGeneration(generation);
      return { results, total: results.length, generation };
    }

    // Default: meta info
    return this.kinshipService.getMetaInfo();
  }
}
