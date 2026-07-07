// server/src/pulse/collectors/birthday.collector.ts
//
// BirthdayCollector — finds family members with birthdays in the next 7 days.
//
// Strategy:
//   1. Query Person rows in the user's family where:
//        - deletedAt IS NULL
//        - isDeceased = false
//        - dateOfBirth IS NOT NULL  OR  birthYear IS NOT NULL
//   2. For each Person, compute days-until-next-birthday.
//   3. Filter to days <= 7 (this week).
//   4. Compute priority by inferred relationship closeness:
//        parent/child    (relationshipType father|mother|son|daughter) → 90
//        sibling         (brother|sister)                              → 80
//        cousin                                                          → 60
//        other                                                           → 40
//      If no direct relationship exists between the user's Person and this
//      Person, default priority is 50.
//   5. Build BriefItemData with localized title/body/actionLabel.
//   6. Cap at 3 items (we don't want all 6 brief slots taken by birthdays).
//
// Localization: title/body are in English (the orchestrator localizes the
// actionLabel using ACTION_LABELS). For Phase 2 we'll add full body localization.

import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import {
  BriefCollector,
  BriefCollectorContext,
  BriefItemData,
  daysUntilNextBirthday,
  estimateAge,
  localizeAction,
} from '../brief-types';

const PRIORITY_BY_RELATIONSHIP_TYPE: Record<string, number> = {
  father: 90,
  mother: 90,
  son: 90,
  daughter: 90,
  husband: 95,
  wife: 95,
  brother: 80,
  sister: 80,
  grandfather: 88,
  grandmother: 88,
  grandfather_mother: 88,
  grandfather_father: 88,
  grandson: 70,
  granddaughter: 70,
  uncle: 65,
  aunt: 65,
  cousin: 60,
  nephew: 65,
  niece: 65,
};

const MAX_BIRTHDAY_ITEMS = 3;
const BIRTHDAY_HORIZON_DAYS = 7;

@Injectable()
export class BirthdayCollector implements BriefCollector {
  readonly name = 'birthday';
  private readonly logger = new Logger(BirthdayCollector.name);

  constructor(private readonly prisma: PrismaService) {}

  async collect(ctx: BriefCollectorContext): Promise<BriefItemData[]> {
    try {
      // 1. Load all candidate Persons (with DOB or birthYear)
      const persons = await this.prisma.person.findMany({
        where: {
          familyId: ctx.familyId,
          deletedAt: null,
          isDeceased: false,
          OR: [{ dateOfBirth: { not: null } }, { birthYear: { not: null } }],
        },
        select: {
          id: true,
          name: true,
          dateOfBirth: true,
          birthYear: true,
          gender: true,
        },
      });

      // 2. Compute days-until-next-birthday for each
      const candidates = persons
        .map((p) => {
          const days = daysUntilNextBirthday(p.dateOfBirth, p.birthYear);
          return { person: p, daysUntil: days };
        })
        .filter(
          (c): c is { person: typeof c.person; daysUntil: number } =>
            c.daysUntil !== null && c.daysUntil <= BIRTHDAY_HORIZON_DAYS,
        );

      if (candidates.length === 0) return [];

      // 3. If the user has a linked Person, load all relationships involving
      //    them so we can compute closeness priority.
      let relPriorityMap = new Map<string, number>();
      if (ctx.userPersonId) {
        const rels = await this.prisma.relationship.findMany({
          where: {
            familyId: ctx.familyId,
            isActive: true,
            OR: [
              { fromPersonId: ctx.userPersonId },
              { toPersonId: ctx.userPersonId },
            ],
          },
          select: {
            fromPersonId: true,
            toPersonId: true,
            relationshipType: true,
          },
        });
        for (const r of rels) {
          const otherPersonId =
            r.fromPersonId === ctx.userPersonId ? r.toPersonId : r.fromPersonId;
          const pri = PRIORITY_BY_RELATIONSHIP_TYPE[r.relationshipType?.toLowerCase()] ?? 50;
          // If multiple rels exist, keep the highest priority
          const existing = relPriorityMap.get(otherPersonId) ?? 0;
          if (pri > existing) {
            relPriorityMap.set(otherPersonId, pri);
          }
        }
      }

      // 4. Sort by (days-until ASC, priority DESC) and take top N
      candidates.sort((a, b) => {
        if (a.daysUntil !== b.daysUntil) return a.daysUntil - b.daysUntil;
        const priA = relPriorityMap.get(a.person.id) ?? 50;
        const priB = relPriorityMap.get(b.person.id) ?? 50;
        return priB - priA;
      });

      const top = candidates.slice(0, MAX_BIRTHDAY_ITEMS);

      // 5. Build BriefItemData
      return top.map((c) => {
        const pri = relPriorityMap.get(c.person.id) ?? 50;
        const age = estimateAge(c.person.dateOfBirth, c.person.birthYear);
        const isToday = c.daysUntil === 0;
        const dayWord = isToday
          ? 'today'
          : c.daysUntil === 1
            ? 'tomorrow'
            : `in ${c.daysUntil} days`;
        const ageClause = age !== null ? `Turning ${age + (isToday ? 0 : 1)}. ` : '';
        const title = isToday
          ? `${c.person.name}'s birthday is today 🎂`
          : `${c.person.name}'s birthday — ${dayWord}`;
        const body = `${ageClause}Consider contributing to a family gift pool or sending a message.`;
        return {
          itemType: 'birthday' as const,
          priority: pri,
          title,
          body,
          actionLabel: localizeAction('contribute', ctx.userLanguageCode),
          actionType: 'contribute' as const,
          actionData: {
            personId: c.person.id,
            personName: c.person.name,
            daysUntil: c.daysUntil,
            age: age,
            ...(c.person.dateOfBirth ? { dateOfBirth: c.person.dateOfBirth.toISOString() } : {}),
            ...(c.person.birthYear ? { birthYear: c.person.birthYear } : {}),
          },
          targetPersonId: c.person.id,
          relevanceScore: 0.6,
        };
      });
    } catch (err) {
      this.logger.error(
        `BirthdayCollector failed for family ${ctx.familyId}: ${err instanceof Error ? err.message : err}`,
      );
      return [];
    }
  }
}
