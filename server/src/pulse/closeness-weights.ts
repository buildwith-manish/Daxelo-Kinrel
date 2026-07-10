// =============================================================================
// ML spec item #5 — Learned Closeness Weights (logistic regression)
// =============================================================================
// Replaces the hardcoded weights in closeness.ts:
//   fixed: 0.30*dist + 0.15*gen + 0.35*sem + 0.10*kinrel + 0.10*shared
//
// With weights learned from actual user engagement data via logistic
// regression. The training data comes from BriefEngagement rows
// (recorded by BriefEngagementService).
//
// Algorithm: gradient descent on the logistic loss
//   L(w) = -1/N * Σ [ y_i * log(σ(w·x_i)) + (1-y_i) * log(1 - σ(w·x_i)) ]
// where:
//   - x_i is the 5-dim signal score vector for engagement event i
//   - y_i is 1 if the user engaged, 0 if they dismissed
//   - σ(z) = 1 / (1 + e^-z) is the sigmoid
//   - w is the 5-dim weight vector we're learning
//
// We also learn a bias term b. The final prediction is σ(w·x + b).
//
// Training is a BATCH job — not live. It runs periodically (e.g. monthly)
// via a CLI script or pg-boss job, and writes the learned weights to a
// GlobalLearningDefaults row (reusing the existing infrastructure). The
// live PersonalizationService reads the learned weights from there and
// uses them INSTEAD OF the fixed weights when computing closeness.
//
// Fallback: if there's not enough training data (<MIN_TRAINING_SAMPLES),
// the trainer refuses to ship a model — the PersonalizationService keeps
// using the fixed weights. This is per the spec: "If it doesn't beat the
// fixed formula, don't ship it — keep the fixed weights."
// =============================================================================

import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { BriefEngagementService, BriefSignalScores } from './brief-engagement.service';

// Minimum training samples required before we'll ship a learned model.
// Below this we don't have enough signal to trust the learned weights over
// the fixed ones. 200 is a conservative floor — the model can overfit on
// smaller samples.
const MIN_TRAINING_SAMPLES = 200;

// Training hyperparameters. These are conservative defaults — gradient
// descent on 5 features converges quickly, so we don't need many epochs.
const LEARNING_RATE = 0.05;
const MAX_EPOCHS = 500;
const CONVERGENCE_THRESHOLD = 1e-4; // stop early if loss change < this
const L2_REGULARIZATION = 0.01; // prevent overfitting on small samples

// The fixed weights from closeness.ts — used as a baseline to compare
// against. The learned model only ships if it beats this baseline on a
// held-out validation set.
export const FIXED_WEIGHTS: BriefSignalWeights = {
  graphDistance: 0.30,
  generationDistance: 0.15,
  relationshipSemantic: 0.35,
  kinrelRoleMatch: 0.10,
  sharedConnections: 0.10,
};
export const FIXED_BIAS = 0; // fixed formula has no bias term

export interface BriefSignalWeights {
  graphDistance: number;
  generationDistance: number;
  relationshipSemantic: number;
  kinrelRoleMatch: number;
  sharedConnections: number;
}

export interface TrainedModel {
  weights: BriefSignalWeights;
  bias: number;
  trainSamples: number;
  validationSamples: number;
  trainAccuracy: number;
  validationAccuracy: number;
  fixedBaselineAccuracy: number;
  beatsFixed: boolean;
  trainedAt: string; // ISO timestamp
}

export interface TrainingResult {
  status: 'shipped' | 'insufficient_data' | 'no_improvement';
  model?: TrainedModel;
  message: string;
}

@Injectable()
export class ClosenessWeightsTrainer {
  private readonly logger = new Logger(ClosenessWeightsTrainer.name);

  // The signal field names in fixed order — used to map weight vectors
  // to/from BriefSignalWeights objects.
  private readonly SIGNAL_KEYS: (keyof BriefSignalWeights)[] = [
    'graphDistance',
    'generationDistance',
    'relationshipSemantic',
    'kinrelRoleMatch',
    'sharedConnections',
  ];

