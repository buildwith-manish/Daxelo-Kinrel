/**
 * DAXELO KINREL — Brand Identity System
 *
 * Defines the core brand pillars, personality, emotional promises,
 * brand rituals, and positioning statement for KINREL.
 *
 * Pack 12: Brand & Motion — Identity
 */

// ── Brand Pillars ──────────────────────────────────────────────────
export interface BrandPillar {
  name: string;
  tagline: string;
  description: string;
  designImplication: string;
}

export const BRAND_PILLARS: BrandPillar[] = [
  {
    name: 'Roots & Wings',
    tagline: 'Honour where you come from, discover where you can go',
    description:
      'Every family tree is both a root system and a canopy. KINREL honours the roots — the ancestors, the traditions, the mother tongue — while giving wings to discovery: finding cousins you never knew, languages you never learned, and stories waiting to be told.',
    designImplication:
      'Tree visualizations must grow downward (roots) and upward (branches) with equal reverence. Ancestor nodes are treated with ceremonial gravitas; descendant nodes with exploratory lightness.',
  },
  {
    name: 'Many Tongues, One Family',
    tagline: '14 scripts, one heartbeat',
    description:
      'India speaks in 14 official languages and hundreds of dialects. KINREL does not flatten this richness — it celebrates it. Every relationship label, every festival wish, every memorial tribute can be expressed in the language your family actually speaks.',
    designImplication:
      'Locale is never a second-class citizen. Typography must render Devanagari, Tamil, Urdu, Bengali, and all 14 scripts with equal beauty. Translation is cultural, not literal.',
  },
  {
    name: 'Generational Bridge',
    tagline: "Connecting Daadi's stories to Chhoti's screen",
    description:
      'The greatest gap in Indian families is not geographic — it is generational. KINREL builds bridges: voice notes from grandparents, photo tagging for grandchildren, WhatsApp integration for the uncle who will never install another app. We meet every generation where they are.',
    designImplication:
      'Accessibility is non-negotiable. Large touch targets, voice-first inputs, WhatsApp as a first-class channel, and progressive disclosure that respects both the tech-savvy and the tech-reluctant.',
  },
  {
    name: 'Living Memory',
    tagline: 'The family that remembers together, stays together',
    description:
      'A family tree is not a static chart — it is a living, breathing archive. Birthdays, festivals, memorials, migrations, marriages: KINREL captures the rhythm of family life and replays it when it matters most. A notification on a grandmother\'s birthday is not a feature — it is a promise kept.',
    designImplication:
      'Every interaction should feel ceremonial, not transactional. Animations carry emotional weight. Celebrations have visual fanfare. Memorials are treated with sacred respect.',
  },
];

// ── Brand Personality ──────────────────────────────────────────────
export interface PersonalityDimension {
  dimension: string;
  weAre: string;
  weAreNot: string;
}

export const BRAND_PERSONALITY: PersonalityDimension[] = [
  {
    dimension: 'Tone',
    weAre: 'Warm, knowledgeable, like a family elder who knows everyone\'s story',
    weAreNot: 'Clinical, corporate, or coldly efficient',
  },
  {
    dimension: 'Style',
    weAre: 'Gracefully Indian — saffron warmth, festival joy, script beauty',
    weAreNot: 'Generic global tech or minimalist Western aesthetics',
  },
  {
    dimension: 'Emotion',
    weAre: 'Celebratory for milestones, reverent for memories, playful for discovery',
    weAreNot: 'Neutral, detached, or emotionally flat',
  },
  {
    dimension: 'Voice',
    weAre: 'Inclusive of every generation — from Daadi\'s voice note to Chhoti\'s story',
    weAreNot: 'Only for the tech-savvy or the young',
  },
  {
    dimension: 'Interaction',
    weAre: 'Ceremonial — every tap carries meaning, every animation tells a story',
    weAreNot: 'Mechanical, transactional, or forgettable',
  },
  {
    dimension: 'Visual',
    weAre: 'Organic, warm, rooted in Indian craft traditions',
    weAreNot: 'Geometric, sterile, or devoid of cultural reference',
  },
];

// ── Emotional Promises ─────────────────────────────────────────────
export interface EmotionalPromise {
  promise: string;
  deliveryMethod: string;
  measurementMetric: string;
}

