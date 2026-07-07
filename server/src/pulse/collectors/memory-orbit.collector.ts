// server/src/pulse/collectors/memory-orbit.collector.ts
//
// MemoryOrbitCollector — surfaces ancestral voice memories on anniversaries
// and "the day they were recorded" + when tagged Persons have birthdays.
//
// PHASE 1 STUB → NOW IMPLEMENTED (Pitru Pt-1+2 shipped).
//
// Strategy:
//   1. Query AncestralMemory rows where:
//        - familyId = ctx.familyId
//        - status = 'ready' (AI processing complete)
//        - isRevealed = true (respect time-capsule reveal dates)
//        - AND one of:
//            (a) EXTRACT(MONTH/DAY FROM "createdAt") = today's month+day AND
//                EXTRACT(YEAR FROM "createdAt") < current year  (recording anniversary)
//            (b) The memory is tagged to a Person whose birthday (dateOfBirth
//                month+day, OR birthYear with synthesized Jan 1) is today
//   2. Sort by createdAt ASC (oldest memory first — more emotionally powerful)
//   3. Cap at 1 item (we don't want the brief flooded with memories)
//   4. Title: "{Elder name} shared a memory — {topic}"
//      Body: "{durationSec}s {audio|video}. Recorded {yearsAgo} years ago. {aiSummary}"
//      ActionType: 'listen_memory'
//   5. Special case: if the elder Person is deceased, frame as memorial:
//      "{Elder name} left this memory for you. {yearsAgo} years ago today."
//
// Note: We use raw SQL with EXTRACT(MONTH/DAY ...) because Prisma doesn't have
// a clean API for "same month+day in any prior year".

import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import {
  BriefCollector,
  BriefCollectorContext,
  BriefItemData,
  localizeAction,
} from '../brief-types';

const MAX_MEMORY_ITEMS = 1;

interface MemoryRow {
  id: string;
  title: string;
  topic: string | null;
  media_type: string;
  duration_sec: number;
  created_at: Date;
  ai_summary: string | null;
  elder_name: string | null;
  elder_id: string | null;
  elder_deceased: boolean;
  listen_count: number;
}

@Injectable()
export class MemoryOrbitCollector implements BriefCollector {
  readonly name = 'memory_orbit';
  private readonly logger = new Logger(MemoryOrbitCollector.name);

  constructor(private readonly prisma: PrismaService) {}

