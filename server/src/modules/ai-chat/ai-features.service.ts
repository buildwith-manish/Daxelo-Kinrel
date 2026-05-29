import {
  Injectable,
  Logger,
  TooManyRequestsException,
  BadRequestException,
  InternalServerErrorException,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { ConfigService } from '@nestjs/config';
import { GoogleGenerativeAI, HarmCategory, HarmBlockThreshold } from '@google/generative-ai';
import { ExplainRelationshipDto } from './dto/explain-relationship.dto';
import { SmartSearchDto } from './dto/smart-search.dto';
import { KinshipService } from '../kinship/kinship.service';

// ── Response Types ──────────────────────────────────────────────────

export class AiResponse {
  content: string;
  hindiContent?: string;
  tokensUsed: number;
  model: string;
  cached: boolean;
}

export class SmartSearchResult {
  query: string;
  persons: Array<{
    personId: string;
    name: string;
    relationship: string;
    relationshipHindi?: string;
  }>;
  explanation: string;
}

export interface AiChatContext {
  familyId?: string;
  personId?: string;
  language?: string;
}

// ── Constants ───────────────────────────────────────────────────────

const DAILY_RATE_LIMIT = 20;
const MAX_INPUT_TOKENS = 4096;
const MODEL_NAME = 'gemini-2.0-flash';

const SYSTEM_PROMPT = `You are an expert assistant specializing in Indian kinship relationships and family terminology. Your name is KINREL AI.

You help users understand how to address family members in different Indian languages and cultures. You provide clear, respectful, and culturally accurate information about Indian family relationships.

Key guidelines:
1. Always include Hindi translations when discussing Indian kinship terms (in both Devanagari and romanized forms).
2. Explain the lineage context (paternal vs maternal side) when relevant.
3. Be aware of regional variations — the same relationship can have different terms in Hindi, Marathi, Tamil, Telugu, Kannada, Bengali, Gujarati, etc.
4. When explaining a relationship path (e.g., "father's brother's son"), walk through each step clearly.
5. Be respectful of cultural nuances around family hierarchy and addressing elders.
6. If asked about a relationship that doesn't exist or is invalid, gently explain why.
7. Keep responses concise but informative — aim for 2-4 sentences for simple queries, longer for complex paths.
8. When generating family summaries, focus on the structure, notable patterns, and cultural significance.
9. For smart search queries, interpret natural language carefully (e.g., "uncles" could mean chacha, mama, or kaka depending on context).

Always format Hindi terms as: Hindi (Devanagari) — romanized form
Example: चाचा (Chacha)`;

@Injectable()
export class AiFeaturesService {
  private readonly logger = new Logger(AiFeaturesService.name);
  private genAI: GoogleGenerativeAI | null = null;
  private model: any = null;

  constructor(
    private prisma: PrismaService,
    private configService: ConfigService,
    private kinshipService: KinshipService,
  ) {
    this.initializeGemini();
  }

  // ── Initialization ────────────────────────────────────────────────

  private initializeGemini() {
    const apiKey = this.configService.get<string>('GEMINI_API_KEY');
    if (!apiKey) {
      this.logger.warn(
        'GEMINI_API_KEY not set — AI features will use fallback responses',
      );
      return;
    }

    try {
      this.genAI = new GoogleGenerativeAI(apiKey);
      this.model = this.genAI.getGenerativeModel({
        model: MODEL_NAME,
        safetySettings: [
          {
            category: HarmCategory.HARM_CATEGORY_HARASSMENT,
            threshold: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
          },
          {
            category: HarmCategory.HARM_CATEGORY_HATE_SPEECH,
            threshold: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
          },
          {
            category: HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT,
            threshold: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
          },
          {
            category: HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT,
            threshold: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
          },
        ],
        generationConfig: {
          maxOutputTokens: 2048,
          temperature: 0.4,
          topP: 0.95,
          topK: 40,
        },
      });
      this.logger.log(`✅ Gemini AI initialized with model: ${MODEL_NAME}`);
    } catch (error) {
      this.logger.error(
        `Failed to initialize Gemini: ${error instanceof Error ? error.message : 'Unknown error'}`,
      );
    }
  }

  // ── Rate Limiting ─────────────────────────────────────────────────

  private async checkRateLimit(userId: string): Promise<void> {
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    const count = await this.prisma.aiInteraction.count({
      where: {
        userId,
        createdAt: { gte: today },
      },
    });

    if (count >= DAILY_RATE_LIMIT) {
      throw new TooManyRequestsException(
        `AI request limit reached (${DAILY_RATE_LIMIT}/day). Please try again tomorrow.`,
      );
    }
  }

  // ── Interaction Logging ───────────────────────────────────────────

  private async logInteraction(params: {
    userId: string;
    familyId?: string;
    personId?: string;
    interactionType: string;
    prompt: string;
    response: string;
    modelUsed: string;
    tokenCount: number;
  }): Promise<void> {
    try {
      await this.prisma.aiInteraction.create({
        data: {
          userId: params.userId,
          familyId: params.familyId || null,
          personId: params.personId || null,
          interactionType: params.interactionType,
          prompt: params.prompt,
          response:
            params.response.length > 4000
              ? params.response.substring(0, 4000)
              : params.response,
          modelUsed: params.modelUsed,
          tokenCount: params.tokenCount,
        },
      });
    } catch (error) {
      this.logger.warn(
        `Failed to log AI interaction: ${error instanceof Error ? error.message : 'Unknown'}`,
      );
    }
  }

  // ── Gemini API Call ───────────────────────────────────────────────

  private async callGemini(
    prompt: string,
    systemContext?: string,
  ): Promise<{ content: string; tokensUsed: number }> {
    if (!this.model) {
      throw new InternalServerErrorException(
        'AI service is not configured. Please set GEMINI_API_KEY.',
      );
    }

    // Truncate input if it exceeds token limits (rough estimate: ~4 chars per token)
    const maxChars = MAX_INPUT_TOKENS * 4;
    const truncatedPrompt =
      prompt.length > maxChars ? prompt.substring(0, maxChars) : prompt;

    try {
      const result = await this.model.generateContent([
        { text: systemContext || SYSTEM_PROMPT },
        { text: truncatedPrompt },
      ]);

      const response = result.response;
      const content = response.text();
      const tokensUsed =
        result.response?.usageMetadata?.totalTokenCount ?? 0;

      return { content, tokensUsed };
    } catch (error) {
      const errMessage =
        error instanceof Error ? error.message : 'Unknown Gemini API error';
      this.logger.error(`Gemini API error: ${errMessage}`);
      throw new InternalServerErrorException(
        `AI generation failed: ${errMessage}`,
      );
    }
  }

  // ── Public API Methods ────────────────────────────────────────────

  /**
   * Explain a relationship path in natural language.
   * Input: path like ["father", "brother", "son"]
   * Output: "Your father's brother's son is your cousin (चचेरा भाई)"
   */
  async explainRelationship(
    userId: string,
    dto: ExplainRelationshipDto,
  ): Promise<AiResponse> {
    await this.checkRateLimit(userId);

    if (!dto.path || dto.path.length === 0) {
      throw new BadRequestException('Path cannot be empty');
    }

    // Build context from kinship database
    const kinshipContext = this.buildKinshipContext(dto.path);

    const prompt = this.buildExplainPrompt(dto);
    const fullPrompt = `${kinshipContext}\n\n${prompt}`;

    let content: string;
    let tokensUsed: number;
    let cached = false;

    try {
      const result = await this.callGemini(fullPrompt);
      content = result.content;
      tokensUsed = result.tokensUsed;
    } catch (error) {
      this.logger.warn(
        `Gemini call failed for explainRelationship, using fallback: ${error instanceof Error ? error.message : 'Unknown'}`,
      );
      content = this.fallbackExplainRelationship(dto);
      tokensUsed = 0;
      cached = true;
    }

    const hindiContent = this.extractHindiContent(content);

    await this.logInteraction({
      userId,
      interactionType: 'explain_relationship',
      prompt: dto.path.join(' → '),
      response: content,
      modelUsed: cached ? 'fallback' : MODEL_NAME,
      tokenCount: tokensUsed,
    });

    return {
      content,
      hindiContent,
      tokensUsed,
      model: cached ? 'fallback' : MODEL_NAME,
      cached,
    };
  }

  /**
   * Generate a family summary.
   * Input: familyId
   * Output: Rich text summary of the family (size, generations, notable members, traditions)
   */
  async generateFamilySummary(
    userId: string,
    familyId: string,
  ): Promise<AiResponse> {
    await this.checkRateLimit(userId);

    const familyData = await this.gatherFamilyData(familyId);
    if (!familyData) {
      throw new BadRequestException('Family not found or access denied');
    }

    const prompt = this.buildFamilySummaryPrompt(familyData);

    let content: string;
    let tokensUsed: number;
    let cached = false;

    try {
      const result = await this.callGemini(prompt);
      content = result.content;
      tokensUsed = result.tokensUsed;
    } catch (error) {
      this.logger.warn(
        `Gemini call failed for familySummary, using fallback: ${error instanceof Error ? error.message : 'Unknown'}`,
      );
      content = this.fallbackFamilySummary(familyData);
      tokensUsed = 0;
      cached = true;
    }

    const hindiContent = this.extractHindiContent(content);

    await this.logInteraction({
      userId,
      familyId,
      interactionType: 'family_summary',
      prompt: `Generate summary for family: ${familyData.name}`,
      response: content,
      modelUsed: cached ? 'fallback' : MODEL_NAME,
      tokenCount: tokensUsed,
    });

    return {
      content,
      hindiContent,
      tokensUsed,
      model: cached ? 'fallback' : MODEL_NAME,
      cached,
    };
  }

  /**
   * Generate family history summary.
   * Input: familyId
   * Output: Narrative summary based on available data
   */
  async generateHistorySummary(
    userId: string,
    familyId: string,
  ): Promise<AiResponse> {
    await this.checkRateLimit(userId);

    const familyData = await this.gatherFamilyData(familyId);
    if (!familyData) {
      throw new BadRequestException('Family not found or access denied');
    }

    const prompt = this.buildHistorySummaryPrompt(familyData);

    let content: string;
    let tokensUsed: number;
    let cached = false;

    try {
      const result = await this.callGemini(prompt);
      content = result.content;
      tokensUsed = result.tokensUsed;
    } catch (error) {
      this.logger.warn(
        `Gemini call failed for historySummary, using fallback: ${error instanceof Error ? error.message : 'Unknown'}`,
      );
      content = this.fallbackHistorySummary(familyData);
      tokensUsed = 0;
      cached = true;
    }

    const hindiContent = this.extractHindiContent(content);

    await this.logInteraction({
      userId,
      familyId,
      interactionType: 'history_summary',
      prompt: `Generate history for family: ${familyData.name}`,
      response: content,
      modelUsed: cached ? 'fallback' : MODEL_NAME,
      tokenCount: tokensUsed,
    });

    return {
      content,
      hindiContent,
      tokensUsed,
      model: cached ? 'fallback' : MODEL_NAME,
      cached,
    };
  }

  /**
   * Smart family search.
   * Input: natural language query like "show me all my uncles"
   * Output: List of matching persons with their relationships
   */
  async smartSearch(
    userId: string,
    dto: SmartSearchDto,
  ): Promise<SmartSearchResult> {
    await this.checkRateLimit(userId);

    // Get family members with their relationships
    const familyMembers = await this.prisma.person.findMany({
      where: {
        familyId: dto.familyId,
        deletedAt: null,
      },
      include: {
        relationshipsFrom: {
          where: { isActive: true },
          select: {
            relationshipKey: true,
            toPersonId: true,
          },
        },
        relationshipsTo: {
          where: { isActive: true },
          select: {
            relationshipKey: true,
            fromPersonId: true,
          },
        },
      },
    });

    // Search kinship database for relevant terms
    const kinshipResults = this.kinshipService.search(dto.query);

    // Build context for AI
    const membersContext = familyMembers
      .map((p) => {
        const relsFrom = p.relationshipsFrom
          .map((r) => r.relationshipKey)
          .join(', ');
        const relsTo = p.relationshipsTo
          .map((r) => r.relationshipKey)
          .join(', ');
        return `${p.name} (ID: ${p.id}, gender: ${p.gender || 'unknown'}${relsFrom ? `, is: ${relsFrom}` : ''}${relsTo ? `, related as: ${relsTo}` : ''})`;
      })
      .join('\n');

    const kinshipContext = kinshipResults
      .slice(0, 5)
      .map(
        (t) =>
          `${t.englishTerm} (${t.relationshipKey}): Hindi - ${t.translations?.hi?.native || 'N/A'} (${t.translations?.hi?.latin || 'N/A'})`,
      )
      .join('\n');

    const prompt = `The user is searching their family with the query: "${dto.query}"

Family members:
${membersContext}

Relevant kinship terms:
${kinshipContext}

Based on the query "${dto.query}", identify which family members match. For each match, explain their relationship. Include Hindi terms where relevant.

Respond in this exact JSON format:
{
  "persons": [
    {"personId": "id", "name": "Name", "relationship": "English description", "relationshipHindi": "Hindi term (Devanagari) - romanized"}
  ],
  "explanation": "Brief explanation of what was searched and found"
}`;

    let content: string;
    let tokensUsed: number;

    try {
      const result = await this.callGemini(prompt);
      content = result.content;
      tokensUsed = result.tokensUsed;
    } catch (error) {
      // Fallback: use kinship database search
      const persons = this.fallbackSmartSearch(familyMembers, kinshipResults);
      await this.logInteraction({
        userId,
        familyId: dto.familyId,
        interactionType: 'smart_search',
        prompt: dto.query,
        response: JSON.stringify(persons),
        modelUsed: 'fallback',
        tokenCount: 0,
      });

      return {
        query: dto.query,
        persons,
        explanation: `Found ${persons.length} matching members based on kinship database lookup.`,
      };
    }

    // Parse AI response
    let parsed: SmartSearchResult;
    try {
      const jsonStr = this.extractJsonFromResponse(content);
      const data = JSON.parse(jsonStr);
      parsed = {
        query: dto.query,
        persons: (data.persons || []).map((p: any) => ({
          personId: p.personId || '',
          name: p.name || '',
          relationship: p.relationship || '',
          relationshipHindi: p.relationshipHindi,
        })),
        explanation: data.explanation || '',
      };
    } catch {
      parsed = {
        query: dto.query,
        persons: [],
        explanation: content,
      };
    }

    await this.logInteraction({
      userId,
      familyId: dto.familyId,
      interactionType: 'smart_search',
      prompt: dto.query,
      response: content,
      modelUsed: MODEL_NAME,
      tokenCount: tokensUsed,
    });

    return parsed;
  }

  /**
   * General AI chat about family relationships.
   */
  async chat(
    userId: string,
    message: string,
    context?: AiChatContext,
  ): Promise<AiResponse> {
    await this.checkRateLimit(userId);

    // Build context from kinship database based on the message
    const kinshipResults = this.kinshipService.search(message);
    const kinshipContext =
      kinshipResults.length > 0
        ? kinshipResults
            .slice(0, 5)
            .map(
              (t) =>
                `${t.englishTerm} (${t.relationshipKey}): ${Object.entries(t.translations)
                  .map(([lang, tr]) => `${lang}: ${tr.native} (${tr.latin})`)
                  .join(', ')}`,
            )
            .join('\n')
        : '';

    let familyContext = '';
    if (context?.familyId) {
      const family = await this.prisma.family.findUnique({
        where: { id: context.familyId },
      });
      if (family) {
        familyContext = `\n\nThe user is currently viewing the family "${family.name}" (${family.primaryLanguage}).`;
      }
    }

    const prompt = `${kinshipContext ? `Relevant kinship data:\n${kinshipContext}\n\n` : ''}${familyContext}User's question: ${message}

Provide a helpful response about Indian kinship and family relationships. Include Hindi terms where relevant.`;

    let content: string;
    let tokensUsed: number;
    let cached = false;

    try {
      const result = await this.callGemini(prompt);
      content = result.content;
      tokensUsed = result.tokensUsed;
    } catch (error) {
      this.logger.warn(
        `Gemini call failed for chat, using fallback: ${error instanceof Error ? error.message : 'Unknown'}`,
      );
      content = this.fallbackChat(message, kinshipResults);
      tokensUsed = 0;
      cached = true;
    }

    const hindiContent = this.extractHindiContent(content);

    await this.logInteraction({
      userId,
      familyId: context?.familyId,
      personId: context?.personId,
      interactionType: 'chat',
      prompt: message,
      response: content,
      modelUsed: cached ? 'fallback' : MODEL_NAME,
      tokenCount: tokensUsed,
    });

    return {
      content,
      hindiContent,
      tokensUsed,
      model: cached ? 'fallback' : MODEL_NAME,
      cached,
    };
  }

  // ── Data Gathering ────────────────────────────────────────────────

  private async gatherFamilyData(familyId: string) {
    const family = await this.prisma.family.findUnique({
      where: { id: familyId },
    });

    if (!family) return null;

    const persons = await this.prisma.person.findMany({
      where: { familyId, deletedAt: null },
      include: {
        relationshipsFrom: {
          where: { isActive: true },
          select: { relationshipKey: true },
        },
      },
      orderBy: { generationIndex: 'asc' },
    });

    const relationships = await this.prisma.relationship.findMany({
      where: { familyId, isActive: true },
    });

    const generationCounts: Record<number, number> = {};
    for (const p of persons) {
      const gen = p.generationIndex || 0;
      generationCounts[gen] = (generationCounts[gen] || 0) + 1;
    }

    return {
      id: family.id,
      name: family.name,
      description: family.description,
      primaryLanguage: family.primaryLanguage,
      gotra: family.gotra,
      originVillage: family.originVillage,
      memberCount: family.memberCount,
      generationCount: family.generationCount,
      persons: persons.map((p) => ({
        id: p.id,
        name: p.name,
        gender: p.gender,
        generationIndex: p.generationIndex,
        isAnchor: p.isAnchor,
        isDeceased: p.isDeceased,
        occupation: p.occupation,
        city: p.city,
        sideOfFamily: p.sideOfFamily,
        relationshipKeys: p.relationshipsFrom.map((r) => r.relationshipKey),
      })),
      totalRelationships: relationships.length,
      generationCounts,
    };
  }

  // ── Prompt Builders ───────────────────────────────────────────────

  private buildKinshipContext(path: string[]): string {
    const terms = path
      .map((step) => {
        const results = this.kinshipService.search(step);
        if (results.length > 0) {
          const term = results[0];
          return `"${step}": ${term.englishTerm} — Hindi: ${term.translations?.hi?.native || 'N/A'} (${term.translations?.hi?.latin || 'N/A'}), Lineage: ${term.lineage}, Category: ${term.relationshipCategory}`;
        }
        return `"${step}": No kinship data found`;
      })
      .join('\n');

    return `Known kinship terms for this path:\n${terms}`;
  }

  private buildExplainPrompt(dto: ExplainRelationshipDto): string {
    const pathStr = dto.path.join(' → ');
    const fromStr = dto.fromPersonName ? ` from ${dto.fromPersonName}` : '';
    const toStr = dto.toPersonName ? ` to ${dto.toPersonName}` : '';
    const langStr = dto.language && dto.language !== 'en'
      ? ` Respond primarily in ${dto.language}.`
      : '';

    return `Explain this relationship path: ${pathStr}${fromStr}${toStr}.

Walk through each step and explain what the final relationship is.
Include the Hindi term for the final relationship in both Devanagari script and romanized form.
If the path is ambiguous (e.g., could be paternal or maternal), explain both possibilities.${langStr}

Format your response as:
1. Step-by-step explanation
2. Final relationship term (English)
3. Hindi term: [Devanagari] ([romanized])
4. Cultural context (if relevant)`;
  }

  private buildFamilySummaryPrompt(data: any): string {
    const personList = data.persons
      .slice(0, 30) // Limit to avoid token overflow
      .map(
        (p: any) =>
          `- ${p.name} (Gen ${p.generationIndex}, ${p.gender || 'unknown'}${p.isAnchor ? ', anchor' : ''}${p.occupation ? `, ${p.occupation}` : ''}${p.sideOfFamily ? `, ${p.sideOfFamily} side` : ''})`,
      )
      .join('\n');

    const genSummary = Object.entries(data.generationCounts)
      .map(([gen, count]) => `Generation ${gen}: ${count} members`)
      .join(', ');

    return `Generate a rich family summary for the "${data.name}" family.

Family details:
- Name: ${data.name}
- Description: ${data.description || 'None'}
- Primary language: ${data.primaryLanguage}
- Gotra: ${data.gotra || 'Not specified'}
- Origin village: ${data.originVillage || 'Not specified'}
- Total members: ${data.memberCount}
- Total relationships: ${data.totalRelationships}
- Generation breakdown: ${genSummary}

Members (sample):
${personList}

Create a comprehensive summary that includes:
1. Overview of the family's size and structure
2. Notable patterns (e.g., large generation gaps, primarily paternal lineage)
3. Cultural observations based on the gotra, origin village, and language
4. Any interesting observations about the family tree
5. Include Hindi translations of key terms where relevant`;
  }

  private buildHistorySummaryPrompt(data: any): string {
    const deceasedMembers = data.persons.filter((p: any) => p.isDeceased);
    const anchorPerson = data.persons.find((p: any) => p.isAnchor);

    const genDetails = Object.entries(data.generationCounts)
      .sort(([a], [b]) => Number(a) - Number(b))
      .map(([gen, count]) => {
        const genMembers = data.persons.filter(
          (p: any) => p.generationIndex === Number(gen),
        );
        const occupations = genMembers
          .filter((p: any) => p.occupation)
          .map((p: any) => `${p.name}: ${p.occupation}`);
        return `Generation ${gen} (${count} members): ${occupations.length > 0 ? occupations.join(', ') : 'No occupation data'}`;
      })
      .join('\n');

    return `Create a narrative history summary for the "${data.name}" family based on the available data.

Family details:
- Name: ${data.name}
- Origin village: ${data.originVillage || 'Unknown'}
- Gotra: ${data.gotra || 'Not specified'}
- Primary language: ${data.primaryLanguage}
- Total members: ${data.memberCount}
- Deceased members: ${deceasedMembers.length}
- Anchor person: ${anchorPerson?.name || 'Not set'}

${genDetails}

Write a narrative summary that:
1. Tells the family's story as a flowing narrative
2. Highlights the generational journey
3. Notes any members who have passed away with respect
4. Mentions the family's roots (gotra, origin village)
5. Observes occupational trends across generations
6. Keeps a respectful, warm tone appropriate for Indian family contexts
7. Include Hindi terms where culturally relevant`;
  }

  // ── Fallback Responses ────────────────────────────────────────────

  private fallbackExplainRelationship(dto: ExplainRelationshipDto): string {
    const pathStr = dto.path.join("'s ");

    // Try to find a direct kinship match for the last element
    const lastStep = dto.path[dto.path.length - 1];
    const results = this.kinshipService.search(lastStep);

    if (results.length > 0) {
      const term = results[0];
      const hindiTerm = term.translations?.hi;
      return (
        `Your ${pathStr} is your **${term.englishTerm}**.\n\n` +
        `This is a ${term.lineage} relationship in the ${term.relationshipCategory.replace(/_/g, ' ')} category.\n\n` +
        (hindiTerm
          ? `In Hindi: **${hindiTerm.native}** (${hindiTerm.latin})`
          : '')
      );
    }

    return (
      `Your ${pathStr} is a relationship in your family tree. ` +
      `I don't have a specific kinship term for this path in my database, ` +
      `but in Indian family context, this would typically be described based on ` +
      `whether the connection is through your paternal (पैतृक) or maternal (मातृक) side.`
    );
  }

  private fallbackFamilySummary(data: any): string {
    const genSummary = Object.entries(data.generationCounts)
      .map(([gen, count]) => `${count} member${count > 1 ? 's' : ''} in Generation ${gen}`)
      .join(', ');

    return (
      `## ${data.name} Family Summary\n\n` +
      `The **${data.name}** family has **${data.memberCount} members** across **${data.generationCount} generation${data.generationCount > 1 ? 's' : ''}**.\n\n` +
      `**Generation breakdown:** ${genSummary}\n\n` +
      (data.gotra ? `**Gotra:** ${data.gotra}\n\n` : '') +
      (data.originVillage
        ? `**Origin village:** ${data.originVillage}\n\n`
        : '') +
      `**Total relationships mapped:** ${data.totalRelationships}\n\n` +
      `This family tree is documented in ${data.primaryLanguage === 'en' ? 'English' : data.primaryLanguage}.`
    );
  }

  private fallbackHistorySummary(data: any): string {
    return (
      `## History of the ${data.name} Family\n\n` +
      `The ${data.name} family's story spans ${data.generationCount} generations with ${data.memberCount} documented members.\n\n` +
      (data.originVillage
        ? `The family traces its roots to ${data.originVillage}.\n\n`
        : '') +
      (data.gotra
        ? `The family belongs to the ${data.gotra} gotra.\n\n`
        : '') +
      `Through the generations, this family has grown and expanded, ` +
      `maintaining connections that span across ${data.totalRelationships} recorded relationships. ` +
      `Each generation has contributed to the family's legacy and cultural heritage.`
    );
  }

  private fallbackSmartSearch(
    familyMembers: any[],
    kinshipResults: any[],
  ): Array<{
    personId: string;
    name: string;
    relationship: string;
    relationshipHindi?: string;
  }> {
    const results: Array<{
      personId: string;
      name: string;
      relationship: string;
      relationshipHindi?: string;
    }> = [];

    for (const member of familyMembers) {
      const allRelKeys = [
        ...member.relationshipsFrom.map((r: any) => r.relationshipKey),
        ...member.relationshipsTo.map((r: any) => r.relationshipKey),
      ];

      for (const relKey of allRelKeys) {
        const kinMatch = kinshipResults.find(
          (k) => k.relationshipKey === relKey,
        );
        if (kinMatch) {
          const hindiTerm = kinMatch.translations?.hi;
          results.push({
            personId: member.id,
            name: member.name,
            relationship: kinMatch.englishTerm,
            relationshipHindi: hindiTerm
              ? `${hindiTerm.native} (${hindiTerm.latin})`
              : undefined,
          });
          break; // One match per person
        }
      }
    }

    return results;
  }

  private fallbackChat(message: string, kinshipResults: any[]): string {
    if (kinshipResults.length > 0) {
      const terms = kinshipResults
        .slice(0, 3)
        .map((t) => {
          const hindi = t.translations?.hi;
          return (
            `**${t.englishTerm}** (${t.relationshipKey}): ` +
            `Gender: ${t.gender}, Lineage: ${t.lineage}, Category: ${t.relationshipCategory}` +
            (hindi ? `\n   Hindi: ${hindi.native} (${hindi.latin})` : '')
          );
        })
        .join('\n\n');

      return (
        `Here's what I found about Indian kinship terms related to your question:\n\n${terms}\n\n` +
        `Would you like to know more about any specific term?`
      );
    }

    return (
      `I'm not sure about that specific kinship term. Could you try rephrasing your question? ` +
      `For example, you could ask "What do I call my father's brother?" or "What does chacha mean?"`
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────

  private extractHindiContent(content: string): string | undefined {
    // Try to extract Hindi content from the response
    // Look for Devanagari script blocks
    const devanagariRegex = /[\u0900-\u097F]+[\u0900-\u097F\s]*/g;
    const matches = content.match(devanagariRegex);
    if (matches && matches.length > 0) {
      return matches.join(' ').trim();
    }
    return undefined;
  }

  private extractJsonFromResponse(content: string): string {
    // Try to find JSON in the response (may be wrapped in markdown code blocks)
    const jsonMatch = content.match(/```(?:json)?\s*([\s\S]*?)```/);
    if (jsonMatch) {
      return jsonMatch[1].trim();
    }

    // Try to find raw JSON object
    const objectMatch = content.match(/\{[\s\S]*\}/);
    if (objectMatch) {
      return objectMatch[0];
    }

    return content;
  }

  /**
   * Get usage stats for a user.
   */
  async getUsageStats(userId: string): Promise<{
    today: number;
    limit: number;
    remaining: number;
  }> {
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    const count = await this.prisma.aiInteraction.count({
      where: {
        userId,
        createdAt: { gte: today },
      },
    });

    return {
      today: count,
      limit: DAILY_RATE_LIMIT,
      remaining: Math.max(0, DAILY_RATE_LIMIT - count),
    };
  }
}
