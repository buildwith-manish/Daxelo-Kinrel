// DAXELO KINREL — Share Card Generator
// Pack 04: WhatsApp Platform
//
// Generates card specifications (metadata/parameters) for client-side canvas rendering.
// Since we don't have canvas on the server, these specs describe the layout, colors,
// text, and dimensions needed to render each card type on the client.
//
// KINREL Brand Colors:
// - Saffron:  #F97316 (primary accent, warmth, celebration)
// - Crimson:  #E94560 (depth, love, relationships)
// - Teal:     #14B8A6 (growth, connection, freshness)

// ── Brand Color Constants ──────────────────────────────────────────────

export const KINREL_COLORS = {
  saffron: '#F97316',
  crimson: '#E94560',
  teal: '#14B8A6',
  saffronLight: '#FFF7ED',
  crimsonLight: '#FFF1F2',
  tealLight: '#F0FDFA',
  white: '#FFFFFF',
  dark: '#1C1917',
  darkMuted: '#57534E',
  darkSubtle: '#A8A29E',
} as const

// ── Card Type Definitions ──────────────────────────────────────────────

export type CardType =
  | 'family_tree'
  | 'birthday'
  | 'anniversary'
  | 'memorial'
  | 'festival_greeting'

export type CardFormat = 'PNG' | 'JPEG' | 'WEBP'

export interface ColorScheme {
  primary: string
  secondary: string
  accent: string
  background: string
  text: string
  textMuted: string
}

export interface TextElement {
  key: string
  text: string
  fontFamily: string
  fontSize: number
  fontWeight: number
  color: string
  x: number
  y: number
  maxWidth: number
  lineHeight: number
  textAlign: 'left' | 'center' | 'right'
}

export interface ImageElement {
  key: string
  url: string
  x: number
  y: number
  width: number
  height: number
  borderRadius: number
  objectFit: 'cover' | 'contain'
}

export interface ShapeElement {
  key: string
  type: 'rect' | 'circle' | 'roundedRect'
  x: number
  y: number
  width: number
  height: number
  fill: string
  opacity: number
  borderRadius?: number
}

export interface CardSpec {
  type: CardType
  dimensions: string
  width: number
  height: number
  format: CardFormat
  colorScheme: ColorScheme
  background: {
    type: 'gradient' | 'solid' | 'image'
    value: string
  }
  elements: {
    texts: TextElement[]
    images: ImageElement[]
    shapes: ShapeElement[]
  }
  content: Record<string, unknown>
  brand: {
    logoPosition: { x: number; y: number; width: number; height: number }
    tagline: string
    websiteUrl: string
  }
  exportConfig: {
    quality: number
    pixelRatio: number
  }
}

// ── Shared Helpers ─────────────────────────────────────────────────────

function createBrandFooter(cardHeight: number): {
  texts: TextElement[]
  shapes: ShapeElement[]
} {
  return {
    texts: [
      {
        key: 'brand_tagline',
        text: '🌱 One Family. One Tree. Infinite Connections.',
        fontFamily: 'Inter, sans-serif',
        fontSize: 14,
        fontWeight: 400,
        color: KINREL_COLORS.darkMuted,
        x: 0,
        y: cardHeight - 40,
        maxWidth: 600,
        lineHeight: 20,
        textAlign: 'center' as const,
      },
      {
        key: 'brand_url',
        text: 'daxelo.app',
        fontFamily: 'Inter, sans-serif',
        fontSize: 12,
        fontWeight: 600,
        color: KINREL_COLORS.saffron,
        x: 0,
        y: cardHeight - 22,
        maxWidth: 200,
        lineHeight: 16,
        textAlign: 'center' as const,
      },
    ],
    shapes: [],
  }
}

// ── Card Generator Class ───────────────────────────────────────────────

