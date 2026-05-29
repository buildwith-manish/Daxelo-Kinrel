import { PrismaService } from '../prisma/prisma.service';
export declare class HealthController {
    private readonly prisma;
    constructor(prisma: PrismaService);
    check(): Promise<{
        status: "error" | "ok";
        db: "error" | "ok";
        uptime: number;
        memory: number;
        ts: number;
    }>;
}
