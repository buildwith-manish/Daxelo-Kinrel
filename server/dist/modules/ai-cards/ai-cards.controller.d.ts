import { AiCardsService } from './ai-cards.service';
import { FestivalCardDto, KinshipCardDto } from './dto/card.dto';
export declare class AiCardsController {
    private readonly aiCardsService;
    constructor(aiCardsService: AiCardsService);
    getTemplates(): Promise<import("./ai-cards.service").FestivalTemplate[]>;
    generateFestivalCard(dto: FestivalCardDto): Promise<{
        imageBase64: string;
        festival?: string;
        kinshipTerm?: string;
    }>;
    generateKinshipCard(dto: KinshipCardDto): Promise<{
        imageBase64: string;
    }>;
}
