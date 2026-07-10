// =============================================================================
// Track C v2.0 — Kinrel Intelligence
// kinds/action-items.kind.ts
// =============================================================================

import { Injectable } from '@nestjs/common';
import { LLMRequest } from '../llm-provider';
import { RedactionService } from '../redaction';

export interface ActionItem {
  assigneeRole: string; // admin|elder|member|all
  text: string;
  dueOffsetDays: number;
}

export interface ActionItemsPayload {
  actionItems: ActionItem[];
}

@Injectable()
export class ActionItemsKind {
  readonly kind = 'action_items' as const;

  constructor(private readonly redaction: RedactionService) {}

  buildRequest(params: {
    meetingTitle: string;
    agenda: string[];
    discussionPoints: string[];
    decisions: string[];
  }): LLMRequest {
    const system = `You are a meeting-secretary assistant. Extract concrete action items from the meeting context below. Return JSON with: actionItems (array of {assigneeRole: "admin"|"elder"|"member"|"all", text: string, dueOffsetDays: number}). Respond ONLY with valid JSON.`;

    const user = `Meeting: ${this.redaction.redact(params.meetingTitle).redacted}

Agenda:
${params.agenda.map((a) => `- ${this.redaction.redact(a).redacted}`).join('\n')}

Discussion points:
${params.discussionPoints.map((d) => `- ${this.redaction.redact(d).redacted}`).join('\n')}

Decisions:
${params.decisions.map((d) => `- ${this.redaction.redact(d).redacted}`).join('\n')}`;

    return {
      modelId: 'glm-4.7-flash',
      messages: [
        { role: 'system', content: system },
        { role: 'user', content: user },
      ],
      maxOutputTokens: 800,
      temperature: 0.3,
      responseFormat: 'json_object',
    };
  }

  parseResponse(content: string): ActionItemsPayload {
    try {
      const parsed = JSON.parse(content);
      const items = Array.isArray(parsed.actionItems) ? parsed.actionItems : [];
      return {
        actionItems: items.map((a: any) => ({
          assigneeRole: typeof a.assigneeRole === 'string' ? a.assigneeRole : 'all',
          text: typeof a.text === 'string' ? a.text : '',
          dueOffsetDays: typeof a.dueOffsetDays === 'number' ? a.dueOffsetDays : 7,
        })),
      };
    } catch {
      return { actionItems: [] };
    }
  }
}