export class CardGenerator {
  /**
   * Generates a family tree card specification.
   * This card showcases a family's tree overview and is designed for
   * sharing on WhatsApp as an OG preview image (1200x630).
   */
  static generateFamilyTreeCard(params: {
    familyName: string
    memberCount: number
    generationCount: number
    languages: string[]
    primaryLanguage: string
    familyPhotoUrl?: string
  }): CardSpec {
    const { familyName, memberCount, generationCount, languages, primaryLanguage, familyPhotoUrl } = params

    const colorScheme: ColorScheme = {
      primary: KINREL_COLORS.saffron,
      secondary: KINREL_COLORS.crimson,
      accent: KINREL_COLORS.teal,
      background: KINREL_COLORS.saffronLight,
      text: KINREL_COLORS.dark,
      textMuted: KINREL_COLORS.darkMuted,
    }

    const texts: TextElement[] = [
      {
        key: 'family_name',
        text: familyName,
        fontFamily: 'Inter, sans-serif',
        fontSize: 48,
        fontWeight: 800,
        color: KINREL_COLORS.dark,
        x: 0,
        y: 120,
        maxWidth: 800,
        lineHeight: 56,
        textAlign: 'center',
      },
      {
        key: 'family_label',
        text: primaryLanguage === 'hi' ? 'परिवार वृक्ष' : 'Family Tree',
        fontFamily: 'Inter, sans-serif',
        fontSize: 20,
        fontWeight: 400,
        color: KINREL_COLORS.saffron,
        x: 0,
        y: 185,
        maxWidth: 400,
        lineHeight: 28,
        textAlign: 'center',
      },
      {
        key: 'member_count',
        text: `${memberCount} ${primaryLanguage === 'hi' ? 'सदस्य' : 'Members'}`,
        fontFamily: 'Inter, sans-serif',
        fontSize: 28,
        fontWeight: 600,
        color: KINREL_COLORS.crimson,
        x: 0,
        y: 260,
        maxWidth: 400,
        lineHeight: 36,
        textAlign: 'center',
      },
      {
        key: 'generation_count',
        text: `${generationCount} ${primaryLanguage === 'hi' ? 'पीढ़ियाँ' : 'Generations'}`,
        fontFamily: 'Inter, sans-serif',
        fontSize: 22,
        fontWeight: 500,
        color: KINREL_COLORS.teal,
        x: 0,
        y: 305,
        maxWidth: 400,
        lineHeight: 30,
        textAlign: 'center',
      },
      {
        key: 'languages',
        text: languages.length > 0
          ? `${primaryLanguage === 'hi' ? 'भाषाएँ' : 'Languages'}: ${languages.join(', ')}`
          : '',
        fontFamily: 'Inter, sans-serif',
        fontSize: 16,
        fontWeight: 400,
        color: KINREL_COLORS.darkMuted,
        x: 0,
        y: 350,
        maxWidth: 600,
        lineHeight: 22,
        textAlign: 'center',
      },
    ]

    const images: ImageElement[] = []
    if (familyPhotoUrl) {
      images.push({
        key: 'family_photo',
        url: familyPhotoUrl,
        x: 800,
        y: 80,
        width: 340,
        height: 340,
        borderRadius: 24,
        objectFit: 'cover',
      })
    }

    const shapes: ShapeElement[] = [
      {
        key: 'bg_accent_circle',
        type: 'circle',
        x: -60,
        y: -60,
        width: 300,
        height: 300,
        fill: KINREL_COLORS.saffron,
        opacity: 0.06,
      },
      {
        key: 'bg_accent_circle_2',
        type: 'circle',
        x: 950,
        y: 400,
        width: 350,
        height: 350,
        fill: KINREL_COLORS.teal,
        opacity: 0.05,
      },
    ]

    const brand = createBrandFooter(630)

    return {
      type: 'family_tree',
      dimensions: '1200x630',
      width: 1200,
      height: 630,
      format: 'PNG',
      colorScheme,
      background: {
        type: 'gradient',
        value: `linear-gradient(135deg, ${KINREL_COLORS.saffronLight} 0%, ${KINREL_COLORS.white} 50%, ${KINREL_COLORS.tealLight} 100%)`,
      },
      elements: {
        texts: [...texts, ...brand.texts],
        images,
        shapes: [...shapes, ...brand.shapes],
      },
      content: {
        familyName,
        memberCount,
        generationCount,
        languages,
        primaryLanguage,
        familyPhotoUrl: familyPhotoUrl ?? null,
      },
      brand: {
        logoPosition: { x: 24, y: 24, width: 32, height: 32 },
        tagline: '🌱 One Family. One Tree. Infinite Connections.',
        websiteUrl: 'https://daxelo.app',
      },
      exportConfig: {
        quality: 0.95,
        pixelRatio: 2,
      },
    }
  }

