import { PrismaService } from '../prisma/prisma.service';
export declare class RelationshipsService {
    private readonly prisma;
    constructor(prisma: PrismaService);
    listRelationships(userId: string, familyId: string): Promise<any>;
    createRelationship(userId: string, familyId: string, data: any): Promise<any>;
    deleteRelationship(userId: string, relationshipId: string): Promise<{
        message: string;
        id: string;
    }>;
}
