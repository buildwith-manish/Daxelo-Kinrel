// =============================================================================
// Track C v2.0 - Embedding Service (ML spec item #3)
// =============================================================================
// Loads `Xenova/all-MiniLM-L6-v2` (~80MB) via @xenova/transformers and
// provides a single entry point: `embed(text) -> number[]` (384-dim vector).
//
// Used by SearchService for semantic rerank of tsvector results. Loaded
// lazily on first call so the server's cold-start memory footprint is
// unaffected. Cached for the lifetime of the process.
//
// Memory note (Render free tier = 512MB):
//   - all-MiniLM-L6-v2 base + ONNX runtime ? 150-200MB resident after first load.
//   - The toxic-bert model from ModerationClassifier adds another ~250MB.
//   - Combined: ~400MB resident, leaving ~100MB for the NestJS app itself.
//   - If this exceeds the free tier, set EMBEDDING_MODEL_ID to a smaller
//     model (e.g. `Xenova/all-MiniLM-L6-v2` quantized int8) via env var.
// =============================================================================

import { Injectable, Logger } from '@nestjs/common';

// Lazy-load transformers - same pattern as ModerationClassifier.
let TransformersModule: typeof import('@xenova/transformers') | null = null;
async function getTransformers() {
  if (!TransformersModule) {
    TransformersModule = await import('@xenova/transformers');
  }
  return TransformersModule;
}

const DEFAULT_MODEL_ID = 'Xenova/all-MiniLM-L6-v2';
const EXPECTED_DIM = 384;

@Injectable()
export class EmbeddingService {
  private readonly logger = new Logger(EmbeddingService.name);
  private pipeline: any = null;
  private modelLoadFailed = false;
  private modelLoadPromise: Promise<any> | null = null;

  private readonly modelId: string =
    process.env.EMBEDDING_MODEL_ID || DEFAULT_MODEL_ID;

  /**
   * Embed a piece of text. Returns a 384-dim float array, or null if the
   * model failed to load (callers should fall back to keyword-only search).
   *
   * Truncates input to ~512 tokens (the model's max). Beyond that the model
   * silently truncates anyway, but we cap raw input length to avoid
   * pathological memory use on very long inputs.
   */
  async embed(text: string): Promise<number[] | null> {
    if (this.modelLoadFailed) return null;
    if (!text || !text.trim()) return null;

    try {
      const pipe = await this.getPipeline();
      const truncated = text.length > 4000 ? text.slice(0, 4000) : text;
      const output = await pipe(truncated, { pooling: 'mean', normalize: true });

      // The pipeline returns a Tensor object. `.data` is a Float32Array.
      // Convert to a regular number array for JSON serialization.
      const data = output.data as Float32Array;
      const arr = Array.from(data);

      // Sanity check - if the model produced an unexpected dimension, log
      // and return null (don't poison the cosine similarity computation).
      if (arr.length !== EXPECTED_DIM) {
        this.logger.warn(
          `Embedding dimension mismatch: expected ${EXPECTED_DIM}, got ${arr.length}. ` +
            `Model may have been changed - update EXPECTED_DIM.`,
        );
        return null;
      }
      return arr;
    } catch (err) {
      this.logger.error(
        `Embedding inference failed: ${(err as Error).message}`,
        (err as Error).stack,
      );
      return null;
    }
  }

  /**
   * Batch embed multiple texts in a single model call. More efficient than
   * calling embed() N times when you have many texts (e.g. during reindex).
   * Returns null-array entries for inputs that failed.
   */
  async embedBatch(texts: string[]): Promise<(number[] | null)[]> {
    if (texts.length === 0) return [];
    const results = await Promise.all(texts.map((t) => this.embed(t)));
    return results;
  }

  /**
   * Cosine similarity between two equal-length vectors. Returns 0 if either
   * is null/empty or lengths differ.
   */
  static cosineSimilarity(a: number[] | null, b: number[] | null): number {
    if (!a || !b || a.length !== b.length || a.length === 0) return 0;
    let dot = 0;
    let normA = 0;
    let normB = 0;
    for (let i = 0; i < a.length; i++) {
      const av = a[i];
      const bv = b[i];
      dot += av * bv;
      normA += av * av;
      normB += bv * bv;
    }
    if (normA === 0 || normB === 0) return 0;
    return dot / Math.sqrt(normA * normB);
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

  private async getPipeline(): Promise<any> {
    if (this.pipeline) return this.pipeline;
    if (this.modelLoadPromise) return this.modelLoadPromise;

    this.modelLoadPromise = (async () => {
      try {
        const transformers = await getTransformers();
        const pipeline = transformers.pipeline;
        const instance = await pipeline('feature-extraction', this.modelId, {
          quantized: true, // int8 quantized - halves memory at minimal accuracy cost
        });
        this.pipeline = instance;
        this.logger.log(`Embedding model loaded: ${this.modelId}`);
        return instance;
      } catch (err) {
        this.modelLoadFailed = true;
        this.logger.error(
          `Failed to load embedding model ${this.modelId}: ${(err as Error).message}. ` +
            `Semantic search rerank will be disabled - falling back to keyword-only. ` +
            `Set EMBEDDING_MODEL_ID to a smaller model if memory-constrained.`,
          (err as Error).stack,
        );
        throw err;
      } finally {
        this.modelLoadPromise = null;
      }
    })();

    return this.modelLoadPromise;
  }
}
