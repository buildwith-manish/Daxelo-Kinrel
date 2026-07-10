// =============================================================================
// Track C v2.0 — ConstitutionService Tests
// =============================================================================
// Exercises the constitution lifecycle: getConstitution() auto-creation,
// saveDraft() validation + delete-before-create, publish() versioning +
// timeline events, openAmendment() guards, and commitAmendment/discardDraft
// idempotency.
// =============================================================================

import { PrismaService } from '../../prisma/prisma.service';
import { ConstitutionService, DraftConstitutionInput } from './constitution.service';
import {
  BadRequestException,
  ForbiddenException,
  NotFoundException,
} from '@nestjs/common';

describe('ConstitutionService', () => {
  let prisma: any;
  let emitter: any;
  let membership: any;
  let service: ConstitutionService;

  beforeEach(() => {
    prisma = new PrismaService();
    for (const m of Object.values(prisma) as any[]) {
      if (m && typeof m === 'object' && 'findUnique' in m) {
        (m as any).findUnique.mockResolvedValue(null);
        (m as any).findMany.mockResolvedValue([]);
        (m as any).create.mockResolvedValue({});
        (m as any).update.mockResolvedValue({});
        (m as any).upsert.mockResolvedValue({});
        (m as any).count.mockResolvedValue(0);
        (m as any).delete.mockResolvedValue({});
        (m as any).deleteMany.mockResolvedValue({ count: 0 });
      }
    }

    emitter = { append: jest.fn().mockResolvedValue('event-id') };
    membership = {
      requireMember: jest.fn().mockResolvedValue({ id: 'm_1', role: 'member' }),
      requireAdmin: jest.fn().mockResolvedValue({ id: 'm_1', role: 'admin' }),
      requireRole: jest.fn().mockResolvedValue({ id: 'm_1', role: 'admin' }),
      getElderUserIds: jest.fn().mockResolvedValue([]),
      getActiveMemberUserIds: jest.fn().mockResolvedValue(['u1', 'u2', 'u3']),
    };

    service = new ConstitutionService(
      prisma as any,
      emitter as any,
      membership as any,
    );
  });

  // ── getConstitution() ────────────────────────────────────────────────
  describe('getConstitution()', () => {
    it('auto-creates an empty shell when none exists', async () => {
      // First findUnique returns null (no constitution exists)
      prisma.familyConstitution.findUnique.mockResolvedValueOnce(null);
      const shell = {
        id: 'c_1',
        familyId: 'fam_1',
        title: 'Family Constitution',
        status: 'draft',
        currentVersionId: null,
        draftVersionId: null,
        currentVersion: null,
        draftVersion: null,
      };
      prisma.familyConstitution.create.mockResolvedValueOnce(shell);

      const result = await service.getConstitution('fam_1', 'u_1');

      expect(result.id).toBe('c_1');
      expect(result.status).toBe('draft');
      expect(prisma.familyConstitution.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            familyId: 'fam_1',
            title: 'Family Constitution',
            status: 'draft',
          }),
        }),
      );
    });

    it('returns the existing constitution without creating a new one', async () => {
      const existing = {
        id: 'c_1',
        familyId: 'fam_1',
        title: 'Existing',
        status: 'published',
        currentVersionId: 'v_1',
        draftVersionId: null,
      };
      prisma.familyConstitution.findUnique.mockResolvedValueOnce(existing);

      const result = await service.getConstitution('fam_1', 'u_1');
      expect(result).toEqual(existing);
      expect(prisma.familyConstitution.create).not.toHaveBeenCalled();
    });
  });

  // ── saveDraft() ──────────────────────────────────────────────────────
  describe('saveDraft()', () => {
    function baseInput(): DraftConstitutionInput {
      return {
        title: 'My Constitution',
        preamble: 'We the family...',
        articles: [
          {
            title: 'Article 1',
            intent: 'decisions',
            clauses: [{ text: 'Decisions require majority.' }],
          },
        ],
      };
    }

    it('rejects zero articles (edge case #12)', async () => {
      await expect(
        service.saveDraft('fam_1', 'u_admin', { ...baseInput(), articles: [] }),
      ).rejects.toThrow(BadRequestException);
    });

    it('deletes existing draft before creating a new one', async () => {
      const constitution = {
        id: 'c_1',
        familyId: 'fam_1',
        title: 'Old title',
        preamble: 'old preamble',
        status: 'published',
        currentVersionId: 'v_1',
        draftVersionId: 'v_draft_old', // ← existing draft that should be deleted
      };
      prisma.familyConstitution.findUnique.mockResolvedValueOnce(constitution);
      // Inside the transaction, count is called → 1 existing version
      prisma.constitutionVersion.count.mockResolvedValueOnce(1);
      // New draft create
      prisma.constitutionVersion.create.mockResolvedValueOnce({
        id: 'v_draft_new',
        constitutionId: 'c_1',
        versionNumber: 2,
        status: 'draft',
      });
      prisma.constitutionArticle.create.mockResolvedValueOnce({ id: 'a_1' });
      prisma.constitutionClause.create.mockResolvedValueOnce({ id: 'cl_1' });
      // Re-fetch
      prisma.constitutionVersion.findUnique.mockResolvedValueOnce({
        id: 'v_draft_new',
        articles: [],
      });
      prisma.familyConstitution.update.mockResolvedValueOnce({});

      await service.saveDraft('fam_1', 'u_admin', baseInput());

      // The OLD draft version must be deleted (inside the transaction)
      expect(prisma.constitutionVersion.delete).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { id: 'v_draft_old' },
        }),
      );
      // A new draft must be created
      expect(prisma.constitutionVersion.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            constitutionId: 'c_1',
            status: 'draft',
            versionNumber: 2,
          }),
        }),
      );
    });
  });

  // ── publish() ────────────────────────────────────────────────────────
  describe('publish()', () => {
    function setupDraft(articles: any[]) {
      const constitution = {
        id: 'c_1',
        familyId: 'fam_1',
        title: 'Title',
        currentVersionId: null, // first publication by default
        draftVersionId: 'v_draft',
      };
      prisma.familyConstitution.findUnique.mockResolvedValueOnce(constitution);
      const draft = {
        id: 'v_draft',
        versionNumber: 1,
        articles,
        articleCount: articles.length,
      };
      prisma.constitutionVersion.findUnique.mockResolvedValueOnce(draft);
      return { constitution, draft };
    }

    it('rejects zero articles (edge case #12)', async () => {
      const constitution = {
        id: 'c_1',
        familyId: 'fam_1',
        currentVersionId: null,
        draftVersionId: 'v_draft',
      };
      prisma.familyConstitution.findUnique.mockResolvedValueOnce(constitution);
      prisma.constitutionVersion.findUnique.mockResolvedValueOnce({
        id: 'v_draft',
        articles: [], // zero articles
      });

      await expect(
        service.publish('fam_1', 'u_admin', 'initial'),
      ).rejects.toThrow(BadRequestException);
    });

    it('marks previous version as superseded on subsequent publication', async () => {
      const constitution = {
        id: 'c_1',
        familyId: 'fam_1',
        currentVersionId: 'v_old', // ← a previous published version exists
        draftVersionId: 'v_draft',
      };
      prisma.familyConstitution.findUnique.mockResolvedValueOnce(constitution);
      const draft = {
        id: 'v_draft',
        versionNumber: 2,
        articles: [{ id: 'a_1' }],
        articleCount: 1,
        clauseCount: 1,
      };
      prisma.constitutionVersion.findUnique.mockResolvedValueOnce(draft);
      const published = {
        id: 'v_draft',
        versionNumber: 2,
        articleCount: 1,
        clauseCount: 1,
        status: 'published',
      };
      prisma.constitutionVersion.update
        .mockResolvedValueOnce(published) // first call: supersede the old version
        .mockResolvedValueOnce(published); // second call: promote draft to published

      await service.publish('fam_1', 'u_admin', 'amended');

      // First update: mark the old version as superseded
      expect(prisma.constitutionVersion.update).toHaveBeenNthCalledWith(
        1,
        expect.objectContaining({
          where: { id: 'v_old' },
          data: expect.objectContaining({ status: 'superseded' }),
        }),
      );
      // Second update: promote the draft
      expect(prisma.constitutionVersion.update).toHaveBeenNthCalledWith(
        2,
        expect.objectContaining({
          where: { id: 'v_draft' },
          data: expect.objectContaining({ status: 'published' }),
        }),
      );
    });

    it('emits constitution_amended timeline event on subsequent publication', async () => {
      const constitution = {
        id: 'c_1',
        familyId: 'fam_1',
        currentVersionId: 'v_old',
        draftVersionId: 'v_draft',
      };
      prisma.familyConstitution.findUnique.mockResolvedValueOnce(constitution);
      prisma.constitutionVersion.findUnique.mockResolvedValueOnce({
        id: 'v_draft',
        versionNumber: 2,
        articles: [{ id: 'a_1' }],
        articleCount: 1,
        clauseCount: 1,
      });
      prisma.constitutionVersion.update.mockResolvedValue({
        id: 'v_draft',
        versionNumber: 2,
        articleCount: 1,
        clauseCount: 1,
        status: 'published',
      });

      await service.publish('fam_1', 'u_admin', 'amended');

      // emitter.append is called twice (constitution_amended + version_published).
      // Verify at least one call emits the constitution_amended kind.
      expect(emitter.append).toHaveBeenCalledWith(
        expect.objectContaining({
          familyId: 'fam_1',
          kind: 'constitution_amended',
          targetEntityType: 'ConstitutionVersion',
        }),
      );
    });

    it('emits constitution_created timeline event on first publication', async () => {
      const constitution = {
        id: 'c_1',
        familyId: 'fam_1',
        currentVersionId: null, // ← no prior published version → first publication
        draftVersionId: 'v_draft',
      };
      prisma.familyConstitution.findUnique.mockResolvedValueOnce(constitution);
      prisma.constitutionVersion.findUnique.mockResolvedValueOnce({
        id: 'v_draft',
        versionNumber: 1,
        articles: [{ id: 'a_1' }],
        articleCount: 1,
        clauseCount: 1,
      });
      prisma.constitutionVersion.update.mockResolvedValue({
        id: 'v_draft',
        versionNumber: 1,
        articleCount: 1,
        clauseCount: 1,
        status: 'published',
      });

      await service.publish('fam_1', 'u_admin', 'initial');

      expect(emitter.append).toHaveBeenCalledWith(
        expect.objectContaining({
          familyId: 'fam_1',
          kind: 'constitution_created',
          targetEntityType: 'ConstitutionVersion',
        }),
      );
    });

    it('rejects publish when no draft exists', async () => {
      const constitution = {
        id: 'c_1',
        familyId: 'fam_1',
        currentVersionId: 'v_1',
        draftVersionId: null, // ← no draft
      };
      prisma.familyConstitution.findUnique.mockResolvedValueOnce(constitution);

      await expect(
        service.publish('fam_1', 'u_admin', 'amend'),
      ).rejects.toThrow(BadRequestException);
    });
  });

  // ── openAmendment() ──────────────────────────────────────────────────
  describe('openAmendment()', () => {
    function baseParams() {
      return {
        title: 'Amendment 1',
        description: 'A change',
        changeSummary: 'Adds a clause about voting',
        deadlineAt: new Date(Date.now() + 7 * 86_400_000).toISOString(),
      };
    }

    it('rejects when no published constitution exists', async () => {
      const constitution = {
        id: 'c_1',
        familyId: 'fam_1',
        currentVersionId: null, // ← no published version
      };
      prisma.familyConstitution.findUnique.mockResolvedValueOnce(constitution);

      await expect(
        service.openAmendment('fam_1', 'u_admin', baseParams()),
      ).rejects.toThrow(BadRequestException);
    });

    it('rejects deadline in the past', async () => {
      const constitution = {
        id: 'c_1',
        familyId: 'fam_1',
        currentVersionId: 'v_1',
      };
      prisma.familyConstitution.findUnique.mockResolvedValueOnce(constitution);

      await expect(
        service.openAmendment('fam_1', 'u_admin', {
          ...baseParams(),
          deadlineAt: new Date(Date.now() - 1000).toISOString(),
        }),
      ).rejects.toThrow(BadRequestException);
    });

    it('rejects quorum < 67%', async () => {
      const constitution = {
        id: 'c_1',
        familyId: 'fam_1',
        currentVersionId: 'v_1',
      };
      prisma.familyConstitution.findUnique.mockResolvedValueOnce(constitution);

      await expect(
        service.openAmendment('fam_1', 'u_admin', {
          ...baseParams(),
          quorumPct: 50, // below 67
        }),
      ).rejects.toThrow(BadRequestException);
    });

    it('creates the amendment decision and locks the constitution', async () => {
      const constitution = {
        id: 'c_1',
        familyId: 'fam_1',
        currentVersionId: 'v_1',
      };
      prisma.familyConstitution.findUnique.mockResolvedValueOnce(constitution);
      prisma.familyDecision.create.mockResolvedValueOnce({
        id: 'd_amend',
        familyId: 'fam_1',
        type: 'constitution_amend',
      });
      prisma.familyConstitution.update.mockResolvedValueOnce({});

      const result = await service.openAmendment('fam_1', 'u_admin', baseParams());

      expect(result.id).toBe('d_amend');
      expect(prisma.familyDecision.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            familyId: 'fam_1',
            type: 'constitution_amend',
            options: ['approve', 'reject'],
            quorumPct: 67,
            constitutionVersionId: 'v_1',
          }),
        }),
      );
      // Constitution status must be flipped to in_review (the "lock")
      expect(prisma.familyConstitution.update).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { familyId: 'fam_1' },
          data: expect.objectContaining({ status: 'in_review' }),
        }),
      );
    });
  });

  // ── commitAmendment() ────────────────────────────────────────────────
  describe('commitAmendment()', () => {
    it('is idempotent when no draft exists', async () => {
      prisma.familyConstitution.findUnique.mockResolvedValueOnce({
        id: 'c_1',
        familyId: 'fam_1',
        currentVersionId: 'v_1',
        draftVersionId: null, // ← no draft, already committed
      });

      const result = await service.commitAmendment('fam_1', 'v_1', 'u_admin');

      expect(result).toBeNull();
      expect(prisma.constitutionVersion.update).not.toHaveBeenCalled();
    });

    it('rejects zero articles in draft (edge case #12)', async () => {
      prisma.familyConstitution.findUnique.mockResolvedValueOnce({
        id: 'c_1',
        familyId: 'fam_1',
        currentVersionId: 'v_1',
        draftVersionId: 'v_draft',
      });
      prisma.constitutionVersion.findUnique.mockResolvedValueOnce({
        id: 'v_draft',
        familyId: 'fam_1',
        articles: [], // zero articles
      });

      await expect(
        service.commitAmendment('fam_1', 'v_1', 'u_admin'),
      ).rejects.toThrow(BadRequestException);
    });

    it('promotes draft to published and clears draftVersionId', async () => {
      prisma.familyConstitution.findUnique.mockResolvedValueOnce({
        id: 'c_1',
        familyId: 'fam_1',
        currentVersionId: 'v_1', // existing published version
        draftVersionId: 'v_draft',
      });
      prisma.constitutionVersion.findUnique.mockResolvedValueOnce({
        id: 'v_draft',
        familyId: 'fam_1',
        articles: [{ id: 'a_1' }],
        versionNumber: 2,
        articleCount: 1,
      });
      const published = {
        id: 'v_draft',
        versionNumber: 2,
        articleCount: 1,
        status: 'published',
      };
      prisma.constitutionVersion.update
        .mockResolvedValueOnce(published) // supersede the previous version
        .mockResolvedValueOnce(published); // promote draft

      const result = await service.commitAmendment('fam_1', 'v_1', 'u_admin', undefined, 'd_amend');

      expect(result.status).toBe('published');
      // The constitution must be updated to clear draftVersionId (the "unlock")
      expect(prisma.familyConstitution.update).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { familyId: 'fam_1' },
          data: expect.objectContaining({
            currentVersionId: 'v_draft',
            draftVersionId: null,
            status: 'published',
          }),
        }),
      );
      // The previous version must be marked as superseded
      expect(prisma.constitutionVersion.update).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { id: 'v_1' },
          data: expect.objectContaining({ status: 'superseded' }),
        }),
      );
      // constitution_amended timeline event must be emitted
      expect(emitter.append).toHaveBeenCalledWith(
        expect.objectContaining({
          familyId: 'fam_1',
          kind: 'constitution_amended',
          targetEntityType: 'ConstitutionVersion',
        }),
      );
    });

    it('throws NotFoundException when constitution does not exist', async () => {
      prisma.familyConstitution.findUnique.mockResolvedValueOnce(null);

      await expect(
        service.commitAmendment('fam_1', 'v_1', 'u_admin'),
      ).rejects.toThrow(NotFoundException);
    });
  });

  // ── discardDraft() ───────────────────────────────────────────────────
  describe('discardDraft()', () => {
    it('is idempotent when no draft exists', async () => {
      prisma.familyConstitution.findUnique.mockResolvedValueOnce({
        id: 'c_1',
        familyId: 'fam_1',
        currentVersionId: 'v_1',
        draftVersionId: null, // ← no draft
      });

      await service.discardDraft('fam_1', 'u_admin');

      expect(prisma.constitutionVersion.delete).not.toHaveBeenCalled();
    });

    it('is idempotent when no constitution row exists at all', async () => {
      prisma.familyConstitution.findUnique.mockResolvedValueOnce(null);

      // Should not throw
      await service.discardDraft('fam_1', 'u_admin');
      expect(prisma.constitutionVersion.delete).not.toHaveBeenCalled();
    });

    it('deletes the draft and resets constitution status', async () => {
      prisma.familyConstitution.findUnique.mockResolvedValueOnce({
        id: 'c_1',
        familyId: 'fam_1',
        currentVersionId: 'v_1', // existing published version
        draftVersionId: 'v_draft',
      });
      prisma.constitutionVersion.delete.mockResolvedValueOnce({ id: 'v_draft' });
      prisma.familyConstitution.update.mockResolvedValueOnce({});

      await service.discardDraft('fam_1', 'u_admin');

      // Draft must be deleted
      expect(prisma.constitutionVersion.delete).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { id: 'v_draft' },
        }),
      );
      // Constitution must be reset (draftVersionId=null, status='published' since currentVersionId exists)
      expect(prisma.familyConstitution.update).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { familyId: 'fam_1' },
          data: expect.objectContaining({
            draftVersionId: null,
            status: 'published',
          }),
        }),
      );
      // Best-effort timeline event must be emitted
      expect(emitter.append).toHaveBeenCalledWith(
        expect.objectContaining({
          familyId: 'fam_1',
          kind: 'correction',
          targetEntityType: 'FamilyConstitution',
        }),
      );
    });

    it('resets status to draft (not published) when no published version exists', async () => {
      prisma.familyConstitution.findUnique.mockResolvedValueOnce({
        id: 'c_1',
        familyId: 'fam_1',
        currentVersionId: null, // no published version
        draftVersionId: 'v_draft',
      });
      prisma.constitutionVersion.delete.mockResolvedValueOnce({ id: 'v_draft' });
      prisma.familyConstitution.update.mockResolvedValueOnce({});

      await service.discardDraft('fam_1', 'u_admin');

      expect(prisma.familyConstitution.update).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            draftVersionId: null,
            status: 'draft', // ← because currentVersionId was null
          }),
        }),
      );
    });
  });
});
