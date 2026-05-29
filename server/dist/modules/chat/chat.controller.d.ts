import { ChatService } from './chat.service';
export declare class ChatController {
    private readonly chatService;
    constructor(chatService: ChatService);
    listMessages(familyId: string, limit?: string, before?: string): Promise<any>;
    sendMessage(familyId: string, body: {
        authorId: string;
        content: string;
    }): Promise<any>;
}