  /**
   * Generates a birthday card specification.
   * Designed as a square card (1080x1080) for WhatsApp sharing.
   */
  static generateBirthdayCard(params: {
    personName: string
    relation: string
    language: string
    age?: number
    photoUrl?: string
  }): CardSpec {
    const { personName, relation, language, age, photoUrl } = params

    const colorScheme: ColorScheme = {
      primary: KINREL_COLORS.saffron,
      secondary: KINREL_COLORS.crimson,
      accent: KINREL_COLORS.teal,
      background: KINREL_COLORS.saffronLight,
      text: KINREL_COLORS.dark,
      textMuted: KINREL_COLORS.darkMuted,
    }

    const greetingText = language === 'hi'
      ? `🎂 जन्मदिन मुबारक हो!`
      : `🎂 Happy Birthday!`

    const nameText = personName
    const relationText = language === 'hi'
      ? `आपके ${relation}`
      : `Your ${relation}`

    const ageText = age
      ? language === 'hi'
        ? `🎂 ${age} साल के हो गए!`
        : `🎂 Turning ${age}!`
      : ''

    const texts: TextElement[] = [
      {
        key: 'greeting',
        text: greetingText,
        fontFamily: 'Inter, sans-serif',
        fontSize: 36,
        fontWeight: 700,
        color: KINREL_COLORS.crimson,
        x: 0,
        y: photoUrl ? 100 : 200,
        maxWidth: 900,
        lineHeight: 44,
        textAlign: 'center',
      },
      {
        key: 'person_name',
        text: nameText,
        fontFamily: 'Inter, sans-serif',
        fontSize: 56,
        fontWeight: 800,
        color: KINREL_COLORS.dark,
        x: 0,
        y: photoUrl ? 170 : 280,
        maxWidth: 900,
        lineHeight: 64,
        textAlign: 'center',
      },
      {
        key: 'relation',
        text: relationText,
        fontFamily: 'Inter, sans-serif',
        fontSize: 24,
        fontWeight: 400,
        color: KINREL_COLORS.saffron,
        x: 0,
        y: photoUrl ? 250 : 360,
        maxWidth: 700,
        lineHeight: 32,
        textAlign: 'center',
      },
    ]

    if (ageText) {
      texts.push({
        key: 'age',
        text: ageText,
        fontFamily: 'Inter, sans-serif',
        fontSize: 22,
        fontWeight: 500,
        color: KINREL_COLORS.teal,
        x: 0,
        y: photoUrl ? 300 : 410,
        maxWidth: 600,
        lineHeight: 30,
        textAlign: 'center',
      })
    }

    const images: ImageElement[] = []
    if (photoUrl) {
      images.push({
        key: 'person_photo',
        url: photoUrl,
        x: 390,
        y: 380,
        width: 300,
        height: 300,
        borderRadius: 150,
        objectFit: 'cover',
      })
    }

    const shapes: ShapeElement[] = [
      {
        key: 'bg_decoration_top',
        type: 'circle',
        x: -80,
        y: -80,
        width: 250,
        height: 250,
        fill: KINREL_COLORS.saffron,
        opacity: 0.08,
      },
      {
        key: 'bg_decoration_bottom',
        type: 'circle',
        x: 850,
        y: 850,
        width: 300,
        height: 300,
        fill: KINREL_COLORS.crimson,
        opacity: 0.06,
      },
    ]

    const brand = createBrandFooter(1080)

    return {
      type: 'birthday',
      dimensions: '1080x1080',
      width: 1080,
      height: 1080,
      format: 'PNG',
      colorScheme,
      background: {
        type: 'gradient',
        value: `linear-gradient(160deg, ${KINREL_COLORS.saffronLight} 0%, ${KINREL_COLORS.white} 40%, ${KINREL_COLORS.crimsonLight} 100%)`,
      },
      elements: {
        texts: [...texts, ...brand.texts],
        images,
        shapes: [...shapes, ...brand.shapes],
      },
      content: {
        personName,
        relation,
        language,
        age: age ?? null,
        photoUrl: photoUrl ?? null,
      },
      brand: {
        logoPosition: { x: 24, y: 24, width: 28, height: 28 },
        tagline: '🌱 One Family. One Tree. Infinite Connections.',
        websiteUrl: 'https://daxelo.app',
      },
      exportConfig: {
        quality: 0.95,
        pixelRatio: 2,
      },
    }
  }

