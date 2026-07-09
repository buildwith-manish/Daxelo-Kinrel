// =============================================================================
// Track C v2.0 — AURA Governance: Constitution
// constitution.service.ts
// =============================================================================
// Implements Section 10.1 (constitution lifecycle) + Section 6.2 endpoints.
//
// Lifecycle: Draft → In Review → Published (v1) → [Amendment Decision] → Published (v2) → ...
// Each version is immutable once published.
// Amendments are themselves FamilyDecision rows with type='constitution_amend'.
// =============================================================================

import {
  Injectable,
  NotFoundException,
  BadRequestException,
  ForbiddenException,
  Logger,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { TimelineEmitter } from '../governance-timeline/timeline.emitter';
import { FamilyMembershipService } from '../common/family-membership.service';
import { Prisma } from '@prisma/client';

export interface DraftArticleInput {
  title: string;
  intent?: string;
  clauses: { text: string; intent?: string; orderIndex?: number }[];
  orderIndex?: number;
}

export interface DraftConstitutionInput {
  title: string;
  preamble?: string;
  articles: DraftArticleInput[];
}

@Injectable()
export class ConstitutionService {
  private readonly logger = new Logger(ConstitutionService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly emitter: TimelineEmitter,
    private readonly membership: FamilyMembershipService,
  ) {}

  /**
   * Get the family's constitution (current published version + draft if exists).
   */
  async getConstitution(familyId: string) {
    let constitution = await this.prisma.familyConstitution.findUnique({
      where: { familyId },
      include: {
        currentVersion: {
          include: {
            articles: { orderBy: { orderIndex: 'asc' }, include: { clauses: { orderBy: { orderIndex: 'asc' } } } },
          },
        },
        draftVersion: {
          include: {
            articles: { orderBy: { orderIndex: 'asc' }, include: { clauses: { orderBy: { orderIndex: 'asc' } } } },
          },
        },
      },
    });

    if (!constitution) {
      // Auto-create an empty constitution shell if none exists.
      constitution = await this.prisma.familyConstitution.create({
        data: { familyId, title: 'Family Constitution', status: 'draft' },
        include: { currentVersion: { include: { articles: { include: { clauses: true } } } }, draftVersion: { include: { articles: { include: { clauses: true } } } } },
      });
    }

    return constitution;
  }

  /**
   * Create or update the draft version of the constitution.
   * Admin-only.
   */
  async saveDraft(
    familyId: string,
    actorId: string,
    input: DraftConstitutionInput,
  ) {
    await this.membership.requireAdmin(actorId, familyId);

    if (!input.articles?.length) {
      throw new BadRequestException('Constitution must have at least one article');
    }

    const constitution = await this.getConstitution(familyId);

    return this.prisma.$transaction(async (tx) => {
      // Determine next version number
      const existingVersions = await tx.constitutionVersion.count({
        where: { constitutionId: constitution.id },
      });
      const versionNumber = existingVersions + 1;

      // Delete existing draft (if any) — drafts are mutable
      if (constitution.draftVersionId) {
        await tx.constitutionVersion.delete({
          where: { id: constitution.draftVersionId },
        });
      }

      // Create new draft version with articles + clauses
      const draft = await tx.constitutionVersion.create({
        data: {
          constitutionId: constitution.id,
          familyId,
          versionNumber,
          status: 'draft',
          articleCount: input.articles.length,
          clauseCount: input.articles.reduce((acc, a) => acc + a.clauses.length, 0),
          articles: {
            create: input.articles.map((article, ai) => ({
              familyId,
              orderIndex: article.orderIndex ?? ai,
              title: article.title,
              intent: article.intent ?? null,
              clauses: {
                create: article.clauses.map((clause, ci) => ({
                  familyId,
                  orderIndex: clause.orderIndex ?? ci,
                  text: clause.text,
                  intent: clause.intent ?? null,
                })) as any,
              },
            })) as any,
          },
        },
        include: {
          articles: { orderBy: { orderIndex: 'asc' }, include: { clauses: { orderBy: { orderIndex: 'asc' } } } },
        },
      });

      // Point the constitution's draftVersionId to the new draft
      await tx.familyConstitution.update({
        where: { familyId },
        data: {
          draftVersionId: draft.id,
          title: input.title,
          preamble: input.preamble ?? constitution.preamble,
          status: 'in_review',
        },
      });

      return draft;
    });
  }

  /**
   * Publish the current draft. Makes the version immutable.
   * Admin-only.
   */
  async publish(familyId: string, actorId: string, changeSummary?: string) {
    await this.membership.requireAdmin(actorId, familyId);

    const constitution = await this.getConstitution(familyId);
    if (!constitution.draftVersionId) {
      throw new BadRequestException('No draft to publish. Create or edit a draft first.');
    }

    const draft = await this.prisma.constitutionVersion.findUnique({
      where: { id: constitution.draftVersionId },
      include: { articles: { include: { clauses: true } } },
    });
    if (!draft) throw new NotFoundException('Draft version not found');

    // Edge case #12: Constitution published with zero articles — rejected
    if (!draft.articles.length) {
      throw new BadRequestException('Cannot publish a constitution with zero articles');
    }

    return this.prisma.$transaction(async (tx) => {
      // Mark the previous published version as superseded
      if (constitution.currentVersionId) {
        await tx.constitutionVersion.update({
          where: { id: constitution.currentVersionId },
          data: { status: 'superseded' },
        });
      }

      // Promote draft to published
      const published = await tx.constitutionVersion.update({
        where: { id: draft.id },
        data: {
          status: 'published',
          publishedAt: new Date(),
          publishedById: actorId,
          changeSummary,
        },
      });

      // Update constitution pointers
      await tx.familyConstitution.update({
        where: { familyId },
        data: {
          currentVersionId: published.id,
          draftVersionId: null,
          status: 'published',
        },
      });

      // Emit timeline event
      const isFirstPublication = !constitution.currentVersionId;
      await this.emitter.append({
        familyId,
        kind: isFirstPublication ? 'constitution_created' : 'constitution_amended',
        actorId,
        targetEntityType: 'ConstitutionVersion',
        targetEntityId: published.id,
        title: isFirstPublication
          ? 'Family constitution established'
          : 'Family constitution amended',
        description: changeSummary ?? `Published version ${published.versionNumber}`,
        payload: isFirstPublication
          ? { versionId: published.id, articleCount: published.articleCount }
          : {
              fromVersionId: constitution.currentVersionId,
              toVersionId: published.id,
              changeCount: published.articleCount,
              decisionId: null,
            },
      });

      // Always emit the version_published event too
      await this.emitter.append({
        familyId,
        kind: 'constitution_version_published',
        actorId,
        targetEntityType: 'ConstitutionVersion',
        targetEntityId: published.id,
        title: `Constitution v${published.versionNumber} published`,
        payload: {
          versionId: published.id,
          articleCount: published.articleCount,
          clauseCount: published.clauseCount,
        },
      });

      return published;
    });
  }

  /**
   * List all versions of the constitution (published + drafts + superseded).
   */
  async listVersions(familyId: string) {
    const constitution = await this.getConstitution(familyId);
    return this.prisma.constitutionVersion.findMany({
      where: { constitutionId: constitution.id },
      orderBy: { versionNumber: 'desc' },
      include: {
        articles: { orderBy: { orderIndex: 'asc' }, select: { id: true, title: true, orderIndex: true } },
      },
    });
  }

  async getVersion(familyId: string, versionId: string) {
    const version = await this.prisma.constitutionVersion.findUnique({
      where: { id: versionId },
      include: {
        articles: {
          orderBy: { orderIndex: 'asc' },
          include: { clauses: { orderBy: { orderIndex: 'asc' } } },
        },
      },
    });
    if (!version || version.familyId !== familyId) {
      throw new NotFoundException('Version not found');
    }
    return version;
  }

  /**
   * Open an amendment decision. Creates a FamilyDecision with type='constitution_amend'.
   * The amendment is applied only if the decision resolves with supermajority.
   */
  async openAmendment(
    familyId: string,
    actorId: string,
    params: {
      title: string;
      description: string;
      changeSummary: string;
      deadlineAt: string; // ISO
      quorumPct?: number; // default 67 (supermajority per Section 10.2)
    },
  ) {
    await this.membership.requireAdmin(actorId, familyId);

    const constitution = await this.getConstitution(familyId);
    if (!constitution.currentVersionId) {
      throw new BadRequestException('Cannot amend — no published constitution. Publish v1 first.');
    }

    const deadline = new Date(params.deadlineAt);
    if (deadline <= new Date()) {
      throw new BadRequestException('Deadline must be in the future (edge case #7)');
    }

    if (params.quorumPct !== undefined && (params.quorumPct < 67 || params.quorumPct > 100)) {
      throw new BadRequestException('Constitution amendment requires ≥67% quorum');
    }

    // Eligible voters: all active members
    const eligibleUserIds = await this.membership.getActiveMemberUserIds(familyId);
    if (!eligibleUserIds.length) {
      throw new BadRequestException('No eligible voters in family');
    }

    const decision = await this.prisma.familyDecision.create({
      data: {
        familyId,
        createdById: actorId,
        title: params.title,
        description: params.description,
        type: 'constitution_amend',
        status: 'open',
        options: ['approve', 'reject'],
        eligibleUserIds,
        quorumPct: params.quorumPct ?? 67,
        showVotesLive: false,
        deadlineAt: deadline,
        constitutionVersionId: constitution.currentVersionId,
      },
    });

    await this.emitter.append({
      familyId,
      kind: 'decision_created',
      actorId,
      targetEntityType: 'FamilyDecision',
      targetEntityId: decision.id,
      title: `Amendment proposed: ${params.title}`,
      payload: { decisionId: decision.id, type: 'constitution_amend', deadlineAt: deadline.toISOString() },
    });

    return decision;
  }
}
