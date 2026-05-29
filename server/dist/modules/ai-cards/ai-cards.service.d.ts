import { KinshipService } from '../kinship/kinship.service';
export interface FestivalTemplate {
    name: string;
    icon: string;
    colorTheme: string;
    defaultMessageTemplates: string[];
}
export declare class AiCardsService {
    private readonly kinshipService;
    private readonly logger;
    constructor(kinshipService: KinshipService);
    getTemplates(): FestivalTemplate[];
    generateFestivalCard(dto: {
        festival: string;
        kinshipTerm?: string;
        language?: string;
        style?: string;
    }): Promise<{
        imageBase64: string;
        festival?: string;
        kinshipTerm?: string;
    }>;
    generateKinshipCard(dto: {
        relationshipKey: string;
        language?: string;
        style?: string;
    }): Promise<{
        imageBase64: string;
    }>;
    private generateImage;
}