export const EMOTIONAL_PROMISES: EmotionalPromise[] = [
  {
    promise: 'You will feel known — your family, your language, your way',
    deliveryMethod:
      'Auto-detect language, culturally aware relationship labels, festival-aware UI theming',
    measurementMetric: 'Language selection match rate > 90% on first launch',
  },
  {
    promise: 'You will feel belonging — connected across generations and distances',
    deliveryMethod:
      'WhatsApp integration, voice notes, generational bridging features, shared family calendar',
    measurementMetric: 'Cross-generation interaction rate (grandparent-grandchild) > 40%',
  },
  {
    promise: 'You will feel celebrated — milestones matter, not just data points',
    deliveryMethod:
      'Celebration animations, festival theming, birthday/anniversary reminders with cultural context',
    measurementMetric: 'Celebration interaction rate > 70% on milestone events',
  },
  {
    promise: 'You will feel reverence — memories and memorials are sacred',
    deliveryMethod:
      'Memorial pages with ceremonial design, respectful animations, no ads on memorial content',
    measurementMetric: 'Memorial visit duration > 2 minutes average',
  },
  {
    promise: 'You will feel discovery — every branch hides a story',
    deliveryMethod:
      'Smart relationship discovery, "Did you know?" notifications, ancestry insights',
    measurementMetric: 'Discovery feature engagement > 50% of active users monthly',
  },
];

// ── Brand Rituals ──────────────────────────────────────────────────
export interface BrandRitual {
  name: string;
  description: string;
  frequency: string;
  designOpportunity: string;
}

export const BRAND_RITUALS: BrandRitual[] = [
  {
    name: 'Birthday',
    description:
      'A family member\'s birthday is the most personal ritual — a moment to celebrate not just age, but relationships. KINREL surfaces not just the birthday, but the web of connections around that person.',
    frequency: 'Annual per member',
    designOpportunity:
      'Personalized birthday card with family tree highlight showing the person\'s position. Festival-grade animation. WhatsApp wish templates in their preferred language.',
  },
  {
    name: 'Festival',
    description:
      'India celebrates 50+ major festivals across communities. KINREL transforms its visual identity to match the season — Diwali gold, Holi colours, Eid green — making the app feel alive and culturally attuned.',
    frequency: 'Seasonal (8 major festivals)',
    designOpportunity:
      'Full festival theme with colour extensions, greeting card templates, and community celebration feeds. Auto-detect regional festival calendar.',
  },
  {
    name: 'Anniversary',
    description:
      'Wedding anniversaries in Indian families are community events. KINREL surfaces the couple\'s photo, their journey, and invites the family to share memories.',
    frequency: 'Annual per couple',
    designOpportunity:
      'Couple spotlight animation, memory lane timeline, family contribution wall for messages and photos.',
  },
  {
    name: 'New Member',
    description:
      'Whether a birth, a marriage, or an adoption, every new member changes the family tree. KINREL marks this as a celebratory event with visual fanfare.',
    frequency: 'As it happens',
    designOpportunity:
      'Tree growth animation — branch extends, node appears with celebratory burst. Welcome card generation for sharing. Auto-suggest relationships.',
  },
  {
    name: 'Generation Milestone',
    description:
      'When a family gains its 4th or 5th generation, KINREL marks this as a generational milestone — a moment of pride and reflection.',
    frequency: 'Rare (once per family)',
    designOpportunity:
      'Generational depth badge, special "Living Legacy" visualization showing all living generations, family story prompt.',
  },
  {
    name: 'Daily Discovery',
    description:
      'Every day, KINREL offers a small discovery — a photo from this day last year, a relationship you might not have explored, a fact about your family name.',
    frequency: 'Daily',
    designOpportunity:
      'Gentle notification with micro-animation. "Did you know?" card with swipe-to-dismiss. No pressure, always optional.',
  },
];

// ── Positioning Statement ──────────────────────────────────────────
export const POSITIONING_STATEMENT =
  'KINREL is the Indian family\'s living archive — a relationship intelligence platform that speaks your language, honours your roots, and bridges generations. We transform the family tree from a static chart into a living, breathing, celebrating community that remembers together. In a land of 14 scripts and a thousand traditions, KINREL is the one app that feels like home.';
