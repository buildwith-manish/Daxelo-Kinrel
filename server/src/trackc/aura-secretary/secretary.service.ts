// =============================================================================
// Track C v2.0 — AURA Secretary
// secretary.service.ts
// =============================================================================
// Section 5.8 + Section 6 (MeetingArtifact endpoints).
//
// Generates draft minutes from a meeting context using the LLM, then
// extracts action items. The draft is editable Markdown; the published
// version is immutable and emits a timeline event.
// =============================================================================

import {
  Injectable,
  NotFoundException,
  BadRequestException,
  Logger,
  Inject,
  Optional,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { TimelineEmitter } from '../governance-timeline/timeline.emitter';
import { FamilyMembershipService } from '../common/family-membership.service';
import { LLM_PROVIDER, LLMProvider } from '../aura-intelligence/llm-provider';
import { RedactionService } from '../aura-intelligence/redaction';
import { ActionItemsKind } from '../aura-intelligence/kinds/action-items.kind';

export interface CreateArtifactInput {
  title: string;
  heldAt: string;
  decisionId?: string;
  participants: string[];
  agenda: string[];
  discussionPoints: { point: string; perspectives: { userId: string; perspective: string }[] }[];
  decisions: { text: string; decided: boolean; rationale?: string }[];
}

@Injectable()
export class SecretaryService {
  private readonly logger = new Logger(SecretaryService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly emitter: TimelineEmitter,
    private readonly membership: FamilyMembershipService,
    private readonly redaction: RedactionService,
    private readonly actionItemsKind: ActionItemsKind,
    @Inject(LLM_PROVIDER) private readonly llm: LLMProvider,
  ) {}

  async create(familyId: string, actorId: string, input: CreateArtifactInput) {
    await this.membership.requireMember(actorId, familyId);
    if (!input.title?.trim()) throw new BadRequestException('title is required');
    if (!input.heldAt) throw new BadRequestException('heldAt is required');

    // Generate draft minutes via LLM
    const draftMinutesMd = await this.generateDraftMinutes(input);

    // Generate action items via LLM
    let actionItems: any[] = [];
    try {
      const request = this.actionItemsKind.buildRequest({
        meetingTitle: input.title,
        agenda: input.agenda,
        discussionPoints: input.discussionPoints.map((d) => d.point),
        decisions: input.decisions.map((d) => d.text),
      });
      const response = await this.llm.generate(request);
      actionItems = this.actionItemsKind.parseResponse(response.content).actionItems;
    } catch (err) {
      this.logger.warn(`Action item extraction failed: ${(err as Error).message}`);
    }

    return this.prisma.meetingArtifact.create({
      data: {
        familyId,
        decisionId: input.decisionId ?? null,
        title: input.title,
        heldAt: new Date(input.heldAt),
        participants: input.participants,
        agenda: input.agenda,
        discussionPoints: input.discussionPoints as any,
        decisions: input.decisions as any,
        actionItems: actionItems as any,
        draftMinutesMd,
        status: 'draft',
      },
    });
  }

  async list(familyId: string, opts: { status?: string; limit?: number } = {}) {
    return this.prisma.meetingArtifact.findMany({
      where: {
        familyId,
        ...(opts.status ? { status: opts.status } : {}),
      },
      orderBy: { heldAt: 'desc' },
      take: Math.min(opts.limit ?? 50, 100),
    });
  }

  async getOne(familyId: string, artifactId: string) {
    const artifact = await this.prisma.meetingArtifact.findUnique({
      where: { id: artifactId },
    });
    if (!artifact || artifact.familyId !== familyId) {
      throw new NotFoundException('Meeting artifact not found');
    }
    return artifact;
  }

  async editDraft(familyId: string, artifactId: string, actorId: string, draftMinutesMd: string) {
    await this.membership.requireMember(actorId, familyId);
    const artifact = await this.getOne(familyId, artifactId);
    if (artifact.status === 'published') {
      throw new BadRequestException('Cannot edit a published artifact');
    }
    return this.prisma.meetingArtifact.update({
      where: { id: artifactId },
      data: { draftMinutesMd, status: 'reviewed' },
    });
  }

  async publish(familyId: string, artifactId: string, actorId: string, finalMinutesMd?: string) {
    await this.membership.requireAdmin(actorId, familyId);
    const artifact = await this.getOne(familyId, artifactId);

    const updated = await this.prisma.meetingArtifact.update({
      where: { id: artifactId },
      data: {
        status: 'published',
        finalMinutesMd: finalMinutesMd ?? artifact.draftMinutesMd,
      },
    });

    await this.emitter.append({
      familyId,
      kind: 'meeting_artifact_published',
      actorId,
      targetEntityType: 'MeetingArtifact',
      targetEntityId: artifactId,
      title: `Meeting minutes published: ${artifact.title}`,
      payload: { artifactId, decisionId: artifact.decisionId },
    });

    return updated;
  }

  private async generateDraftMinutes(input: CreateArtifactInput): Promise<string> {
    const system = `You are a family-governance secretary. Generate Markdown meeting minutes from the structured input below. Use the following sections: # Meeting, ## Held On, ## Participants, ## Agenda, ## Discussion, ## Decisions, ## Action Items. Respond with valid Markdown only.`;

    const agendaText = input.agenda.map((a, i) => `${i + 1}. ${this.redaction.redact(a).redacted}`).join('\n');
    const discussionText = input.discussionPoints
      .map((d) => {
        const point = this.redaction.redact(d.point).redacted;
        const perspectives = d.perspectives
          .map((p) => `  - ${p.userId}: ${this.redaction.redact(p.perspective).redacted}`)
          .join('\n');
        return `- ${point}\n${perspectives}`;
      })
      .join('\n');
    const decisionsText = input.decisions
      .map((d) => `- ${d.decided ? '✓' : '○'} ${this.redaction.redact(d.text).redacted}${d.rationale ? ` — ${this.redaction.redact(d.rationale).redacted}` : ''}`)
      .join('\n');

    const user = `Title: ${this.redaction.redact(input.title).redacted}
Held At: ${input.heldAt}
Participants: ${input.participants.join(', ')}

## Agenda
${agendaText}

## Discussion
${discussionText}

## Decisions
${decisionsText}`;

    try {
      const response = await this.llm.generate({
        modelId: 'glm-4.7-flash',
        messages: [
          { role: 'system', content: system },
          { role: 'user', content: user },
        ],
        maxOutputTokens: 2000,
        temperature: 0.3,
      });
      return response.content;
    } catch (err) {
      this.logger.warn(`Draft minutes generation failed: ${(err as Error).message}`);
      // Fallback: minimal Markdown from the structured input
      return `# ${input.title}\n\n## Held On\n${input.heldAt}\n\n## Participants\n${input.participants.join(', ')}\n\n## Agenda\n${agendaText}\n\n## Discussion\n${discussionText}\n\n## Decisions\n${decisionsText}\n`;
    }
  }
}
