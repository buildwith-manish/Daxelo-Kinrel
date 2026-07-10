// =============================================================================
// Moderation Classifier - local ONNX model for toxicity / hate-speech detection
// =============================================================================
// Replaces the regex-only content classification in moderation.service.ts with
// a hybrid approach:
//
//   1. Regex fast-pass (existing CLASSIFICATION_RULES) - catches obvious
//      literal-word matches in O(1). No model load needed.
//   2. If regex doesn't match AND content is long enough to be worth scoring
//      (>= MIN_LENGTH_FOR_MODEL chars), route to the local transformer model.
//   3. Model output (per-label probabilities) is merged into the existing
//      category/action/priority shape so downstream code doesn't change.
//
// Model: `Xenova/toxic-bert` (ONNX-converted unitary/toxic-bert, ~110MB).
// Loaded lazily on first call so the server's cold-start memory footprint is
// unaffected. Cached for the lifetime of the process.
//
// Memory note (Render free tier = 512MB):
//   - toxic-bert base + ONNX runtime ? 250-300MB resident after first load.
//   - If this exceeds the free tier, switch the model id to a smaller
//     quantized variant (e.g. `Xenova/toxic-bert` int8) via env var
//     MODERATION_MODEL_ID. The pipeline call below already respects that.
// =============================================================================

import { Injectable, Logger, Optional } from '@nestjs/common';

// Lazy-load @xenova/transformers - the import itself pulls in onnxruntime
// native bindings, which we don't want at server boot time. We use a dynamic
// import() guarded by a flag so the module only loads when the classifier is
// actually first invoked.
let TransformersModule: typeof import('@xenova/transformers') | null = null;
async function getTransformers() {
  if (!TransformersModule) {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    TransformersModule = await import('@xenova/transformers');
  }
  return TransformersModule;
}

// Thresholds - tuned for low false-positive rate. The model outputs per-label
// scores in [0,1]; we treat any label exceeding its threshold as a hit.
const TOXICITY_THRESHOLD = 0.55;
const SEVERE_TOXICITY_THRESHOLD = 0.45;
const IDENTITY_ATTACK_THRESHOLD = 0.5;
const INSULT_THRESHOLD = 0.55;
const THREAT_THRESHOLD = 0.5;
const PROFANITY_THRESHOLD = 0.7; // profanity alone is low-priority

// Minimum content length before we bother invoking the model. Single emoji
// reactions and "ok" replies aren't worth the inference cost.
const MIN_LENGTH_FOR_MODEL = 12;

// Model labels for Xenova/toxic-bert (in the order the model returns them)
const MODEL_LABELS = [
  'toxicity',
  'severe_toxicity',
  'obscene',
  'identity_attack',
  'insult',
  'threat',
  'sexual_explicit',
] as const;

export interface ModerationClassification {
  category: string; // 'safe' | 'violence' | 'hate_speech' | 'sexual_content' | 'toxic' | 'threat'
  action: string; // 'allow' | 'allow_with_flag' | 'quarantine' | 'reject'
  priority: string; // 'low' | 'normal' | 'high' | 'urgent' | 'critical'
  confidence: number; // 0..1
  flaggedCategories: string[];
  source: 'regex' | 'model' | 'skipped_short' | 'skipped_unavailable';
  modelScores?: Record<string, number>; // raw model output, for debugging/audit
}

@Injectable()
export class ModerationClassifier {
  private readonly logger = new Logger(ModerationClassifier.name);
  private pipeline: any = null;
  private modelLoadFailed = false;
  private modelLoadPromise: Promise<any> | null = null;

  // Allow override via env var (in case the default model is too heavy for
  // the deployment environment).
  private readonly modelId: string =
    process.env.MODERATION_MODEL_ID || 'Xenova/toxic-bert';

