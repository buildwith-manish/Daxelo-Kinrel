import { KinshipService } from '../kinship/kinship.service';
export interface ChatMessage {
    role: 'system' | 'user' | 'assistant';
    content: string;
}
export interface KinshipDataItem {
    relationshipKey: string;
    englishTerm: string;
    gender: string;
    lineage: string;
    relationshipCategory: string;
    translations: Record<string, {
        native: string;
        latin: string;
    }>;
}
export interface AiChatResponse {
    response: string;
    kinshipData: KinshipDataItem[];
}
export declare class AiChatService {
    private readonly kinshipService;
    private readonly logger;
    private readonly sessions;
    constructor(kinshipService: KinshipService);
    getSuggestions(): string[];
    chat(userId: string, dto: {
        sessionId?: string;
        message: string;
    }): Promise<AiChatResponse>;
    deleteSession(sessionId: string, userId: string): {
        success: boolean;
    };
    private generateLlmResponse;
    private generateFallbackResponse;
    private extractKinshipData;
    private generateSessionId;
}
