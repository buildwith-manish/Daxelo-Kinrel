import { Injectable, Logger } from '@nestjs/common';
import { KinshipService } from '../kinship/kinship.service';
import ZAI from 'z-ai-web-dev-sdk';

interface ChatMessage {
  role: 'user' | 'assistant';
  content: string;
}

interface KinshipResult {
  relationshipKey: string;
  englishTerm: string;
  gender: string;
  lineage: string;
  generation: number;
  relationshipCategory: string;
  searchKeywords: string[];
  translations: Record<string, { native: string; latin: string }>;
}

interface ChatResponse {
  response: string;
  kinshipData?: KinshipResult[];
  suggestions?: string[];
}

const SYSTEM_PROMPT = `You are Kinrel AI, an expert in Indian kinship terminology. You help users understand family relationships across 15 Indian languages. Be warm, culturally sensitive, and educational. When asked about a kinship term, always provide: (1) the Hindi term, (2) English meaning, (3) the relationship path, (4) 2-3 other language translations. Use the kinship data context provided when available. If the user asks about a term not in the data, share what you know from general knowledge but clarify it may not be in the Kinrel database. Keep responses concise but informative. Use bullet points for clarity when listing terms or translations.`;

const MAX_HISTORY = 20;

const DEFAULT_SUGGESTIONS: Record<string, string[]> = {
  hi: [
    'मेरे मामा कौन होते हैं?',
    'चाचा और ताऊ में क्या फर्क है?',
    'ससुर को क्या बुलाते हैं?',
    'ननद कौन होती है?',
    'समधी और समधान में अंतर?',
    'देवरानी और जेठानी क्या है?',
  ],
  en: [
    'What do I call my mother\'s brother?',
    'Who is Chacha?',
    'What is the difference between Tau and Chacha?',
    'Who is Nanad?',
    'What do I call my husband\'s younger brother?',
    'Who is Samdhi?',
    'What is the Hindi term for father-in-law?',
    'How is Devrani different from Jethani?',
  ],
  mr: [
    'मामांना मराठीत काय म्हणतात?',
    'काका आणि मामा यात काय फरक आहे?',
    'सासऱ्यांना काय म्हणतात?',
    'नणंद कोण असते?',
  ],
  bn: [
    'মামা কাকে বলে?',
    'চাচা আর কাকুর মধ্যে পার্থক্য কী?',
    'শ্বশুরকে কী বলে?',
    'ননদ কে?',
  ],
  ta: [
    'தாய் சகோதரனை தமிழில் என்ன சொல்வது?',
    'சித்தா யார்?',
    'மாமனாரை என்ன அழைப்பது?',
  ],
  te: [
    'తల్లి సోదరుడిని తెలుగులో ఏమంటారు?',
    'చిత్త అంటే ఎవరు?',
    'మామయ్యను ఏమంటారు?',
  ],
};

@Injectable()
export class AiChatService {
  private readonly logger = new Logger(AiChatService.name);
  private readonly sessions = new Map<string, ChatMessage[]>();
  private zai: ZAI | null = null;
  private initializationPromise: Promise<void> | null = null;

  constructor(private readonly kinshipService: KinshipService) {
    this.initializationPromise = this.initializeZai();
  }

  private async initializeZai(): Promise<void> {
    try {
      this.zai = await ZAI.create();
      this.logger.log('ZAI SDK initialized successfully');
    } catch (error) {
      this.logger.error('Failed to initialize ZAI SDK', error);
      throw error;
    }
  }

  private async ensureInitialized(): Promise<void> {
    if (this.zai) return;
    if (this.initializationPromise) {
      await this.initializationPromise;
      return;
    }
    this.initializationPromise = this.initializeZai();
    await this.initializationPromise;
  }

  async chat(sessionId: string, message: string, language?: string): Promise<ChatResponse> {
    await this.ensureInitialized();

    // 1. Get or create conversation history
    let history = this.sessions.get(sessionId) || [];

    // 2. Search kinship data for relevant context
    let kinshipData: KinshipResult[] | undefined;
    try {
      const searchResults = this.kinshipService.searchKinship(message);
      if (searchResults.results.length > 0) {
        kinshipData = searchResults.results.slice(0, 5) as KinshipResult[];
      }
    } catch {
      this.logger.warn('Kinship search failed, proceeding without context');
    }

    // 3. Build enriched prompt with kinship context
    let contextMessage = '';
    if (kinshipData && kinshipData.length > 0) {
      const contextEntries = kinshipData.map((k) => {
        const translations = Object.entries(k.translations || {})
          .slice(0, 4)
          .map(([lang, t]) => `${lang}: ${t.native} (${t.latin})`)
          .join(', ');
        return `- ${k.englishTerm} (${k.relationshipKey}): Gender=${k.gender}, Lineage=${k.lineage}, Category=${k.relationshipCategory}. Translations: ${translations || 'N/A'}`;
      });
      contextMessage = `\n\n[Relevant Kinship Data from our database]:\n${contextEntries.join('\n')}\n\nUse this data to provide accurate information. If the data doesn't fully answer the question, supplement with your knowledge but clearly distinguish between database information and general knowledge.`;
    }

    if (language) {
      contextMessage += `\n\n[User's preferred language: ${language}. Please respond considering this language context, though you may use English where appropriate for clarity.]`;
    }

    // 4. Build full message list for LLM
    const systemMessage: ChatMessage = {
      role: 'assistant',
      content: SYSTEM_PROMPT + contextMessage,
    };

    const messagesForLlm: ChatMessage[] = [systemMessage, ...history];

    // Add user message
    const userMessage: ChatMessage = { role: 'user', content: message };
    messagesForLlm.push(userMessage);

    // 5. Call LLM with full conversation history
    try {
      const completion = await this.zai!.chat.completions.create({
        messages: messagesForLlm.map((m) => ({
          role: m.role,
          content: m.content,
        })),
        thinking: { type: 'disabled' },
      });

      const aiResponse = completion.choices[0]?.message?.content || 'I apologize, I was unable to generate a response. Please try again.';

      // 6. Save to history
      history.push(userMessage);
      history.push({ role: 'assistant', content: aiResponse });

      // Trim to max history
      if (history.length > MAX_HISTORY) {
        history = history.slice(-MAX_HISTORY);
      }

      this.sessions.set(sessionId, history);

      // 7. Return response with kinship data if found
      const response: ChatResponse = {
        response: aiResponse,
      };

      if (kinshipData && kinshipData.length > 0) {
        response.kinshipData = kinshipData;
      }

      return response;
    } catch (error) {
      this.logger.error('LLM completion failed', error);
      throw new Error('AI chat service temporarily unavailable. Please try again.');
    }
  }

  clearSession(sessionId: string): void {
    this.sessions.delete(sessionId);
  }

  getSuggestions(language?: string): string[] {
    const lang = language || 'en';
    return DEFAULT_SUGGESTIONS[lang] || DEFAULT_SUGGESTIONS['en'];
  }
}
