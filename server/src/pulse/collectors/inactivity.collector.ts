// server/src/pulse/collectors/inactivity.collector.ts
//
// InactivityCollector — finds family members who haven't been active in 4+ days.
//
// Strategy:
//   1. Query all Persons in the user's family (excluding deceased, deleted, and
//      the user's own Person node).
//   2. For each Person:
//        - If linkedUserId is set → use that User.updatedAt as last-active
//        - Else → use Person.updatedAt as last-active proxy
//   3. Compute daysSinceLastActive.
//   4. Filter to daysSinceLastActive >= 4.
//   5. Priority rules:
//        - Elder (age ≥ 60) AND daysSinceLastActive >= 4 → 'need_you' at priority 95
//          (this is the "💜 Needs you today" section in the brief UX)
//        - Anyone else with daysSinceLastActive >= 7 → 'need_you' at priority 80
//        - Anyone else with daysSinceLastActive >= 4 → 'inactivity' (mapped to 'need_you'
//          since the BriefItemType union only has 'need_you' for this category) at priority 60
//   6. Title includes the person's name and days inactive.
//      Body includes the last-active day-of-week for context.
//   7. Cap at 2 items (we don't want the brief to be all about inactivity).
//
// Note: 'inactivity' was mentioned in the implementation prompt as a separate
// itemType, but we deliberately collapse it into 'need_you' here because:
//   (a) the BriefItemType union in brief-types.ts is exactly the 6 types in §7
//   (b) the UX target has only one "Needs you today" section
//   (c) the priority field already differentiates urgency

import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import {
  BriefCollector,
  BriefCollectorContext,
  BriefItemData,
  estimateAge,
  localizeAction,
} from '../brief-types';

const INACTIVITY_THRESHOLD_DAYS = 4;
const ELDER_AGE_THRESHOLD = 60;
const SEVERE_INACTIVITY_DAYS = 7;
const MAX_INACTIVITY_ITEMS = 2;

const DAY_NAMES = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];

@Injectable()
export class InactivityCollector implements BriefCollector {
  readonly name = 'inactivity';
  private readonly logger = new Logger(InactivityCollector.name);

  constructor(private readonly prisma: PrismaService) {}

  async collect(ctx: BriefCollectorContext): Promise<BriefItemData[]> {
    try {
      // 1. Load all Persons (excluding deceased, deleted, and the user's own Person)
      const persons = await this.prisma.person.findMany({
        where: {
          familyId: ctx.familyId,
          deletedAt: null,
          isDeceased: false,
          ...(ctx.userPersonId ? { id: { not: ctx.userPersonId } } : {}),
        },
        select: {
          id: true,
          name: true,
          dateOfBirth: true,
          birthYear: true,
          gender: true,
          linkedUserId: true,
          updatedAt: true,
        },
      });

      if (persons.length === 0) return [];

      // 2. For Persons with linkedUserId, fetch the User.updatedAt
      const linkedUserIds = persons
        .map((p) => p.linkedUserId)
        .filter((id): id is string => id !== null && id !== undefined);

      const userActivityMap = new Map<string, Date>();
      if (linkedUserIds.length > 0) {
        const users = await this.prisma.user.findMany({
          where: { id: { in: linkedUserIds } },
          select: { id: true, updatedAt: true },
        });
        for (const u of users) {
          userActivityMap.set(u.id, u.updatedAt);
        }
      }

      // 3. Compute daysSinceLastActive per Person
      const now = new Date();
      const msPerDay = 1000 * 60 * 60 * 24;
      const candidates = persons
        .map((p) => {
          const lastActive = p.linkedUserId
            ? (userActivityMap.get(p.linkedUserId) ?? p.updatedAt)
            : p.updatedAt;
          const daysSince = Math.floor(
            (now.getTime() - lastActive.getTime()) / msPerDay,
          );
          return { person: p, daysSince, lastActive };
        })
        .filter((c) => c.daysSince >= INACTIVITY_THRESHOLD_DAYS);

      if (candidates.length === 0) return [];

      // 4. Sort: most inactive first, elders prioritized
      candidates.sort((a, b) => {
        const ageA = estimateAge(a.person.dateOfBirth, a.person.birthYear) ?? 0;
        const ageB = estimateAge(b.person.dateOfBirth, b.person.birthYear) ?? 0;
        const aIsElder = ageA >= ELDER_AGE_THRESHOLD;
        const bIsElder = ageB >= ELDER_AGE_THRESHOLD;
        if (aIsElder !== bIsElder) return aIsElder ? -1 : 1;
        return b.daysSince - a.daysSince;
      });

      // 5. Cap and build items
      const top = candidates.slice(0, MAX_INACTIVITY_ITEMS);

      return top.map((c) => {
        const age = estimateAge(c.person.dateOfBirth, c.person.birthYear);
        const isElder = age !== null && age >= ELDER_AGE_THRESHOLD;
        const isSevere = c.daysSince >= SEVERE_INACTIVITY_DAYS;

        // Priority: elder/severe=95, severe=80, otherwise=60
        const priority = isElder ? 95 : isSevere ? 80 : 60;

        const dayOfWeek = DAY_NAMES[c.lastActive.getUTCDay()];
        const daysWord = c.daysSince === 1 ? '1 day' : `${c.daysSince} days`;

        const title = isElder
          ? `${c.person.name} hasn't been active in ${daysWord}`
          : `${c.person.name} has been quiet for ${daysWord}`;
        const body = `Last seen: ${dayOfWeek}. ${
          isElder
            ? 'As an elder, they may need a check-in.'
            : 'A quick hello could brighten their day.'
        }`;

        // Phase 2: closeness score boosts elders who are also close relatives
        // (Dadi at 0.9 closeness beats random-distant-aunt at 0.2 closeness)
        const closeness = ctx.personalization?.computeClosenessForTarget(c.person.id);
        const baseRelevance = isElder ? 0.95 : 0.7;
        const relevanceScore = closeness ? Math.max(baseRelevance, closeness.total) : baseRelevance;

        const actionData: Record<string, unknown> = {
          personId: c.person.id,
          personName: c.person.name,
          daysSinceLastActive: c.daysSince,
          lastActiveAt: c.lastActive.toISOString(),
          isElder,
          age,
          closeness: closeness
            ? {
                total: closeness.total,
                hopCount: closeness.hopCount,
                relationshipSemantic: closeness.relationshipSemantic,
              }
            : undefined,
        };
        if (c.person.linkedUserId) {
          actionData.targetUserId = c.person.linkedUserId;
        }

        return {
          itemType: 'need_you' as const,
          priority,
          title,
          body,
          actionLabel: localizeAction('message', ctx.userLanguageCode),
          actionType: 'message' as const,
          actionData,
          targetPersonId: c.person.id,
          ...(c.person.linkedUserId ? { targetUserId: c.person.linkedUserId } : {}),
          relevanceScore,
        };
      });
    } catch (err) {
      this.logger.error(
        `InactivityCollector failed for family ${ctx.familyId}: ${err instanceof Error ? err.message : err}`,
      );
      return [];
    }
  }
}
