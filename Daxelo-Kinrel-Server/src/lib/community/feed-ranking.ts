// DAXELO KINREL — Pack 09: Feed Ranking Algorithm
// Personalized feed with time decay, engagement boost, and kinship proximity

import { db } from '@/lib/db';

// ── Types ────────────────────────────────────────────────────────────

export type FeedItemType =
  | 'birthday'
  | 'anniversary'
  | 'new_member'
  | 'new_photo'
  | 'milestone'
  | 'memorial'
  | 'community_post'
  | 'event'
  | 'relationship_discovery'
  | 'story'
  | 'person_update';

export interface FeedItem {
  id: string;
  type: FeedItemType;
  title: string;
  body: string;
  authorId: string;
  authorName: string;
  familyId?: string;
  communityId?: string;
  personId?: string;
  eventId?: string;
  mediaUrls: string[];
  createdAt: Date;
  reactionCount: number;
  commentCount: number;
  score: number;
  metadata?: Record<string, unknown>;
}

// ── Constants ────────────────────────────────────────────────────────

export const BASE_WEIGHTS: Record<FeedItemType, number> = {
  birthday: 100,
  anniversary: 80,
  new_member: 70,
  new_photo: 40,
  milestone: 90,
  memorial: 95,
  community_post: 50,
  event: 60,
  relationship_discovery: 85,
  story: 55,
  person_update: 30,
};

export const HALF_LIVES: Record<FeedItemType, number> = {
  birthday: 24,        // 24 hours — birthdays decay quickly
  anniversary: 48,     // 48 hours
  new_member: 72,      // 72 hours
  new_photo: 168,      // 7 days
  milestone: 720,      // 30 days — milestones stay relevant
  memorial: 360,       // 15 days
  community_post: 120, // 5 days
  event: 96,           // 4 days
  relationship_discovery: 240, // 10 days
  story: 168,          // 7 days
  person_update: 48,   // 2 days
};

// DEDUP_PRIORITY: when items of different types reference the same entity,
// the higher-priority type wins (lower number = higher priority)
const DEDUP_PRIORITY: Record<FeedItemType, number> = {
  memorial: 1,
  birthday: 2,
  milestone: 3,
  relationship_discovery: 4,
  anniversary: 5,
  event: 6,
  new_member: 7,
  story: 8,
  community_post: 9,
  new_photo: 10,
  person_update: 11,
};

// ── Core Functions ───────────────────────────────────────────────────

/**
 * Get the base weight for a feed item type
 */
export function getBaseWeight(type: FeedItemType): number {
  return BASE_WEIGHTS[type] ?? 50;
}

/**
 * Calculate time decay score using exponential decay
 * Score = baseWeight * e^(-ln(2) * hoursElapsed / halfLife)
 * Returns 0-1 multiplier that gets applied to the base weight
 */
export function timeDecayScore(createdAt: Date, type: FeedItemType): number {
  const halfLife = HALF_LIVES[type] ?? 120;
  const hoursElapsed =
    (Date.now() - createdAt.getTime()) / (1000 * 60 * 60);

  if (hoursElapsed < 0) return 1;

  const decayMultiplier = Math.exp(
    (-Math.LN2 * hoursElapsed) / halfLife
  );

  return Math.max(0, Math.min(1, decayMultiplier));
}

/**
 * Calculate engagement boost based on reactions and comments
 * Uses logarithmic scaling to prevent viral items from dominating
 */
export function engagementBoost(reactions: number, comments: number): number {
  const reactionBoost = Math.log2(reactions + 1) * 3;
  const commentBoost = Math.log2(comments + 1) * 5;
  return reactionBoost + commentBoost;
}

/**
 * Calculate kinship proximity bonus (0-15 points)
 * Based on relationship distance in the family tree
 */
