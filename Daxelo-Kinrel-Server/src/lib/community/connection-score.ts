// DAXELO KINREL — Pack 09: Family Connection Scoring
// Scores connections between families based on gotra, village, surname, shared communities

import { db } from '@/lib/db';

// ── Types ────────────────────────────────────────────────────────────

export type ConnectionType = 'sagotra' | 'same_village' | 'inter_marriage' | 'manual';

export interface ConnectionSuggestion {
  familyId: string;
  familyName: string;
  score: number;
  reasons: ConnectionReason[];
  connectionType: ConnectionType;
}

export interface ConnectionReason {
  type: ConnectionType;
  detail: string;
  points: number;
}

interface FamilyAttributes {
  id: string;
  name: string;
  gotra: string | null;
  originVillage: string | null;
  surname: string | null;
}

// ── Constants ────────────────────────────────────────────────────────

export const CONNECTION_TYPES: Record<ConnectionType, { label: string; labelHi: string; description: string }> = {
  sagotra: {
    label: 'Same Gotra',
    labelHi: 'समगोत्र',
    description: 'Families sharing the same gotra (ancestral lineage)',
  },
  same_village: {
    label: 'Same Village',
    labelHi: 'सम ग्राम',
    description: 'Families originating from the same village',
  },
  inter_marriage: {
    label: 'Inter-Marriage',
    labelHi: 'विवाह सम्बन्ध',
    description: 'Families connected through marriage alliances',
  },
  manual: {
    label: 'Manual',
    labelHi: 'मैनुअल',
    description: 'Manually established connection',
  },
};

const GOTRA_MATCH_POINTS = 40;
const VILLAGE_MATCH_POINTS = 25;
const SURNAME_MATCH_POINTS = 20;
const SHARED_COMMUNITY_POINTS = 15;

// ── Core Functions ───────────────────────────────────────────────────

/**
 * Compute a connection score between two families (0-100)
 * Based on gotra match, same village, same surname, and shared communities
 */
export async function computeConnectionScore(
  fromFamilyId: string,
  toFamilyId: string
): Promise<number> {
  if (fromFamilyId === toFamilyId) return 100;

  const [fromFamily, toFamily] = await Promise.all([
    db.family.findUnique({ where: { id: fromFamilyId } }),
    db.family.findUnique({ where: { id: toFamilyId } }),
  ]);

  if (!fromFamily || !toFamily) return 0;

  let score = 0;

  // Gotra match (+40)
  if (fromFamily.gotra && toFamily.gotra && fromFamily.gotra === toFamily.gotra) {
    score += GOTRA_MATCH_POINTS;
  }

  // Same village (+25)
  if (
    fromFamily.originVillage &&
    toFamily.originVillage &&
    fromFamily.originVillage.toLowerCase() === toFamily.originVillage.toLowerCase()
  ) {
    score += VILLAGE_MATCH_POINTS;
  }

  // Same surname (+20) — extracted from family name's last word
  const fromSurname = extractSurname(fromFamily.name);
  const toSurname = extractSurname(toFamily.name);
  if (fromSurname && toSurname && fromSurname.toLowerCase() === toSurname.toLowerCase()) {
    score += SURNAME_MATCH_POINTS;
  }

  // Shared communities (+15 max)
  const fromCommunities = await db.communityMember.findMany({
    where: { userId: { in: await getFamilyUserIds(fromFamilyId) } },
    select: { communityId: true },
    distinct: ['communityId'],
  });
  const toCommunities = await db.communityMember.findMany({
    where: { userId: { in: await getFamilyUserIds(toFamilyId) } },
    select: { communityId: true },
    distinct: ['communityId'],
  });

  const fromSet = new Set(fromCommunities.map((c) => c.communityId));
  const sharedCount = toCommunities.filter((c) => fromSet.has(c.communityId)).length;
  if (sharedCount > 0) {
    score += Math.min(sharedCount * 5, SHARED_COMMUNITY_POINTS);
  }

  return Math.min(score, 100);
}

/**
 * Suggest connections for a family based on matching attributes
 */
