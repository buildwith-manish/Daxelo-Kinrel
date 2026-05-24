import { Injectable, Logger, BadRequestException } from '@nestjs/common';
import { KinshipService } from '../kinship/kinship.service';
import { ZAI } from 'z-ai-web-dev-sdk';

interface FestivalTemplate {
  name: string;
  icon: string;
  colorTheme: string;
  defaultMessageTemplates: string[];
}

@Injectable()
export class AiCardsService {
  private readonly logger = new Logger(AiCardsService.name);
  private readonly zai = ZAI.create();

  private readonly festivalTemplates: FestivalTemplate[] = [
    {
      name: 'Diwali',
      icon: '🪔',
      colorTheme: '#FFD700',
      defaultMessageTemplates: [
        'Happy Diwali, dear {term}! May the festival of lights bring joy to your life.',
        'Wishing you a bright and prosperous Diwali, {term}!',
        'May the diyas light up your life, {term}. Happy Diwali!',
      ],
    },
    {
      name: 'Raksha Bandhan',
      icon: '🧵',
      colorTheme: '#FF69B4',
      defaultMessageTemplates: [
        'Happy Raksha Bandhan, {term}! The bond we share is unbreakable.',
        'A thread of love and protection, {term}. Happy Rakhi!',
        'Celebrating our special bond, {term}. Happy Raksha Bandhan!',
      ],
    },
    {
      name: 'Bhai Dooj',
      icon: '🙏',
      colorTheme: '#FF8C00',
      defaultMessageTemplates: [
        'Happy Bhai Dooj, {term}! Blessings and love always.',
        'Celebrating the bond between siblings, {term}. Happy Bhai Dooj!',
        'May our bond grow stronger, {term}. Happy Bhai Dooj!',
      ],
    },
    {
      name: 'Holi',
      icon: '🎨',
      colorTheme: '#FF69B4',
      defaultMessageTemplates: [
        'Happy Holi, {term}! May your life be colorful and bright.',
        'Let the colors of Holi spread joy, {term}!',
        'Wishing you a vibrant and joyful Holi, {term}!',
      ],
    },
    {
      name: 'Eid',
      icon: '🌙',
      colorTheme: '#2E8B57',
      defaultMessageTemplates: [
        'Eid Mubarak, {term}! May blessings and peace be with you.',
        'Wishing you joy and prosperity, {term}. Eid Mubarak!',
        'May this Eid bring happiness to your home, {term}.',
      ],
    },
    {
      name: 'Navratri',
      icon: '🪘',
      colorTheme: '#DC143C',
      defaultMessageTemplates: [
        'Happy Navratri, {term}! May the divine bless you.',
        'Celebrating the power of the goddess, {term}. Happy Navratri!',
        'May Navratri bring strength and joy, {term}!',
      ],
    },
    {
      name: 'Pongal',
      icon: '🌾',
      colorTheme: '#8B4513',
      defaultMessageTemplates: [
        'Happy Pongal, {term}! May the harvest bring prosperity.',
        'Celebrating the harvest festival, {term}. Happy Pongal!',
        'May prosperity overflow, {term}. Happy Pongal!',
      ],
    },
    {
      name: 'Onam',
      icon: '🌺',
      colorTheme: '#FFC107',
      defaultMessageTemplates: [
        'Happy Onam, {term}! May the king visit your home.',
        'Celebrating the spirit of Onam, {term}!',
        'Wishing you a joyful Onam, {term}!',
      ],
    },
    {
      name: 'Baisakhi',
      icon: '🌽',
      colorTheme: '#FF8C00',
      defaultMessageTemplates: [
        'Happy Baisakhi, {term}! May the new year bring abundance.',
        'Celebrating the harvest and new beginnings, {term}. Happy Baisakhi!',
        'May Baisakhi bring joy and prosperity, {term}!',
      ],
    },
    {
      name: 'Durga Puja',
      icon: '🔱',
      colorTheme: '#8B008B',
      defaultMessageTemplates: [
        'Happy Durga Puja, {term}! May the goddess empower you.',
        'Celebrating the victory of good over evil, {term}. Happy Durga Puja!',
        'May Maa Durga bless you, {term}. Shubho Durga Puja!',
      ],
    },
  ];

  constructor(private readonly kinshipService: KinshipService) {}

