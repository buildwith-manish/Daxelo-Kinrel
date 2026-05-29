import { PrismaService } from '../../prisma/prisma.service';
import { KinrelGateway } from '../gateway/kinrel.gateway';
import { CreateRelationshipDto } from './dto/create-relationship.dto';
export declare function getInverseKey(forwardKey: string, toGender?: string | null): string;
export declare class RelationshipsService {
    private prisma;
    private gateway;
    constructor(prisma: PrismaService, gateway: KinrelGateway);
    create(userId: string, familyId: string, dto: CreateRelationshipDto): Promise<{
        id: any;
        familyId: any;
        fromPersonId: any;
        toPersonId: any;
        relationshipKey: any;
        direction: any;
        isActive: any;
        label: any;
    }>;
    findAll(userId: string, familyId: string, query: {
        personId?: string;
    }): Promise<any>;
    remove(userId: string, familyId: string, relationshipId: string): Promise<{
        deleted: boolean;
        relationshipId: string;
    }>;
    private requireFamilyMember;
    private requireFamilyRole;
    private formatRelationship;
}