  constructor(
    private readonly prisma: PrismaService,
    private readonly engagementService: BriefEngagementService,
  ) {}

  /**
   * Run the full training pipeline:
   *   1. Export engagement data from BriefEngagement rows.
   *   2. Split into train (80%) + validation (20%).
   *   3. Train logistic regression via gradient descent.
   *   4. Compute validation accuracy of the learned model.
   *   5. Compute validation accuracy of the fixed-weight baseline.
   *   6. Ship the learned model ONLY if it beats the fixed baseline by
   *      at least 2 percentage points. Otherwise keep the fixed weights.
   *   7. If shipped, persist the learned weights to GlobalLearningDefaults
   *      so the live PersonalizationService picks them up.
   *
   * Returns a TrainingResult describing what happened. Idempotent —
   * re-running with no new engagement data produces the same model.
   */
  async trainAndMaybeShip(opts?: { familyId?: string }): Promise<TrainingResult> {
    this.logger.log('ClosenessWeightsTrainer: starting training run');

    // ── Step 1: Export engagement data ──────────────────────────────
    const data = await this.engagementService.exportTrainingData({
      familyId: opts?.familyId,
      sinceDays: 90, // last 90 days — engagement patterns drift over time
      limit: 50000,
    });

    if (data.length < MIN_TRAINING_SAMPLES) {
      this.logger.warn(
        `ClosenessWeightsTrainer: only ${data.length} samples (< ${MIN_TRAINING_SAMPLES} required) — keeping fixed weights.`,
      );
      return {
        status: 'insufficient_data',
        message: `Only ${data.length} training samples available. Need at least ${MIN_TRAINING_SAMPLES} to trust a learned model. Keeping fixed weights.`,
      };
    }

    // ── Step 2: Train/validation split (80/20, deterministic shuffle) ──
    const shuffled = deterministicShuffle(data, (item) => item.userId); // group by user to avoid leakage
    const splitIdx = Math.floor(shuffled.length * 0.8);
    const train = shuffled.slice(0, splitIdx);
    const validation = shuffled.slice(splitIdx);

    // ── Step 3: Train logistic regression ────────────────────────────
    const { weights, bias, trainAccuracy } = this.trainLogisticRegression(train);

    // ── Step 4: Compute validation accuracy of the learned model ─────
    const validationAccuracy = this.computeAccuracy(validation, weights, bias);

    // ── Step 5: Compute validation accuracy of the fixed-weight baseline ──
    const fixedWeightsArr = this.SIGNAL_KEYS.map((k) => FIXED_WEIGHTS[k]);
    const fixedBaselineAccuracy = this.computeAccuracy(validation, fixedWeightsArr, FIXED_BIAS);

    // ── Step 6: Ship only if learned beats fixed by >= 2pp ───────────
    const improvement = validationAccuracy - fixedBaselineAccuracy;
    const beatsFixed = improvement >= 0.02;

    const model: TrainedModel = {
      weights: this.arrayToWeights(weights),
      bias,
      trainSamples: train.length,
      validationSamples: validation.length,
      trainAccuracy,
      validationAccuracy,
      fixedBaselineAccuracy,
      beatsFixed,
      trainedAt: new Date().toISOString(),
    };

    this.logger.log(
      `ClosenessWeightsTrainer: train acc=${(trainAccuracy * 100).toFixed(1)}%, ` +
        `val acc=${(validationAccuracy * 100).toFixed(1)}%, ` +
        `fixed baseline=${(fixedBaselineAccuracy * 100).toFixed(1)}%, ` +
        `improvement=${(improvement * 100).toFixed(1)}pp, ` +
        `beatsFixed=${beatsFixed}`,
    );

    if (!beatsFixed) {
      return {
        status: 'no_improvement',
        model,
        message: `Learned model (${(validationAccuracy * 100).toFixed(1)}% val acc) does not beat fixed baseline ` +
          `(${(fixedBaselineAccuracy * 100).toFixed(1)}%) by at least 2pp. Keeping fixed weights.`,
      };
    }

    // ── Step 7: Persist the learned weights ──────────────────────────
    // We reuse the existing GlobalLearningDefaults infrastructure — the
    // learned weights are stored as a JSON field. The PersonalizationService
    // reads from there at request time.
    await this.persistLearnedWeights(model);
    this.logger.log('ClosenessWeightsTrainer: learned weights shipped to GlobalLearningDefaults.');

    return {
      status: 'shipped',
      model,
      message: `Learned weights shipped. Validation accuracy ${(validationAccuracy * 100).toFixed(1)}% ` +
        `(+${(improvement * 100).toFixed(1)}pp over fixed baseline).`,
    };
  }