  async collect(ctx: BriefCollectorContext): Promise<BriefItemData[]> {
    try {
      const now = new Date();
      const month = now.getUTCMonth() + 1; // 1-12
      const day = now.getUTCDate();

      // Query 1: Recording anniversaries (created on this month+day in a prior year)
      const anniversaryMemories = await this.prisma.$queryRaw<MemoryRow[]>`
        SELECT
          am."id"::text AS id,
          am."title" AS title,
          am."topic" AS topic,
          am."mediaType" AS media_type,
          am."durationSec" AS duration_sec,
          am."createdAt" AS created_at,
          am."aiSummary" AS ai_summary,
          p."name" AS elder_name,
          p."id"::text AS elder_id,
          COALESCE(p."isDeceased", false) AS elder_deceased,
          am."listenCount" AS listen_count
        FROM public."AncestralMemory" am
        LEFT JOIN public."Person" p ON p."id" = am."elderPersonId"
        WHERE am."familyId" = ${ctx.familyId}::text
          AND am."status" = 'ready'
          AND am."isRevealed" = true
          AND EXTRACT(MONTH FROM am."createdAt") = ${month}
          AND EXTRACT(DAY   FROM am."createdAt") = ${day}
          AND EXTRACT(YEAR  FROM am."createdAt") < EXTRACT(YEAR FROM NOW())
        ORDER BY am."createdAt" ASC
        LIMIT 5;
      `;

      // Query 2: Memories tagged to Persons whose birthday is today.
      // We only use Person.dateOfBirth (full date with month+day).
      // Person.birthYear alone doesn't give us month/day info, so we can't
      // determine the birthday — those Persons are skipped here.
      const birthdayTaggedMemories = await this.prisma.$queryRaw<MemoryRow[]>`
        SELECT
          am."id"::text AS id,
          am."title" AS title,
          am."topic" AS topic,
          am."mediaType" AS media_type,
          am."durationSec" AS duration_sec,
          am."createdAt" AS created_at,
          am."aiSummary" AS ai_summary,
          p."name" AS elder_name,
          p."id"::text AS elder_id,
          COALESCE(p."isDeceased", false) AS elder_deceased,
          am."listenCount" AS listen_count
        FROM public."AncestralMemory" am
        JOIN public."MemoryTag" mt ON mt."memoryId" = am."id"
        JOIN public."Person" p ON p."id" = mt."personId"
        WHERE am."familyId" = ${ctx.familyId}::text
          AND am."status" = 'ready'
          AND am."isRevealed" = true
          AND p."dateOfBirth" IS NOT NULL
          AND EXTRACT(MONTH FROM p."dateOfBirth") = ${month}
          AND EXTRACT(DAY   FROM p."dateOfBirth") = ${day}
        ORDER BY am."createdAt" ASC
        LIMIT 5;
      `;

      const all = [...anniversaryMemories, ...birthdayTaggedMemories];
      if (all.length === 0) {
        // No memory anniversaries today — return empty
        return [];
      }

      // Dedupe by memory id (a memory might appear in both queries)
      const seen = new Set<string>();
      const unique = all.filter((m) => {
        if (seen.has(m.id)) return false;
        seen.add(m.id);
        return true;
      });

      // Sort oldest-first (more poignant)
      unique.sort((a, b) => a.created_at.getTime() - b.created_at.getTime());

      const top = unique.slice(0, MAX_MEMORY_ITEMS);

      return top.map((m) => {
        const year = m.created_at.getUTCFullYear();
        const yearsAgo = now.getUTCFullYear() - year;
        const yearsWord = yearsAgo === 1 ? '1 year ago' : `${yearsAgo} years ago`;
        const elderName = m.elder_name ?? 'A family elder';
        const durationWord = this.formatDuration(m.duration_sec);

        // Phase 2: closeness to the elder Person
        const closeness = m.elder_id
          ? ctx.personalization?.computeClosenessForTarget(m.elder_id)
          : undefined;
        const relevanceScore = closeness
          ? Math.max(0.65, closeness.total)
          : 0.65;

        let title: string;
        let body: string;

        if (m.elder_deceased) {
          // Memorial framing
          title = `${elderName} left this memory for you`;
          body = `Recorded ${yearsWord}${
            m.topic ? ` · ${m.topic}` : ''
          } · ${durationWord} ${m.media_type}. ${
            m.ai_summary ? m.ai_summary : ''
          }`.trim();
        } else {
          title = `${elderName} shared a memory — ${m.topic ?? m.title}`;
          body = `${durationWord} ${m.media_type}, recorded ${yearsWord}. ${
            m.ai_summary ? m.ai_summary : m.title
          }`.trim();
        }

        return {
          itemType: 'memory_orbit' as const,
          priority: 70,
          title,
          body,
          actionLabel: localizeAction('listen_memory', ctx.userLanguageCode),
          actionType: 'listen_memory' as const,
          actionData: {
            memoryId: m.id,
            title: m.title,
            topic: m.topic,
            mediaType: m.media_type,
            durationSec: m.duration_sec,
            yearsAgo,
            recordedAt: m.created_at.toISOString(),
            elderName,
            elderDeceased: m.elder_deceased,
            listenCount: m.listen_count,
            closeness: closeness
              ? { total: closeness.total, hopCount: closeness.hopCount }
              : undefined,
          },
          ...(m.elder_id ? { targetPersonId: m.elder_id } : {}),
          relevanceScore,
        };
      });
    } catch (err) {
      this.logger.error(
        `MemoryOrbitCollector failed for family ${ctx.familyId}: ${err instanceof Error ? err.message : err}`,
      );
      return [];
    }
  }

  private formatDuration(sec: number): string {
    if (sec <= 0) return '';
    if (sec < 60) return `${sec}s`;
    const m = Math.floor(sec / 60);
    const s = sec % 60;
    return s > 0 ? `${m}m${s}s` : `${m}min`;
  }
}
