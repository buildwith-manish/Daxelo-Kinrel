import { Injectable, Logger } from '@nestjs/common';
import { GoogleGenerativeAI } from '@google/generative-ai';
import Groq from 'groq-sdk';

@Injectable()
export class AiChatService {
  private readonly logger = new Logger(AiChatService.name);
  private gemini = new GoogleGenerativeAI(process.env.GEMINI_API_KEY || '');
  private groq = new Groq({ apiKey: process.env.GROQ_API_KEY || '' });

  async chat(message: string, sessionId?: string, language?: string): Promise<string> {
    try {
      this.logger.log('Using Gemini...');
      const model = this.gemini.getGenerativeModel({ model: 'gemini-1.5-flash' });
      const result = await model.generateContent(message);
      return result.response.text();
    } catch (geminiError) {
      this.logger.warn('Gemini failed, trying Groq...');
    }
    try {
      this.logger.log('Using Groq...');
      const response = await this.groq.chat.completions.create({
        model: 'llama3-8b-8192',
        messages: [{ role: 'user', content: message }],
      });
      return response.choices[0]?.message?.content || '';
    } catch (groqError) {
      this.logger.warn('Groq failed, trying ZAI...');
    }
    try {
      this.logger.log('Using ZAI GLM...');
      const response = await fetch('https://api.z.ai/api/paas/v4/chat/completions', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${process.env.ZAI_API_KEY}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model: 'glm-4.7-flash',
          messages: [{ role: 'user', content: message }],
        }),
      });
      const data = await response.json() as any;
      return data.choices[0]?.message?.content || '';
    } catch (zaiError) {
      this.logger.error('All AI providers failed');
      throw new Error('AI service unavailable');
    }
  }

  async clearSession(sessionId: string): Promise<void> {
    this.logger.log(`Clearing session: ${sessionId}`);
  }

  async getSuggestions(language?: string): Promise<string[]> {
    return [
      'What do you call your mother\'s brother?',
      'How do you say grandmother in Telugu?',
      'What is the kinship term for father\'s sister?',
    ];
  }
}
