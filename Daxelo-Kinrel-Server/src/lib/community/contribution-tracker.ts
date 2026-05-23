// DAXELO KINREL — Pack 09: Contribution Tracker & Gamification
// Points, levels, badges, and family milestones

import { db } from '@/lib/db';

// ── Point Values ─────────────────────────────────────────────────────

export const POINT_VALUES: Record<string, number> = {
  personAdded: 10,
  relationshipAdded: 15,
  photoAdded: 5,
  eventCreated: 10,
  storyShared: 15,
  commentWritten: 3,
  invitationSent: 5,
  invitationAccepted: 15,
  profileCompleted: 20,
  personEdited: 2,
  memorialContributed: 10,
  dailyLogin: 1,
};

// ── Level Thresholds ─────────────────────────────────────────────────

export interface LevelDef {
  level: number;
  title: string;
  titleHi: string;
  minPoints: number;
}

export const LEVEL_THRESHOLDS: LevelDef[] = [
  { level: 1,  title: 'Newcomer',        titleHi: 'नवागंतुक',      minPoints: 0 },
  { level: 2,  title: 'Family Seed',     titleHi: 'पारिवारिक बीज',  minPoints: 50 },
  { level: 3,  title: 'Branch Builder',  titleHi: 'शाखा निर्माता',  minPoints: 150 },
  { level: 4,  title: 'Tree Tender',     titleHi: 'वृक्ष पालक',      minPoints: 350 },
  { level: 5,  title: 'Root Keeper',     titleHi: 'जड़ रक्षक',       minPoints: 700 },
  { level: 6,  title: 'Heritage Scribe', titleHi: 'विरासत लेखक',    minPoints: 1500 },
  { level: 7,  title: 'Lineage Sage',    titleHi: 'वंश मनीषी',     minPoints: 3500 },
  { level: 8,  title: 'Kula Pandit',     titleHi: 'कुल पंडित',      minPoints: 7000 },
  { level: 9,  title: 'Vansh Guru',      titleHi: 'वंश गुरु',       minPoints: 12000 },
  { level: 10, title: 'Kula Guru',        titleHi: 'कुल गुरु',       minPoints: 20000 },
];

// ── Badge Definitions ────────────────────────────────────────────────

export interface BadgeDef {
  slug: string;
  name: string;
  nameHi: string;
  description: string;
  icon: string;
  category: 'tree_builder' | 'connector' | 'historian' | 'social' | 'special';
  tier: 'bronze' | 'silver' | 'gold' | 'platinum';
  threshold: number;
  checkField: string;
  isSecret: boolean;
}

