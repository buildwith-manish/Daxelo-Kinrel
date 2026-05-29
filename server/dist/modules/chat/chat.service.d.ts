import { PrismaService } from '../../prisma/prisma.service';
export declare class ChatService {
    private readonly prisma;
    constructor(prisma: PrismaService);
    listMessages(familyId: string, limit?: number, before?: string): Promise<any>;
    sendMessage(familyId: string, authorId: string, content: string): Promise<any>;
}