  /**
   * Classify content using the hybrid regex + model pipeline.
   *
   * @param content Raw user content (post body, comment, sparq text, etc.)
   * @param regexMatch The category the regex pass already matched, or 'safe'
   *   if no regex rule fired. When non-'safe', we trust the regex result and
   *   skip the model call (regex matches are high-precision by design).
   */
  async classify(content: string, regexMatch: { category: string; action: string; priority: string }): Promise<ModerationClassification> {
    // If regex already matched, return that - regex matches are deterministic
    // and high-precision (literal slurs, etc.). The model is only for content
    // the regex misses (typos, leetspeak, paraphrased threats, non-English).
    if (regexMatch.category !== 'safe') {
      return {
        category: regexMatch.category,
        action: regexMatch.action,
        priority: regexMatch.priority,
        confidence: 0.9, // regex matches are high-confidence by construction
        flaggedCategories: [regexMatch.category],
        source: 'regex',
      };
    }

    // Skip the model for very short content (single emoji, "ok", etc.) -
    // not worth the inference cost, and the model is unreliable on <12 chars.
    const trimmed = content.trim();
    if (trimmed.length < MIN_LENGTH_FOR_MODEL) {
      return {
        category: 'safe',
        action: 'allow',
        priority: 'normal',
        confidence: 0.6,
        flaggedCategories: [],
        source: 'skipped_short',
      };
    }

    // If a previous model load attempt failed (e.g. onnxruntime native binding
    // missing on the host), don't keep retrying - fall through to 'safe'.
    if (this.modelLoadFailed) {
      return {
        category: 'safe',
        action: 'allow',
        priority: 'normal',
        confidence: 0.5,
        flaggedCategories: [],
        source: 'skipped_unavailable',
      };
    }

    // Run the model
    try {
      const scores = await this.runModel(trimmed);
      return this.interpretScores(scores);
    } catch (err) {
      this.logger.error(
        `Moderation model inference failed: ${(err as Error).message}`,
        (err as Error).stack,
      );
      // Fail open - don't block content because the model broke. The regex
      // pass already ran, so anything truly heinous would have been caught.
      return {
        category: 'safe',
        action: 'allow',
        priority: 'normal',
        confidence: 0.5,
        flaggedCategories: [],
        source: 'skipped_unavailable',
        modelScores: undefined,
      };
    }
  }

  /**
   * Load the pipeline (idempotent - concurrent callers share the same promise).
   * Stored on the instance so subsequent classify() calls reuse it.
   */
  private async getPipeline(): Promise<any> {
    if (this.pipeline) return this.pipeline;
    if (this.modelLoadPromise) return this.modelLoadPromise;

    this.modelLoadPromise = (async () => {
      try {
        const transformers = await getTransformers();
        // Use the text-classification pipeline. The pipeline downloads the
        // model from Hugging Face on first use (~110MB), then caches it in
        // the OS tmp dir for subsequent boots.
        const pipeline = transformers.pipeline;
        const instance = await pipeline('text-classification', this.modelId, {
          quantized: true, // use int8 quantized weights - halves memory at minimal accuracy cost
        });
        this.pipeline = instance;
        this.logger.log(`Moderation model loaded: ${this.modelId}`);
        return instance;
      } catch (err) {
        this.modelLoadFailed = true;
        this.logger.error(
          `Failed to load moderation model ${this.modelId}: ${(err as Error).message}. ` +
            `Content moderation will fall back to regex-only. Set MODERATION_MODEL_ID to a smaller model if memory-constrained.`,
          (err as Error).stack,
        );
        throw err;
      } finally {
        this.modelLoadPromise = null;
      }
    })();

    return this.modelLoadPromise;
  }

  /**
   * Run the model on a single text input. Returns a map of label -> score.
   */
  private async runModel(text: string): Promise<Record<string, number>> {
    const pipe = await this.getPipeline();
    // The pipeline returns an array of { label, score } objects (single-label)
    // OR an array of objects with per-label scores (multi-label). toxic-bert
    // is multi-label, so we expect the latter.
    //
    // We truncate to 512 tokens (model max) - the pipeline does this by
    // default, but we also cap raw input length to avoid pathological cases.
    const truncated = text.length > 2000 ? text.slice(0, 2000) : text;
    const output = await pipe(truncated);

    // Normalize the output into a Record<label, score>
    const scores: Record<string, number> = {};
    if (Array.isArray(output)) {
      for (const item of output) {
        if (item && typeof item.label === 'string' && typeof item.score === 'number') {
          scores[item.label] = item.score;
        }
      }
    } else if (output && typeof output === 'object') {
      // Some pipelines return [{ score: [..], labels: [...] }] for multi-label
      // Handle that shape too.
      const anyOut = output as any;
      if (Array.isArray(anyOut.scores) && Array.isArray(anyOut.labels)) {
        anyOut.labels.forEach((label: string, i: number) => {
          scores[label] = anyOut.scores[i];
        });
      }
    }
    return scores;
  }

