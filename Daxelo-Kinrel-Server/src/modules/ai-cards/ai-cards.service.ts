import { Injectable, Logger } from '@nestjs/common';

@Injectable()
export class AiCardsService {
  private readonly logger = new Logger(AiCardsService.name);

  private async callZAI(query: string): Promise<string> {
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
  }

  async getTemplates(language?: string): Promise<any[]> {
    return [];
  }

  async getFestivalTemplates(): Promise<any[]> {
    return [];
  }

  async generateKinshipCard(dto: any): Promise<any> {
    const explanation = await this.callZAI(`Explain kinship term: ${dto.relationshipKey}`);
    return { term: dto.relationshipKey, explanation, style: dto.style };
  }

  async generateFestivalCard(dto: any): Promise<any> {
    const info = await this.callZAI(`Tell me about festival: ${dto.festival}`);
    return { festival: dto.festival, info, style: dto.style };
  }
}
