import { FamiliesService } from './families.service';
import { CreateFamilyDto } from '../dto/create-family.dto';
import { UpdateFamilyDto } from '../dto/update-family.dto';
export declare class FamiliesController {
    private readonly familiesService;
    constructor(familiesService: FamiliesService);
    listFamilies(user: any): Promise<{
        families: any;
    }>;
    createFamily(user: any, body: CreateFamilyDto): Promise<{
        family: any;
    }>;
    getFamily(user: any, id: string): Promise<{
        family: any;
    }>;
    updateFamily(user: any, id: string, body: UpdateFamilyDto): Promise<{
        family: any;
    }>;
    deleteFamily(user: any, id: string): Promise<{
        message: string;
    }>;
    exportFamily(user: any, id: string): Promise<{
        export: any;
        exportedAt: string;
        format: string;
    }>;
}
