import { PrismaService } from '../prisma/prisma.service';
export declare class FamiliesService {
    private readonly prisma;
    constructor(prisma: PrismaService);
    listFamilies(userId: string): Promise<any>;
    createFamily(userId: string, data: any): Promise<any>;
    getFamily(userId: string, familyId: string): Promise<any>;
    updateFamily(userId: string, familyId: string, data: any): Promise<any>;
    deleteFamily(userId: string, familyId: string): Promise<{
        message: string;
    }>;
    exportFamily(userId: string, familyId: string): Promise<{
        export: any;
        exportedAt: string;
        format: string;
    }>;
}
