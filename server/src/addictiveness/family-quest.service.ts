// server/src/addictiveness/family-quest.service.ts
//
// A-3 Family Quests — weekly AI-generated quests targeting weak relationships.
//
// Strategy:
//   1. Every Monday 7am IST, generateQuestsForFamily() runs for each family
//   2. For each family member, analyze their relationship graph:
//      - Find the 3 weakest relationships (highest daysSinceLastContact,
//        lowest closeness score, stormy weather)
//      - Generate a quest for each weak relationship
//   3. Quest types:
//      - call: "Call {name} this week — you haven't spoken in {N} days"
//      - message: "Send a message to {name} — your relationship is feeling {weather}"
//      - share_photo: "Share a photo with {name} — reconnect through a moment"
//      - wish_birthday: "Wish {name} a happy birthday (in {N} days)"
//      - visit: "Plan a visit to {name} — it's been a while"
//      - ritual: "Do a {festival} ritual with {name} this week"
//   4. Each quest has a karmaReward (10-30 based on quest type + difficulty)
//   5. Quests expire at end of week (Sunday 11:59pm IST)
//   6. When user completes a quest action (call/message/etc.), the BriefInteraction
//      handler checks for matching active quests and marks them complete + awards karma

import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

export interface QuestGenerationResult {
  familyId: string;
  questsGenerated: number;
  usersProcessed: number;
  errors: string[];
}

const MAX_QUESTS_PER_USER = 3;
const QUEST_KARMA_BY_TYPE: Record<string, number> = {
  call: 15,
  message: 10,
  share_photo: 20,
  wish_birthday: 25,
  visit: 30,
  ritual: 25,
};

@Injectable()
export class FamilyQuestService {
  private readonly logger = new Logger(FamilyQuestService.name);

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Generate weekly quests for all families.
   * Called by the Monday 7am IST cron.
   */
  async generateQuestsForAllFamilies(): Promise<{
    familiesProcessed: number;
    totalQuestsGenerated: number;
    errors: string[];
  }> {
    const families = await this.prisma.family.findMany({
      where: { deletedAt: null },
      select: { id: true },
    });

    let totalQuestsGenerated = 0;
    const errors: string[] = [];

    for (const fam of families) {
      try {
        const result = await this.generateQuestsForFamily(fam.id);
        totalQuestsGenerated += result.questsGenerated;
      } catch (err) {
        errors.push(
          `family ${fam.id}: ${err instanceof Error ? err.message : err}`,
        );
      }
    }

    this.logger.log(
      `FamilyQuest: generated ${totalQuestsGenerated} quests across ${families.length} families (${errors.length} errors)`,
    );
    return { familiesProcessed: families.length, totalQuestsGenerated, errors };
  }

  /**
   * Generate quests for a single family.
   * For each member, find their 3 weakest relationships and create quests.
   */
  async generateQuestsForFamily(familyId: string): Promise<QuestGenerationResult> {
    const weekOf = this.getMondayOfWeek(new Date());
    const deadline = this.getSundayEndOfWeek(new Date());

    // Get all family members
    const members = await this.prisma.familyMember.findMany({
      where: { familyId },
      select: { userId: true },
    });

    let questsGenerated = 0;
    const errors: string[] = [];

    // Delete old quests from previous weeks for this family (keep history for analytics,
    // but mark them expired if they're still active)
    await this.prisma.familyQuest.updateMany({
      where: { familyId, status: 'active', deadline: { lt: new Date() } },
      data: { status: 'expired', expiredAt: new Date() },
    });

    for (const member of members) {
      try {
        const quests = await this.generateQuestsForUser(
          member.userId,
          familyId,
          weekOf,
          deadline,
        );
        questsGenerated += quests;
      } catch (err) {
        errors.push(
          `user ${member.userId}: ${err instanceof Error ? err.message : err}`,
        );
      }
    }

    this.logger.log(
      `FamilyQuest: family ${familyId} — ${questsGenerated} quests generated for ${members.length} users`,
    );

    return { familyId, questsGenerated, usersProcessed: members.length, errors };
  }