  /**
   * Generates an anniversary card specification.
   * Square card (1080x1080) celebrating a couple's milestone.
   */
  static generateAnniversaryCard(params: {
    personName: string
    partnerName: string
    years: number
    language: string
  }): CardSpec {
    const { personName, partnerName, years, language } = params

    const colorScheme: ColorScheme = {
      primary: KINREL_COLORS.crimson,
      secondary: KINREL_COLORS.saffron,
      accent: KINREL_COLORS.teal,
      background: KINREL_COLORS.crimsonLight,
      text: KINREL_COLORS.dark,
      textMuted: KINREL_COLORS.darkMuted,
    }

    const greetingText = language === 'hi'
      ? `💝 सालगिरह मुबारक हो!`
      : `💝 Happy Anniversary!`

    const coupleText = `${personName} & ${partnerName}`

    const yearsText = language === 'hi'
      ? `${years} साल का साथ`
      : `${years} ${years === 1 ? 'Year' : 'Years'} Together`

    const texts: TextElement[] = [
      {
        key: 'greeting',
        text: greetingText,
        fontFamily: 'Inter, sans-serif',
        fontSize: 36,
        fontWeight: 700,
        color: KINREL_COLORS.crimson,
        x: 0,
        y: 200,
        maxWidth: 900,
        lineHeight: 44,
        textAlign: 'center',
      },
      {
        key: 'couple_name',
        text: coupleText,
        fontFamily: 'Inter, sans-serif',
        fontSize: 48,
        fontWeight: 800,
        color: KINREL_COLORS.dark,
        x: 0,
        y: 300,
        maxWidth: 900,
        lineHeight: 56,
        textAlign: 'center',
      },
      {
        key: 'years',
        text: yearsText,
        fontFamily: 'Inter, sans-serif',
        fontSize: 28,
        fontWeight: 500,
        color: KINREL_COLORS.saffron,
        x: 0,
        y: 400,
        maxWidth: 700,
        lineHeight: 36,
        textAlign: 'center',
      },
      {
        key: 'heart_decoration',
        text: '❤️',
        fontFamily: 'Inter, sans-serif',
        fontSize: 60,
        fontWeight: 400,
        color: KINREL_COLORS.crimson,
        x: 0,
        y: 500,
        maxWidth: 100,
        lineHeight: 70,
        textAlign: 'center',
      },
    ]

    const shapes: ShapeElement[] = [
      {
        key: 'bg_heart_glow',
        type: 'circle',
        x: 340,
        y: 450,
        width: 400,
        height: 400,
        fill: KINREL_COLORS.crimson,
        opacity: 0.04,
      },
      {
        key: 'bg_corner_accent',
        type: 'circle',
        x: -100,
        y: -100,
        width: 300,
        height: 300,
        fill: KINREL_COLORS.saffron,
        opacity: 0.07,
      },
    ]

    const brand = createBrandFooter(1080)

    return {
      type: 'anniversary',
      dimensions: '1080x1080',
      width: 1080,
      height: 1080,
      format: 'PNG',
      colorScheme,
      background: {
        type: 'gradient',
        value: `linear-gradient(150deg, ${KINREL_COLORS.crimsonLight} 0%, ${KINREL_COLORS.white} 50%, ${KINREL_COLORS.saffronLight} 100%)`,
      },
      elements: {
        texts: [...texts, ...brand.texts],
        images: [],
        shapes: [...shapes, ...brand.shapes],
      },
      content: {
        personName,
        partnerName,
        years,
        language,
      },
      brand: {
        logoPosition: { x: 24, y: 24, width: 28, height: 28 },
        tagline: '🌱 One Family. One Tree. Infinite Connections.',
        websiteUrl: 'https://daxelo.app',
      },
      exportConfig: {
        quality: 0.95,
        pixelRatio: 2,
      },
    }
  }