  /**
   * Generate a festival greeting card image using AI.
   */
  async generateFestivalCard(options: {
    festival: string;
    kinshipTerm: string;
    language: string;
    style: string;
  }) {
    const { festival, kinshipTerm, language = 'en', style = 'traditional' } = options;

    // Find the matching template for additional context
    const template = this.festivalTemplates.find(
      (t) => t.name.toLowerCase() === festival.toLowerCase(),
    );

    const festivalName = template?.name ?? festival;
    const styleDesc = style === 'modern' ? 'modern minimalist' : style === 'elegant' ? 'elegant luxurious' : 'traditional ornate';

    // Build a detailed prompt for the image generation
    const prompt = [
      `Create a beautiful Indian festival greeting card for ${festivalName}.`,
      `The card features the kinship term "${kinshipTerm}" in ${this._languageDisplayName(language)} script prominently in the center.`,
      `Traditional Indian decorative borders with rangoli patterns and ${festivalName}-specific motifs.`,
      `Warm festive colors with ${template?.colorTheme ?? 'golden'} accents.`,
      `${styleDesc} typography and layout.`,
      `Cultural motifs and symbols related to ${festivalName}.`,
      `Portrait orientation greeting card suitable for sharing on messaging apps.`,
      `High quality, detailed illustration, professional design.`,
    ].join(' ');

    this.logger.log(`Generating festival card for ${festivalName} with term "${kinshipTerm}"`);

    try {
      const result = await this.zai.images.generations.create({
        prompt,
        size: '768x1344',
      });

      const imageBase64 = result.data?.[0]?.b64_json ?? '';

      return {
        imageBase64,
        prompt,
        festival: festivalName,
        kinshipTerm,
      };
    } catch (error) {
      this.logger.error('Image generation failed', error);
      throw new BadRequestException('Failed to generate festival card image. Please try again.');
    }
  }

  /**
   * Generate a kinship relationship card using AI.
   */
  async generateKinshipCard(options: {
    relationshipKey: string;
    language: string;
    style: string;
  }) {
    const { relationshipKey, language = 'en', style = 'traditional' } = options;

    // Look up kinship term using KinshipService
    const termData = this.kinshipService.lookupKey(relationshipKey, language);

    // Extract native script term and English meaning
    const englishTerm = termData.relationship.englishTerm;
    const translations = termData.translations ?? {};

    // Get the native script term for the prompt
    let nativeTerm = englishTerm;
    const langTranslations = language !== 'en' ? translations[language] : null;
    if (langTranslations) {
      nativeTerm = (langTranslations as { native: string; latin: string }).native;
    }

    const styleDesc = style === 'modern' ? 'modern minimalist' : style === 'elegant' ? 'elegant luxurious' : 'traditional ornate';

    // Build prompt with the native script term + English meaning
    const prompt = [
      `Create a beautiful Indian kinship greeting card.`,
      `The card features the kinship term "${nativeTerm}" prominently in the center.`,
      `Below it, the English meaning "${englishTerm}" is displayed in smaller text.`,
      `${this._languageDisplayName(language)} script typography with ${styleDesc} design.`,
      `Traditional Indian decorative borders with paisley and mandala patterns.`,
      `Warm earthy tones with golden accents — saffron, amber, and deep red.`,
      `Cultural motifs representing family bonds and Indian heritage.`,
      `Portrait orientation greeting card suitable for sharing on messaging apps.`,
      `High quality, detailed illustration, professional design.`,
    ].join(' ');

    this.logger.log(`Generating kinship card for "${relationshipKey}" (${nativeTerm})`);

    try {
      const result = await this.zai.images.generations.create({
        prompt,
        size: '768x1344',
      });

      const imageBase64 = result.data?.[0]?.b64_json ?? '';

      return {
        imageBase64,
        term: termData,
        translations,
      };
    } catch (error) {
      this.logger.error('Image generation failed', error);
      throw new BadRequestException('Failed to generate kinship card image. Please try again.');
    }
  }

  /**
   * Get predefined festival template configurations.
   */
  getFestivalTemplates(): FestivalTemplate[] {
    return this.festivalTemplates;
  }

  /**
   * Map language codes to display names for prompt generation.
   */
  private _languageDisplayName(lang: string): string {
    const map: Record<string, string> = {
      hi: 'Hindi (Devanagari)',
      bn: 'Bengali',
      te: 'Telugu',
      mr: 'Marathi (Devanagari)',
      ta: 'Tamil',
      gu: 'Gujarati',
      kn: 'Kannada',
      ml: 'Malayalam',
      pa: 'Punjabi (Gurmukhi)',
      or: 'Odia',
      as: 'Assamese',
      ur: 'Urdu (Arabic)',
      sa: 'Sanskrit (Devanagari)',
      en: 'English (Latin)',
    };
    return map[lang] ?? lang;
  }
}
