// =============================================================================
// Track C v2.0 - Local TF-IDF + cosine similarity pre-filter for duplicate
// detection. Pure statistics - no model, no package, no API call.
// =============================================================================
// Sits in front of the existing AI-based DuplicateDetectionKind. The
// IntelligenceService calls `preFilter()` before building the LLM request.
//
// Decision tree:
//   - tfidfCosineSimilarity(newDecision, closestPrior) >= HIGH_THRESHOLD
//     -> return { path: 'local_match', duplicates: [closestPrior] }
//       (skip the AI call entirely - title wording is near-identical)
//   - tfidfCosineSimilarity(newDecision, closestPrior) < LOW_THRESHOLD
//     -> return { path: 'local_skip', duplicates: [] }
//       (skip the AI call - wording is too dissimilar to be a duplicate)
//   - LOW_THRESHOLD <= sim < HIGH_THRESHOLD
//     -> return { path: 'escalate', duplicates: [] }
//       (ambiguous band - proceed to the AI call as before)
//
// Tokenization: lowercase, split on non-alphanumeric, drop stopwords + 1-char
// tokens. Sufficient for title-based dedup - we're not trying to detect
// semantic duplicates of paraphrased titles, that's the AI's job.
// =============================================================================

const STOPWORDS = new Set<string>([
  // English
  'a', 'an', 'the', 'and', 'or', 'but', 'is', 'are', 'was', 'were', 'be',
  'been', 'being', 'have', 'has', 'had', 'do', 'does', 'did', 'will',
  'would', 'could', 'should', 'may', 'might', 'must', 'shall', 'can',
  'to', 'of', 'in', 'on', 'at', 'by', 'for', 'with', 'about', 'against',
  'between', 'into', 'through', 'during', 'before', 'after', 'above',
  'below', 'from', 'up', 'down', 'out', 'off', 'over', 'under', 'again',
  'further', 'then', 'once', 'here', 'there', 'when', 'where', 'why',
  'how', 'all', 'both', 'each', 'few', 'more', 'most', 'other', 'some',
  'such', 'no', 'nor', 'not', 'only', 'own', 'same', 'so', 'than', 'too',
  'very', 's', 't', 'just', 'don', 'now', 'we', 'our', 'you', 'your',
  'they', 'their', 'it', 'its', 'i', 'me', 'my', 'he', 'she', 'him',
  'her', 'his', 'hers', 'this', 'that', 'these', 'those',
  // Common Indian family-meeting words that don't help distinguish decisions
  'family', 'decision', 'vote', 'should', 'about', 'what', 'who', 'which',
  // Hindi romanized common words (transliterated Indian English)
  'hai', 'hai?', 'kya', 'ka', 'ki', 'ke', 'ko', 'se', 'me', 'par', 'aur',
  'ya', 'nahi', 'ho', 'tha', 'the', 'hum', 'aap', 'tum',
]);

const HIGH_THRESHOLD = 0.85; // near-identical wording -> skip AI, return local match
const LOW_THRESHOLD = 0.40;  // dissimilar -> skip AI, no duplicates

export type DuplicatePrefilterPath = 'local_match' | 'local_skip' | 'escalate';

export interface DuplicatePrefilterResult {
  path: DuplicatePrefilterPath;
  duplicates: Array<{ decisionId: string; similarity: number; reason: string }>;
  closestMatch: { decisionId: string; similarity: number; reason: string } | null;
  message: string;
  /** Score of the top match - recorded for telemetry even when path==='local_skip'. */
  topScore: number;
}

/**
 * Tokenize a piece of text into a list of normalized tokens. Lowercases,
 * strips non-alphanumeric (preserves Unicode letters via \p{L} property
 * escape - important for Hindi/Marathi/Tamil text), drops stopwords and
 * single-character tokens.
 */