  /**
   * Generate up to 3 quests for a single user.
   * Analyzes their relationship graph for weak points.
   */
  async generateQuestsForUser(
    userId: string,
    familyId: string,
    weekOf: Date,
    deadline: Date,
  ): Promise<number> {
    // 1. Find the user's linked Person
    const linkedPerson = await this.prisma.person.findFirst({
      where: { linkedUserId: userId, deletedAt: null, familyId },
      select: { id: true },
    });

    // 2. Get all Persons in the family (excluding the user's own Person + deceased)
    const persons = await this.prisma.person.findMany({
      where: {
        familyId,
        deletedAt: null,
        isDeceased: false,
        ...(linkedPerson ? { id: { not: linkedPerson.id } } : {}),
      },
      select: {
        id: true,
        name: true,
        dateOfBirth: true,
        birthYear: true,
        updatedAt: true,
        linkedUserId: true,
      },
    });

    if (persons.length === 0) return 0;

    // 3. Get RelationshipWeather for this user (to find weak relationships)
    const weatherRows = await this.prisma.relationshipWeather.findMany({
      where: { familyId, userAId: userId },
      select: {
        personBId: true,
        weather: true,
        daysSinceLastContact: true,
      },
    });
    const weatherMap = new Map<string, { weather: string; daysSince: number }>();
    for (const w of weatherRows) {
      if (w.personBId) {
        weatherMap.set(w.personBId, {
          weather: w.weather,
          daysSince: w.daysSinceLastContact,
        });
      }
    }

    // 4. Score each Person by "quest need" (higher = more urgent)
    //    Quest need = daysSinceLastContact * 0.5 + weatherSeverity * 0.3 + hasBirthdayThisWeek * 0.2
    const msPerDay = 1000 * 60 * 60 * 24;
    const now = new Date();
    const weekFromNow = new Date(now.getTime() + 7 * msPerDay);

    const scored = persons
      .map((p) => {
        const weather = weatherMap.get(p.id);
        const daysSince = weather?.daysSince ?? Math.floor((now.getTime() - p.updatedAt.getTime()) / msPerDay);

        // Check if birthday is this week
        let birthdayThisWeek = false;
        let daysUntilBirthday: number | null = null;
        if (p.dateOfBirth) {
          const thisYearBday = new Date(Date.UTC(now.getUTCFullYear(), p.dateOfBirth.getUTCMonth(), p.dateOfBirth.getUTCDate()));
          if (thisYearBday < now) {
            thisYearBday.setUTCFullYear(now.getUTCFullYear() + 1);
          }
          const daysUntil = Math.floor((thisYearBday.getTime() - now.getTime()) / msPerDay);
          if (daysUntil >= 0 && daysUntil <= 7) {
            birthdayThisWeek = true;
            daysUntilBirthday = daysUntil;
          }
        }

        const weatherSeverity =
          weather?.weather === 'stormy' ? 1.0 :
          weather?.weather === 'rainy' ? 0.8 :
          weather?.weather === 'cloudy' ? 0.6 :
          weather?.weather === 'partly_cloudy' ? 0.3 :
          0.1;

        const questNeed =
          Math.min(daysSince / 30, 1.0) * 0.5 +
          weatherSeverity * 0.3 +
          (birthdayThisWeek ? 0.2 : 0);

        return {
          person: p,
          daysSince,
          weather: weather?.weather,
          birthdayThisWeek,
          daysUntilBirthday,
          questNeed,
        };
      })
      .sort((a, b) => b.questNeed - a.questNeed);

    // 5. Take top N and generate quests
    const top = scored.slice(0, MAX_QUESTS_PER_USER);
    const questsToCreate: any[] = [];

    for (const candidate of top) {
      // Skip if quest need is too low (no point generating a quest for a sunny relationship)
      if (candidate.questNeed < 0.15 && !candidate.birthdayThisWeek) continue;

      let questType: string;
      let title: string;
      let description: string;
      let actionType: string;
      let actionData: Record<string, unknown> = {
        targetPersonId: candidate.person.id,
        targetName: candidate.person.name,
      };
      let generatedBy: string;

      if (candidate.birthdayThisWeek) {
        questType = 'wish_birthday';
        title = `Wish ${candidate.person.name} a happy birthday`;
        description =
          candidate.daysUntilBirthday === 0
            ? `${candidate.person.name}'s birthday is TODAY. Don't forget to wish them!`
            : `${candidate.person.name}'s birthday is in ${candidate.daysUntilBirthday} day${candidate.daysUntilBirthday === 1 ? '' : 's'}. Be the first to wish them.`;
        actionType = 'message';
        actionData.birthday = true;
        actionData.daysUntilBirthday = candidate.daysUntilBirthday;
        generatedBy = 'birthday';
      } else if (candidate.weather === 'stormy' || candidate.weather === 'rainy') {
        questType = 'call';
        title = `Call ${candidate.person.name} this week`;
        description = `Your relationship is feeling ${candidate.weather}. You haven't spoken in ${candidate.daysSince} days. A call could turn things around.`;
        actionType = 'call';
        actionData.weather = candidate.weather;
        actionData.daysSince = candidate.daysSince;
        generatedBy = 'weather';
      } else if (candidate.daysSince >= 14) {
        questType = 'message';
        title = `Send a message to ${candidate.person.name}`;
        description = `It's been ${candidate.daysSince} days since you last connected. A simple "thinking of you" goes a long way.`;
        actionType = 'message';
        actionData.daysSince = candidate.daysSince;
        generatedBy = 'graph_weak_point';
      } else if (candidate.daysSince >= 7) {
        questType = 'share_photo';
        title = `Share a photo with ${candidate.person.name}`;
        description = `Share a Sparq (moment) with ${candidate.person.name}. Reconnect through a memory.`;
        actionType = 'view_post';
        actionData.daysSince = candidate.daysSince;
        generatedBy = 'graph_weak_point';
      } else {
        // Low-need candidate — skip
        continue;
      }

      // Check if a quest already exists for this user+target+week
      const existing = await this.prisma.familyQuest.findFirst({
        where: {
          userId,
          familyId,
          weekOf,
          targetPersonId: candidate.person.id,
          status: 'active',
        },
        select: { id: true },
      });
      if (existing) continue; // Don't create duplicates

      questsToCreate.push({
        familyId,
        userId,
        targetPersonId: candidate.person.id,
        targetUserId: candidate.person.linkedUserId ?? null,
        questType,
        title,
        description,
        actionType,
        actionData: actionData as any,
        weekOf,
        deadline,
        karmaReward: QUEST_KARMA_BY_TYPE[questType] ?? 10,
        status: 'active',
        generatedBy,
        questScore: candidate.questNeed,
      });
    }

    if (questsToCreate.length === 0) return 0;

    await this.prisma.familyQuest.createMany({ data: questsToCreate });
    return questsToCreate.length;
  }

