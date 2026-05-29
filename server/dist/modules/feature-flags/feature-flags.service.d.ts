import { PrismaService } from '../../prisma/prisma.service';
export declare class FeatureFlagsService {
    private prisma;
    constructor(prisma: PrismaService);
    isEnabled(flagName: string): Promise<boolean>;
    getAllFlags(): Promise<any>;
    setFlag(name: string, enabled: boolean, description?: string): Promise<any>;
}