export function tokenize(text: string): string[] {
  if (!text) return [];
  // \p{L} = any Unicode letter; \p{N} = any Unicode number. The 'u' flag
  // enables Unicode property escapes. We split on anything that isn't a
  // letter or number - this handles Latin, Devanagari, Tamil, etc. uniformly.
  const raw = text.toLowerCase().match(/[\p{L}\p{N}]+/gu) ?? [];
  return raw.filter((t) => t.length > 1 && !STOPWORDS.has(t));
}

/**
 * Build a TF (term frequency) map from a token list.
 */
function termFrequencies(tokens: string[]): Map<string, number> {
  const tf = new Map<string, number>();
  for (const t of tokens) {
    tf.set(t, (tf.get(t) ?? 0) + 1);
  }
  // Normalize by max frequency (so a single repeated word doesn't dominate)
  const max = Math.max(1, ...tf.values());
  for (const [k, v] of tf) {
    tf.set(k, v / max);
  }
  return tf;
}

/**
 * Compute the IDF for each token across a corpus of documents.
 * idf(t) = ln(N / (1 + df(t))) where N is the corpus size and df(t) is the
 * number of documents containing t.
 */
function inverseDocFrequencies(corpus: string[][]): Map<string, number> {
  const N = Math.max(1, corpus.length);
  const df = new Map<string, number>();
  for (const doc of corpus) {
    const seen = new Set<string>();
    for (const t of doc) {
      if (!seen.has(t)) {
        df.set(t, (df.get(t) ?? 0) + 1);
        seen.add(t);
      }
    }
  }
  const idf = new Map<string, number>();
  for (const [t, d] of df) {
    idf.set(t, Math.log(N / (1 + d)) + 1); // +1 smoothing, +1 floor to avoid zero
  }
  return idf;
}

/**
 * Compute the TF-IDF vector for a document, given an IDF map.
 * The vector is a Map<token, weight> - we don't need a fixed dimension space.
 */
function tfidfVector(tokens: string[], idf: Map<string, number>): Map<string, number> {
  const tf = termFrequencies(tokens);
  const vec = new Map<string, number>();
  for (const [t, freq] of tf) {
    vec.set(t, freq * (idf.get(t) ?? 1));
  }
  return vec;
}

/**
 * Cosine similarity between two sparse vectors represented as Maps.
 * Returns 0..1 (TF-IDF vectors are non-negative, so cosine is in [0,1]).
 */
function cosineSimilarity(a: Map<string, number>, b: Map<string, number>): number {
  let dot = 0;
  let normA = 0;
  let normB = 0;
  for (const [k, v] of a) {
    normA += v * v;
    const w = b.get(k);
    if (w !== undefined) dot += v * w;
  }
  for (const [, v] of b) {
    normB += v * v;
  }
  if (normA === 0 || normB === 0) return 0;
  return dot / Math.sqrt(normA * normB);
}

/**
 * Build a corpus from the prior decisions + the new decision. The IDF is
 * computed over this corpus so the new decision is taken into account when
 * weighing how distinctive each term is.
 */
function buildCorpus(
  newTitle: string,
  newDesc: string,
  priors: Array<{ id: string; title: string; description?: string }>,
): { docs: string[][]; docsById: Map<string, string[]> } {
  const docs: string[][] = [];
  const docsById = new Map<string, string[]>();
  const newDoc = tokenize(`${newTitle} ${newDesc ?? ''}`);
  docs.push(newDoc);
  for (const p of priors) {
    const d = tokenize(`${p.title} ${p.description ?? ''}`);
    docs.push(d);
    docsById.set(p.id, d);
  }
  return { docs, docsById };
}

/**
 * Main entry point. Returns the pre-filter decision + (if applicable) the
 * local match. The caller logs the path taken so token savings can be
 * measured after shipping.
 */
