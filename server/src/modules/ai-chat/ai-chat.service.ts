import {
  Injectable,
  Logger,
  InternalServerErrorException,
} from '@nestjs/common';
import { KinshipService, KinshipTerm } from '../kinship/kinship.service';

// ── Types ────────────────────────────────────────────────────────────

export interface ChatMessage {
  role: 'system' | 'user' | 'assistant';
  content: string;
}

interface ChatSession {
  id: string;
  userId: string;
  messages: ChatMessage[];
  createdAt: Date;
  updatedAt: Date;
}

export interface KinshipDataItem {
  relationshipKey: string;
  englishTerm: string;
  gender: string;
  lineage: string;
  relationshipCategory: string;
  translations: Record<string, { native: string; latin: string }>;
}

export interface AiChatResponse {
  response: string;
  kinshipData: KinshipDataItem[];
}

// ── Suggestion Templates ─────────────────────────────────────────────

const SUGGESTION_TEMPLATES = [
  'What do I call my father\'s elder brother in Hindi?',
  'How is "chacha" related to me?',
  'What is the Tamil word for grandmother?',
  'Explain the difference between bua and mausi',
  'What do I call my wife\'s brother in Bengali?',
  'How do I address my mother\'s sister in Marathi?',
  'What is the Kannada word for father-in-law?',
  'Tell me about the Gujarati term for daughter-in-law',
  'What does "devar" mean in Indian kinship?',
  'How do I refer to my husband\'s sister in Telugu?',
  'What is "nana" in Indian family relationships?',
  'Explain "bhabhi" relationship in Indian culture',
];

@Injectable()
export class AiChatService {
  private readonly logger = new Logger(AiChatService.name);
  private readonly sessions: Map<string, ChatSession> = new Map();

  constructor(private readonly kinshipService: KinshipService) {}

  /**
   * Get chat suggestions related to Indian kinship.
   */
  getSuggestions(): string[] {
    // Shuffle and return 6 suggestions
    const shuffled = [...SUGGESTION_TEMPLATES].sort(() => Math.random() - 0.5);
    return shuffled.slice(0, 6);
  }

  /**
   * Send a message and get an AI response with kinship data.
   */
  async chat(
    userId: string,
    dto: { sessionId?: string; message: string },
  ): Promise<AiChatResponse> {
    const { sessionId, message } = dto;

    // Retrieve or create session
    let session: ChatSession;
    if (sessionId && this.sessions.has(sessionId)) {
      session = this.sessions.get(sessionId)!;
      session.messages.push({ role: 'user', content: message });
      session.updatedAt = new Date();
    } else {
      session = {
        id: sessionId || this.generateSessionId(),
        userId,
        messages: [
          {
            role: 'system',
            content:
              'You are a helpful assistant that specializes in Indian kinship relationships and family terminology. ' +
              'You help users understand how to address family members in different Indian languages and cultures. ' +
              'Provide clear, respectful, and culturally accurate information about Indian family relationships. ' +
              'When discussing kinship terms, always include the relationship in English and at least one Indian language translation.',
          },
          { role: 'user', content: message },
        ],
        createdAt: new Date(),
        updatedAt: new Date(),
      };
    }

    // Try to use LLM for response generation
    let aiResponse: string;
    try {
      aiResponse = await this.generateLlmResponse(session.messages);
    } catch (error) {
      this.logger.warn(
        `LLM generation failed, falling back to built-in responses: ${error instanceof Error ? error.message : 'Unknown error'}`,
      );
      aiResponse = this.generateFallbackResponse(message);
    }

    // Extract kinship data from the message and response
    const kinshipData = this.extractKinshipData(message, aiResponse);

    // Update session with assistant response
    session.messages.push({ role: 'assistant', content: aiResponse });
    this.sessions.set(session.id, session);

    return {
      response: aiResponse,
      kinshipData,
    };
  }

  /**
   * Delete a chat session.
   */
  deleteSession(sessionId: string, userId: string): { success: boolean } {
    const session = this.sessions.get(sessionId);
    if (!session) {
      return { success: true }; // Idempotent
    }
    if (session.userId !== userId) {
      return { success: false };
    }
    this.sessions.delete(sessionId);
    return { success: true };
  }

  // ── Private Helpers ────────────────────────────────────────────────

  private async generateLlmResponse(messages: ChatMessage[]): Promise<string> {
    const ZAI = (await import('z-ai-web-dev-sdk')).default;
    const sdk = await ZAI.create();

    const response = await sdk.chat.completions.create({
      messages: messages.map((m) => ({
        role: m.role,
        content: m.content,
      })),
      model: 'deepseek-chat',
    });

    // Extract the text from the LLM response
    if (response?.choices?.[0]?.message?.content) {
      return response.choices[0].message.content;
    }

    throw new Error('No content in LLM response');
  }

  /**
   * Fallback response generator when LLM is unavailable.
   * Uses the kinship database to provide accurate responses.
   */
  private generateFallbackResponse(message: string): string {
    const lowerMessage = message.toLowerCase().trim();

    // Search kinship database for relevant terms
    const results = this.kinshipService.search(message);

    if (results.length === 0) {
      return (
        "I'm not sure about that specific kinship term. Could you try rephrasing your question? " +
        "For example, you could ask 'What do I call my father's brother?' or 'What does chacha mean?'"
      );
    }

    // Build a helpful response from the first few results
    const topResults = results.slice(0, 3);
    const parts = topResults.map((term) => {
      const translations = Object.entries(term.translations)
        .map(([lang, t]) => `${lang.toUpperCase()}: ${t.native} (${t.latin})`)
        .join(', ');

      return (
        `**${term.englishTerm}** (${term.relationshipKey}):\n` +
        `Gender: ${term.gender}, Lineage: ${term.lineage}, Category: ${term.relationshipCategory}\n` +
        `Translations: ${translations}`
      );
    });

    let response = `Here's what I found about Indian kinship terms related to your question:\n\n${parts.join('\n\n')}`;

    if (topResults.length > 1) {
      response +=
        '\n\nThese are the most relevant terms. Would you like to know more about any specific one?';
    }

    return response;
  }

  /**
   * Extract kinship data items from the user message and AI response.
   */
  private extractKinshipData(
    message: string,
    _response: string,
  ): KinshipDataItem[] {
    const results = this.kinshipService.search(message);
    return results.slice(0, 5).map((term: KinshipTerm) => ({
      relationshipKey: term.relationshipKey,
      englishTerm: term.englishTerm,
      gender: term.gender,
      lineage: term.lineage,
      relationshipCategory: term.relationshipCategory,
      translations: term.translations,
    }));
  }

  private generateSessionId(): string {
    return `chat_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
  }
}
