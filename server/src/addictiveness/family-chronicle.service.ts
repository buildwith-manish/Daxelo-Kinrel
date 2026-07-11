// server/src/addictiveness/family-chronicle.service.ts
//
// A-7 Family Chronicle — AI-written family history book, monthly auto-update.
//
// What it does:
//   Generates a beautifully-written family history from the family's graph data,
//   member biographies, key events, Sparqs, and ancestral memories.
//
// The chronicle is structured as "chapters":
//   Chapter 1: "The Founding Generation" — the oldest ancestors, where they came from
//   Chapter 2: "Growing the Family" — marriages, births, migrations
//   Chapter 3: "The Current Generation" — who's here now, what they're doing
//   Chapter 4: "Stories Worth Telling" — curated Sparqs + ancestral memories
//   Chapter 5: "The Family Today" — Kinrel archetype, what makes this family unique
//
// Monthly cron generates a new chapter or updates existing ones with recent events.
//
// AI integration:
//   In production, this would call GPT/Claude with the family data as context.
//   For this MVP, we use a template-based generator that produces readable text
//   from the structured data. The template can be replaced with an AI call later
//   by swapping the `generateChapterContent()` method.

import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

const MONTHLY_CHAPTER_TITLES = [
  'The Founding Generation',
  'Growing the Family',
  'The Current Generation',
  'Stories Worth Telling',
  'The Family Today',
];

@Injectable()
export class FamilyChronicleService {
  private readonly logger = new Logger(FamilyChronicleService.name);

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Generate or update the chronicle for a family.
   * Called by the monthly cron, or manually via the API.
   */
  async generateChronicle(familyId: string): Promise<{ chapterCount: number; isNew: boolean }> {
    const start = Date.now();

    // 1. Load family + graph data
    const family = await this.prisma.family.findUnique({
      where: { id: familyId },
      select: {
        id: true,
        name: true,
        primaryLanguage: true,
        gotra: true,
        originVillage: true,
        createdAt: true,
      },
    });
    if (!family) throw new Error('Family not found');

    // 2. Load all active Persons (grouped by generation)
    const persons = await this.prisma.person.findMany({
      where: { familyId, deletedAt: null },
      select: {
        id: true,
        name: true,
        dateOfBirth: true,
        birthYear: true,
        isDeceased: true,
        gender: true,
        occupation: true,
        city: true,
        biography: true,
        generationIndex: true,
      },
      orderBy: { generationIndex: 'asc' },
    });

    // 3. Load Kinrel archetype
    const kinrel = await this.prisma.familyKinrel.findUnique({
      where: { familyId },
      select: {
        archetypeKey: true,
        memberCount: true,
        generationDepth: true,
        distinctLineages: true,
        languageDistribution: true,
      },
    });

    // 4. Load recent Sparqs (top 5 by recency)
    const familyMemberIds = await this.prisma.familyMember.findMany({
      where: { familyId },
      select: { userId: true },
    });
    const userIds = familyMemberIds.map((m) => m.userId);
    const recentSparqs = userIds.length > 0
      ? await this.prisma.sparq.findMany({
          where: { userId: { in: userIds } },
          orderBy: { createdAt: 'desc' },
          take: 5,
          select: { id: true, text: true, createdAt: true },
        })
      : [];

    // 5. Load ancestral memories (with consent check — only use if consent given)
    const memories = await this.prisma.ancestralMemory.findMany({
      where: { familyId, status: 'ready', isRevealed: true },
      orderBy: { createdAt: 'desc' },
      take: 5,
      select: { id: true, title: true, topic: true, aiSummary: true, createdAt: true },
    });

    // 6. Generate chapters
    const chapters = this.generateChapters({
      family,
      persons,
      kinrel,
      recentSparqs,
      memories,
    });

    // 7. Upsert the chronicle
    const existing = await this.prisma.familyChronicle.findUnique({
      where: { familyId },
    });

    const title = `The Chronicle of the ${family.name} Family`;
    const subtitle = this.generateSubtitle(family, kinrel, persons.length);

    const now = new Date();
    const nextMonth = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000);

