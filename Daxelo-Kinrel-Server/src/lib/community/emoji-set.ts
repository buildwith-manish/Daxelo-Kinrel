// DAXELO KINREL — Pack 09: Context-Sensitive Emoji Sets
// Hindi-labeled emojis for Indian family context

// ── Types ────────────────────────────────────────────────────────────

export interface EmojiDef {
  emoji: string;
  labelHi: string;
  labelEn: string;
}

// ── Core Emoji Set ───────────────────────────────────────────────────

export const DEFAULT_EMOJIS: EmojiDef[] = [
  { emoji: '❤️', labelHi: 'जय', labelEn: 'Love' },
  { emoji: '🎂', labelHi: 'जन्मदिन', labelEn: 'Birthday' },
  { emoji: '🙏', labelHi: 'प्रणाम', labelEn: 'Respect' },
  { emoji: '👏', labelHi: 'वाह', labelEn: 'Applause' },
  { emoji: '🔥', labelHi: 'जबरदस्त', labelEn: 'Fire' },
  { emoji: '😢', labelHi: 'दुख', labelEn: 'Sad' },
  { emoji: '🎉', labelHi: 'शुभकामना', labelEn: 'Congratulations' },
  { emoji: '💐', labelHi: 'पुष्प', labelEn: 'Flowers' },
];

// ── Context-Sensitive Sets ───────────────────────────────────────────

