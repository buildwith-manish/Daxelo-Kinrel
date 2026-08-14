/**
 * Daxelo-Kinrel — Canonical Relationship ID Layer (spec §4)
 * =========================================================
 * All user-facing kinship terms, colloquial names, and regional variants
 * must map to a Canonical Relationship ID before entering the engine.
 *
 *   father/dad/appa/papa/baba    → PARENT
 *   mother/mom/amma/maa          → PARENT
 *   husband/pati/miya            → SPOUSE
 *   wife/patni/biwi              → SPOUSE
 *   son/beta/putra               → PARENT (inverse direction)
 *   grandfather/dada/nana        → DERIVED (do not store; engine resolves)
 *   uncle/chacha/mama            → DERIVED
 *   cousin                       → DERIVED
 */

export type CanonicalId =
  | "PARENT"
  | "SPOUSE"
  | "ADOPTIVE_PARENT"
  | "STEP_PARENT"
  | "DERIVED";

// Locale-aware synonym table. New variants can be added without engine changes.
// Format: { languageCode: { term_lowercased: CanonicalId } }
const SYNONYMS: Record<string, Record<string, CanonicalId>> = {
  en: {
    father: "PARENT", dad: "PARENT", papa: "PARENT", daddy: "PARENT",
    mother: "PARENT", mom: "PARENT", mama: "PARENT", mummy: "PARENT",
    parent: "PARENT",
    son: "PARENT", daughter: "PARENT", child: "PARENT",
    husband: "SPOUSE", wife: "SPOUSE", spouse: "SPOUSE",
    "adoptive father": "ADOPTIVE_PARENT", "adoptive mother": "ADOPTIVE_PARENT",
    "adoptive parent": "ADOPTIVE_PARENT",
    "stepfather": "STEP_PARENT", "stepmother": "STEP_PARENT",
    "step father": "STEP_PARENT", "step mother": "STEP_PARENT", "step parent": "STEP_PARENT",
    // Derived — engine must NOT store; it traces back to a fundamental edge.
    grandfather: "DERIVED", grandmother: "DERIVED",
    uncle: "DERIVED", aunt: "DERIVED",
    cousin: "DERIVED", nephew: "DERIVED", niece: "DERIVED",
    brother: "DERIVED", sister: "DERIVED",
  },
  hi: {
    पिता: "PARENT", पापा: "PARENT", बाबा: "PARENT",
    माता: "PARENT", अम्मा: "PARENT", माँ: "PARENT", मम्मी: "PARENT",
    पति: "SPOUSE", पत्नी: "SPOUSE",
    पुत्र: "PARENT", पुत्री: "PARENT", बेटा: "PARENT", बेटी: "PARENT",
    "दत्तक पिता": "ADOPTIVE_PARENT", "दत्तक माता": "ADOPTIVE_PARENT",
    "सौतेला पिता": "STEP_PARENT", "सौतेली माता": "STEP_PARENT",
    दादा: "DERIVED", दादी: "DERIVED", नाना: "DERIVED", नानी: "DERIVED",
    चाचा: "DERIVED", बुआ: "DERIVED", मामा: "DERIVED", मामी: "DERIVED",
    भाई: "DERIVED", बहन: "DERIVED",
    भतीजा: "DERIVED", भतीजी: "DERIVED",
  },
  ta: {
    அப்பா: "PARENT", தந்தை: "PARENT",
    அம்மா: "PARENT", தாய்: "PARENT",
    கணவர்: "SPOUSE", மனைவி: "SPOUSE",
    மகன்: "PARENT", மகள்: "PARENT",
    தாத்தா: "DERIVED", பாட்டி: "DERIVED",
    மாமா: "DERIVED", அத்தை: "DERIVED",
    சகோதரன்: "DERIVED", சகோதரி: "DERIVED",
  },
  te: {
    నాన్న: "PARENT", తండ్రి: "PARENT",
    అమ్మ: "PARENT", తల్లి: "PARENT",
    భర్త: "SPOUSE", భార్య: "SPOUSE",
    కుమారుడు: "PARENT", కుమార్తె: "PARENT",
    తాత: "DERIVED", అమ్మమ్మ: "DERIVED",
    మామయ్య: "DERIVED", పిన్ని: "DERIVED",
  },
  // Add more languages as needed — engine never changes.
};

const DEFAULT_FALLBACK: Record<string, CanonicalId> = {
  father: "PARENT", mother: "PARENT", parent: "PARENT",
  husband: "SPOUSE", wife: "SPOUSE", spouse: "SPOUSE",
  son: "PARENT", daughter: "PARENT", child: "PARENT",
};

export class CanonicalIdService {
  /**
   * Map a user-facing term to its CanonicalId.
   * Returns "DERIVED" when the term is a derived kinship label
   * (grandfather, uncle, cousin, etc.) — the engine must then
   * trace back to the missing fundamental edge (spec §8.2).
   */
  normalizeToCanonical(input: string, locale: string = "en"): CanonicalId {
    if (!input) return "DERIVED";
    const term = input.trim().toLowerCase();
    const localeTable = SYNONYMS[locale] ?? SYNONYMS.en ?? {};
    if (term in localeTable) return localeTable[term];
    if (term in DEFAULT_FALLBACK) return DEFAULT_FALLBACK[term];
    // Unknown term — treat as derived; engine will prompt the user.
    return "DERIVED";
  }

  /**
   * Returns true if the canonical ID is a storable fundamental edge
   * (parent, spouse, adoptive_parent, step_parent).
   * Returns false for DERIVED — engine must not store directly.
   */
  isStorable(canonicalId: CanonicalId): boolean {
    return canonicalId !== "DERIVED";
  }

  /**
   * Returns true if the term is a derived kinship label that the
   * engine must resolve by tracing back to a fundamental edge.
   */
  isDerived(input: string, locale: string = "en"): boolean {
    return this.normalizeToCanonical(input, locale) === "DERIVED";
  }
}
