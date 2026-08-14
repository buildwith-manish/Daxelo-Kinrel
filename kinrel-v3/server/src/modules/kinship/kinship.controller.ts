/**
 * Daxelo-Kinrel — Kinship HTTP Controller
 * ========================================
 * Browse-only endpoints over the 9,552-row vocabulary table.
 *
 *   GET /kinship/languages                  list all supported languages
 *   GET /kinship/categories                 list all categories
 *   GET /kinship/browse?lang=&category=     browse primary terms (variant_rank=0)
 *   GET /kinship/lookup?sig=&lang=          direct lookup by signatureKey
 */

import { Controller, Get, Query, BadRequestException } from "@nestjs/common";
import { KinshipService } from "./kinship.service";
import { PrismaService } from "../../prisma/prisma.service";

@Controller("kinship")
export class KinshipController {
  constructor(
    private readonly kinship: KinshipService,
    private readonly prisma: PrismaService,
  ) {}

  @Get("languages")
  async languages() {
    const rows = await this.prisma.kinshipVocabulary.findMany({
      distinct: ["languageCode"],
      select: { languageCode: true, languageName: true },
      orderBy: { languageName: "asc" },
    });
    return { count: rows.length, languages: rows };
  }

  @Get("categories")
  async categories() {
    const rows = await this.prisma.kinshipVocabulary.findMany({
      distinct: ["category"],
      select: { category: true },
      orderBy: { category: "asc" },
    });
    return { count: rows.length, categories: rows.map((r) => r.category) };
  }

  @Get("browse")
  async browse(
    @Query("lang") lang: string = "en",
    @Query("category") category?: string,
    @Query("limit") limit?: string,
  ) {
    const take = limit ? Math.min(parseInt(limit, 10) || 100, 1000) : 100;
    return this.kinship.listByLanguage(lang, category);
  }

  @Get("lookup")
  async lookup(
    @Query("sig") sig: string,
    @Query("lang") lang: string = "en",
    @Query("includeVariants") includeVariants?: string,
  ) {
    if (!sig) throw new BadRequestException("sig query param required (signatureKey)");
    const wantVariants = includeVariants === "1" || includeVariants === "true";
    if (wantVariants) {
      // Fake a signature from the key — for direct lookup we can use findMany
      const rows = await this.prisma.kinshipVocabulary.findMany({
        where: { signatureKey: sig, languageCode: lang },
        orderBy: { variantRank: "asc" },
      });
      return { count: rows.length, rows };
    }
    const row = await this.prisma.kinshipVocabulary.findFirst({
      where: { signatureKey: sig, languageCode: lang, variantRank: 0 },
    });
    return { found: !!row, row };
  }

  @Get("stats")
  async stats() {
    const total = await this.prisma.kinshipVocabulary.count();
    const primary = await this.prisma.kinshipVocabulary.count({ where: { variantRank: 0 } });
    const byLanguage = await this.prisma.kinshipVocabulary.groupBy({
      by: ["languageCode"],
      _count: true,
      orderBy: { _count: { languageCode: "desc" } },
    });
    const byCategory = await this.prisma.kinshipVocabulary.groupBy({
      by: ["category"],
      _count: true,
      orderBy: { _count: { category: "desc" } },
    });
    const byTemporal = await this.prisma.kinshipVocabulary.groupBy({
      by: ["temporal"],
      _count: true,
    });
    return { total, primary, byLanguage, byCategory, byTemporal };
  }
}
