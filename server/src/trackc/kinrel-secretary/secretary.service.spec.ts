// =============================================================================
// Track C v2.0 — SecretaryService Tests
// =============================================================================
// Exercises create() (which generates draft minutes via the LLM and persists
// the artifact) and list() (which returns artifacts in reverse-chronological
// order by heldAt).
//
// The v2 spec test plan refers to generateMinutes() and listArtifacts(). The
// actual SecretaryService exposes create() (which calls generateDraftMinutes
// internally) and list() — these tests exercise those methods.
// =============================================================================

import { PrismaService } from '../../prisma/prisma.service';
import { SecretaryService, CreateArtifactInput } from './secretary.service';
import { RedactionService } from '../kinrel-intelligence/redaction';
import { ActionItemsKind } from '../kinrel-intelligence/kinds/action-items.kind';
import { LLMProvider } from '../kinrel-intelligence/llm-provider';
import { BadRequestException, NotFoundException } from '@nestjs/common';

describe('SecretaryService', () => {
  let prisma: any;
  let emitter: any;
  let membership: any;
  let redaction: RedactionService;
  let actionItemsKind: ActionItemsKind;
  let llm: jest.Mocked<LLMProvider>;
  let service: SecretaryService;

  beforeEach(() => {
    prisma = new PrismaService();
    for (const m of Object.values(prisma) as any[]) {
      if (m && typeof m === 'object' && 'findUnique' in m) {
        (m as any).findUnique.mockResolvedValue(null);
        (m as any).findMany.mockResolvedValue([]);
        (m as any).create.mockResolvedValue({});
        (m as any).update.mockResolvedValue({});
        (m as any).count.mockResolvedValue(0);
      }
    }

    emitter = { append: jest.fn().mockResolvedValue('event-id') };
    membership = {
      requireMember: jest.fn().mockResolvedValue({ id: 'm_1' }),
      requireAdmin: jest.fn().mockResolvedValue({ id: 'm_1', role: 'admin' }),
    };
    redaction = new RedactionService();
    actionItemsKind = new ActionItemsKind(redaction);

    llm = {
      generate: jest.fn().mockResolvedValue({
        modelId: 'mock',
        content: JSON.stringify({
          actionItems: [
            { assigneeRole: 'admin', text: 'Follow up on X', dueOffsetDays: 3 },
          ],
        }),
        tokensIn: 100,
        tokensOut: 50,
        costUsd: 0,
        latencyMs: 10,
      }),
      providerName: 'mock',
      getUsageStats: jest.fn().mockReturnValue({
        totalRequests: 0,
        totalTokensIn: 0,
        totalTokensOut: 0,
        totalCostUsd: 0,
        errorCount: 0,
      }),
    } as any;

    service = new SecretaryService(
      prisma as any,
      emitter as any,
      membership as any,
      redaction,
      actionItemsKind,
      llm as any,
    );
  });

  function baseInput(): CreateArtifactInput {
    return {
      title: 'Family Meeting',
      heldAt: new Date(Date.now() + 86_400_000).toISOString(),
      participants: ['u1', 'u2'],
      agenda: ['Budget review', 'Trip planning'],
      discussionPoints: [
        {
          point: 'We need to decide on the vacation budget',
          perspectives: [
            { userId: 'u1', perspective: 'I think we should spend $5000' },
            { userId: 'u2', perspective: 'I prefer $3000' },
          ],
        },
      ],
      decisions: [
        { text: 'Set vacation budget at $4000', decided: true, rationale: 'Compromise' },
      ],
    };
  }

  // ── create() — equivalent to generateMinutes() ──────────────────────
  describe('create() — generates minutes via the LLM and persists the artifact', () => {
    it('calls the AI provider to generate draft minutes (draft_minutes kind)', async () => {
      prisma.meetingArtifact.create.mockResolvedValueOnce({ id: 'art_1' });

      await service.create('fam_1', 'u_1', baseInput());

      // The LLM provider must be called. The first call is for draft minutes
      // (the second is for action-item extraction).
      expect(llm.generate).toHaveBeenCalledTimes(2);

      // First call: draft_minutes. The system prompt mentions "meeting minutes".
      const firstCall = llm.generate.mock.calls[0][0];
      expect(firstCall.messages[0].role).toBe('system');
      expect(firstCall.messages[0].content).toContain('meeting minutes');
      // The user prompt must include the title (redacted) and the agenda
      const userMsg = firstCall.messages.find((m: any) => m.role === 'user');
      expect(userMsg.content).toContain('Family Meeting');
      expect(userMsg.content).toContain('Budget review');
    });

    it('persists the artifact as a MeetingArtifact with status=draft', async () => {
      prisma.meetingArtifact.create.mockResolvedValueOnce({ id: 'art_persist' });

      await service.create('fam_1', 'u_1', baseInput());

      expect(prisma.meetingArtifact.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            familyId: 'fam_1',
            title: 'Family Meeting',
            status: 'draft',
            draftMinutesMd: expect.any(String),
            actionItems: expect.any(Array),
            participants: ['u1', 'u2'],
            agenda: ['Budget review', 'Trip planning'],
          }),
        }),
      );
    });

    it('redacts PII before sending content to the LLM provider', async () => {
      prisma.meetingArtifact.create.mockResolvedValueOnce({ id: 'art_1' });
      const piiInput = baseInput();
      // Inject PII into the discussion text
      piiInput.discussionPoints[0].perspectives[0].perspective =
        'Email me at john@example.com or call +1-555-867-5309';

      await service.create('fam_1', 'u_1', piiInput);

      // The user message passed to the LLM must NOT contain the raw email/phone
      const firstCall = llm.generate.mock.calls[0][0];
      const userMsg = firstCall.messages.find((m: any) => m.role === 'user');
      expect(userMsg.content).not.toContain('john@example.com');
      expect(userMsg.content).not.toContain('+1-555-867-5309');
      // The redaction markers must be present
      expect(userMsg.content).toContain('[REDACTED_EMAIL]');
    });

    it('rejects empty title', async () => {
      await expect(
        service.create('fam_1', 'u_1', { ...baseInput(), title: '  ' }),
      ).rejects.toThrow(BadRequestException);
      expect(llm.generate).not.toHaveBeenCalled();
    });

    it('rejects missing heldAt', async () => {
      await expect(
        service.create('fam_1', 'u_1', { ...baseInput(), heldAt: '' }),
      ).rejects.toThrow(BadRequestException);
    });

    it('falls back to a minimal Markdown draft if the LLM call fails (graceful degradation)', async () => {
      // First generate() (for draft minutes) rejects
      llm.generate.mockRejectedValueOnce(new Error('LLM unavailable'));
      // Second generate() (for action items) succeeds
      llm.generate.mockResolvedValueOnce({
        modelId: 'mock',
        content: JSON.stringify({ actionItems: [] }),
        tokensIn: 0,
        tokensOut: 0,
        costUsd: 0,
        latencyMs: 0,
      });
      prisma.meetingArtifact.create.mockResolvedValueOnce({ id: 'art_fb' });

      await service.create('fam_1', 'u_1', baseInput());

      // The artifact must still be persisted with a fallback draft
      expect(prisma.meetingArtifact.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            draftMinutesMd: expect.stringContaining('# Family Meeting'),
            status: 'draft',
          }),
        }),
      );
    });

    it('extracts action items via the ActionItemsKind pipeline', async () => {
      prisma.meetingArtifact.create.mockResolvedValueOnce({ id: 'art_ai' });
      // The create() method calls llm.generate() twice: once for draft minutes
      // (1st call), once for action items (2nd call). Set up both:
      llm.generate
        .mockResolvedValueOnce({
          // 1st call: draft minutes — any markdown string is fine
          modelId: 'mock',
          content: '# Family Meeting\n\nDraft minutes...',
          tokensIn: 80,
          tokensOut: 40,
          costUsd: 0,
          latencyMs: 5,
        })
        .mockResolvedValueOnce({
          // 2nd call: action items JSON
          modelId: 'mock',
          content: JSON.stringify({
            actionItems: [
              { assigneeRole: 'admin', text: 'Schedule follow-up', dueOffsetDays: 5 },
              { assigneeRole: 'member', text: 'Send budget draft', dueOffsetDays: 2 },
            ],
          }),
          tokensIn: 50,
          tokensOut: 30,
          costUsd: 0,
          latencyMs: 5,
        });

      await service.create('fam_1', 'u_1', baseInput());

      // The persisted artifact must contain the extracted action items
      const persisted = prisma.meetingArtifact.create.mock.calls[0][0].data;
      expect(persisted.actionItems).toHaveLength(2);
      expect(persisted.actionItems[0].text).toContain('Schedule follow-up');
    });
  });

  // ── list() — equivalent to listArtifacts() ──────────────────────────
  describe('list() — returns artifacts in reverse-chronological order', () => {
    it('returns artifacts ordered by heldAt DESC (reverse-chronological)', async () => {
      const newest = { id: 'a1', title: 'Newest', heldAt: new Date('2026-07-13') };
      const middle = { id: 'a2', title: 'Middle', heldAt: new Date('2026-07-06') };
      const oldest = { id: 'a3', title: 'Oldest', heldAt: new Date('2026-06-29') };
      prisma.meetingArtifact.findMany.mockResolvedValueOnce([newest, middle, oldest]);

      const result = await service.list('fam_1');

      expect(result).toEqual([newest, middle, oldest]);
      // Verify the query uses heldAt DESC ordering
      expect(prisma.meetingArtifact.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { familyId: 'fam_1' },
          orderBy: { heldAt: 'desc' },
        }),
      );
    });

    it('filters by status when provided', async () => {
      prisma.meetingArtifact.findMany.mockResolvedValueOnce([]);
      await service.list('fam_1', { status: 'published' });
      expect(prisma.meetingArtifact.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { familyId: 'fam_1', status: 'published' },
        }),
      );
    });

    it('caps the limit at 100 (server-side maximum)', async () => {
      prisma.meetingArtifact.findMany.mockResolvedValueOnce([]);
      await service.list('fam_1', { limit: 99999 });
      expect(prisma.meetingArtifact.findMany).toHaveBeenCalledWith(
        expect.objectContaining({ take: 100 }),
      );
    });

    it('defaults to a limit of 50 when none is provided', async () => {
      prisma.meetingArtifact.findMany.mockResolvedValueOnce([]);
      await service.list('fam_1');
      expect(prisma.meetingArtifact.findMany).toHaveBeenCalledWith(
        expect.objectContaining({ take: 50 }),
      );
    });
  });

  // ── getOne() ────────────────────────────────────────────────────────
  describe('getOne()', () => {
    it('returns the artifact when it belongs to the family', async () => {
      const artifact = { id: 'a1', familyId: 'fam_1', title: 'My meeting' };
      prisma.meetingArtifact.findUnique.mockResolvedValueOnce(artifact);

      const result = await service.getOne('fam_1', 'a1');
      expect(result).toEqual(artifact);
    });

    it('throws NotFoundException when the artifact does not exist', async () => {
      prisma.meetingArtifact.findUnique.mockResolvedValueOnce(null);
      await expect(service.getOne('fam_1', 'missing')).rejects.toThrow(NotFoundException);
    });

    it('throws NotFoundException when the artifact belongs to a different family', async () => {
      prisma.meetingArtifact.findUnique.mockResolvedValueOnce({
        id: 'a1',
        familyId: 'fam_other', // ← different family
      });
      await expect(service.getOne('fam_1', 'a1')).rejects.toThrow(NotFoundException);
    });
  });

  // ── publish() ───────────────────────────────────────────────────────
  describe('publish()', () => {
    it('flips the artifact to published and emits a timeline event', async () => {
      prisma.meetingArtifact.findUnique.mockResolvedValueOnce({
        id: 'a1',
        familyId: 'fam_1',
        title: 'My meeting',
        draftMinutesMd: '# Minutes',
        decisionId: 'd1',
      });
      prisma.meetingArtifact.update.mockResolvedValueOnce({
        id: 'a1',
        status: 'published',
        finalMinutesMd: '# Minutes',
      });

      const result = await service.publish('fam_1', 'a1', 'u_admin');

      expect(result.status).toBe('published');
      expect(prisma.meetingArtifact.update).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { id: 'a1' },
          data: expect.objectContaining({
            status: 'published',
            finalMinutesMd: '# Minutes',
          }),
        }),
      );
      // Timeline event must be emitted
      expect(emitter.append).toHaveBeenCalledWith(
        expect.objectContaining({
          familyId: 'fam_1',
          kind: 'meeting_artifact_published',
          targetEntityType: 'MeetingArtifact',
        }),
      );
    });

    it('uses the provided finalMinutesMd when supplied (instead of the draft)', async () => {
      prisma.meetingArtifact.findUnique.mockResolvedValueOnce({
        id: 'a1',
        familyId: 'fam_1',
        title: 'T',
        draftMinutesMd: 'DRAFT',
        decisionId: null,
      });
      prisma.meetingArtifact.update.mockResolvedValueOnce({ status: 'published' });

      await service.publish('fam_1', 'a1', 'u_admin', '# EDITED FINAL');

      expect(prisma.meetingArtifact.update).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({ finalMinutesMd: '# EDITED FINAL' }),
        }),
      );
    });

    it('rejects non-admins from publishing', async () => {
      membership.requireAdmin.mockRejectedValueOnce(new Error('requires admin'));
      await expect(
        service.publish('fam_1', 'a1', 'u_member'),
      ).rejects.toThrow('requires admin');
      expect(prisma.meetingArtifact.update).not.toHaveBeenCalled();
    });
  });
});
