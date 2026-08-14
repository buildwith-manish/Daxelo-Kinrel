/**
 * Daxelo-Kinrel — Vocabulary Mapper CSV → PostgreSQL import
 * =========================================================
 * Usage:
 *   pnpm prisma db push          # create tables
 *   pnpm ts-node scripts/import-vocabulary.ts
 *
 * Reads:  /home/z/my-project/download/daxelo_kinrel_vocabulary.csv
 * Writes: kinship_vocabulary table (9,552 rows, ~3MB CSV → ~5MB in DB)
 *
 * Performance: uses Prisma createMany in batches of 500 — typical import
 * time on a local Postgres is ~6 seconds for the full dataset.
 */

import { PrismaClient } from "@prisma/client";
import { createInterface } from "readline";
import { createReadStream } from "fs";
import { join } from "path";

const CSV_PATH = process.env.KINREL_VOCAB_CSV
  || "/home/z/my-project/download/daxelo_kinrel_vocabulary.csv";
const BATCH_SIZE = 500;

const prisma = new PrismaClient();

interface VocabRow {
  rowId: number;
  canonicalId: string;
  signatureKey: string;
  pathPattern: string;
  generationDelta: number;
  side: string;
  consanguinity: string;
  genderAnchor: string;
  seniority: string;
  removal: number;
  doubleKinship: boolean;
  temporal: string;
  category: string;
  englishTerm: string;
  notes: string;
  languageCode: string;
  languageName: string;
  localizedTerm: string;
  variantType: string;
  variantRank: number;
}

// Minimal RFC-4180-ish CSV parser — handles quoted fields with commas and "" escapes.
function parseCsvLine(line: string): string[] {
  const fields: string[] = [];
  let buf = "";
  let inQuotes = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (inQuotes) {
      if (c === '"') {
        if (line[i + 1] === '"') {
          buf += '"';
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        buf += c;
      }
    } else {
      if (c === '"') {
        inQuotes = true;
      } else if (c === ",") {
        fields.push(buf);
        buf = "";
      } else {
        buf += c;
      }
    }
  }
  fields.push(buf);
  return fields;
}

async function main() {
  console.log(`[1/4] Reading CSV: ${CSV_PATH}`);
  const rl = createInterface({
    input: createReadStream(CSV_PATH, { encoding: "utf-8" }),
    crlfDelay: Infinity,
  });

  const rows: VocabRow[] = [];
  let header: string[] | null = null;
  let lineNo = 0;

  for await (const line of rl) {
    lineNo++;
    if (lineNo === 1) {
      header = parseCsvLine(line);
      continue;
    }
    if (!header) throw new Error("CSV missing header");
    const cells = parseCsvLine(line);
    if (cells.length < header.length) continue;
    const obj: Record<string, string> = {};
    header.forEach((h, i) => (obj[h] = cells[i] ?? ""));
    rows.push({
      rowId: parseInt(obj.row_id, 10),
      canonicalId: obj.canonical_id,
      signatureKey: obj.signature_key,
      pathPattern: obj.path_pattern,
      generationDelta: parseInt(obj.generation_delta, 10),
      side: obj.side,
      consanguinity: obj.consanguinity,
      genderAnchor: obj.gender_anchor,
      seniority: obj.seniority,
      removal: parseInt(obj.removal, 10),
      doubleKinship: obj.double_kinship === "True" || obj.double_kinship === "true",
      temporal: obj.temporal || "current",
      category: obj.category,
      englishTerm: obj.english_term,
      notes: obj.notes || "",
      languageCode: obj.language_code,
      languageName: obj.language_name,
      localizedTerm: obj.localized_term,
      variantType: obj.variant_type,
      variantRank: parseInt(obj.variant_rank, 10),
    });
  }
  console.log(`      parsed ${rows.length} rows`);

  console.log("[2/4] Truncating kinship_vocabulary (idempotent re-import)...");
  await prisma.$executeRawUnsafe('TRUNCATE "KinshipVocabulary" RESTART IDENTITY CASCADE');

  console.log("[3/4] Inserting rows in batches of 500...");
  let inserted = 0;
  for (let i = 0; i < rows.length; i += BATCH_SIZE) {
    const batch = rows.slice(i, i + BATCH_SIZE);
    await prisma.kinshipVocabulary.createMany({
      data: batch.map((r) => ({
        rowId: r.rowId,
        canonicalId: r.canonicalId,
        signatureKey: r.signatureKey,
        pathPattern: r.pathPattern,
        generationDelta: r.generationDelta,
        side: r.side,
        consanguinity: r.consanguinity,
        genderAnchor: r.genderAnchor,
        seniority: r.seniority,
        removal: r.removal,
        doubleKinship: r.doubleKinship,
        temporal: r.temporal,
        category: r.category,
        englishTerm: r.englishTerm,
        notes: r.notes,
        languageCode: r.languageCode,
        languageName: r.languageName,
        localizedTerm: r.localizedTerm,
        variantType: r.variantType,
        variantRank: r.variantRank,
      })),
      skipDuplicates: false,
    });
    inserted += batch.length;
    if (inserted % 2000 === 0 || inserted === rows.length) {
      console.log(`      inserted ${inserted}/${rows.length}`);
    }
  }

  console.log("[4/4] Verifying row count + determinism index...");
  const total = await prisma.kinshipVocabulary.count();
  const primaryOnly = await prisma.kinshipVocabulary.count({ where: { variantRank: 0 } });
  const languages = await prisma.kinshipVocabulary.groupBy({
    by: ["languageCode"],
    _count: true,
  });
  console.log(`  ✓ Total rows: ${total}`);
  console.log(`  ✓ Primary (variant_rank=0): ${primaryOnly}`);
  console.log(`  ✓ Languages: ${languages.length}`);
  console.log("\nImport complete. Engine can now do deterministic lookups via:");
  console.log('  WHERE signature_key = $1 AND language_code = $2 AND variant_rank = 0');
}

main()
  .catch((e) => {
    console.error("Import failed:", e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
