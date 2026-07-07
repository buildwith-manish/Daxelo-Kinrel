// server/src/pulse/collectors/weather.collector.ts
//
// WeatherCollector — surfaces cloudy/stormy relationships that need attention.
//
// Strategy:
//   1. Query RelationshipWeather rows where:
//        - userAId = ctx.userId  (the user is the "viewer" of the weather)
//        - weather != 'sunny'    (sunny pairs are not surfaced)
//        - familyId = ctx.familyId
//   2. Sort by weather priority (stormy > rainy > cloudy > partly_cloudy).
//   3. Cap at 2 items (don't flood the brief with relationship warnings).
//   4. Title: "{Person name} — {weather}. You haven't spoken in {N} days."
//   5. Body: "Last conversation: {context}" if available, else generic.
//   6. ActionType: 'message' (the user can tap to send a message).
//
// Note: the RelationshipWeather table is populated by PulseCronService at 1am
// (see pulse-cron.service.ts). For Phase 1, this table will likely be empty
// since the 1am cron hasn't run yet — this collector will return [].
// That's expected and fine.

import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import {
  BriefCollector,
  BriefCollectorContext,
  BriefItemData,
  localizeAction,
  WEATHER_PRIORITY,
  type WeatherType,
} from '../brief-types';

const MAX_WEATHER_ITEMS = 2;

const WEATHER_EMOJI: Record<WeatherType, string> = {
  sunny: '☀️',
  partly_cloudy: '⛅',
  cloudy: '☁️',
  rainy: '🌧️',
  stormy: '⛈️',
};

const WEATHER_LABEL: Record<WeatherType, string> = {
  sunny: 'sunny',
  partly_cloudy: 'partly cloudy',
  cloudy: 'cloudy',
  rainy: 'rainy',
  stormy: 'stormy',
};

function isWeatherType(s: string): s is WeatherType {
  return s === 'sunny' || s === 'partly_cloudy' || s === 'cloudy' || s === 'rainy' || s === 'stormy';
}

@Injectable()
export class WeatherCollector implements BriefCollector {
  readonly name = 'weather';
  private readonly logger = new Logger(WeatherCollector.name);

  constructor(private readonly prisma: PrismaService) {}

  async collect(ctx: BriefCollectorContext): Promise<BriefItemData[]> {
    try {
      // 1. Load all non-sunny weather rows for this user in this family
      const rows = await this.prisma.relationshipWeather.findMany({
        where: {
          familyId: ctx.familyId,
          userAId: ctx.userId,
          weather: { not: 'sunny' },
        },
        select: {
          id: true,
          weather: true,
          daysSinceLastContact: true,
          interactionCount30d: true,
          sentimentScore: true,
          streakDays: true,
          personBId: true,
          userBId: true,
          personB: { select: { id: true, name: true } },
          userB: { select: { id: true, name: true } },
        },
        orderBy: { updatedAt: 'desc' },
        take: 10,
      });

      if (rows.length === 0) return [];

      // 2. Score + sort by weather priority (stormy > rainy > cloudy > partly_cloudy)
      const scored = rows
        .filter((r) => isWeatherType(r.weather))
        .map((r) => {
          const wt = r.weather as WeatherType;
          const pri = WEATHER_PRIORITY[wt];
          return { row: r, wt, pri };
        })
        .sort((a, b) => b.pri - a.pri);

      const top = scored.slice(0, MAX_WEATHER_ITEMS);

      // 3. Build items
      return top.map(({ row, wt, pri }) => {
        const personName =
          row.personB?.name ?? row.userB?.name ?? 'A family member';
        const daysWord =
          row.daysSinceLastContact === 0
            ? 'recently'
            : row.daysSinceLastContact === 1
              ? '1 day ago'
              : `${row.daysSinceLastContact} days ago`;

        const title = `${personName} — ${WEATHER_EMOJI[wt]} ${WEATHER_LABEL[wt]}`;
        const body =
          row.daysSinceLastContact > 0
            ? `You haven't spoken in ${row.daysSinceLastContact} days. Last contact: ${daysWord}.`
            : `Your relationship is feeling ${WEATHER_LABEL[wt]} right now.`;

        // Phase 2: relevance = blend of weather severity + closeness
        // (a stormy relationship with your sibling is more urgent than a stormy
        // relationship with a distant cousin you rarely see anyway)
        const targetPersonId = row.personB?.id;
        const closeness = targetPersonId
          ? ctx.personalization?.computeClosenessForTarget(targetPersonId)
          : undefined;
        const weatherSeverity = pri / 100; // stormy=0.85, rainy=0.75, cloudy=0.65
        const relevanceScore = closeness
          ? weatherSeverity * 0.6 + closeness.total * 0.4
          : weatherSeverity;

        const actionData: Record<string, unknown> = {
          weatherId: row.id,
          weather: wt,
          daysSinceLastContact: row.daysSinceLastContact,
          interactionCount30d: row.interactionCount30d,
          sentimentScore: row.sentimentScore
            ? Number(row.sentimentScore)
            : 0.5,
          targetName: personName,
          closeness: closeness
            ? { total: closeness.total, hopCount: closeness.hopCount }
            : undefined,
        };
        if (row.personB?.id) actionData.targetPersonId = row.personB.id;
        if (row.userB?.id) actionData.targetUserId = row.userB.id;

        return {
          itemType: 'weather' as const,
          priority: pri,
          title,
          body,
          actionLabel: localizeAction('message', ctx.userLanguageCode),
          actionType: 'message' as const,
          actionData,
          ...(row.personB?.id ? { targetPersonId: row.personB.id } : {}),
          ...(row.userB?.id ? { targetUserId: row.userB.id } : {}),
          relevanceScore,
        };
      });
    } catch (err) {
      this.logger.error(
        `WeatherCollector failed for family ${ctx.familyId}: ${err instanceof Error ? err.message : err}`,
      );
      return [];
    }
  }
}