export function preFilterDuplicates(params: {
  newDecisionTitle: string;
  newDecisionDescription?: string;
  priorDecisions: Array<{ id: string; title: string; description?: string }>;
}): DuplicatePrefilterResult {
  // Edge case: no prior decisions -> no duplicates possible, skip the AI call.
  if (params.priorDecisions.length === 0) {
    return {
      path: 'local_skip',
      duplicates: [],
      closestMatch: null,
      message: 'No prior decisions to compare against.',
      topScore: 0,
    };
  }

  // Edge case: empty new title -> can't compute similarity, escalate to AI
  // (the AI prompt will handle the empty case gracefully).
  const newTokens = tokenize(`${params.newDecisionTitle} ${params.newDecisionDescription ?? ''}`);
  if (newTokens.length === 0) {
    return {
      path: 'escalate',
      duplicates: [],
      closestMatch: null,
      message: 'New decision has no usable text - escalating to AI.',
      topScore: 0,
    };
  }

  const { docs, docsById } = buildCorpus(
    params.newDecisionTitle,
    params.newDecisionDescription ?? '',
    params.priorDecisions,
  );
  const idf = inverseDocFrequencies(docs);
  const newVec = tfidfVector(newTokens, idf);

  // Score each prior decision
  let bestId: string | null = null;
  let bestScore = -1;
  const allScores: Array<{ id: string; score: number }> = [];
  for (const prior of params.priorDecisions) {
    const priorVec = tfidfVector(docsById.get(prior.id) ?? [], idf);
    const score = cosineSimilarity(newVec, priorVec);
    allScores.push({ id: prior.id, score });
    if (score > bestScore) {
      bestScore = score;
      bestId = prior.id;
    }
  }

  if (bestId === null || bestScore < 0) {
    return {
      path: 'local_skip',
      duplicates: [],
      closestMatch: null,
      message: 'No similar decisions found locally.',
      topScore: 0,
    };
  }

  const bestTitle =
    params.priorDecisions.find((p) => p.id === bestId)?.title ?? '(unknown)';

  // High similarity -> return the local match, skip the AI call.
  if (bestScore >= HIGH_THRESHOLD) {
    const reason = `Title/description is ${(bestScore * 100).toFixed(0)}% similar to "${bestTitle}" (TF-IDF cosine)`;
    return {
      path: 'local_match',
      duplicates: [
        {
          decisionId: bestId,
          similarity: Number(bestScore.toFixed(3)),
          reason,
        },
      ],
      closestMatch: {
        decisionId: bestId,
        similarity: Number(bestScore.toFixed(3)),
        reason,
      },
      message: `Near-duplicate detected locally (score ${bestScore.toFixed(2)} >= ${HIGH_THRESHOLD}). AI call skipped.`,
      topScore: Number(bestScore.toFixed(3)),
    };
  }

  // Low similarity -> no duplicates, skip the AI call.
  if (bestScore < LOW_THRESHOLD) {
    return {
      path: 'local_skip',
      duplicates: [],
      closestMatch: {
        decisionId: bestId,
        similarity: Number(bestScore.toFixed(3)),
        reason: `Closest prior decision "${bestTitle}" has only ${(bestScore * 100).toFixed(0)}% similarity (TF-IDF cosine) - below the ${LOW_THRESHOLD * 100}% threshold for considering a duplicate.`,
      },
      message: `No plausible duplicates (top score ${bestScore.toFixed(2)} < ${LOW_THRESHOLD}). AI call skipped.`,
      topScore: Number(bestScore.toFixed(3)),
    };
  }

  // Ambiguous band -> escalate to AI
  return {
    path: 'escalate',
    duplicates: [],
    closestMatch: {
      decisionId: bestId,
      similarity: Number(bestScore.toFixed(3)),
      reason: `Ambiguous similarity (${(bestScore * 100).toFixed(0)}%) to "${bestTitle}" - escalating to AI for semantic judgment.`,
    },
    message: `Ambiguous band (score ${bestScore.toFixed(2)} is between ${LOW_THRESHOLD} and ${HIGH_THRESHOLD}) - escalating to AI.`,
    topScore: Number(bestScore.toFixed(3)),
  };
}

/**
 * Exported for unit testing + telemetry. Returns the high/low thresholds
 * so callers can verify the pre-filter configuration.
 */
export const PREFILTER_THRESHOLDS = {
  HIGH_THRESHOLD,
  LOW_THRESHOLD,
} as const;