  /**
   * Generates a memorial card specification.
   * Taller card (1080x1350) for tribute and remembrance.
   */
  static generateMemorialCard(params: {
    personName: string
    dates: string
    tribute: string
    language: string
  }): CardSpec {
    const { personName, dates, tribute, language } = params

    const colorScheme: ColorScheme = {
      primary: KINREL_COLORS.teal,
      secondary: KINREL_COLORS.saffron,
      accent: KINREL_COLORS.crimson,
      background: KINREL_COLORS.tealLight,
      text: KINREL_COLORS.dark,
      textMuted: KINREL_COLORS.darkSubtle,
    }

    const headerText = language === 'hi'
      ? '🙏 श्रद्धांजलि'
      : '🙏 In Loving Memory'

    const candleText = '🕯️'

    const tributeLabel = language === 'hi'
      ? 'स्मृति में'
      : 'In Remembrance'

    const texts: TextElement[] = [
      {
        key: 'header',
        text: headerText,
        fontFamily: 'Inter, sans-serif',
        fontSize: 32,
        fontWeight: 600,
        color: KINREL_COLORS.teal,
        x: 0,
        y: 120,
        maxWidth: 800,
        lineHeight: 40,
        textAlign: 'center',
      },
      {
        key: 'candle',
        text: candleText,
        fontFamily: 'Inter, sans-serif',
        fontSize: 80,
        fontWeight: 400,
        color: KINREL_COLORS.saffron,
        x: 0,
        y: 190,
        maxWidth: 120,
        lineHeight: 90,
        textAlign: 'center',
      },
      {
        key: 'person_name',
        text: personName,
        fontFamily: 'Inter, sans-serif',
        fontSize: 44,
        fontWeight: 700,
        color: KINREL_COLORS.dark,
        x: 0,
        y: 320,
        maxWidth: 900,
        lineHeight: 52,
        textAlign: 'center',
      },
      {
        key: 'dates',
        text: dates,
        fontFamily: 'Inter, sans-serif',
        fontSize: 22,
        fontWeight: 400,
        color: KINREL_COLORS.darkMuted,
        x: 0,
        y: 390,
        maxWidth: 700,
        lineHeight: 30,
        textAlign: 'center',
      },
      {
        key: 'tribute_label',
        text: tributeLabel,
        fontFamily: 'Inter, sans-serif',
        fontSize: 18,
        fontWeight: 600,
        color: KINREL_COLORS.teal,
        x: 0,
        y: 460,
        maxWidth: 400,
        lineHeight: 26,
        textAlign: 'center',
      },
      {
        key: 'tribute',
        text: tribute,
        fontFamily: 'Inter, sans-serif',
        fontSize: 20,
        fontWeight: 400,
        color: KINREL_COLORS.darkMuted,
        x: 90,
        y: 500,
        maxWidth: 900,
        lineHeight: 30,
        textAlign: 'center',
      },
    ]

    const shapes: ShapeElement[] = [
      {
        key: 'bg_glow',
        type: 'circle',
        x: 340,
        y: 180,
        width: 400,
        height: 400,
        fill: KINREL_COLORS.saffron,
        opacity: 0.05,
      },
      {
        key: 'divider_line',
        type: 'roundedRect',
        x: 340,
        y: 440,
        width: 400,
        height: 2,
        fill: KINREL_COLORS.teal,
        opacity: 0.2,
        borderRadius: 1,
      },
    ]

    const brand = createBrandFooter(1350)

    return {
      type: 'memorial',
      dimensions: '1080x1350',
      width: 1080,
      height: 1350,
      format: 'PNG',
      colorScheme,
      background: {
        type: 'gradient',
        value: `linear-gradient(180deg, ${KINREL_COLORS.tealLight} 0%, ${KINREL_COLORS.white} 40%, ${KINREL_COLORS.saffronLight} 100%)`,
      },
      elements: {
        texts: [...texts, ...brand.texts],
        images: [],
        shapes: [...shapes, ...brand.shapes],
      },
      content: {
        personName,
        dates,
        tribute,
        language,
      },
      brand: {
        logoPosition: { x: 24, y: 24, width: 28, height: 28 },
        tagline: '🌱 One Family. One Tree. Infinite Connections.',
        websiteUrl: 'https://daxelo.app',
      },
      exportConfig: {
        quality: 0.95,
        pixelRatio: 2,
      },
    }
  }