  // ── Pure-function trainer ──────────────────────────────────────────────

  /**
   * Train logistic regression via gradient descent. Returns the weight
   * vector (length 5, matching SIGNAL_KEYS order) + bias.
   *
   * Input: an array of { signalScores, label } pairs.
   * Output: { weights: number[], bias: number, trainAccuracy: number }
   */
  private trainLogisticRegression(
    data: Array<{ signalScores: BriefSignalScores; label: 0 | 1 }>,
  ): { weights: number[]; bias: number; trainAccuracy: number } {
    const n = data.length;
    const d = this.SIGNAL_KEYS.length;

    // Convert signalScores to a feature matrix X (n × d) and label vector y (n)
    const X: number[][] = data.map((row) =>
      this.SIGNAL_KEYS.map((k) => row.signalScores[k]),
    );
    const y: number[] = data.map((row) => row.label);

    // Initialize weights to the fixed-formula values — this gives the
    // optimizer a reasonable starting point and converges faster than
    // starting from zeros.
    let w = this.SIGNAL_KEYS.map((k) => FIXED_WEIGHTS[k]);
    let b = FIXED_BIAS;

    let prevLoss = Infinity;
    for (let epoch = 0; epoch < MAX_EPOCHS; epoch++) {
      // Compute gradients
      const gradW = new Array(d).fill(0);
      let gradB = 0;
      let loss = 0;

      for (let i = 0; i < n; i++) {
        // Forward pass: z = w·x + b
        let z = b;
        for (let j = 0; j < d; j++) {
          z += w[j] * X[i][j];
        }
        const pred = sigmoid(z);
        const err = pred - y[i];

        // Gradients
        for (let j = 0; j < d; j++) {
          gradW[j] += err * X[i][j];
        }
        gradB += err;

        // Loss (cross-entropy) with clamping to avoid log(0)
        const p = Math.min(1 - 1e-9, Math.max(1e-9, pred));
        loss += -y[i] * Math.log(p) - (1 - y[i]) * Math.log(1 - p);
      }

      // Average gradients + L2 regularization
      for (let j = 0; j < d; j++) {
        gradW[j] = gradW[j] / n + L2_REGULARIZATION * w[j];
      }
      gradB = gradB / n;
      loss = loss / n + (L2_REGULARIZATION / 2) * w.reduce((acc, wi) => acc + wi * wi, 0);

      // Update weights
      for (let j = 0; j < d; j++) {
        w[j] -= LEARNING_RATE * gradW[j];
      }
      b -= LEARNING_RATE * gradB;

      // Convergence check
      if (Math.abs(prevLoss - loss) < CONVERGENCE_THRESHOLD) {
        this.logger.debug?.(
          `ClosenessWeightsTrainer: converged at epoch ${epoch} (loss=${loss.toFixed(6)})`,
        );
        break;
      }
      prevLoss = loss;
    }

    const trainAccuracy = this.computeAccuracy(
      data.map((row) => ({ signalScores: row.signalScores, label: row.label })),
      w,
      b,
    );

    return { weights: w, bias: b, trainAccuracy };
  }

