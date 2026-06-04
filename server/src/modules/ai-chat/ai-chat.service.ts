import {
  Injectable,
  Logger,
  InternalServerErrorException,
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { KinshipService, KinshipTerm } from '../kinship/kinship.service';
import { GraphService } from '../graph/graph.service';
import { PrismaService } from '../../prisma/prisma.service';
import { ConfigService } from '@nestjs/config';

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

// ── Additional Response Types ──────────────────────────────────────

export interface RelationshipExplanation {
  fromPersonId: string;
  fromPersonName: string;
  toPersonId: string;
  toPersonName: string;
  familyId: string;
  path: Array<{
    personId: string;
    personName: string;
    relationshipKey: string;
  }>;
  explanation: string;
  kinshipTerm?: string;
  kinshipTermHindi?: string;
  distance: number;
}

export interface FamilySummaryResponse {
  familyId: string;
  familyName: string;
  memberCount: number;
  generationCount: number;
  totalRelationships: number;
  summary: string;
  interestingStats: Array<{ label: string; value: string }>;
}

export interface SmartSearchSuggestion {
  query: string;
  suggestions: Array<{
    text: string;
    type: 'person' | 'relationship' | 'term';
    description: string;
  }>;
}

@Injectable()
export class AiChatService {
  private readonly logger = new Logger(AiChatService.name);
  private readonly sessions: Map<string, ChatSession> = new Map();

  constructor(
    private readonly kinshipService: KinshipService,
    private readonly graphService: GraphService,
    private readonly prisma: PrismaService,
    private readonly configService: ConfigService,
  ) {}

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

  // ── New Public API Methods ─────────────────────────────────────────

  /**
   * Get a natural language explanation of the relationship between two persons.
   * Uses the graph engine to find the shortest path, then generates an
   * explanation like "Rahul is your paternal uncle (चाचा) because he is
   * your father's brother".
   */
  async getRelationshipExplanation(
    fromPersonId: string,
    toPersonId: string,
    familyId: string,
  ): Promise<RelationshipExplanation> {
    // Verify both persons exist and belong to the family
    const [fromPerson, toPerson] = await Promise.all([
      this.prisma.person.findFirst({
        where: { id: fromPersonId, familyId, deletedAt: null },
        select: { id: true, name: true, gender: true },
      }),
      this.prisma.person.findFirst({
        where: { id: toPersonId, familyId, deletedAt: null },
        select: { id: true, name: true, gender: true },
      }),
    ]);

    if (!fromPerson) {
      throw new NotFoundException(
        `Person with ID ${fromPersonId} not found in family`,
      );
    }
    if (!toPerson) {
      throw new NotFoundException(
        `Person with ID ${toPersonId} not found in family`,
      );
    }

    if (fromPersonId === toPersonId) {
      return {
        fromPersonId,
        fromPersonName: fromPerson.name,
        toPersonId,
        toPersonName: toPerson.name,
        familyId,
        path: [],
        explanation: `${fromPerson.name} is the same person.`,
        distance: 0,
      };
    }

    // Find the shortest path using the graph engine
    const pathResult = await this.graphService.getPath(
      familyId,
      fromPersonId,
      toPersonId,
    );

    if (!pathResult.path || pathResult.path.length === 0) {
      return {
        fromPersonId,
        fromPersonName: fromPerson.name,
        toPersonId,
        toPersonName: toPerson.name,
        familyId,
        path: [],
        explanation: `No relationship path found between ${fromPerson.name} and ${toPerson.name} in this family tree.`,
        distance: -1,
      };
    }

    // Build the path steps with relationship keys
    const pathSteps: Array<{
      personId: string;
      personName: string;
      relationshipKey: string;
    }> = [];

    for (let i = 0; i < pathResult.relationships.length; i++) {
      const rel = pathResult.relationships[i];
      const person = pathResult.path[i];
      pathSteps.push({
        personId: person.id,
        personName: person.name,
        relationshipKey: rel.relationshipKey,
      });
    }

    // Extract relationship keys for the path
    const relationshipKeys = pathResult.relationships.map(
      (r: any) => r.relationshipKey,
    );

    // Try to find the composed kinship term from the kinship database
    let kinshipTerm: string | undefined;
    let kinshipTermHindi: string | undefined;

    // Search for the final relationship term
    const lastRelKey =
      relationshipKeys.length > 0
        ? relationshipKeys[relationshipKeys.length - 1]
        : undefined;

    if (lastRelKey) {
      const kinshipResults = this.kinshipService.search(lastRelKey);
      if (kinshipResults.length > 0) {
        kinshipTerm = kinshipResults[0].englishTerm;
        kinshipTermHindi =
          kinshipResults[0].translations?.hi?.native || undefined;
      }
    }

    // Generate the natural language explanation
    const explanation = await this.generateRelationshipNarrative(
      fromPerson.name,
      toPerson.name,
      toPerson.gender,
      pathSteps,
      kinshipTerm,
      kinshipTermHindi,
    );

    return {
      fromPersonId,
      fromPersonName: fromPerson.name,
      toPersonId,
      toPersonName: toPerson.name,
      familyId,
      path: pathSteps,
      explanation,
      kinshipTerm,
      kinshipTermHindi,
      distance: pathSteps.length,
    };
  }

  /**
   * Generate a summary of a family — number of members, generations,
   * interesting stats — using the AI model when available, with fallback.
   */
  async getFamilySummary(familyId: string): Promise<FamilySummaryResponse> {
    const family = await this.prisma.family.findUnique({
      where: { id: familyId },
    });

    if (!family) {
      throw new NotFoundException('Family not found');
    }

    // Gather family statistics
    const [persons, relationships, familyMembers] = await Promise.all([
      this.prisma.person.findMany({
        where: { familyId, deletedAt: null },
        select: {
          id: true,
          name: true,
          gender: true,
          generationIndex: true,
          isDeceased: true,
          isAnchor: true,
          occupation: true,
          sideOfFamily: true,
        },
      }),
      this.prisma.relationship.count({
        where: { familyId, isActive: true },
      }),
      this.prisma.familyMember.count({
        where: { familyId },
      }),
    ]);

    const generationCounts: Record<number, number> = {};
    const genderCounts: Record<string, number> = {};
    const sideCounts: Record<string, number> = {};
    let deceasedCount = 0;
    const occupations = new Set<string>();

    for (const p of persons) {
      const gen = p.generationIndex || 0;
      generationCounts[gen] = (generationCounts[gen] || 0) + 1;
      if (p.gender) genderCounts[p.gender] = (genderCounts[p.gender] || 0) + 1;
      if (p.sideOfFamily)
        sideCounts[p.sideOfFamily] = (sideCounts[p.sideOfFamily] || 0) + 1;
      if (p.isDeceased) deceasedCount++;
      if (p.occupation) occupations.add(p.occupation);
    }

    const generationCount = Object.keys(generationCounts).length;
    const anchorPerson = persons.find((p) => p.isAnchor);

    // Build interesting stats
    const interestingStats: Array<{ label: string; value: string }> = [];

    interestingStats.push({
      label: 'Total Members',
      value: String(persons.length),
    });
    interestingStats.push({
      label: 'Generations',
      value: String(generationCount),
    });
    interestingStats.push({
      label: 'Relationships Mapped',
      value: String(relationships),
    });
    interestingStats.push({
      label: 'Registered Users',
      value: String(familyMembers),
    });

    if (deceasedCount > 0) {
      interestingStats.push({
        label: 'Deceased Members',
        value: String(deceasedCount),
      });
    }

    if (Object.keys(genderCounts).length > 0) {
      const genderStr = Object.entries(genderCounts)
        .map(([g, c]) => `${g}: ${c}`)
        .join(', ');
      interestingStats.push({ label: 'Gender Split', value: genderStr });
    }

    if (anchorPerson) {
      interestingStats.push({
        label: 'Anchor Person',
        value: anchorPerson.name,
      });
    }

    if (occupations.size > 0 && occupations.size <= 10) {
      interestingStats.push({
        label: 'Occupations',
        value: [...occupations].slice(0, 5).join(', '),
      });
    }

    // Build generation breakdown
    const genBreakdown = Object.entries(generationCounts)
      .sort(([a], [b]) => Number(a) - Number(b))
      .map(([gen, count]) => `Generation ${gen}: ${count} member${count > 1 ? 's' : ''}`)
      .join(', ');

    // Try to generate AI summary
    let summary: string;
    try {
      summary = await this.generateFamilySummaryNarrative(
        family.name,
        persons.length,
        generationCount,
        relationships,
        genBreakdown,
        family.gotra,
        family.originVillage,
        family.primaryLanguage,
        deceasedCount,
        anchorPerson?.name,
      );
    } catch (error) {
      this.logger.warn(
        `AI summary generation failed, using fallback: ${error instanceof Error ? error.message : 'Unknown'}`,
      );
      summary = this.buildFallbackFamilySummary(
        family.name,
        persons.length,
        generationCount,
        relationships,
        genBreakdown,
        family.gotra,
        family.originVillage,
      );
    }

    return {
      familyId: family.id,
      familyName: family.name,
      memberCount: persons.length,
      generationCount,
      totalRelationships: relationships,
      summary,
      interestingStats,
    };
  }

  /**
   * Return AI-powered search suggestions based on the query and user's
   * family context. Suggests kinship terms, family members, and
   * relationship queries the user might be interested in.
   */
  async getSmartSearchSuggestions(
    query: string,
    userId: string,
  ): Promise<SmartSearchSuggestion> {
    if (!query || query.trim().length === 0) {
      throw new BadRequestException('Query parameter is required');
    }

    const trimmedQuery = query.trim();

    // Get user's families for context
    const userFamilies = await this.prisma.familyMember.findMany({
      where: { userId },
      select: {
        familyId: true,
        family: {
          select: {
            id: true,
            name: true,
            memberCount: true,
            primaryLanguage: true,
          },
        },
      },
    });

    // Search kinship database for relevant terms
    const kinshipResults = this.kinshipService.search(trimmedQuery);

    // Build suggestions from kinship database
    const suggestions: Array<{
      text: string;
      type: 'person' | 'relationship' | 'term';
      description: string;
    }> = [];

    // Add kinship term suggestions
    for (const term of kinshipResults.slice(0, 5)) {
      const hindiTerm = term.translations?.hi;
      suggestions.push({
        text: term.englishTerm,
        type: 'term',
        description:
          `${term.englishTerm} (${term.relationshipKey}) — ${term.lineage} lineage` +
          (hindiTerm
            ? ` | Hindi: ${hindiTerm.native} (${hindiTerm.latin})`
            : ''),
      });

      // Add alias suggestions
      if (term.aliases && term.aliases.length > 0) {
        for (const alias of term.aliases.slice(0, 2)) {
          if (
            alias.toLowerCase().includes(trimmedQuery.toLowerCase()) &&
            alias.toLowerCase() !== term.englishTerm.toLowerCase()
          ) {
            suggestions.push({
              text: alias,
              type: 'term',
              description: `Alias for ${term.englishTerm}`,
            });
          }
        }
      }
    }

    // Add family-specific relationship suggestions
    for (const membership of userFamilies.slice(0, 3)) {
      const familyName = membership.family.name;

      // Search for persons in this family matching the query
      const matchingPersons = await this.prisma.person.findMany({
        where: {
          familyId: membership.familyId,
          deletedAt: null,
          name: { contains: trimmedQuery },
        },
        select: {
          id: true,
          name: true,
          relationshipsFrom: {
            where: { isActive: true },
            select: { relationshipKey: true },
            take: 3,
          },
        },
        take: 5,
      });

      for (const person of matchingPersons) {
        const relKeys = person.relationshipsFrom
          .map((r) => r.relationshipKey)
          .join(', ');
        suggestions.push({
          text: person.name,
          type: 'person',
          description:
            `Member of ${familyName}` +
            (relKeys ? ` | Relationships: ${relKeys}` : ''),
        });
      }

      // Add relationship query suggestions for this family
      if (kinshipResults.length > 0) {
        suggestions.push({
          text: `Find my ${kinshipResults[0].englishTerm.toLowerCase()} in ${familyName}`,
          type: 'relationship',
          description: `Search for ${kinshipResults[0].englishTerm} relationships in the ${familyName} family`,
        });
      }
    }

    // If no suggestions found, provide generic ones based on the query
    if (suggestions.length === 0) {
      const genericSuggestions = [
        `What do I call my father's brother?`,
        `How is "${trimmedQuery}" related to me?`,
        `Find the Hindi term for ${trimmedQuery}`,
        `Explain my relationship to ${trimmedQuery}`,
      ];
      for (const text of genericSuggestions) {
        suggestions.push({
          text,
          type: 'relationship',
          description: 'Suggested search query',
        });
      }
    }

    return {
      query: trimmedQuery,
      suggestions: suggestions.slice(0, 10),
    };
  }

  // ── AI Narrative Generation ──────────────────────────────────────

  private async generateRelationshipNarrative(
    fromName: string,
    toName: string,
    toGender: string | null,
    pathSteps: Array<{ personId: string; personName: string; relationshipKey: string }>,
    kinshipTerm?: string,
    kinshipTermHindi?: string,
  ): Promise<string> {
    if (pathSteps.length === 0) {
      return `${fromName} and ${toName} are the same person.`;
    }

    // Build path description
    const pathDescription = pathSteps
      .map((step, i) => {
        if (i === 0) return `${step.personName} is your ${step.relationshipKey}`;
        return `${step.personName}'s ${step.relationshipKey}`;
      })
      .join(', who is ');

    // Try LLM first
    try {
      const ZAI = (await import('z-ai-web-dev-sdk')).default;
      const sdk = await ZAI.create();

      const prompt =
        `Explain in 1-2 sentences: ${fromName} is related to ${toName} through the path: ${pathDescription}. ` +
        `The composed kinship term is "${kinshipTerm || 'unknown'}"` +
        (kinshipTermHindi ? ` (Hindi: ${kinshipTermHindi})` : '') +
        `. ${toGender === 'female' ? 'The target person is female.' : toGender === 'male' ? 'The target person is male.' : ''} ` +
        `Generate a natural, concise explanation like "Rahul is your paternal uncle (चाचा) because he is your father's brother".`;

      const response = await sdk.chat.completions.create({
        messages: [
          {
            role: 'system',
            content:
              'You are an expert in Indian kinship relationships. Provide concise, natural language explanations of family relationships. Always include Hindi terms where relevant.',
          },
          { role: 'user', content: prompt },
        ],
        model: 'deepseek-chat',
      });

      if (response?.choices?.[0]?.message?.content) {
        return response.choices[0].message.content;
      }
    } catch (error) {
      this.logger.warn(
        `LLM generation failed for relationship narrative, using fallback: ${error instanceof Error ? error.message : 'Unknown'}`,
      );
    }

    // Fallback: build explanation from path steps
    return this.buildFallbackRelationshipNarrative(
      fromName,
      toName,
      pathSteps,
      kinshipTerm,
      kinshipTermHindi,
    );
  }

  private buildFallbackRelationshipNarrative(
    fromName: string,
    toName: string,
    pathSteps: Array<{ personId: string; personName: string; relationshipKey: string }>,
    kinshipTerm?: string,
    kinshipTermHindi?: string,
  ): string {
    if (pathSteps.length === 1) {
      const step = pathSteps[0];
      const hindiStr = kinshipTermHindi ? ` (${kinshipTermHindi})` : '';
      return `${toName} is your ${kinshipTerm || step.relationshipKey}${hindiStr}.`;
    }

    const pathStr = pathSteps
      .map((s) => s.relationshipKey)
      .join(' → ');

    const possessivePath = pathSteps
      .map((s) => s.relationshipKey)
      .join("'s ");

    const hindiStr = kinshipTermHindi ? ` (${kinshipTermHindi})` : '';

    return (
      `${toName} is your ${kinshipTerm || 'relative'}${hindiStr} because ` +
      `${toName} is your ${possessivePath} (path: ${pathStr}).`
    );
  }

  private async generateFamilySummaryNarrative(
    familyName: string,
    memberCount: number,
    generationCount: number,
    totalRelationships: number,
    genBreakdown: string,
    gotra: string | null,
    originVillage: string | null,
    primaryLanguage: string,
    deceasedCount: number,
    anchorName: string | undefined,
  ): Promise<string> {
    try {
      const ZAI = (await import('z-ai-web-dev-sdk')).default;
      const sdk = await ZAI.create();

      const prompt =
        `Generate a concise family summary (3-5 sentences) for the "${familyName}" family with these details:\n` +
        `- Members: ${memberCount}\n` +
        `- Generations: ${generationCount}\n` +
        `- Relationships mapped: ${totalRelationships}\n` +
        `- Generation breakdown: ${genBreakdown}\n` +
        (gotra ? `- Gotra: ${gotra}\n` : '') +
        (originVillage ? `- Origin village: ${originVillage}\n` : '') +
        `- Primary language: ${primaryLanguage}\n` +
        (deceasedCount > 0 ? `- Deceased members: ${deceasedCount}\n` : '') +
        (anchorName ? `- Anchor/Root person: ${anchorName}\n` : '') +
        `Include Hindi kinship terms where relevant. Keep it warm and culturally appropriate.`;

      const response = await sdk.chat.completions.create({
        messages: [
          {
            role: 'system',
            content:
              'You are an expert assistant specializing in Indian family relationships. Generate warm, culturally appropriate family summaries. Include Hindi terms where relevant.',
          },
          { role: 'user', content: prompt },
        ],
        model: 'deepseek-chat',
      });

      if (response?.choices?.[0]?.message?.content) {
        return response.choices[0].message.content;
      }

      throw new Error('No content in LLM response');
    } catch (error) {
      this.logger.warn(
        `LLM family summary failed: ${error instanceof Error ? error.message : 'Unknown'}`,
      );
      throw error; // Let the caller use fallback
    }
  }

  private buildFallbackFamilySummary(
    familyName: string,
    memberCount: number,
    generationCount: number,
    totalRelationships: number,
    genBreakdown: string,
    gotra: string | null,
    originVillage: string | null,
  ): string {
    return (
      `The **${familyName}** family has **${memberCount} members** across **${generationCount} generation${generationCount > 1 ? 's' : ''}** ` +
      `with **${totalRelationships} relationships** mapped. ${genBreakdown}.` +
      (gotra ? ` The family belongs to the **${gotra}** gotra.` : '') +
      (originVillage ? ` The family traces its roots to **${originVillage}**.` : '')
    );
  }
}
