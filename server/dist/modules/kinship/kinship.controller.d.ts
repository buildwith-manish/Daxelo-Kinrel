import { KinshipService } from './kinship.service';
import { KinshipQueryDto } from './dto/kinship-query.dto';
export declare class KinshipController {
    private readonly kinshipService;
    constructor(kinshipService: KinshipService);
    lookup(query: KinshipQueryDto): Promise<import("./kinship.service").KinshipTerm[]>;
    search(term: string, lang: string, limit?: string): Promise<import("./kinship.service").KinshipTerm[]>;
    getLanguages(): Promise<{
        code: string;
        name: string;
    }[]>;
}