export const BADGE_DEFINITIONS: BadgeDef[] = [
  // Tree Builder badges
  { slug: 'first_person', name: 'First Person', nameHi: 'प्रथम व्यक्ति', description: 'Added your first family member', icon: '🌱', category: 'tree_builder', tier: 'bronze', threshold: 1, checkField: 'personsAdded', isSecret: false },
  { slug: 'sapling', name: 'Sapling', nameHi: 'अंकुर', description: 'Added 10 family members', icon: '🌿', category: 'tree_builder', tier: 'bronze', threshold: 10, checkField: 'personsAdded', isSecret: false },
  { slug: 'growing_tree', name: 'Growing Tree', nameHi: 'बढ़ता वृक्ष', description: 'Added 25 family members', icon: '🌳', category: 'tree_builder', tier: 'silver', threshold: 25, checkField: 'personsAdded', isSecret: false },
  { slug: 'centurion', name: 'Centurion', nameHi: 'शताधिक', description: 'Added 100 family members', icon: '🏔️', category: 'tree_builder', tier: 'gold', threshold: 100, checkField: 'personsAdded', isSecret: false },
  { slug: 'family_forest', name: 'Family Forest', nameHi: 'पारिवारिक वन', description: 'Added 250 family members', icon: '🌲', category: 'tree_builder', tier: 'platinum', threshold: 250, checkField: 'personsAdded', isSecret: false },
  { slug: 'relationship_starter', name: 'Bond Maker', nameHi: 'सम्बन्ध निर्माता', description: 'Added 5 relationships', icon: '🔗', category: 'tree_builder', tier: 'bronze', threshold: 5, checkField: 'relationshipsAdded', isSecret: false },
  { slug: 'relationship_master', name: 'Relationship Master', nameHi: 'सम्बन्ध विशेषज्ञ', description: 'Added 50 relationships', icon: '🕸️', category: 'tree_builder', tier: 'gold', threshold: 50, checkField: 'relationshipsAdded', isSecret: false },

  // Connector badges
  { slug: 'inviter', name: 'Inviter', nameHi: 'आमंत्रक', description: 'Sent 5 invitations', icon: '✉️', category: 'connector', tier: 'bronze', threshold: 5, checkField: 'invitationsSent', isSecret: false },
  { slug: 'magnet', name: 'Family Magnet', nameHi: 'पारिवारिक चुम्बक', description: 'Got 10 invitations accepted', icon: '🧲', category: 'connector', tier: 'silver', threshold: 10, checkField: 'invitationAccepted', isSecret: false },
  { slug: 'bridge_builder', name: 'Bridge Builder', nameHi: 'सेतु निर्माता', description: 'Connected 3 families', icon: '🌉', category: 'connector', tier: 'gold', threshold: 3, checkField: 'invitationAccepted', isSecret: true },

  // Historian badges
  { slug: 'photographer', name: 'Family Photographer', nameHi: 'पारिवारिक फोटोग्राफर', description: 'Added 20 photos', icon: '📸', category: 'historian', tier: 'bronze', threshold: 20, checkField: 'photosAdded', isSecret: false },
  { slug: 'storyteller', name: 'Storyteller', nameHi: 'कथाकार', description: 'Shared 5 family stories', icon: '📖', category: 'historian', tier: 'silver', threshold: 5, checkField: 'storiesShared', isSecret: false },
  { slug: 'memorial_keeper', name: 'Memorial Keeper', nameHi: 'स्मृति रक्षक', description: 'Contributed to 3 memorials', icon: '🕯️', category: 'historian', tier: 'gold', threshold: 3, checkField: 'memorialContributed', isSecret: false },
  { slug: 'archivist', name: 'Archivist', nameHi: 'अभिलेखागार अध्यक्ष', description: 'Edited 50 person profiles', icon: '📝', category: 'historian', tier: 'silver', threshold: 50, checkField: 'personsEdited', isSecret: false },

  // Social badges
  { slug: 'first_comment', name: 'Conversationalist', nameHi: 'वार्ताकार', description: 'Wrote your first comment', icon: '💬', category: 'social', tier: 'bronze', threshold: 1, checkField: 'commentsWritten', isSecret: false },
  { slug: 'chatterbox', name: 'Chatterbox', nameHi: 'बातूनी', description: 'Wrote 50 comments', icon: '🗣️', category: 'social', tier: 'silver', threshold: 50, checkField: 'commentsWritten', isSecret: false },
  { slug: 'event_planner', name: 'Event Planner', nameHi: 'कार्यक्रम आयोजक', description: 'Created 5 events', icon: '🎪', category: 'social', tier: 'bronze', threshold: 5, checkField: 'eventsCreated', isSecret: false },
  { slug: 'celebration_expert', name: 'Celebration Expert', nameHi: 'उत्सव विशेषज्ञ', description: 'Created 20 events', icon: '🎊', category: 'social', tier: 'gold', threshold: 20, checkField: 'eventsCreated', isSecret: false },

  // Special badges
  { slug: 'profile_complete', name: 'Profile Complete', nameHi: 'प्रोफ़ाइल पूर्ण', description: 'Completed your profile', icon: '✅', category: 'special', tier: 'bronze', threshold: 1, checkField: 'profileCompleted', isSecret: false },
  { slug: 'daily_devotee', name: 'Daily Devotee', nameHi: 'दैनिक भक्त', description: 'Logged in 30 days in a row', icon: '🗓️', category: 'special', tier: 'silver', threshold: 30, checkField: 'dailyLogin', isSecret: false },
  { slug: 'pioneer', name: 'Pioneer', nameHi: 'अग्रगामी', description: 'One of the first 100 users', icon: '🚀', category: 'special', tier: 'platinum', threshold: 1, checkField: 'special', isSecret: true },
];

