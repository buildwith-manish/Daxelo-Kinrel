/**
 * Daxelo-Kinrel — Kinship Vocabulary Mapper Service (spec §7)
 * ============================================================
 * Looks up a localized kinship term from a KinshipSignature.
 *
 *   KinshipSignature
 *         ↓
 *   Vocabulary Mapper  (this service)
 *         ↓
 *   Kinship Term (from 9,552-row table)
 *
 * Lookup contract (deterministic, spec §14):
 *   WHERE signature_key = $1
 *     AND language_code = $2
 *     AND variant_rank  = 0
 *
 * Fallback chain (spec §7.2):
 *   1. Try without seniority
 *   2. Try with genderAnchor = neutral
 *   3. Try generic term
 *   4. Compose descriptive term as last resort
 */

import { Injectable } from "@nestjs/common";
import { PrismaService } from "../../prisma/prisma.service"; // assumed
import {
  KinshipSignature,
  signatureKey,
  GenderAnchor,
  Seniority,
} from "./kinship-signature";

export interface LookupResult {
  localizedTerm: string;
  englishTerm: string;
  canonicalId: string;
  category: string;
  signatureKey: string;
  matchedViaFallback: boolean;
  fallbackStep?: 1 | 2 | 3 | 4;
}

@Injectable()
export class KinshipService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Deterministic primary lookup — variant_rank=0 only.
   * Same signature + same language = same term. Always. (spec §14)
   */
  async resolveTerm(sig: KinshipSignature, languageCode: string): Promise<LookupResult> {
    const key = signatureKey(sig);

    // Step 0: exact match
    const exact = await this.prisma.kinshipVocabulary.findFirst({
      where: { signatureKey: key, languageCode, variantRank: 0 },
    });
    if (exact) {
      return {
        localizedTerm: exact.localizedTerm,
        englishTerm: exact.englishTerm,
        canonicalId: exact.canonicalId,
        category: exact.category,
        signatureKey: exact.signatureKey,
        matchedViaFallback: false,
      };
    }

    // Step 1: try without seniority (spec §7.2)
    const sigNoSeniority: KinshipSignature = { ...sig, seniority: "none" as Seniority };
    const key1 = signatureKey(sigNoSeniority);
    const r1 = await this.prisma.kinshipVocabulary.findFirst({
      where: { signatureKey: key1, languageCode, variantRank: 0 },
    });
    if (r1) {
      return this.toResult(r1, true, 1);
    }

    // Step 2: try with genderAnchor = neutral
    const sigNeutral: KinshipSignature = { ...sig, genderAnchor: "neutral" as GenderAnchor };
    const key2 = signatureKey(sigNeutral);
    const r2 = await this.prisma.kinshipVocabulary.findFirst({
      where: { signatureKey: key2, languageCode, variantRank: 0 },
    });
    if (r2) {
      return this.toResult(r2, true, 2);
    }

    // Step 3: try generic term — match on pathPattern + side only
    const r3 = await this.prisma.kinshipVocabulary.findFirst({
      where: {
        pathPattern: sig.pathPattern,
        languageCode,
        variantRank: 0,
      },
    });
    if (r3) {
      return this.toResult(r3, true, 3);
    }

    // Step 4: compose a descriptive term as last resort
    const composed = this.composeDescriptive(sig);
    return {
      localizedTerm: composed,
      englishTerm: composed,
      canonicalId: "DERIVED",
      category: "composed",
      signatureKey: key,
      matchedViaFallback: true,
      fallbackStep: 4,
    };
  }

  /**
   * Resolve all regional/dialectal variants for a signature.
   * Used by the UI to show "Also known as: granduncle, great-uncle".
   */
  async resolveVariants(sig: KinshipSignature, languageCode: string): Promise<LookupResult[]> {
    const key = signatureKey(sig);
    const rows = await this.prisma.kinshipVocabulary.findMany({
      where: { signatureKey: key, languageCode },
      orderBy: { variantRank: "asc" },
    });
    return rows.map((r) => this.toResult(r, false));
  }

  /**
   * Return all known terms in a given language for browsing/search.
   */
  async listByLanguage(languageCode: string, category?: string) {
    return this.prisma.kinshipVocabulary.findMany({
      where: {
        languageCode,
        variantRank: 0,
        ...(category ? { category } : {}),
      },
      orderBy: [{ category: "asc" }, { englishTerm: "asc" }],
    });
  }

  // -------------------------------------------------------------------------
  // Internal helpers
  // -------------------------------------------------------------------------

  private toResult(
    row: any,
    matchedViaFallback: boolean,
    fallbackStep?: 1 | 2 | 3 | 4,
  ): LookupResult {
    return {
      localizedTerm: row.localizedTerm,
      englishTerm: row.englishTerm,
      canonicalId: row.canonicalId,
      category: row.category,
      signatureKey: row.signatureKey,
      matchedViaFallback,
      fallbackStep,
    };
  }

  /**
   * Compose a human-readable description as last-resort fallback (spec §7.2 step 4).
   * Example: gen=-3, side=paternal, gender=male → "paternal great-great-grandfather (composed)"
   */
  private composeDescriptive(sig: KinshipSignature): string {
    const ordinals = [
      "", "grand", "great-grand", "2nd great-grand",
      "3rd great-grand", "4th great-grand", "5th great-grand",
      "6th great-grand", "7th great-grand",
    ];
    const sidePrefix = sig.side !== "none" ? `${sig.side} ` : "";
    const genAbs = Math.abs(sig.generationDelta);

    if (sig.generationDelta < 0) {
      // Ancestor
      const root = sig.genderAnchor === "female" ? "mother" : "father";
      const ord = ordinals[genAbs] || `${genAbs}th great-grand`;
      return `${sidePrefix}${ord}${root} (composed)`;
    }
    if (sig.generationDelta > 0) {
      const root = sig.genderAnchor === "female" ? "daughter" : "son";
      const ord = ordinals[genAbs] || `${genAbs}th great-grand`;
      return `${ord}${root} (composed)`;
    }
    // Same generation
    if (sig.consanguinity === "inLaw") return "in-law (composed)";
    return `${sig.pathPattern} (composed)`;
  }
}