export async function suggestConnections(
  familyId: string
): Promise<ConnectionSuggestion[]> {
  const family = await db.family.findUnique({ where: { id: familyId } });
  if (!family) return [];

  const suggestions: ConnectionSuggestion[] = [];
  const existingConnections = await db.familyConnection.findMany({
    where: {
      OR: [
        { fromFamilyId: familyId },
        { toFamilyId: familyId },
      ],
    },
    select: { fromFamilyId: true, toFamilyId: true },
  });

  const connectedFamilyIds = new Set<string>();
  for (const conn of existingConnections) {
    connectedFamilyIds.add(conn.fromFamilyId);
    connectedFamilyIds.add(conn.toFamilyId);
  }
  connectedFamilyIds.add(familyId); // Exclude self

  // Find families with same gotra
  if (family.gotra) {
    const gotraMatches = await db.family.findMany({
      where: {
        gotra: family.gotra,
        id: { notIn: [...connectedFamilyIds] },
      },
      take: 20,
    });

    for (const match of gotraMatches) {
      suggestions.push({
        familyId: match.id,
        familyName: match.name,
        score: GOTRA_MATCH_POINTS,
        reasons: [{ type: 'sagotra', detail: `Same gotra: ${family.gotra}`, points: GOTRA_MATCH_POINTS }],
        connectionType: 'sagotra',
      });
    }
  }

  // Find families from same village
  if (family.originVillage) {
    const villageMatches = await db.family.findMany({
      where: {
        originVillage: { equals: family.originVillage },
        id: { notIn: [...connectedFamilyIds] },
      },
      take: 20,
    });

    for (const match of villageMatches) {
      const existing = suggestions.find((s) => s.familyId === match.id);
      if (existing) {
        existing.score += VILLAGE_MATCH_POINTS;
        existing.reasons.push({
          type: 'same_village',
          detail: `Same village: ${family.originVillage}`,
          points: VILLAGE_MATCH_POINTS,
        });
      } else {
        suggestions.push({
          familyId: match.id,
          familyName: match.name,
          score: VILLAGE_MATCH_POINTS,
          reasons: [{ type: 'same_village', detail: `Same village: ${family.originVillage}`, points: VILLAGE_MATCH_POINTS }],
          connectionType: 'same_village',
        });
      }
    }
  }

  // Find families with same surname
  const familySurname = extractSurname(family.name);
  if (familySurname) {
    const surnameMatches = await db.family.findMany({
      where: {
        name: { contains: familySurname },
        id: { notIn: [...connectedFamilyIds] },
      },
      take: 20,
    });

    for (const match of surnameMatches) {
      const existing = suggestions.find((s) => s.familyId === match.id);
      if (existing) {
        existing.score += SURNAME_MATCH_POINTS;
        existing.reasons.push({
          type: 'sagotra',
          detail: `Same surname: ${familySurname}`,
          points: SURNAME_MATCH_POINTS,
        });
      } else {
        suggestions.push({
          familyId: match.id,
          familyName: match.name,
          score: SURNAME_MATCH_POINTS,
          reasons: [{ type: 'sagotra', detail: `Same surname: ${familySurname}`, points: SURNAME_MATCH_POINTS }],
          connectionType: 'sagotra',
        });
      }
    }
  }

  // Sort by score descending, cap at 100
  suggestions.sort((a, b) => b.score - a.score);
  for (const s of suggestions) {
    s.score = Math.min(s.score, 100);
  }

  return suggestions.slice(0, 50);
}

// ── Helpers ──────────────────────────────────────────────────────────

function extractSurname(familyName: string): string | null {
  // Indian family names often end with a surname word
  // E.g., "Sharma Family" → "Sharma"
  const parts = familyName.trim().split(/\s+/);
  if (parts.length >= 2) {
    // Remove common suffixes
    const suffixes = ['family', 'parivar', 'kutumb', 'kul'];
    const filtered = parts.filter(
      (p) => !suffixes.includes(p.toLowerCase())
    );
    if (filtered.length > 0) {
      return filtered[filtered.length - 1];
    }
  }
  return parts.length === 1 ? parts[0] : null;
}

async function getFamilyUserIds(familyId: string): Promise<string[]> {
  const members = await db.familyMember.findMany({
    where: { familyId },
    select: { userId: true },
  });
  return members.map((m) => m.userId);
}
