import { MembersService } from './members.service';
import { CreateMemberDto } from './dto/create-member.dto';
import { UpdateMemberDto } from './dto/update-member.dto';
export declare class MembersController {
    private membersService;
    constructor(membersService: MembersService);
    findAll(userId: string, familyId: string, cursor?: string, limit?: string, search?: string, sort?: string, order?: string, includeRelationships?: string): Promise<{
        data: any;
        nextCursor: any;
    }>;
    create(userId: string, familyId: string, dto: CreateMemberDto): Promise<Record<string, any>>;
    findOne(userId: string, familyId: string, personId: string): Promise<Record<string, any>>;
    update(userId: string, familyId: string, personId: string, dto: UpdateMemberDto): Promise<Record<string, any>>;
    remove(userId: string, familyId: string, personId: string): Promise<{
        deleted: boolean;
        personId: string;
    }>;
}
