import { AiChatService } from './ai-chat.service';
import { AiChatMessageDto } from './dto/ai-chat-message.dto';
export declare class AiChatController {
    private readonly aiChatService;
    constructor(aiChatService: AiChatService);
    getSuggestions(): Promise<string[]>;
    chat(userId: string, dto: AiChatMessageDto): Promise<import("./ai-chat.service").AiChatResponse>;
    deleteSession(userId: string, sessionId: string): Promise<{
        success: boolean;
    }>;
}