// ── Family Milestones ────────────────────────────────────────────────

export const FAMILY_MILESTONES = [
  { milestone: '10_members',  labelEn: '10 Members',     labelHi: '10 सदस्य',      memberThreshold: 10 },
  { milestone: '25_members',  labelEn: '25 Members',     labelHi: '25 सदस्य',      memberThreshold: 25 },
  { milestone: '50_members',  labelEn: '50 Members',     labelHi: '50 सदस्य',      memberThreshold: 50 },
  { milestone: '100_members', labelEn: '100 Members',    labelHi: '100 सदस्य',     memberThreshold: 100 },
  { milestone: '250_members', labelEn: '250 Members',    labelHi: '250 सदस्य',     memberThreshold: 250 },
  { milestone: '500_members', labelEn: '500 Members',    labelHi: '500 सदस्य',     memberThreshold: 500 },
  { milestone: '5_generations', labelEn: '5 Generations', labelHi: '5 पीढ़ियाँ', generationThreshold: 5 },
];

// ── Core Functions ───────────────────────────────────────────────────

/**
 * Record a contribution and check for badge/milestone unlocks
 */
export async function recordContribution(
  userId: string,
  familyId: string,
  action: string
): Promise<{
  contribution: Awaited<ReturnType<typeof db.userContribution.upsert>>;
  newBadges: Awaited<ReturnType<typeof db.badge.findMany>>;
  newMilestones: Awaited<ReturnType<typeof db.familyMilestone.findMany>>;
}> {
  const points = POINT_VALUES[action] ?? 0;

  // Map action to the contribution field
  const fieldMap: Record<string, string> = {
    personAdded: 'personsAdded',
    relationshipAdded: 'relationshipsAdded',
    photoAdded: 'photosAdded',
    eventCreated: 'eventsCreated',
    storyShared: 'storiesShared',
    commentWritten: 'commentsWritten',
    invitationSent: 'invitationsSent',
    invitationAccepted: 'invitationAccepted',
    profileCompleted: 'profileCompleted',
    personEdited: 'personsEdited',
    memorialContributed: 'memorialContributed',
    dailyLogin: 'dailyLogin',
  };

  const field = fieldMap[action];
  if (!field) {
    throw new Error(`Unknown contribution action: ${action}`);
  }

  // Upsert the contribution record
  const contribution = await db.userContribution.upsert({
    where: { userId_familyId: { userId, familyId } },
    create: {
      userId,
      familyId,
      [field]: 1,
      totalPoints: points,
    },
    update: {
      [field]: { increment: 1 },
      totalPoints: { increment: points },
    },
  });

  // Update level based on total points
  const newLevel = getLevel(contribution.totalPoints);
  await db.userContribution.update({
    where: { id: contribution.id },
    data: { level: newLevel.level },
  });

  // Check for new badges
  const newBadges = await checkBadges(userId, familyId);

  // Check for family milestones
  const newMilestones = await checkFamilyMilestones(familyId);

  return { contribution, newBadges, newMilestones };
}

/**
 * Check and award badges for a user
 */
