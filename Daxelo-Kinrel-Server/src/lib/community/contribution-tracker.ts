/**
 * Contribution Tracker — Stub implementation
 *
 * Provides level calculation and contribution recording
 * for the family community features.
 */

export interface LevelInfo {
  level: number;
  title: string;
  nextLevelPoints: number;
}

const LEVEL_THRESHOLDS = [
  { level: 1, title: 'Newcomer', minPoints: 0 },
  { level: 2, title: 'Contributor', minPoints: 100 },
  { level: 3, title: 'Active Member', minPoints: 500 },
  { level: 4, title: 'Community Leader', minPoints: 1500 },
  { level: 5, title: 'Family Pillar', minPoints: 5000 },
];

/**
 * Get the level info for a given number of contribution points.
 */
export function getLevel(points: number): LevelInfo {
  let current = LEVEL_THRESHOLDS[0];
  for (const threshold of LEVEL_THRESHOLDS) {
    if (points >= threshold.minPoints) {
      current = threshold;
    } else {
      break;
    }
  }
  const nextIndex = LEVEL_THRESHOLDS.findIndex((t) => t.level === current.level) + 1;
  const nextLevelPoints = nextIndex < LEVEL_THRESHOLDS.length
    ? LEVEL_THRESHOLDS[nextIndex].minPoints
    : current.minPoints;

  return {
    level: current.level,
    title: current.title,
    nextLevelPoints,
  };
}

/**
 * Record a contribution for a user within a family.
 * Stub implementation — returns a resolved promise.
 */
export async function recordContribution(
  userId: string,
  familyId: string,
  type: string,
): Promise<{ recorded: boolean }> {
  // Stub: in production this would persist to the database
  return { recorded: true };
}
