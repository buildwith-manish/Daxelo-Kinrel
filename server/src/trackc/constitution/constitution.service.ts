// =============================================================================
// Track C v2.0 — Kinrel Governance: Constitution
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
import { VisibilityService } from '../common/visibility.service';
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
    private readonly visibility: VisibilityService,
  ) {}

  /**
   * Get the family's constitution (current published version + draft if exists).
   */
  async getConstitution(familyId: string, userId: string) {
    // Security: verify family membership before returning data
    await this.membership.requireMember(userId, familyId);

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
   *
   * VISIBILITY MATRIX: edit/propose amendment is restricted to
   * 'owner' | 'admin' | 'elder' | 'member' (non-viewer) AND non-minor.
   * Previously this was admin-only; the matrix expands it to any
   * active non-viewer role (so elders and members can draft too),
   * while still blocking viewers and minors.
   */
  async saveDraft(
    familyId: string,
    actorId: string,
    input: DraftConstitutionInput,
  ) {
    await this.visibility.requireCanAct(actorId, familyId);

    if (!input.articles?.length) {
      throw new BadRequestException('Constitution must have at least one article');
    }

    const constitution = await this.getConstitution(familyId, actorId);

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

      // Create new draft version first (without nested articles)
      const draft = await tx.constitutionVersion.create({
        data: {
          constitutionId: constitution.id,
          familyId,
          versionNumber,
          status: 'draft',
          articleCount: input.articles.length,
          clauseCount: input.articles.reduce((acc, a) => acc + a.clauses.length, 0),
        },
      });

      // Create articles + clauses separately (avoids Prisma nested create type issues)
      for (let ai = 0; ai < input.articles.length; ai++) {
        const article = input.articles[ai];
        const createdArticle = await tx.constitutionArticle.create({
          data: {
            versionId: draft.id,
            familyId,
            orderIndex: article.orderIndex ?? ai,
            title: article.title,
            intent: article.intent ?? null,
          },
        });

        for (let ci = 0; ci < article.clauses.length; ci++) {
          const clause = article.clauses[ci];
          await tx.constitutionClause.create({
            data: {
              articleId: createdArticle.id,
              versionId: draft.id,
              familyId,
              orderIndex: clause.orderIndex ?? ci,
              text: clause.text,
              intent: clause.intent ?? null,
            },
          });
        }
      }

      // Re-fetch with relations
      const draftWithRelations = await tx.constitutionVersion.findUnique({
        where: { id: draft.id },
        include: {
          articles: {
            orderBy: { orderIndex: 'asc' },
            include: { clauses: { orderBy: { orderIndex: 'asc' } } },
          },
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

      return draftWithRelations;
    });
  }

  /**
   * Publish the current draft. Makes the version immutable.
   *
   * VISIBILITY MATRIX: publish is restricted to 'owner' | 'admin' | 'elder' |
   * 'member' (non-viewer) AND non-minor. The matrix treats publish the same
   * as saveDraft — any active member can publish their draft. (The
   * immutability of published versions + the timeline audit log provide
   * the safety net.)
   */
  async publish(familyId: string, actorId: string, changeSummary?: string) {
    await this.visibility.requireCanAct(actorId, familyId);

    const constitution = await this.getConstitution(familyId, actorId);
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
  async listVersions(familyId: string, userId: string) {
    await this.membership.requireMember(userId, familyId);
    const constitution = await this.getConstitution(familyId, userId);
    return this.prisma.constitutionVersion.findMany({
      where: { constitutionId: constitution.id },
      orderBy: { versionNumber: 'desc' },
      include: {
        articles: { orderBy: { orderIndex: 'asc' }, select: { id: true, title: true, orderIndex: true } },
      },
    });
  }

  async getVersion(familyId: string, versionId: string, userId: string) {
    await this.membership.requireMember(userId, familyId);
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
   *
   * VISIBILITY MATRIX: proposing an amendment is restricted to
   * 'owner' | 'admin' | 'elder' | 'member' (non-viewer) AND non-minor.
   * Voting on the amendment goes through DecisionsService.vote which
   * applies the same requireCanAct check.
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
    await this.visibility.requireCanAct(actorId, familyId);

    const constitution = await this.getConstitution(familyId, actorId);
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

    // Lock the constitution while the amendment vote is open: status moves to in_review
    // (the existence of a non-null draftVersionId is the de-facto "lock" indicator —
    // Section 5.2 of the spec. We also flip the constitution status so the UI can
    // surface "amendment in progress" without needing to query the decision table.)
    await this.prisma.familyConstitution.update({
      where: { familyId },
      data: { status: 'in_review' },
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

  // ===========================================================================
  // Amendment resolution hooks (called by DecisionsService.resolve / expire)
  //
  // These methods implement the "lock release" side of the constitution_amend
  // workflow. They are invoked by DecisionsService when a constitution_amend
  // decision resolves:
  //   - approved  → commitAmendment() promotes the draft to published
  //   - rejected  → discardDraft() deletes the draft and clears the lock
  //   - expired   → discardDraft() same as rejected
  //
  // Both methods are designed to be safe to call from inside a NestJS
  // $transaction callback: they perform their writes against the *same* `tx`
  // if one is passed, otherwise they use a fresh transaction. Failures are
  // allowed to bubble: the caller wraps the call so that a commit/discard
  // failure does not leave the decision resolved but the constitution still
  // locked.
  // ===========================================================================

  /**
   * Promote the current draft version to published, superseding the previous
   * published version. Emits a `constitution_amended` timeline event on
   * success (best-effort — never throws from the emitter).
   *
   * @param familyId The family whose constitution is being amended.
   * @param constitutionVersionId The version ID stored on the decision row
   *   (i.e. the *previous* published version that's being superseded). Used
   *   only for verification — the version that gets promoted is the family's
   *   current `draftVersionId`, not this ID.
   * @param actorId The user who triggered the resolution (or null for the
   *   pg-boss auto-expire path). Used for the `publishedById` audit column.
   * @param tx Optional transaction client. If omitted, a new $transaction is
   *   used. If provided, all writes participate in the caller's transaction.
   * @param decisionId Optional decision ID — recorded on the published
   *   version's `amendmentDecisionId` column for audit traceability.
   */
  async commitAmendment(
    familyId: string,
    constitutionVersionId: string,
    actorId?: string | null,
    tx?: any,
    decisionId?: string,
  ) {
    const run = async (client: any) => {
      const constitution = await client.familyConstitution.findUnique({
        where: { familyId },
      });
      if (!constitution) {
        throw new NotFoundException(
          `Constitution not found for family ${familyId} during amendment commit`,
        );
      }
      if (!constitution.draftVersionId) {
        // Idempotent: nothing to commit. Either the amendment was already
        // committed, or no draft was ever created. Either way, log and exit.
        this.logger.warn(
          `commitAmendment called for family ${familyId} but no draftVersionId exists — already committed?`,
        );
        return null;
      }

      // Verify the decision's recorded constitutionVersionId matches the
      // version that's being superseded (the current published version).
      // If they don't match, log loudly but proceed — the decision row is
      // the source of truth for "what the family voted on", and we don't
      // want to leave the constitution locked because of a stale pointer.
      if (
        constitution.currentVersionId &&
        constitution.currentVersionId !== constitutionVersionId
      ) {
        this.logger.error(
          `Constitution version mismatch on amendment commit: decision references ${constitutionVersionId} but currentVersionId is ${constitution.currentVersionId}. Proceeding with current state.`,
        );
      }

      const draft = await client.constitutionVersion.findUnique({
        where: { id: constitution.draftVersionId },
        include: { articles: true },
      });
      if (!draft) {
        throw new NotFoundException(
          `Draft version ${constitution.draftVersionId} not found during amendment commit`,
        );
      }
      if (draft.familyId !== familyId) {
        throw new ForbiddenException('Draft version does not belong to this family');
      }

      // Edge case #12: zero articles — refuse to publish, leave the draft
      // in place so the admin can fix it. The caller is expected to log
      // this loudly and surface it for manual remediation.
      if (!draft.articles.length) {
        throw new BadRequestException(
          'Cannot commit amendment — draft has zero articles (edge case #12). Manual remediation required.',
        );
      }

      const previousPublishedId = constitution.currentVersionId;

      // Mark the previous published version as superseded
      if (previousPublishedId) {
        await client.constitutionVersion.update({
          where: { id: previousPublishedId },
          data: { status: 'superseded' },
        });
      }

      // Promote draft to published
      const published = await client.constitutionVersion.update({
        where: { id: draft.id },
        data: {
          status: 'published',
          publishedAt: new Date(),
          publishedById: actorId ?? null,
          amendmentDecisionId: decisionId ?? null,
        },
      });

      // Update constitution pointers — this is the "unlock"
      await client.familyConstitution.update({
        where: { familyId },
        data: {
          currentVersionId: published.id,
          draftVersionId: null,
          status: 'published',
        },
      });

      // Emit timeline event (best-effort — never throws)
      try {
        await this.emitter.append({
          familyId,
          kind: 'constitution_amended',
          actorId: actorId ?? null,
          targetEntityType: 'ConstitutionVersion',
          targetEntityId: published.id,
          title: 'Family constitution amended',
          description: `Published version ${published.versionNumber}`,
          payload: {
            fromVersionId: previousPublishedId,
            toVersionId: published.id,
            changeCount: published.articleCount,
            decisionId: decisionId ?? null,
          },
        });
      } catch (e) {
        this.logger.warn(
          `constitution_amended timeline emission failed (non-fatal): ${(e as Error).message}`,
        );
      }

      return published;
    };

    if (tx) {
      return run(tx);
    }
    return this.prisma.$transaction(run);
  }

  /**
   * Discard the current draft version and clear the amendment lock.
   * Used when a constitution_amend decision resolves as rejected or expired.
   *
   * Safe to call when there is no draft (idempotent — logs and returns).
   *
   * @param familyId The family whose amendment is being discarded.
   * @param actorId The user who triggered the discard (or null for auto-expire).
   * @param tx Optional transaction client.
   */
  async discardDraft(familyId: string, actorId?: string | null, tx?: any): Promise<void> {
    const run = async (client: any) => {
      const constitution = await client.familyConstitution.findUnique({
        where: { familyId },
      });
      if (!constitution) {
        this.logger.warn(
          `discardDraft called for family ${familyId} but no constitution row exists — nothing to discard.`,
        );
        return;
      }
      if (!constitution.draftVersionId) {
        // Idempotent: nothing to discard.
        this.logger.warn(
          `discardDraft called for family ${familyId} but no draftVersionId exists — already discarded?`,
        );
        return;
      }

      // Delete the draft version (cascade deletes articles + clauses)
      await client.constitutionVersion.delete({
        where: { id: constitution.draftVersionId },
      });

      // Reset constitution pointers — this is the "unlock"
      await client.familyConstitution.update({
        where: { familyId },
        data: {
          draftVersionId: null,
          status: constitution.currentVersionId ? 'published' : 'draft',
        },
      });

      // Best-effort timeline event for audit trail
      try {
        await this.emitter.append({
          familyId,
          kind: 'correction',
          actorId: actorId ?? null,
          targetEntityType: 'FamilyConstitution',
          targetEntityId: constitution.id,
          title: 'Constitution amendment discarded',
          description: 'A proposed amendment was rejected or expired without approval.',
          payload: {
            note: 'Draft version discarded after constitution_amend decision resolved as rejected/expired.',
          },
        });
      } catch (e) {
        this.logger.warn(
          `discardDraft timeline emission failed (non-fatal): ${(e as Error).message}`,
        );
      }
    };

    if (tx) {
      await run(tx);
      return;
    }
    await this.prisma.$transaction(run);
  }
}