export const CONTEXT_EMOJIS: Record<string, EmojiDef[]> = {
  // Memorial: solemn, respectful emojis
  memorial: [
    { emoji: '🙏', labelHi: 'प्रणाम', labelEn: 'Respect' },
    { emoji: '💐', labelHi: 'पुष्प', labelEn: 'Flowers' },
    { emoji: '😢', labelHi: 'दुख', labelEn: 'Sad' },
    { emoji: '❤️', labelHi: 'जय', labelEn: 'Love' },
    { emoji: '🕯️', labelHi: 'दीपक', labelEn: 'Candle' },
    { emoji: '🪷', labelHi: 'कमल', labelEn: 'Lotus' },
    { emoji: 'ॐ', labelHi: 'ॐ', labelEn: 'Om' },
    { emoji: '🕊️', labelHi: 'शांति', labelEn: 'Peace' },
  ],

  // Birthday: festive, celebratory
  birthday: [
    { emoji: '🎂', labelHi: 'जन्मदिन', labelEn: 'Birthday' },
    { emoji: '❤️', labelHi: 'जय', labelEn: 'Love' },
    { emoji: '🎉', labelHi: 'शुभकामना', labelEn: 'Congratulations' },
    { emoji: '👏', labelHi: 'वाह', labelEn: 'Applause' },
    { emoji: '🥳', labelHi: 'झूम', labelEn: 'Party' },
    { emoji: '🎁', labelHi: 'उपहार', labelEn: 'Gift' },
    { emoji: '🎊', labelHi: 'बधाई', labelEn: 'Celebrate' },
    { emoji: '💐', labelHi: 'पुष्प', labelEn: 'Flowers' },
  ],

  // Anniversary: romantic, congratulatory
  anniversary: [
    { emoji: '❤️', labelHi: 'जय', labelEn: 'Love' },
    { emoji: '🎉', labelHi: 'शुभकामना', labelEn: 'Congratulations' },
    { emoji: '💐', labelHi: 'पुष्प', labelEn: 'Flowers' },
    { emoji: '👏', labelHi: 'वाह', labelEn: 'Applause' },
    { emoji: '🥂', labelHi: 'चियर्स', labelEn: 'Cheers' },
    { emoji: '💕', labelHi: 'प्रेम', labelEn: 'Affection' },
    { emoji: '🎊', labelHi: 'बधाई', labelEn: 'Celebrate' },
    { emoji: '🙏', labelHi: 'प्रणाम', labelEn: 'Respect' },
  ],

  // Wedding: grand, festive, traditional
  wedding: [
    { emoji: '❤️', labelHi: 'जय', labelEn: 'Love' },
    { emoji: '🎉', labelHi: 'शुभकामना', labelEn: 'Congratulations' },
    { emoji: '💐', labelHi: 'पुष्प', labelEn: 'Flowers' },
    { emoji: '👏', labelHi: 'वाह', labelEn: 'Applause' },
    { emoji: '🙏', labelHi: 'प्रणाम', labelEn: 'Respect' },
    { emoji: '🎊', labelHi: 'बधाई', labelEn: 'Celebrate' },
    { emoji: '🪷', labelHi: 'कमल', labelEn: 'Lotus' },
    { emoji: '🔥', labelHi: 'जबरदस्त', labelEn: 'Fire' },
  ],

  // Milestone: achievement-oriented
  milestone: [
    { emoji: '🎉', labelHi: 'शुभकामना', labelEn: 'Congratulations' },
    { emoji: '👏', labelHi: 'वाह', labelEn: 'Applause' },
    { emoji: '🔥', labelHi: 'जबरदस्त', labelEn: 'Fire' },
    { emoji: '❤️', labelHi: 'जय', labelEn: 'Love' },
    { emoji: '🏆', labelHi: 'उपलब्धि', labelEn: 'Achievement' },
    { emoji: '🌟', labelHi: 'तारा', labelEn: 'Star' },
    { emoji: '💪', labelHi: 'शक्ति', labelEn: 'Strength' },
    { emoji: '🎊', labelHi: 'बधाई', labelEn: 'Celebrate' },
  ],

  // Puja / Religious: reverent
  puja: [
    { emoji: '🙏', labelHi: 'प्रणाम', labelEn: 'Respect' },
    { emoji: '💐', labelHi: 'पुष्प', labelEn: 'Flowers' },
    { emoji: '🪷', labelHi: 'कमल', labelEn: 'Lotus' },
    { emoji: 'ॐ', labelHi: 'ॐ', labelEn: 'Om' },
    { emoji: '🪔', labelHi: 'दीया', labelEn: 'Diya' },
    { emoji: '❤️', labelHi: 'जय', labelEn: 'Love' },
    { emoji: '🎊', labelHi: 'बधाई', labelEn: 'Celebrate' },
    { emoji: '🎉', labelHi: 'शुभकामना', labelEn: 'Congratulations' },
  ],

  // New member: welcoming
  new_member: [
    { emoji: '🎉', labelHi: 'शुभकामना', labelEn: 'Congratulations' },
    { emoji: '👋', labelHi: 'स्वागत', labelEn: 'Welcome' },
    { emoji: '❤️', labelHi: 'जय', labelEn: 'Love' },
    { emoji: '👏', labelHi: 'वाह', labelEn: 'Applause' },
    { emoji: '🙏', labelHi: 'प्रणाम', labelEn: 'Respect' },
    { emoji: '💐', labelHi: 'पुष्प', labelEn: 'Flowers' },
    { emoji: '🎊', labelHi: 'बधाई', labelEn: 'Celebrate' },
    { emoji: '🔥', labelHi: 'जबरदस्त', labelEn: 'Fire' },
  ],

  // General / community post: all 8 default
  community_post: DEFAULT_EMOJIS,
  text: DEFAULT_EMOJIS,
  photo: DEFAULT_EMOJIS,
  event: DEFAULT_EMOJIS,
  announcement: DEFAULT_EMOJIS,
  story: DEFAULT_EMOJIS,
  relationship_discovery: DEFAULT_EMOJIS,
  person_update: DEFAULT_EMOJIS,
  new_photo: DEFAULT_EMOJIS,
};

// ── Public Functions ─────────────────────────────────────────────────

/**
 * Get the appropriate emoji set for a post type
 * Falls back to DEFAULT_EMOJIS if no specific set exists
 */
export function getEmojiSet(postType: string): EmojiDef[] {
  return CONTEXT_EMOJIS[postType] ?? DEFAULT_EMOJIS;
}