    if (existing) {
      await this.prisma.familyChronicle.update({
        where: { id: existing.id },
        data: {
          title,
          subtitle,
          chapters: chapters as any,
          chapterCount: chapters.length,
          lastGeneratedAt: now,
          nextGenerationAt: nextMonth,
          aiModel: 'kinrel-template-v1',
        },
      });
      this.logger.log(
        `FamilyChronicle: updated chronicle for family ${familyId} (${chapters.length} chapters) in ${Date.now() - start}ms`,
      );
      return { chapterCount: chapters.length, isNew: false };
    } else {
      await this.prisma.familyChronicle.create({
        data: {
          familyId,
          title,
          subtitle,
          chapters: chapters as any,
          chapterCount: chapters.length,
          lastGeneratedAt: now,
          nextGenerationAt: nextMonth,
          aiModel: 'kinrel-template-v1',
        },
      });
      this.logger.log(
        `FamilyChronicle: created chronicle for family ${familyId} (${chapters.length} chapters) in ${Date.now() - start}ms`,
      );
      return { chapterCount: chapters.length, isNew: true };
    }
  }

  /** Get the chronicle for a family. */
  async getChronicle(familyId: string, userId: string) {
    // Verify family membership
    const fm = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId } },
      select: { id: true },
    });
    if (!fm) throw new Error('Not a family member');

    const chronicle = await this.prisma.familyChronicle.findUnique({
      where: { familyId },
    });
    if (!chronicle) return null;

    return {
      id: chronicle.id,
      familyId: chronicle.familyId,
      title: chronicle.title,
      subtitle: chronicle.subtitle,
      chapters: chronicle.chapters,
      chapterCount: chronicle.chapterCount,
      lastGeneratedAt: chronicle.lastGeneratedAt?.toISOString() ?? null,
      nextGenerationAt: chronicle.nextGenerationAt?.toISOString() ?? null,
      aiModel: chronicle.aiModel,
      createdAt: chronicle.createdAt.toISOString(),
      updatedAt: chronicle.updatedAt.toISOString(),
    };
  }

  /**
   * Monthly cron: generate/update chronicles for all families.
   */
  async generateAllChronicles(): Promise<{
    familiesProcessed: number;
    chroniclesUpdated: number;
    errors: string[];
  }> {
    const families = await this.prisma.family.findMany({
      where: { deletedAt: null },
      select: { id: true },
    });

    let chroniclesUpdated = 0;
    const errors: string[] = [];

    for (const fam of families) {
      try {
        await this.generateChronicle(fam.id);
        chroniclesUpdated++;
      } catch (err) {
        errors.push(`family ${fam.id}: ${err instanceof Error ? err.message : err}`);
      }
    }

    this.logger.log(
      `FamilyChronicle: monthly generation — ${chroniclesUpdated}/${families.length} chronicles updated (${errors.length} errors)`,
    );

    return {
      familiesProcessed: families.length,
      chroniclesUpdated,
      errors,
    };
  }

  // ────────────────────────────────────────────────────────────────────────
  // Chapter generation (template-based — replaceable with AI call later)
  // ────────────────────────────────────────────────────────────────────────

  private generateChapters(data: {
    family: any;
    persons: any[];
    kinrel: any;
    recentSparqs: any[];
    memories: any[];
  }): any[] {
    const chapters: any[] = [];
    const now = new Date().toISOString();

    // Group persons by generation
    const byGeneration = new Map<number, any[]>();
    for (const p of data.persons) {
      const gen = p.generationIndex ?? 0;
      if (!byGeneration.has(gen)) byGeneration.set(gen, []);
      byGeneration.get(gen)!.push(p);
    }
    const generations = Array.from(byGeneration.keys()).sort((a, b) => a - b);

    // Chapter 1: The Founding Generation (oldest generation)
    if (generations.length > 0) {
      const oldestGen = byGeneration.get(generations[0]) ?? [];
      const founders = oldestGen.filter((p) => !p.isDeceased);
      const ancestors = oldestGen.filter((p) => p.isDeceased);

      let content = `The ${data.family.name} family`;
      if (data.family.originVillage) {
        content += ` traces its roots to ${data.family.originVillage}`;
      }
      if (data.family.gotra) {
        content += ` and belongs to the ${data.family.gotra} gotra`;
      }
      content += '. ';

      if (ancestors.length > 0) {
        content += `The earliest known members of the family include ${ancestors.map((p) => p.name).join(', ')}. `;
        content += `Their stories live on through the memories and traditions they passed down. `;
      }
      if (founders.length > 0) {
        content += `The founding generation still with us includes ${founders.map((p) => p.name).join(', ')}. `;
        if (founders.some((p) => p.biography)) {
          const bio = founders.find((p) => p.biography);
          if (bio) content += `${bio.name}'s biography notes: "${bio.biography.slice(0, 200)}" `;
        }
      }
      content += `This generation laid the foundation for everything that followed.`;

      chapters.push({
        chapterNumber: 1,
        title: MONTHLY_CHAPTER_TITLES[0],
        content,
        generatedAt: now,
        sourceData: {
          generationIndex: generations[0],
          memberCount: oldestGen.length,
          founders: founders.map((p) => p.name),
          ancestors: ancestors.map((p) => p.name),
        },
      });
    }

    // Chapter 2: Growing the Family (middle generations)
    if (generations.length > 1) {
      const middleGens = generations.slice(1, -1);
      if (middleGens.length > 0) {
        let content = `As the family grew, new generations branched out. `;
        for (const gen of middleGens) {
          const members = byGeneration.get(gen) ?? [];
          content += `Generation ${gen + 1} includes ${members.map((p) => p.name).join(', ')}. `;
          const withOccupation = members.filter((p) => p.occupation);
          if (withOccupation.length > 0) {
            content += `${withOccupation.map((p) => `${p.name} (${p.occupation})`).join('; ')}. `;
          }
          const withCity = members.filter((p) => p.city);
          if (withCity.length > 0) {
            content += `Some settled in ${[...new Set(withCity.map((p) => p.city))].join(', ')}. `;
          }
        }
        content += `Each branch added its own story to the family tapestry.`;

        chapters.push({
          chapterNumber: 2,
          title: MONTHLY_CHAPTER_TITLES[1],
          content,
          generatedAt: now,
          sourceData: {
            generations: middleGens,
            memberCount: middleGens.reduce((sum, g) => sum + (byGeneration.get(g)?.length ?? 0), 0),
          },
        });
      }
    }

    // Chapter 3: The Current Generation (youngest generation)
    if (generations.length > 0) {
      const youngestGen = byGeneration.get(generations[generations.length - 1]) ?? [];
      let content = `The current generation — Generation ${generations[generations.length - 1] + 1} — includes ${youngestGen.map((p) => p.name).join(', ')}. `;
      content += `They carry the family forward, blending tradition with the modern world. `;
      const withOccupation = youngestGen.filter((p) => p.occupation);
      if (withOccupation.length > 0) {
        content += `${withOccupation.map((p) => `${p.name} is pursuing ${p.occupation}`).join('; ')}. `;
      }
      content += `The future of the ${data.family.name} family rests in their hands.`;

      chapters.push({
        chapterNumber: 3,
        title: MONTHLY_CHAPTER_TITLES[2],
        content,
        generatedAt: now,
        sourceData: {
          generationIndex: generations[generations.length - 1],
          memberCount: youngestGen.length,
        },
      });
    }

    // Chapter 4: Stories Worth Telling (Sparqs + memories)
    if (data.recentSparqs.length > 0 || data.memories.length > 0) {
      let content = `Every family has stories worth telling. Here are some from the ${data.family.name} family:\n\n`;

      if (data.memories.length > 0) {
        content += `**Ancestral Memories:**\n`;
        for (const m of data.memories) {
          content += `- "${m.title}"`;
          if (m.aiSummary) content += ` — ${m.aiSummary}`;
          content += `\n`;
        }
        content += `\n`;
      }

      if (data.recentSparqs.length > 0) {
        content += `**Recent Moments (Sparqs):**\n`;
        for (const s of data.recentSparqs) {
          if (s.text) {
            content += `- "${s.text.slice(0, 150)}${s.text.length > 150 ? '...' : ''}"\n`;
          }
        }
      }

      content += `\nThese moments, big and small, weave the ongoing story of the family.`;

      chapters.push({
        chapterNumber: 4,
        title: MONTHLY_CHAPTER_TITLES[3],
        content,
        generatedAt: now,
        sourceData: {
          sparqCount: data.recentSparqs.length,
          memoryCount: data.memories.length,
        },
      });
    }

    // Chapter 5: The Family Today (Kinrel archetype)
    if (data.kinrel) {
      // Global-launch fix: archetype descriptions updated to match the
      // renamed display names. The `banyan` archetype is now displayed
      // as "The Deep Root" (no longer references the sacred banyan
      // tree species) and the `lotus` archetype is now "The Radiant"
      // (no longer references the lotus flower). Internal keys are
      // unchanged for DB backward compatibility — only the prose
      // descriptions of what each archetype "is like" changed.
      const archetypeDescriptions: Record<string, string> = {
        banyan: 'a deep root — deeply grounded, with branches that reach wide and shelter many generations',
        river_delta: 'a river delta — multiple streams converging, bringing together different lineages and traditions',
        confluence: 'a confluence — where different families and cultures meet and merge into something new',
        spine: 'a spine — a strong central lineage with branches extending outward',
        lotus: 'a radiant center — centered and balanced, with each member playing a distinct role',
        forest: 'a forest — a diverse collection of individuals, each growing in their own direction yet connected underground',
      };
      const archetypeDesc = archetypeDescriptions[data.kinrel.archetypeKey] || 'a unique family structure';

      let content = `The ${data.family.name} family is ${archetypeDesc}. `;
      content += `With ${data.kinrel.memberCount} members across ${data.kinrel.generationDepth} generation${data.kinrel.generationDepth === 1 ? '' : 's'}, `;
      content += `the family spans ${data.kinrel.distinctLineages} distinct lineage${data.kinrel.distinctLineages === 1 ? '' : 's'}. `;

      const langDist = data.kinrel.languageDistribution as Record<string, number>;
      if (langDist && Object.keys(langDist).length > 0) {
        const langNames: Record<string, string> = {
          en: 'English', hi: 'Hindi', ta: 'Tamil', te: 'Telugu',
          kn: 'Kannada', mr: 'Marathi', gu: 'Gujarati', bn: 'Bengali',
        };
        const langs = Object.entries(langDist)
          .sort((a, b) => b[1] - a[1])
          .map(([code, ratio]) => `${langNames[code] || code} (${Math.round(ratio * 100)}%)`);
        content += `The family speaks ${langs.join(', ')}. `;
      }

      content += `This is what makes the ${data.family.name} family unique — not just who they are, but how they're connected.`;

      chapters.push({
        chapterNumber: 5,
        title: MONTHLY_CHAPTER_TITLES[4],
        content,
        generatedAt: now,
        sourceData: {
          archetype: data.kinrel.archetypeKey,
          memberCount: data.kinrel.memberCount,
          generationDepth: data.kinrel.generationDepth,
          distinctLineages: data.kinrel.distinctLineages,
        },
      });
    }

    return chapters;
  }

  private generateSubtitle(family: any, kinrel: any, memberCount: number): string {
    if (kinrel) {
      return `A story spanning ${kinrel.generationDepth} generation${kinrel.generationDepth === 1 ? '' : 's'}, with ${memberCount} members and ${kinrel.distinctLineages} lineage${kinrel.distinctLineages === 1 ? '' : 's'}.`;
    }
    return `A story of ${memberCount} family member${memberCount === 1 ? '' : 's'}.`;
  }
}