  /** Get active quests for a user (for the Flutter "This Week's Quests" widget). */
  async getActiveQuests(userId: string) {
    const now = new Date();
    const quests = await this.prisma.familyQuest.findMany({
      where: {
        userId,
        status: 'active',
        deadline: { gte: now },
      },
      orderBy: { deadline: 'asc' },
      include: {
        targetPerson: { select: { id: true, name: true, photoThumb: true } },
      },
    });
    return quests.map((q) => this.serializeQuest(q));
  }

  /** Get quest history for a user (completed + expired). */
  async getQuestHistory(userId: string, limit: number = 20) {
    const quests = await this.prisma.familyQuest.findMany({
      where: {
        userId,
        status: { in: ['completed', 'expired', 'skipped'] },
      },
      orderBy: { updatedAt: 'desc' },
      take: Math.min(limit, 50),
      include: {
        targetPerson: { select: { id: true, name: true, photoThumb: true } },
      },
    });
    return quests.map((q) => this.serializeQuest(q));
  }

  /** Mark a quest as completed (called when the user does the quest action). */
  async completeQuest(questId: string, userId: string): Promise<{ karmaAwarded: number }> {
    const quest = await this.prisma.familyQuest.findUnique({
      where: { id: questId },
      select: { id: true, userId: true, status: true, karmaReward: true, familyId: true },
    });
    if (!quest) throw new Error('Quest not found');
    if (quest.userId !== userId) throw new Error('Not your quest');
    if (quest.status !== 'active') throw new Error(`Quest is ${quest.status}, not active`);

    await this.prisma.familyQuest.update({
      where: { id: questId },
      data: {
        status: 'completed',
        completedAt: new Date(),
        karmaAwarded: quest.karmaReward,
      },
    });

    // Award karma via FamilyKarma upsert
    const karmaRow = await this.prisma.familyKarma.upsert({
      where: { userId_familyId: { userId, familyId: quest.familyId } },
      create: {
        userId,
        familyId: quest.familyId,
        totalKarma: quest.karmaReward,
        karmaThisWeek: quest.karmaReward,
        karmaThisMonth: quest.karmaReward,
        karmaAsLeaf: quest.karmaReward,
        lastKarmaAt: new Date(),
        recentReasons: [
          { amount: quest.karmaReward, reason: 'quest_completed', timestamp: new Date().toISOString() },
        ] as any,
      },
      update: {
        totalKarma: { increment: quest.karmaReward },
        karmaThisWeek: { increment: quest.karmaReward },
        karmaThisMonth: { increment: quest.karmaReward },
        karmaAsLeaf: { increment: quest.karmaReward },
        lastKarmaAt: new Date(),
      },
    });

    return { karmaAwarded: quest.karmaReward };
  }

