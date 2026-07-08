// server/src/pitru/pitru.service.ts
//
// PitruService — core service for the Ancestral Voice Memory feature.
//
// Responsibilities:
//   1. createMemory() — record a new memory (URL uploaded by client first)
//   2. getMemory() / listMemories() — read queries
//   3. updateAiResults() — called by the AI pipeline (Whisper + GPT) when done
//   4. tagPerson() / untagPerson() — manage MemoryTag relationships
//   5. setConsent() — record consent for AI persona / voice cloning
//   6. createMemorialProfile() — when a Person is marked deceased
//   7. incrementListenCount() — engagement tracking
//
// All write methods verify family membership inline (no FamilyMemberGuard).
// All methods return JSON-serializable shapes (no Prisma model instances).

import {
  Injectable,
  Logger,
  ForbiddenException,
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

export interface CreateMemoryInput {
  familyId: string;
  recorderId: string;
  elderPersonId?: string | null;
  mediaType: 'audio' | 'video';
  mediaUrl: string;
  thumbnailUrl?: string | null;
  durationSec?: number;
  title: string;
  topic?: string | null;
  language?: string;
  description?: string | null;
  revealAt?: Date | null;
}

export interface UpdateAiResultsInput {
  transcript?: string;
  transcriptLanguage?: string;
  translation?: string;
  aiSummary?: string;
  aiTags?: string[];
  aiProcessingError?: string;
  status?: 'pending' | 'processing' | 'ready' | 'failed' | 'archived';
}

export type ConsentType =
  | 'ai_persona'
  | 'voice_cloning'
  | 'public_memorial'
  | 'cross_family_share';

// ─────────────────────────────────────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────────────────────────────────────

@Injectable()
export class PitruService {
  private readonly logger = new Logger(PitruService.name);

  constructor(private readonly prisma: PrismaService) {}

  // ────────────────────────────────────────────────────────────────────────
  // Create + read
  // ────────────────────────────────────────────────────────────────────────

  /**
   * Create a new ancestral memory record.
   * The client is responsible for uploading the media to Supabase Storage
   * first and passing the resulting URL here.
   */
  async createMemory(input: CreateMemoryInput) {
    // Verify family membership
    await this.assertFamilyMember(input.recorderId, input.familyId);

    // Verify elderPersonId belongs to this family (if provided)
    if (input.elderPersonId) {
      const elder = await this.prisma.person.findUnique({
        where: { id: input.elderPersonId },
        select: { familyId: true, isDeceased: true, deletedAt: true },
      });
      if (!elder || elder.deletedAt) {
        throw new NotFoundException('Elder person not found');
      }
      if (elder.familyId !== input.familyId) {
        throw new ForbiddenException('Elder person is not in this family');
      }
    }

    // Determine isRevealed based on revealAt
    const isRevealed = !input.revealAt || input.revealAt <= new Date();

    const memory = await this.prisma.ancestralMemory.create({
      data: {
        familyId: input.familyId,
        recorderId: input.recorderId,
        elderPersonId: input.elderPersonId ?? null,
        mediaType: input.mediaType,
        mediaUrl: input.mediaUrl,
        thumbnailUrl: input.thumbnailUrl ?? null,
        durationSec: input.durationSec ?? 0,
        title: input.title,
        topic: input.topic ?? null,
        language: input.language ?? 'en',
        description: input.description ?? null,
        revealAt: input.revealAt ?? null,
        isRevealed,
        status: 'pending',
      },
      include: {
        elderPerson: { select: { id: true, name: true, photoThumb: true } },
        recorder: { select: { id: true, name: true } },
        tags: { include: { person: { select: { id: true, name: true, photoThumb: true } } } },
      },
    });

    this.logger.log(
      `Pitru: created memory "${input.title}" (id=${memory.id}) for family ${input.familyId}`,
    );

    // If elderPersonId is set, auto-tag the elder as "about"
    if (input.elderPersonId) {
      await this.prisma.memoryTag.create({
        data: {
          memoryId: memory.id,
          personId: input.elderPersonId,
          taggedById: input.recorderId,
          tagType: 'about',
        },
      });
    }

    return this.serializeMemory(memory);
  }

  async getMemory(memoryId: string, userId: string) {
    const memory = await this.prisma.ancestralMemory.findUnique({
      where: { id: memoryId },
      include: {
        elderPerson: { select: { id: true, name: true, photoThumb: true } },
        recorder: { select: { id: true, name: true } },
        tags: { include: { person: { select: { id: true, name: true, photoThumb: true } } } },
      },
    });
    if (!memory) throw new NotFoundException('Memory not found');

    // Verify family membership
    await this.assertFamilyMember(userId, memory.familyId);

    return this.serializeMemory(memory);
  }

  /**
   * List memories for a family. Optional filters: elderPersonId, topic, status.
   * Only returns revealed memories (unless includeUnrevealed=true).
   */
  async listMemories(
    userId: string,
    familyId: string,
    opts: {
      elderPersonId?: string;
      topic?: string;
      status?: string;
      includeUnrevealed?: boolean;
      limit?: number;
      offset?: number;
    } = {},
  ) {
    await this.assertFamilyMember(userId, familyId);

    const limit = Math.min(opts.limit ?? 50, 100);
    const offset = opts.offset ?? 0;

    const memories = await this.prisma.ancestralMemory.findMany({
      where: {
        familyId,
        ...(opts.elderPersonId ? { elderPersonId: opts.elderPersonId } : {}),
        ...(opts.topic ? { topic: opts.topic } : {}),
        ...(opts.status ? { status: opts.status } : {}),
        ...(opts.includeUnrevealed ? {} : { isRevealed: true }),
      },
      orderBy: { createdAt: 'desc' },
      take: limit,
      skip: offset,
      include: {
        elderPerson: { select: { id: true, name: true, photoThumb: true } },
        recorder: { select: { id: true, name: true } },
        tags: { include: { person: { select: { id: true, name: true, photoThumb: true } } } },
      },
    });

    return memories.map((m) => this.serializeMemory(m));
  }

  // ────────────────────────────────────────────────────────────────────────
  // AI pipeline integration
  // ────────────────────────────────────────────────────────────────────────

  /**
   * Update a memory with AI processing results.
   * Called by the AI pipeline (Whisper transcription + GPT translation/summary).
   * In Phase 1, this is called manually — Phase 5 will wire it to a queue.
   */
  async updateAiResults(memoryId: string, update: UpdateAiResultsInput) {
    const memory = await this.prisma.ancestralMemory.findUnique({
      where: { id: memoryId },
      select: { id: true, status: true },
    });
    if (!memory) throw new NotFoundException('Memory not found');

    const updated = await this.prisma.ancestralMemory.update({
      where: { id: memoryId },
      data: {
        ...(update.transcript !== undefined ? { transcript: update.transcript } : {}),
        ...(update.transcriptLanguage !== undefined
          ? { transcriptLanguage: update.transcriptLanguage }
          : {}),
        ...(update.translation !== undefined ? { translation: update.translation } : {}),
        ...(update.aiSummary !== undefined ? { aiSummary: update.aiSummary } : {}),
        ...(update.aiTags !== undefined ? { aiTags: update.aiTags } : {}),
        ...(update.aiProcessingError !== undefined
          ? { aiProcessingError: update.aiProcessingError }
          : {}),
        ...(update.status !== undefined
          ? {
              status: update.status,
              ...(update.status === 'ready' || update.status === 'failed'
                ? { aiProcessedAt: new Date() }
                : {}),
            }
          : {}),
      },
      include: {
        elderPerson: { select: { id: true, name: true, photoThumb: true } },
        recorder: { select: { id: true, name: true } },
        tags: { include: { person: { select: { id: true, name: true, photoThumb: true } } } },
      },
    });

    this.logger.log(
      `Pitru: updated AI results for memory ${memoryId} (status=${update.status ?? memory.status})`,
    );

    return this.serializeMemory(updated);
  }

  // ────────────────────────────────────────────────────────────────────────
  // Tagging
  // ────────────────────────────────────────────────────────────────────────

  /**
   * Tag a Person in a memory. Creates a MemoryTag row.
   * Idempotent: if the tag already exists (same memory+person+type), returns OK.
   */
  async tagPerson(
    memoryId: string,
    personId: string,
    taggedById: string,
    tagType: 'mentions' | 'about' | 'recorded_by' | 'featured' = 'mentions',
  ) {
    const memory = await this.prisma.ancestralMemory.findUnique({
      where: { id: memoryId },
      select: { familyId: true },
    });
    if (!memory) throw new NotFoundException('Memory not found');

    await this.assertFamilyMember(taggedById, memory.familyId);

    // Verify personId belongs to this family
    const person = await this.prisma.person.findUnique({
      where: { id: personId },
      select: { familyId: true, deletedAt: true },
    });
    if (!person || person.deletedAt) {
      throw new NotFoundException('Person not found');
    }
    if (person.familyId !== memory.familyId) {
      throw new ForbiddenException('Person is not in this family');
    }

    // Upsert (idempotent — the @@unique([memoryId, personId, tagType]) handles dups)
    const tag = await this.prisma.memoryTag.upsert({
      where: {
        memoryId_personId_tagType: { memoryId, personId, tagType },
      },
      create: { memoryId, personId, taggedById, tagType },
      update: { taggedById }, // update who applied the tag
    });

    return { id: tag.id, memoryId, personId, tagType, taggedAt: tag.taggedAt.toISOString() };
  }

  async untagPerson(memoryId: string, personId: string, tagType: string, userId: string) {
    const memory = await this.prisma.ancestralMemory.findUnique({
      where: { id: memoryId },
      select: { familyId: true },
    });
    if (!memory) throw new NotFoundException('Memory not found');
    await this.assertFamilyMember(userId, memory.familyId);

    await this.prisma.memoryTag.deleteMany({
      where: { memoryId, personId, tagType },
    });

    return { ok: true };
  }

  // ────────────────────────────────────────────────────────────────────────
  // Consent
  // ────────────────────────────────────────────────────────────────────────

  /**
   * Set consent for an elder Person. CRITICAL: AI persona features require
   * explicit consent — without it, they are disabled.
   */
  async setConsent(
    elderPersonId: string,
    consentType: ConsentType,
    consentGiven: boolean,
    consentedById: string,
    notes?: string,
  ) {
    const elder = await this.prisma.person.findUnique({
      where: { id: elderPersonId },
      select: { familyId: true, deletedAt: true },
    });
    if (!elder || elder.deletedAt) {
      throw new NotFoundException('Elder person not found');
    }
    await this.assertFamilyMember(consentedById, elder.familyId);

    const consent = await this.prisma.memoryConsent.upsert({
      where: {
        elderPersonId_consentType: { elderPersonId, consentType },
      },
      create: {
        familyId: elder.familyId,
        elderPersonId,
        consentType,
        consentGiven,
        consentedById,
        consentedAt: consentGiven ? new Date() : null,
        consentNotes: notes,
      },
      update: {
        consentGiven,
        consentedById,
        consentedAt: consentGiven ? new Date() : null,
        consentNotes: notes,
      },
    });

    this.logger.log(
      `Pitru: consent ${consentGiven ? 'GRANTED' : 'REVOKED'} for elder ${elderPersonId} (${consentType})`,
    );

    return {
      id: consent.id,
      elderPersonId,
      consentType,
      consentGiven,
      consentedAt: consent.consentedAt?.toISOString() ?? null,
    };
  }

  async getConsents(elderPersonId: string, userId: string) {
    const elder = await this.prisma.person.findUnique({
      where: { id: elderPersonId },
      select: { familyId: true },
    });
    if (!elder) throw new NotFoundException('Elder person not found');
    await this.assertFamilyMember(userId, elder.familyId);

    const consents = await this.prisma.memoryConsent.findMany({
      where: { elderPersonId },
    });
    return consents.map((c) => ({
      id: c.id,
      consentType: c.consentType,
      consentGiven: c.consentGiven,
      consentedAt: c.consentedAt?.toISOString() ?? null,
      consentExpiresAt: c.consentExpiresAt?.toISOString() ?? null,
      consentNotes: c.consentNotes,
    }));
  }

  // ────────────────────────────────────────────────────────────────────────
  // Memorial
  // ────────────────────────────────────────────────────────────────────────

  /**
   * Create a memorial profile for a deceased Person.
   * The Person must have isDeceased=true.
   * If aiPersonaEnabled=true, the elder must have MemoryConsent ai_persona granted.
   */
  async createMemorialProfile(
    personId: string,
    input: {
      memorialTitle?: string;
      memorialBio?: string;
      birthDate?: Date;
      deathDate?: Date;
      coverPhotoUrl?: string;
      isPublic?: boolean;
      allowMessages?: boolean;
      aiPersonaEnabled?: boolean;
    },
    createdById: string,
  ) {
    const person = await this.prisma.person.findUnique({
      where: { id: personId },
      select: { familyId: true, isDeceased: true, deletedAt: true },
    });
    if (!person || person.deletedAt) {
      throw new NotFoundException('Person not found');
    }
    if (!person.isDeceased) {
      throw new BadRequestException(
        'Memorial profiles can only be created for deceased Persons',
      );
    }
    await this.assertFamilyMember(createdById, person.familyId);

    // If aiPersonaEnabled, verify consent
    if (input.aiPersonaEnabled) {
      const consent = await this.prisma.memoryConsent.findUnique({
        where: {
          elderPersonId_consentType: {
            elderPersonId: personId,
            consentType: 'ai_persona',
          },
        },
      });
      if (!consent || !consent.consentGiven) {
        throw new BadRequestException(
          'AI persona cannot be enabled without explicit ai_persona consent from the elder (or their family)',
        );
      }
    }

    const profile = await this.prisma.memorialProfile.upsert({
      where: { personId },
      create: {
        familyId: person.familyId,
        personId,
        memorialTitle: input.memorialTitle ?? null,
        memorialBio: input.memorialBio ?? null,
        birthDate: input.birthDate ?? null,
        deathDate: input.deathDate ?? null,
        coverPhotoUrl: input.coverPhotoUrl ?? null,
        isPublic: input.isPublic ?? false,
        allowMessages: input.allowMessages ?? true,
        aiPersonaEnabled: input.aiPersonaEnabled ?? false,
      },
      update: {
        memorialTitle: input.memorialTitle ?? undefined,
        memorialBio: input.memorialBio ?? undefined,
        birthDate: input.birthDate ?? undefined,
        deathDate: input.deathDate ?? undefined,
        coverPhotoUrl: input.coverPhotoUrl ?? undefined,
        isPublic: input.isPublic ?? undefined,
        allowMessages: input.allowMessages ?? undefined,
        aiPersonaEnabled: input.aiPersonaEnabled ?? undefined,
      },
    });

    this.logger.log(`Pitru: created memorial profile for person ${personId}`);

    return {
      id: profile.id,
      personId,
      familyId: profile.familyId,
      memorialTitle: profile.memorialTitle,
      memorialBio: profile.memorialBio,
      birthDate: profile.birthDate?.toISOString().slice(0, 10) ?? null,
      deathDate: profile.deathDate?.toISOString().slice(0, 10) ?? null,
      coverPhotoUrl: profile.coverPhotoUrl,
      isPublic: profile.isPublic,
      allowMessages: profile.allowMessages,
      aiPersonaEnabled: profile.aiPersonaEnabled,
    };
  }

  /**
   * Get a memorial profile for a deceased Person.
   * Returns the profile + the Person's basic info + memory count.
   * If isPublic=true, any authenticated user can view; otherwise family members only.
   */
  async getMemorialProfile(personId: string, userId: string) {
    const profile = await this.prisma.memorialProfile.findUnique({
      where: { personId },
      include: {
        person: {
          select: {
            id: true,
            name: true,
            photoThumb: true,
            photoFull: true,
            dateOfBirth: true,
            biography: true,
            familyId: true,
          },
        },
      },
    });

    if (!profile) {
      throw new NotFoundException('No memorial profile for this Person');
    }

    // Access check: if not public, verify family membership
    if (!profile.isPublic) {
      await this.assertFamilyMember(userId, profile.familyId);
    }

    // Count the deceased Person's memories
    const memoryCount = await this.prisma.ancestralMemory.count({
      where: {
        elderPersonId: personId,
        status: 'ready',
        isRevealed: true,
      },
    });

    // Count family members who left messages (BriefInteraction with itemType memory_orbit
    // targeting this Person — a proxy for "how many people listened")
    const listenerCount = await this.prisma.ancestralMemory.aggregate({
      where: { elderPersonId: personId },
      _sum: { listenCount: true },
    });

    return {
      id: profile.id,
      personId: profile.personId,
      familyId: profile.familyId,
      memorialTitle: profile.memorialTitle,
      memorialBio: profile.memorialBio ?? profile.person.biography,
      birthDate: profile.birthDate?.toISOString().slice(0, 10) ?? null,
      deathDate: profile.deathDate?.toISOString().slice(0, 10) ?? null,
      coverPhotoUrl: profile.coverPhotoUrl,
      isPublic: profile.isPublic,
      allowMessages: profile.allowMessages,
      aiPersonaEnabled: profile.aiPersonaEnabled,
      person: {
        id: profile.person.id,
        name: profile.person.name,
        photoThumb: profile.person.photoThumb,
        photoFull: profile.person.photoFull,
      },
      memoryCount,
      totalListens: listenerCount._sum.listenCount ?? 0,
    };
  }

  /**
   * Get the memorial feed — all memories for a deceased Person, plus the
   * memorial profile info. This is the data for the memorial page in Flutter.
   */
  async getMemorialFeed(personId: string, userId: string) {
    const profile = await this.getMemorialProfile(personId, userId);

    const memories = await this.prisma.ancestralMemory.findMany({
      where: {
        elderPersonId: personId,
        status: 'ready',
        isRevealed: true,
      },
      orderBy: { createdAt: 'desc' },
      include: {
        tags: { include: { person: { select: { id: true, name: true, photoThumb: true } } } },
      },
    });

    return {
      memorial: profile,
      memories: memories.map((m) => this.serializeMemory(m)),
    };
  }

  /**
   * List all memorial profiles in a family. Used by the Flutter "In Memoriam" section.
   */
  async listMemorials(familyId: string, userId: string) {
    await this.assertFamilyMember(userId, familyId);

    const profiles = await this.prisma.memorialProfile.findMany({
      where: { familyId },
      orderBy: { createdAt: 'desc' },
      include: {
        person: {
          select: {
            id: true,
            name: true,
            photoThumb: true,
            dateOfBirth: true,
          },
        },
      },
    });

    return Promise.all(
      profiles.map(async (p) => {
        const memoryCount = await this.prisma.ancestralMemory.count({
          where: {
            elderPersonId: p.personId,
            status: 'ready',
            isRevealed: true,
          },
        });
        return {
          id: p.id,
          personId: p.personId,
          personName: p.person.name,
          personPhoto: p.person.photoThumb,
          memorialTitle: p.memorialTitle ?? `In loving memory of ${p.person.name}`,
          birthDate: p.birthDate?.toISOString().slice(0, 10) ?? null,
          deathDate: p.deathDate?.toISOString().slice(0, 10) ?? null,
          isPublic: p.isPublic,
          aiPersonaEnabled: p.aiPersonaEnabled,
          memoryCount,
        };
      }),
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // Engagement
  // ────────────────────────────────────────────────────────────────────────

  /** Increment listen count + update lastListenedAt. Called when a user plays a memory. */
  async incrementListenCount(memoryId: string, userId: string): Promise<{ listenCount: number }> {
    const memory = await this.prisma.ancestralMemory.findUnique({
      where: { id: memoryId },
      select: { familyId: true },
    });
    if (!memory) throw new NotFoundException('Memory not found');
    await this.assertFamilyMember(userId, memory.familyId);

    const updated = await this.prisma.ancestralMemory.update({
      where: { id: memoryId },
      data: {
        listenCount: { increment: 1 },
        lastListenedAt: new Date(),
      },
      select: { listenCount: true },
    });

    return { listenCount: updated.listenCount };
  }

  // ────────────────────────────────────────────────────────────────────────
  // Helpers
  // ────────────────────────────────────────────────────────────────────────

  private async assertFamilyMember(userId: string, familyId: string): Promise<void> {
    const fm = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId } },
      select: { id: true },
    });
    if (!fm) {
      throw new ForbiddenException('User is not a member of this family');
    }
  }

  private serializeMemory(m: any) {
    return {
      id: m.id,
      familyId: m.familyId,
      recorderId: m.recorderId,
      recorder: m.recorder
        ? { id: m.recorder.id, name: m.recorder.name }
        : null,
      elderPersonId: m.elderPersonId,
      elderPerson: m.elderPerson
        ? {
            id: m.elderPerson.id,
            name: m.elderPerson.name,
            photoThumb: m.elderPerson.photoThumb,
          }
        : null,
      mediaType: m.mediaType,
      mediaUrl: m.mediaUrl,
      thumbnailUrl: m.thumbnailUrl,
      durationSec: m.durationSec,
      title: m.title,
      topic: m.topic,
      language: m.language,
      description: m.description,
      transcript: m.transcript,
      transcriptLanguage: m.transcriptLanguage,
      translation: m.translation,
      aiSummary: m.aiSummary,
      aiTags: m.aiTags,
      aiProcessedAt: m.aiProcessedAt?.toISOString() ?? null,
      aiProcessingError: m.aiProcessingError,
      status: m.status,
      isPublic: m.isPublic,
      revealAt: m.revealAt?.toISOString() ?? null,
      isRevealed: m.isRevealed,
      viewCount: m.viewCount,
      listenCount: m.listenCount,
      lastListenedAt: m.lastListenedAt?.toISOString() ?? null,
      createdAt: m.createdAt.toISOString(),
      updatedAt: m.updatedAt.toISOString(),
      tags: (m.tags ?? []).map((t: any) => ({
        id: t.id,
        personId: t.personId,
        tagType: t.tagType,
        taggedAt: t.taggedAt.toISOString(),
        person: t.person
          ? {
              id: t.person.id,
              name: t.person.name,
              photoThumb: t.person.photoThumb,
            }
          : null,
      })),
    };
  }
}