export async function getKinshipProximity(
  viewerId: string,
  authorId: string,
  familyId?: string
): Promise<number> {
  if (viewerId === authorId) return 15; // Self

  if (!familyId) return 0;

  // Check if both are in the same family
  const [viewerMembership, authorMembership] = await Promise.all([
    db.familyMember.findFirst({
      where: { familyId, userId: viewerId },
    }),
    db.familyMember.findFirst({
      where: { familyId, userId: authorId },
    }),
  ]);

  if (!viewerMembership || !authorMembership) {
    // Check shared community memberships
    const sharedCommunities = await db.communityMember.findMany({
      where: {
        userId: viewerId,
        community: {
          members: {
            some: { userId: authorId },
          },
        },
      },
    });
    return Math.min(sharedCommunities.length * 2, 6);
  }

  // Both in same family — check roles for proximity
  if (viewerMembership.role === 'admin' || authorMembership.role === 'admin') {
    return 12;
  }

  // Same family members get a base proximity
  return 10;
}

/**
 * Rank a single feed item for a specific viewer
 * Score = baseWeight * timeDecay + engagementBoost + kinshipProximity
 */
export function rankFeedItem(
  item: Omit<FeedItem, 'score'>,
  viewerId: string
): number {
  const base = getBaseWeight(item.type);
  const decay = timeDecayScore(item.createdAt, item.type);
  const engagement = engagementBoost(item.reactionCount, item.commentCount);

  // Kinship proximity is async, so we compute a placeholder
  // Callers should use rankFeedItemAsync for full scoring
  return base * decay + engagement;
}

/**
 * Full async ranking with kinship proximity
 */
export async function rankFeedItemAsync(
  item: Omit<FeedItem, 'score'>,
  viewerId: string
): Promise<number> {
  const base = getBaseWeight(item.type);
  const decay = timeDecayScore(item.createdAt, item.type);
  const engagement = engagementBoost(item.reactionCount, item.commentCount);
  const proximity = await getKinshipProximity(
    viewerId,
    item.authorId,
    item.familyId
  );

  return base * decay + engagement + proximity;
}

/**
 * Deduplicate feed items by entity reference.
 * - Birthday wins over person_update for the same person
 * - Photos from the same batch are collapsed
 * - Memorial wins over everything for the same person
 */
export function deduplicateFeed(items: FeedItem[]): FeedItem[] {
  const entityMap = new Map<string, FeedItem[]>();

  for (const item of items) {
    // Build dedup keys based on type and entity references
    const keys: string[] = [];

    if (item.personId) {
      keys.push(`person:${item.personId}`);
    }
    if (item.eventId) {
      keys.push(`event:${item.eventId}`);
    }
    if (item.communityId && item.type === 'community_post') {
      // Don't dedup community posts by community alone
    }
    if (item.familyId && (item.type === 'new_member' || item.type === 'milestone')) {
      keys.push(`family:${item.familyId}:${item.type}`);
    }

    // For photo dedup — group photos from same author within 1 hour
    if (item.type === 'new_photo' && item.authorId) {
      const hourBucket = Math.floor(item.createdAt.getTime() / (1000 * 60 * 60));
      keys.push(`photo:${item.authorId}:${hourBucket}`);
    }

    if (keys.length === 0) {
      keys.push(`unique:${item.id}`);
    }

    for (const key of keys) {
      const existing = entityMap.get(key) ?? [];
      existing.push(item);
      entityMap.set(key, existing);
    }
  }

  // For each dedup group, keep the highest-priority item
  const seen = new Set<string>();
  const result: FeedItem[] = [];

  for (const [, group] of entityMap) {
    if (group.length <= 1) {
      const item = group[0];
      if (!seen.has(item.id)) {
        seen.add(item.id);
        result.push(item);
      }
      continue;
    }

    // Sort by dedup priority (lower number = higher priority)
    group.sort((a, b) => {
      const prioA = DEDUP_PRIORITY[a.type] ?? 10;
      const prioB = DEDUP_PRIORITY[b.type] ?? 10;
      if (prioA !== prioB) return prioA - prioB;
      return b.score - a.score;
    });

    const winner = group[0];
    if (!seen.has(winner.id)) {
      seen.add(winner.id);

      // If collapsing photos, annotate the winner
      if (winner.type === 'new_photo' && group.length > 1) {
        winner.metadata = {
          ...winner.metadata,
          collapsedCount: group.length,
          collapsedIds: group.slice(1).map((g) => g.id),
        };
      }

      result.push(winner);
    }
  }

  // Sort by score descending
  result.sort((a, b) => b.score - a.score);

  return result;
}
