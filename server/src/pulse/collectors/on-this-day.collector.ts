// server/src/pulse/collectors/on-this-day.collector.ts
//
// OnThisDayCollector — finds Sparqs or FamilyPosts from previous years on
// this same calendar date (month + day).
//
// Why this matters: this is the "🔮 On this day, 1987" section in the brief UX.
// It's emotionally powerful — surfacing a story the user's grandfather told 3
// years ago, on the anniversary of the event he described.
//
// Strategy:
//   1. Compute the user's month+day (UTC).
//   2. Query Sparqs by this user (or any family member's user) where:
//        - date_trunc('day', "createdAt") matches month+day in any PRIOR year
//        - isTimeCapsule = false OR (isTimeCapsule = true AND isRevealed = true)
//        - expiresAt > now (skip expired)
//   3. Query FamilyPosts in this family where:
//        - date_trunc('day', "createdAt") matches month+day in any PRIOR year
//   4. Merge both sources, sort by yearsAgo DESC (oldest memory first), cap at 1.
//   5. Build BriefItemData with localized title/body/actionLabel.
//
// Note: We use raw SQL with `EXTRACT(MONTH FROM ...)` and `EXTRACT(DAY FROM ...)`
// because Prisma doesn't have a clean API for "same month+day in any prior year".

import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import {
  BriefCollector,
  BriefCollectorContext,
  BriefItemData,
  localizeAction,
} from '../brief-types';

const MAX_ON_THIS_DAY_ITEMS = 1;

interface OnThisDayRow {
  source: 'sparq' | 'post';
  id: string;
  created_at: Date;
  author_name: string | null;
  preview: string | null;
  author_id: string | null;
  person_id: string | null;
}

@Injectable()
export class OnThisDayCollector implements BriefCollector {
  readonly name = 'on_this_day';
  private readonly logger = new Logger(OnThisDayCollector.name);

  constructor(private readonly prisma: PrismaService) {}

  async collect(ctx: BriefCollectorContext): Promise<BriefItemData[]> {
    try {
      const now = new Date();
      const month = now.getUTCMonth() + 1; // 1-12
      const day = now.getUTCDate();

      // We need the userIds of all family members (so we surface Sparqs from
      // anyone in the family, not just the user).
      const familyMembers = await this.prisma.familyMember.findMany({
        where: { familyId: ctx.familyId },
        select: { userId: true },
      });
      const familyUserIds = familyMembers.map((m) => m.userId);
      if (familyUserIds.length === 0) return [];

      // 1. Sparqs from prior years on this month+day
      //    Use raw SQL because Prisma can't express EXTRACT(MONTH ...)
      const sparqsRaw = await this.prisma.$queryRaw<OnThisDayRow[]>`
        SELECT
          'sparq'::text AS source,
          s."id"::text AS id,
          s."createdAt" AS created_at,
          u."name" AS author_name,
          COALESCE(s."text", '') AS preview,
          s."userId"::text AS author_id,
          NULL::text AS person_id
        FROM public."Sparq" s
        LEFT JOIN public."User" u ON u."id" = s."userId"
        WHERE s."userId" = ANY(${familyUserIds}::text[])
          AND EXTRACT(MONTH FROM s."createdAt") = ${month}
          AND EXTRACT(DAY   FROM s."createdAt") = ${day}
          AND EXTRACT(YEAR  FROM s."createdAt") < EXTRACT(YEAR FROM NOW())
          AND (s."isTimeCapsule" = false OR (s."isTimeCapsule" = true AND s."isRevealed" = true))
          AND s."expiresAt" > NOW()
        ORDER BY s."createdAt" DESC
        LIMIT 5;
      `;

      // 2. FamilyPosts from prior years on this month+day
      const postsRaw = await this.prisma.$queryRaw<OnThisDayRow[]>`
        SELECT
          'post'::text AS source,
          p."id"::text AS id,
          p."createdAt" AS created_at,
          per."name" AS author_name,
          NULL::text AS preview,
          p."authorId"::text AS author_id,
          p."authorId"::text AS person_id
        FROM public."FamilyPost" p
        LEFT JOIN public."Person" per ON per."id" = p."authorId"
        WHERE p."familyId" = ${ctx.familyId}::text
          AND EXTRACT(MONTH FROM p."createdAt") = ${month}
          AND EXTRACT(DAY   FROM p."createdAt") = ${day}
          AND EXTRACT(YEAR  FROM p."createdAt") < EXTRACT(YEAR FROM NOW())
        ORDER BY p."createdAt" DESC
        LIMIT 5;
      `;

      const all = [...sparqsRaw, ...postsRaw];
      if (all.length === 0) return [];

      // 3. Sort by yearsAgo DESC (oldest first — more emotionally powerful)
      const nowYear = now.getUTCFullYear();
      all.sort((a, b) => {
        const yA = a.created_at.getUTCFullYear();
        const yB = b.created_at.getUTCFullYear();
        return yA - yB; // oldest first
      });

      const top = all.slice(0, MAX_ON_THIS_DAY_ITEMS);

      return top.map((row) => {
        const year = row.created_at.getUTCFullYear();
        const yearsAgo = nowYear - year;
        const authorName = row.author_name ?? 'A family member';
        const yearsWord = yearsAgo === 1 ? '1 year ago' : `${yearsAgo} years ago`;

        let title: string;
        let body: string;
        let actionType: BriefItemData['actionType'];
        let actionData: Record<string, unknown> = {
          yearsAgo,
          sourceDate: row.created_at.toISOString(),
          source: row.source,
          sourceId: row.id,
          authorName,
        };

        if (row.source === 'sparq') {
          title = `On this day, ${year}`;
          body =
            row.preview && row.preview.length > 0
              ? `${authorName} shared: "${row.preview.slice(0, 140)}${
                  row.preview.length > 140 ? '…' : ''
                }"`
              : `${authorName} shared a moment ${yearsWord}.`;
          actionType = 'view_sparq';
          actionData = { ...actionData, sparqId: row.id };
        } else {
          title = `On this day, ${year}`;
          body = `${authorName} posted a family update ${yearsWord}.`;
          actionType = 'view_post';
          actionData = { ...actionData, postId: row.id };
        }

        return {
          itemType: 'on_this_day' as const,
          priority: 70,
          title,
          body,
          actionLabel: localizeAction(
            row.source === 'sparq' ? 'view_sparq' : 'view_post',
            ctx.userLanguageCode,
          ),
          actionType,
          actionData,
          ...(row.author_id && row.source === 'post' ? { targetPersonId: row.author_id } : {}),
          ...(row.source === 'sparq' ? { targetSparqId: row.id } : {}),
          ...(row.source === 'post' ? { targetPostId: row.id } : {}),
          relevanceScore: 0.65,
        };
      });
    } catch (err) {
      this.logger.error(
        `OnThisDayCollector failed for family ${ctx.familyId}: ${err instanceof Error ? err.message : err}`,
      );
      return [];
    }
  }
}
