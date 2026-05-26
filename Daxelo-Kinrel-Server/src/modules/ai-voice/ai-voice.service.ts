import { Injectable, Logger } from '@nestjs/common';

@Injectable()
export class AiVoiceService {
  private readonly logger = new Logger(AiVoiceService.name);

  async transcribeAndSearch(base64Audio: string, language?: string): Promise<string> {
    this.logger.log('Voice transcription requested');
    return 'Voice transcription coming soon';
  }

  async lookup(query: string, language?: string): Promise<string> {
    return this.callZAI(query);
  }

  async quickLookup(audio: string, language?: string): Promise<string> {
    return this.callZAI('Quick lookup: ' + audio);
  }

  private async callZAI(query: string): Promise<string> {
    try {
      const response = await fetch('https://api.z.ai/api/paas/v4/chat/completions', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${process.env.ZAI_API_KEY}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model: 'glm-4.7-flash',
          messages: [{ role: 'user', content: query }],
        }),
      });
      const data = await response.json() as any;
      return data.choices[0]?.message?.content || '';
    } catch (error) {
      this.logger.error('AI lookup failed');
      throw new Error('AI service unavailable');
    }
  }
}
