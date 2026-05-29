import { RelationshipsService } from './relationships.service';
import { CreateRelationshipDto } from '../dto/create-relationship.dto';
export declare class RelationshipsController {
    private readonly relationshipsService;
    constructor(relationshipsService: RelationshipsService);
    listRelationships(user: any, familyId: string): Promise<{
        relationships: any;
    }>;
    createRelationship(user: any, familyId: string, body: CreateRelationshipDto): Promise<{
        relationship: any;
    }>;
}
export declare class RelationshipController {
    private readonly relationshipsService;
    constructor(relationshipsService: RelationshipsService);
    deleteRelationship(user: any, id: string): Promise<{
        message: string;
        id: string;
    }>;
}
