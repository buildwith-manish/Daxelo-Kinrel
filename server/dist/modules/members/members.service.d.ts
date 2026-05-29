import { PrismaService } from '../../prisma/prisma.service';
import { KinrelGateway } from '../gateway/kinrel.gateway';
import { CreateMemberDto } from './dto/create-member.dto';
import { UpdateMemberDto } from './dto/update-member.dto';
export declare class MembersService {
    private prisma;
    private gateway;
    constructor(prisma: PrismaService, gateway: KinrelGateway);
    create(userId: string, familyId: string, dto: CreateMemberDto): Promise<Record<string, any>>;
    findAll(userId: string, familyId: string, query: {
        cursor?: string;
        limit?: number;
        search?: string;
        sort?: string;
        order?: string;
        includeRelationships?: string;
    }): Promise<{
        data: any;
        nextCursor: any;
    }>;
    findOne(userId: string, familyId: string, personId: string): Promise<Record<string, any>>;
    update(userId: string, familyId: string, personId: string, dto: UpdateMemberDto): Promise<Record<string, any>>;
    remove(userId: string, familyId: string, personId: string): Promise<{
        deleted: boolean;
        personId: string;
    }>;
    private requireFamilyMember;
    private requireFamilyRole;
    private formatPerson;
}
