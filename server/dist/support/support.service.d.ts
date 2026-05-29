import { PrismaService } from '../prisma/prisma.service';
export declare class SupportService {
    private readonly prisma;
    constructor(prisma: PrismaService);
    createTicket(userId: string, data: {
        subject: string;
        message: string;
    }): Promise<any>;
}