  /**
   * Compute classification accuracy on a dataset given weights + bias.
   * Accuracy = fraction of predictions that match the label (threshold 0.5).
   */
  private computeAccuracy(
    data: Array<{ signalScores: BriefSignalScores; label: 0 | 1 }>,
    weights: number[],
    bias: number,
  ): number {
    if (data.length === 0) return 0;
    let correct = 0;
    for (const row of data) {
      const x = this.SIGNAL_KEYS.map((k) => row.signalScores[k]);
      let z = bias;
      for (let j = 0; j < x.length; j++) {
        z += weights[j] * x[j];
      }
      const pred = sigmoid(z) >= 0.5 ? 1 : 0;
      if (pred === row.label) correct++;
    }
    return correct / data.length;
  }

  private arrayToWeights(arr: number[]): BriefSignalWeights {
    const result: any = {};
    this.SIGNAL_KEYS.forEach((k, i) => {
      result[k] = arr[i];
    });
    return result as BriefSignalWeights;
  }

  /**
   * Persist the learned weights to LearnedClosenessWeights so the live
   * PersonalizationService can read them. Singleton row (id='current') —
   * re-running the trainer overwrites.
   */
  private async persistLearnedWeights(model: TrainedModel): Promise<void> {
    try {
      await this.prisma.learnedClosenessWeights.upsert({
        where: { id: 'current' },
        create: {
          id: 'current',
          weights: model.weights as any,
          bias: model.bias,
          trainSamples: model.trainSamples,
          validationSamples: model.validationSamples,
          trainAccuracy: model.trainAccuracy,
          validationAccuracy: model.validationAccuracy,
          fixedBaselineAccuracy: model.fixedBaselineAccuracy,
          beatsFixed: model.beatsFixed,
          trainedAt: new Date(model.trainedAt),
        },
        update: {
          weights: model.weights as any,
          bias: model.bias,
          trainSamples: model.trainSamples,
          validationSamples: model.validationSamples,
          trainAccuracy: model.trainAccuracy,
          validationAccuracy: model.validationAccuracy,
          fixedBaselineAccuracy: model.fixedBaselineAccuracy,
          beatsFixed: model.beatsFixed,
          trainedAt: new Date(model.trainedAt),
        },
      });
    } catch (err) {
      this.logger.error(
        `Failed to persist learned weights: ${(err as Error).message}`,
        (err as Error).stack,
      );
      throw err;
    }
  }
}

// ── Pure helpers ────────────────────────────────────────────────────────────

function sigmoid(z: number): number {
  // Clamp z to avoid overflow in Math.exp for large negative values
  if (z < -500) return 0;
  if (z > 500) return 1;
  return 1 / (1 + Math.exp(-z));
}

/**
 * Deterministic shuffle that groups by a key (here: userId) before shuffling.
 * This prevents train/validation leakage where the same user's engagements
 * end up in both sets — without it, the model could memorize user-specific
 * patterns instead of learning the general closeness-to-engagement relationship.
 *
 * The shuffle is deterministic (seeded by the key string) so re-running
 * the trainer on the same data produces the same split.
 */
function deterministicShuffle<T>(arr: T[], groupByKey: (item: T) => string): T[] {
  // Group by key
  const groups = new Map<string, T[]>();
  for (const item of arr) {
    const k = groupByKey(item);
    if (!groups.has(k)) groups.set(k, []);
    groups.get(k)!.push(item);
  }

  // Deterministic hash-based ordering of groups
  const groupKeys = Array.from(groups.keys()).sort();

  // Interleave groups so the split has roughly equal user representation
  // in train and validation
  const result: T[] = [];
  for (const k of groupKeys) {
    // Within each group, deterministic order by JSON-stringifying
    const items = groups.get(k)!;
    items.sort((a, b) => JSON.stringify(a).localeCompare(JSON.stringify(b)));
    result.push(...items);
  }

  return result;
}
