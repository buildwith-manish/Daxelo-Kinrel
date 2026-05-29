"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
var AiCardsService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.AiCardsService = void 0;
const common_1 = require("@nestjs/common");
const kinship_service_1 = require("../kinship/kinship.service");
const FESTIVAL_TEMPLATES = [
    {
        name: 'Diwali',
        icon: '🪔',
        colorTheme: '#FF9933',
        defaultMessageTemplates: [
            'Wishing you and your family a bright and prosperous Diwali! 🪔✨',
            'May the light of Diwali fill your home with happiness and joy!',
            'Happy Diwali! May this festival bring warmth to all your family bonds.',
        ],
    },
    {
        name: 'Holi',
        icon: '🎨',
        colorTheme: '#FF6B6B',
        defaultMessageTemplates: [
            'Happy Holi! May the colors of joy paint your family relationships! 🎨',
            'Wishing you a vibrant Holi filled with love and togetherness!',
            'May the festival of colors strengthen your family bonds! 🌈',
        ],
    },
    {
        name: 'Raksha Bandhan',
        icon: '🧵',
        colorTheme: '#E91E63',
        defaultMessageTemplates: [
            'Happy Raksha Bandhan! Celebrating the sacred bond of love between siblings! 🧵',
            'May the thread of Rakhi always protect and strengthen your sibling bond!',
            'Wishing you a joyful Raksha Bandhan filled with love and memories!',
        ],
    },
    {
        name: 'Navratri',
        icon: '🪘',
        colorTheme: '#9C27B0',
        defaultMessageTemplates: [
            'Happy Navratri! May the divine energy bless your family! 🪘',
            'Wishing you nine nights of devotion, dance, and family togetherness!',
            'May Maa Durga bless your family with strength and prosperity!',
        ],
    },
    {
        name: 'Ganesh Chaturthi',
        icon: '🐘',
        colorTheme: '#FF5722',
        defaultMessageTemplates: [
            'Happy Ganesh Chaturthi! May Lord Ganesha bless your family! 🐘',
            'Ganpati Bappa Morya! Wishing your family prosperity and wisdom!',
            'May the remover of obstacles bless your home and family!',
        ],
    },
    {
        name: 'Dussehra',
        icon: '🏹',
        colorTheme: '#F44336',
        defaultMessageTemplates: [
            'Happy Dussehra! May good always triumph over evil in your family! 🏹',
            'Wishing you a Dussehra filled with victory and celebration!',
            'May the spirit of Dussehra bring courage and prosperity to your family!',
        ],
    },
    {
        name: 'Pongal',
        icon: '🌾',
        colorTheme: '#8BC34A',
        defaultMessageTemplates: [
            'Happy Pongal! May your harvest be bountiful and family bonds strong! 🌾',
            'Pongalo Pongal! Wishing your family prosperity and joy!',
            'May the harvest festival bring abundance and togetherness!',
        ],
    },
    {
        name: 'Onam',
        icon: '🌺',
        colorTheme: '#4CAF50',
        defaultMessageTemplates: [
            'Happy Onam! May the spirit of King Mahabali bless your family! 🌺',
            'Wishing you a beautiful Onam with flower rangoli and family feasts!',
            'May Onam bring prosperity, harmony, and family togetherness!',
        ],
    },
    {
        name: 'Bhai Dooj',
        icon: '👭',
        colorTheme: '#3F51B5',
        defaultMessageTemplates: [
            'Happy Bhai Dooj! Celebrating the eternal bond between siblings! 👭',
            'May the Bhai Dooj tika always protect your sibling bond!',
            'Wishing you a warm and loving Bhai Dooj celebration!',
        ],
    },
    {
        name: 'Makar Sankranti',
        icon: '🪁',
        colorTheme: '#FFC107',
        defaultMessageTemplates: [
            'Happy Makar Sankranti! May your life soar like a kite! 🪁',
            'Til gul ghya, god god bola! Wishing sweetness and joy to your family!',
            'May the sun bring new warmth to your family bonds this Sankranti!',
        ],
    },
];
const PLACEHOLDER_IMAGE_BASE64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
let AiCardsService = AiCardsService_1 = class AiCardsService {
    constructor(kinshipService) {
        this.kinshipService = kinshipService;
        this.logger = new common_1.Logger(AiCardsService_1.name);
    }
    getTemplates() {
        return FESTIVAL_TEMPLATES;
    }
    async generateFestivalCard(dto) {
        const { festival, kinshipTerm, language = 'en', style = 'traditional' } = dto;
        const template = FESTIVAL_TEMPLATES.find((t) => t.name.toLowerCase() === festival.toLowerCase());
        let prompt = '';
        if (template) {
            prompt = `Create a beautiful ${style} Indian festival greeting card for ${festival}. `;
            prompt += `Use ${template.colorTheme} as the primary color theme. `;
            prompt += `Include festive elements like ${template.icon}. `;
        }
        else {
            prompt = `Create a beautiful ${style} Indian festival greeting card for ${festival}. `;
        }
        if (kinshipTerm) {
            const term = this.kinshipService.getByKey(kinshipTerm);
            if (term) {
                const translation = term.translations[language] || term.translations['hi'];
                prompt += `Include the kinship term "${translation?.native || term.englishTerm}" (${term.englishTerm}) in the design. `;
            }
            else {
                prompt += `Include the term "${kinshipTerm}" in the design. `;
            }
        }
        prompt +=
            'The card should have elegant Indian decorative patterns, warm colors, and festive atmosphere. Include space for a personal message.';
        try {
            const imageBase64 = await this.generateImage(prompt);
            return {
                imageBase64,
                festival: template?.name || festival,
                kinshipTerm,
            };
        }
        catch (error) {
            this.logger.warn(`Image generation failed for festival card: ${error instanceof Error ? error.message : 'Unknown error'}`);
            return {
                imageBase64: PLACEHOLDER_IMAGE_BASE64,
                festival: template?.name || festival,
                kinshipTerm,
            };
        }
    }
    async generateKinshipCard(dto) {
        const { relationshipKey, language = 'en', style = 'elegant' } = dto;
        const term = this.kinshipService.getByKey(relationshipKey);
        if (!term) {
            const prompt = `Create a beautiful ${style} Indian family relationship card for "${relationshipKey}". Include elegant Indian decorative patterns and warm family-oriented colors.`;
            try {
                const imageBase64 = await this.generateImage(prompt);
                return { imageBase64 };
            }
            catch {
                return { imageBase64: PLACEHOLDER_IMAGE_BASE64 };
            }
        }
        const translation = term.translations[language] || term.translations['hi'];
        let prompt = `Create a beautiful ${style} Indian kinship relationship card. `;
        prompt += `The card should highlight the relationship "${term.englishTerm}" `;
        if (translation) {
            prompt += `(${translation.native} - ${translation.latin}) `;
        }
        prompt += `from the ${term.relationshipCategory.replace(/_/g, ' ')} category. `;
        prompt += `The design should reflect Indian family values and traditions with decorative elements. `;
        prompt += `Use warm, inviting colors that represent the ${term.lineage} lineage.`;
        try {
            const imageBase64 = await this.generateImage(prompt);
            return { imageBase64 };
        }
        catch (error) {
            this.logger.warn(`Image generation failed for kinship card: ${error instanceof Error ? error.message : 'Unknown error'}`);
            return { imageBase64: PLACEHOLDER_IMAGE_BASE64 };
        }
    }
    async generateImage(prompt) {
        const ZAI = (await Promise.resolve().then(() => __importStar(require('z-ai-web-dev-sdk')))).default;
        const sdk = await ZAI.create();
        const response = await sdk.images.generations.create({
            prompt,
            size: '768x1344',
        });
        if (response?.data?.[0]?.base64) {
            return response.data[0].base64;
        }
        throw new Error('No image data in generation response');
    }
};
exports.AiCardsService = AiCardsService;
exports.AiCardsService = AiCardsService = AiCardsService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [kinship_service_1.KinshipService])
], AiCardsService);
//# sourceMappingURL=ai-cards.service.js.map