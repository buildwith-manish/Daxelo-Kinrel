import { Injectable, Logger } from '@nestjs/common';
import { GoogleGenerativeAI } from '@google/generative-ai';
import Groq from 'groq-sdk';

@Injectable()
export class AiProviderService {
  private readonly logger = new Logger(AiProviderService.name);
  private gemini = new GoogleGenerativeAI(process.env.GEMINI_API_KEY || '');
  private groq = new Groq({ apiKey: process.env.GROQ_API_KEY || '' });

  async chat(prompt: string): Promise<string> {
    // Try Gemini first
    try {
      this.logger.log('Using Gemini...');
      const model = this.gemini.getGenerativeModel({ model: 'gemini-1.5-flash' });
      const result = await model.generateContent(prompt);
      return result.response.text();
    } catch (geminiError) {
      this.logger.warn('Gemini failed, switching to Groq...');
      // Fallback to Groq
      try {
        const response = await this.groq.chat.completions.create({
          model: 'llama3-8b-8192',
          messages: [{ role: 'user', content: prompt }],
        });
        return response.choices[0]?.message?.content || '';
      } catch (groqError) {
        this.logger.error('Both AI providers failed');
        throw new Error('AI service unavailable');
      }
    }
  }
}