  /** Skip a quest (user doesn't want to do it). */
  async skipQuest(questId: string, userId: string) {
    const quest = await this.prisma.familyQuest.findUnique({
      where: { id: questId },
      select: { userId: true, status: true },
    });
    if (!quest) throw new Error('Quest not found');
    if (quest.userId !== userId) throw new Error('Not your quest');
    if (quest.status !== 'active') throw new Error(`Quest is ${quest.status}`);

    await this.prisma.familyQuest.update({
      where: { id: questId },
      data: { status: 'skipped', skippedAt: new Date() },
    });

    return { id: questId, status: 'skipped' };
  }

  // ────────────────────────────────────────────────────────────────────────
  // Helpers
  // ────────────────────────────────────────────────────────────────────────

  private getMondayOfWeek(date: Date): Date {
    const d = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
    const day = d.getUTCDay(); // 0 = Sunday
    const diff = d.getUTCDate() - day + (day === 0 ? -6 : 1); // adjust to Monday
    return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), diff));
  }

  private getSundayEndOfWeek(date: Date): Date {
    const monday = this.getMondayOfWeek(date);
    const sunday = new Date(monday.getTime() + 6 * 24 * 60 * 60 * 1000);
    sunday.setUTCHours(23, 59, 59, 999);
    return sunday;
  }

  private serializeQuest(q: any) {
    return {
      id: q.id,
      familyId: q.familyId,
      userId: q.userId,
      targetPersonId: q.targetPersonId,
      targetPerson: q.targetPerson
        ? { id: q.targetPerson.id, name: q.targetPerson.name, photoThumb: q.targetPerson.photoThumb }
        : null,
      questType: q.questType,
      title: q.title,
      description: q.description,
      actionType: q.actionType,
      actionData: q.actionData,
      weekOf: q.weekOf.toISOString().slice(0, 10),
      deadline: q.deadline.toISOString(),
      karmaReward: q.karmaReward,
      karmaAwarded: q.karmaAwarded,
      status: q.status,
      completedAt: q.completedAt?.toISOString() ?? null,
      generatedBy: q.generatedBy,
      questScore: q.questScore ? Number(q.questScore) : null,
      createdAt: q.createdAt.toISOString(),
    };
  }
}