  /**
   * Generates a festival greeting card specification.
   * Square card (1080x1080) for Indian festivals and celebrations.
   */
  static generateFestivalGreeting(params: {
    festivalName: string
    language: string
    year: number
  }): CardSpec {
    const { festivalName, language, year } = params

    const colorScheme: ColorScheme = {
      primary: KINREL_COLORS.saffron,
      secondary: KINREL_COLORS.crimson,
      accent: KINREL_COLORS.teal,
      background: KINREL_COLORS.saffronLight,
      text: KINREL_COLORS.dark,
      textMuted: KINREL_COLORS.darkMuted,
    }

    const greetingText = language === 'hi'
      ? `${festivalName} की हार्दिक शुभकामनाएँ! 🪔`
      : `Happy ${festivalName}! 🪔`

    const subtitleText = language === 'hi'
      ? `${year} • आपके परिवार को ढेर सारी खुशियाँ`
      : `${year} • Wishing your family joy & togetherness`

    const fromText = language === 'hi'
      ? '— Daxelo Kinrel परिवार की ओर से'
      : '— From the Daxelo Kinrel Family'

    const texts: TextElement[] = [
      {
        key: 'greeting',
        text: greetingText,
        fontFamily: 'Inter, sans-serif',
        fontSize: 42,
        fontWeight: 800,
        color: KINREL_COLORS.saffron,
        x: 0,
        y: 250,
        maxWidth: 900,
        lineHeight: 50,
        textAlign: 'center',
      },
      {
        key: 'subtitle',
        text: subtitleText,
        fontFamily: 'Inter, sans-serif',
        fontSize: 24,
        fontWeight: 400,
        color: KINREL_COLORS.crimson,
        x: 0,
        y: 370,
        maxWidth: 800,
        lineHeight: 34,
        textAlign: 'center',
      },
      {
        key: 'from',
        text: fromText,
        fontFamily: 'Inter, sans-serif',
        fontSize: 18,
        fontWeight: 500,
        color: KINREL_COLORS.teal,
        x: 0,
        y: 440,
        maxWidth: 600,
        lineHeight: 26,
        textAlign: 'center',
      },
    ]

    const shapes: ShapeElement[] = [
      {
        key: 'bg_rangoli_top',
        type: 'circle',
        x: -60,
        y: -60,
        width: 320,
        height: 320,
        fill: KINREL_COLORS.saffron,
        opacity: 0.08,
      },
      {
        key: 'bg_rangoli_bottom',
        type: 'circle',
        x: 800,
        y: 800,
        width: 360,
        height: 360,
        fill: KINREL_COLORS.crimson,
        opacity: 0.06,
      },
      {
        key: 'bg_diya_center',
        type: 'circle',
        x: 390,
        y: 140,
        width: 300,
        height: 300,
        fill: KINREL_COLORS.saffron,
        opacity: 0.04,
      },
    ]

    const brand = createBrandFooter(1080)

    return {
      type: 'festival_greeting',
      dimensions: '1080x1080',
      width: 1080,
      height: 1080,
      format: 'PNG',
      colorScheme,
      background: {
        type: 'gradient',
        value: `linear-gradient(135deg, ${KINREL_COLORS.saffronLight} 0%, ${KINREL_COLORS.white} 45%, ${KINREL_COLORS.crimsonLight} 100%)`,
      },
      elements: {
        texts: [...texts, ...brand.texts],
        images: [],
        shapes: [...shapes, ...brand.shapes],
      },
      content: {
        festivalName,
        language,
        year,
      },
      brand: {
        logoPosition: { x: 24, y: 24, width: 28, height: 28 },
        tagline: '🌱 One Family. One Tree. Infinite Connections.',
        websiteUrl: 'https://daxelo.app',
      },
      exportConfig: {
        quality: 0.95,
        pixelRatio: 2,
      },
    }
  }
}