  /**
   * Map model scores to the existing category/action/priority shape.
   * Priority is determined by the most severe matching label.
   */
  private interpretScores(scores: Record<string, number>): ModerationClassification {
    const flagged: string[] = [];
    let maxSeverity: 'none' | 'low' | 'medium' | 'high' | 'critical' = 'none';
    let bestCategory = 'safe';
    let bestConfidence = 0.5;

    // Helper to bump severity monotonically
    const bump = (s: 'low' | 'medium' | 'high' | 'critical') => {
      const order = { none: 0, low: 1, medium: 2, high: 3, critical: 4 };
      if (order[s] > order[maxSeverity]) maxSeverity = s;
    };

    // Check each known label against its threshold
    if ((scores['severe_toxicity'] ?? 0) >= SEVERE_TOXICITY_THRESHOLD) {
      flagged.push('severe_toxicity');
      bump('critical');
      bestCategory = 'hate_speech';
      bestConfidence = Math.max(bestConfidence, scores['severe_toxicity']);
    }
    if ((scores['identity_attack'] ?? 0) >= IDENTITY_ATTACK_THRESHOLD) {
      flagged.push('identity_attack');
      bump('critical');
      bestCategory = 'hate_speech';
      bestConfidence = Math.max(bestConfidence, scores['identity_attack']);
    }
    if ((scores['threat'] ?? 0) >= THREAT_THRESHOLD) {
      flagged.push('threat');
      bump('high');
      if (bestCategory === 'safe') bestCategory = 'violence';
      bestConfidence = Math.max(bestConfidence, scores['threat']);
    }
    if ((scores['insult'] ?? 0) >= INSULT_THRESHOLD) {
      flagged.push('insult');
      bump('medium');
      if (bestCategory === 'safe') bestCategory = 'toxic';
      bestConfidence = Math.max(bestConfidence, scores['insult']);
    }
    if ((scores['toxicity'] ?? 0) >= TOXICITY_THRESHOLD) {
      flagged.push('toxicity');
      bump('medium');
      if (bestCategory === 'safe') bestCategory = 'toxic';
      bestConfidence = Math.max(bestConfidence, scores['toxicity']);
    }
    if ((scores['sexual_explicit'] ?? 0) >= 0.6) {
      flagged.push('sexual_explicit');
      bump('high');
      if (bestCategory === 'safe') bestCategory = 'sexual_content';
      bestConfidence = Math.max(bestConfidence, scores['sexual_explicit']);
    }
    if ((scores['obscene'] ?? 0) >= PROFANITY_THRESHOLD) {
      flagged.push('profanity');
      bump('low');
      bestConfidence = Math.max(bestConfidence, scores['obscene']);
    }

    if (flagged.length === 0) {
      return {
        category: 'safe',
        action: 'allow',
        priority: 'normal',
        confidence: 0.7,
        flaggedCategories: [],
        source: 'model',
        modelScores: scores,
      };
    }

    // Map severity -> action + priority
    const actionBySeverity: Record<string, string> = {
      low: 'allow_with_flag',
      medium: 'allow_with_flag',
      high: 'quarantine',
      critical: 'reject',
    };
    const priorityBySeverity: Record<string, string> = {
      low: 'low',
      medium: 'normal',
      high: 'urgent',
      critical: 'critical',
    };

    return {
      category: bestCategory,
      action: actionBySeverity[maxSeverity],
      priority: priorityBySeverity[maxSeverity],
      confidence: Math.min(0.99, bestConfidence),
      flaggedCategories: flagged,
      source: 'model',
      modelScores: scores,
    };
  }

  /**
   * Release the model from memory. Called by the module's onModuleDestroy.
   */
  async dispose(): Promise<void> {
    if (this.pipeline) {
      try {
        await this.pipeline.dispose?.();
      } catch {
        // ignore - best effort
      }
      this.pipeline = null;
    }
  }
}
