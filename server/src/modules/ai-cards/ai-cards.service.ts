import { Injectable, Logger } from '@nestjs/common';
import { KinshipService } from '../kinship/kinship.service';

// ── Types ────────────────────────────────────────────────────────────

export interface FestivalTemplate {
  name: string;
  icon: string;
  colorTheme: string;
  defaultMessageTemplates: string[];
}

// ── Festival Templates ───────────────────────────────────────────────

const FESTIVAL_TEMPLATES: FestivalTemplate[] = [
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

// ── Placeholder Base64 Image ─────────────────────────────────────────
// A simple 1x1 pixel PNG as fallback placeholder
const PLACEHOLDER_IMAGE_BASE64 =
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

@Injectable()
export class AiCardsService {
  private readonly logger = new Logger(AiCardsService.name);

  constructor(private readonly kinshipService: KinshipService) {}

  /**
   * Get festival card templates.
   */
  getTemplates(): FestivalTemplate[] {
    return FESTIVAL_TEMPLATES;
  }

  /**
   * Generate a festival greeting card.
   */
  async generateFestivalCard(dto: {
    festival: string;
    kinshipTerm?: string;
    language?: string;
    style?: string;
  }): Promise<{ imageBase64: string; festival?: string; kinshipTerm?: string }> {
    const { festival, kinshipTerm, language = 'en', style = 'traditional' } = dto;

    // Find the festival template
    const template = FESTIVAL_TEMPLATES.find(
      (t) => t.name.toLowerCase() === festival.toLowerCase(),
    );

    // Build the image generation prompt
    let prompt = '';

    if (template) {
      prompt = `Create a beautiful ${style} Indian festival greeting card for ${festival}. `;
      prompt += `Use ${template.colorTheme} as the primary color theme. `;
      prompt += `Include festive elements like ${template.icon}. `;
    } else {
      prompt = `Create a beautiful ${style} Indian festival greeting card for ${festival}. `;
    }

    if (kinshipTerm) {
      const term = this.kinshipService.getByKey(kinshipTerm);
      if (term) {
        const translation = term.translations[language] || term.translations['hi'];
        prompt += `Include the kinship term "${translation?.native || term.englishTerm}" (${term.englishTerm}) in the design. `;
      } else {
        prompt += `Include the term "${kinshipTerm}" in the design. `;
      }
    }

    prompt +=
      'The card should have elegant Indian decorative patterns, warm colors, and festive atmosphere. Include space for a personal message.';

    // Try to generate image using SDK
    try {
      const imageBase64 = await this.generateImage(prompt);
      return {
        imageBase64,
        festival: template?.name || festival,
        kinshipTerm,
      };
    } catch (error) {
      this.logger.warn(
        `Image generation failed for festival card: ${error instanceof Error ? error.message : 'Unknown error'}`,
      );
      return {
        imageBase64: PLACEHOLDER_IMAGE_BASE64,
        festival: template?.name || festival,
        kinshipTerm,
      };
    }
  }

  /**
   * Generate a kinship relationship card.
   */
  async generateKinshipCard(dto: {
    relationshipKey: string;
    language?: string;
    style?: string;
  }): Promise<{ imageBase64: string }> {
    const { relationshipKey, language = 'en', style = 'elegant' } = dto;

    const term = this.kinshipService.getByKey(relationshipKey);

    if (!term) {
      // Still generate a card but with generic prompt
      const prompt = `Create a beautiful ${style} Indian family relationship card for "${relationshipKey}". Include elegant Indian decorative patterns and warm family-oriented colors.`;
      try {
        const imageBase64 = await this.generateImage(prompt);
        return { imageBase64 };
      } catch {
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
    } catch (error) {
      this.logger.warn(
        `Image generation failed for kinship card: ${error instanceof Error ? error.message : 'Unknown error'}`,
      );
      return { imageBase64: PLACEHOLDER_IMAGE_BASE64 };
    }
  }

  // ── Private Helpers ────────────────────────────────────────────────

  private async generateImage(prompt: string): Promise<string> {
    const ZAI = (await import('z-ai-web-dev-sdk')).default;
    const sdk = await ZAI.create();

    const response = await sdk.images.generations.create({
      prompt,
      size: '768x1344', // Portrait card size
    });

    if (response?.data?.[0]?.base64) {
      return response.data[0].base64;
    }

    throw new Error('No image data in generation response');
  }
}
