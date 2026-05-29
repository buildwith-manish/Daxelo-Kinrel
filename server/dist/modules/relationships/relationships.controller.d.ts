import { RelationshipsService } from './relationships.service';
import { CreateRelationshipDto } from './dto/create-relationship.dto';
export declare class RelationshipsController {
    private relationshipsService;
    constructor(relationshipsService: RelationshipsService);
    findAll(userId: string, familyId: string, personId?: string): Promise<any>;
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
    remove(userId: string, familyId: string, id: string): Promise<{
        deleted: boolean;
        relationshipId: string;
    }>;
}