export async function checkBadges(
  userId: string,
  familyId: string
): Promise<Awaited<ReturnType<typeof db.badge.findMany>>> {
  const contribution = await db.userContribution.findUnique({
    where: { userId_familyId: { userId, familyId } },
  });

  if (!contribution) return [];

  const earnedBadgeIds = await db.userBadge.findMany({
    where: { userId, familyId },
    select: { badgeId: true },
  });
  const earnedSet = new Set(earnedBadgeIds.map((b) => b.badgeId));

  const newBadges: Awaited<ReturnType<typeof db.badge.findMany>> = [];

  for (const badgeDef of BADGE_DEFINITIONS) {
    if (earnedSet.has(badgeDef.slug)) continue;

    // Check if the user meets the threshold
    const fieldValue = getFieldFromContribution(contribution, badgeDef.checkField);
    if (fieldValue >= badgeDef.threshold) {
      // Find or create the badge
      let badge = await db.badge.findUnique({
        where: { slug: badgeDef.slug },
      });

      if (!badge) {
        badge = await db.badge.create({
          data: {
            slug: badgeDef.slug,
            name: badgeDef.name,
            nameHi: badgeDef.nameHi,
            description: badgeDef.description,
            icon: badgeDef.icon,
            category: badgeDef.category,
            tier: badgeDef.tier,
            threshold: badgeDef.threshold,
            isSecret: badgeDef.isSecret,
          },
        });
      }

      // Award the badge
      await db.userBadge.create({
        data: {
          userId,
          badgeId: badge.id,
          familyId,
        },
      });

      newBadges.push(badge);
    }
  }

  return newBadges;
}

/**
 * Check and record family milestones
 */
export async function checkFamilyMilestones(
  familyId: string
): Promise<Awaited<ReturnType<typeof db.familyMilestone.findMany>>> {
  const memberCount = await db.familyMember.count({
    where: { familyId },
  });

  const existingMilestones = await db.familyMilestone.findMany({
    where: { familyId },
  });
  const existingSet = new Set(existingMilestones.map((m) => m.milestone));

  const newMilestones: Awaited<ReturnType<typeof db.familyMilestone.findMany>> = [];

  for (const ms of FAMILY_MILESTONES) {
    if (existingSet.has(ms.milestone)) continue;

    if (ms.memberThreshold && memberCount >= ms.memberThreshold) {
      const milestone = await db.familyMilestone.create({
        data: {
          familyId,
          milestone: ms.milestone,
        },
      });
      newMilestones.push(milestone);
    }
    // 5_generations would need a separate graph traversal check
    // For now, we skip generation threshold checks
  }

  return newMilestones;
}

/**
 * Get the level for a given total points
 */
export function getLevel(totalPoints: number): {
  level: number;
  title: string;
  titleHi: string;
  nextLevelPoints: number;
  progress: number;
} {
  let current = LEVEL_THRESHOLDS[0];

  for (const lt of LEVEL_THRESHOLDS) {
    if (totalPoints >= lt.minPoints) {
      current = lt;
    } else {
      break;
    }
  }

  const nextIndex = LEVEL_THRESHOLDS.findIndex((lt) => lt.level === current.level) + 1;
  const nextLevel = nextIndex < LEVEL_THRESHOLDS.length ? LEVEL_THRESHOLDS[nextIndex] : null;
  const nextLevelPoints = nextLevel?.minPoints ?? current.minPoints;

  // Calculate progress within current level
  const prevMin = current.minPoints;
  const nextMin = nextLevel?.minPoints ?? current.minPoints + 1;
  const progress = nextLevel
    ? ((totalPoints - prevMin) / (nextMin - prevMin)) * 100
    : 100;

  return {
    level: current.level,
    title: current.title,
    titleHi: current.titleHi,
    nextLevelPoints,
    progress: Math.min(100, Math.max(0, progress)),
  };
}

// ── Helpers ──────────────────────────────────────────────────────────

function getFieldFromContribution(
  contribution: Record<string, unknown>,
  field: string
): number {
  return (contribution[field] as number) ?? 0;
}
