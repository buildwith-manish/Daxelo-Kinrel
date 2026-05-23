// DAXELO KINREL — Pack 09: Indian Event Type Definitions
// 14 Indian event types with Hindi names, descriptions, default reminders, and religious context

// ── Types ────────────────────────────────────────────────────────────

export type IndianEventType =
  | 'puja'
  | 'wedding'
  | 'engagement'
  | 'birthday'
  | 'shraddh'
  | 'grah_pravesh'
  | 'naming'
  | 'upanayana'
  | 'festival'
  | 'mundan'
  | 'haldi'
  | 'mehndi'
  | 'sangeet'
  | 'custom';

export interface IndianEventTypeDef {
  type: IndianEventType;
  labelEn: string;
  labelHi: string;
  description: string;
  icon: string; // Lucide icon name
  defaultReminders: number[]; // Offsets in minutes before event
  religiousContext: string[];
  color: string; // Tailwind color class
}

// ── Event Type Definitions ───────────────────────────────────────────

export const INDIAN_EVENT_TYPES: Record<IndianEventType, IndianEventTypeDef> = {
  puja: {
    type: 'puja',
    labelEn: 'Puja / Prayer',
    labelHi: 'पूजा',
    description: 'Religious worship ceremony at home or temple',
    icon: 'Flame',
    defaultReminders: [1440, 60], // 1 day, 1 hour
    religiousContext: ['hindu', 'jain', 'sikh', 'buddhist'],
    color: 'text-orange-500',
  },
  wedding: {
    type: 'wedding',
    labelEn: 'Wedding',
    labelHi: 'विवाह',
    description: 'Marriage ceremony with traditional rituals',
    icon: 'Heart',
    defaultReminders: [10080, 1440, 120], // 1 week, 1 day, 2 hours
    religiousContext: ['hindu', 'muslim', 'sikh', 'jain', 'christian', 'buddhist'],
    color: 'text-red-500',
  },
  engagement: {
    type: 'engagement',
    labelEn: 'Engagement / Ring Ceremony',
    labelHi: 'सगाई',
    description: 'Formal engagement and ring exchange ceremony',
    icon: 'Gem',
    defaultReminders: [1440, 120], // 1 day, 2 hours
    religiousContext: ['hindu', 'muslim', 'sikh', 'jain', 'christian'],
    color: 'text-pink-500',
  },
  birthday: {
    type: 'birthday',
    labelEn: 'Birthday',
    labelHi: 'जन्मदिन',
    description: 'Birthday celebration',
    icon: 'Cake',
    defaultReminders: [1440, 60], // 1 day, 1 hour
    religiousContext: ['all'],
    color: 'text-yellow-500',
  },
  shraddh: {
    type: 'shraddh',
    labelEn: 'Shraddh / Memorial',
    labelHi: 'श्राद्ध',
    description: 'Memorial ceremony for departed ancestors',
    icon: 'Candle',
    defaultReminders: [1440], // 1 day
    religiousContext: ['hindu'],
    color: 'text-gray-500',
  },
  grah_pravesh: {
    type: 'grah_pravesh',
    labelEn: 'Grah Pravesh',
    labelHi: 'गृह प्रवेश',
    description: 'Housewarming ceremony with Vastu puja',
    icon: 'Home',
    defaultReminders: [1440, 120], // 1 day, 2 hours
    religiousContext: ['hindu', 'jain'],
    color: 'text-green-500',
  },
  naming: {
    type: 'naming',
    labelEn: 'Naming Ceremony / Naamkaran',
    labelHi: 'नामकरण',
    description: 'Traditional naming ceremony for a newborn',
    icon: 'Baby',
    defaultReminders: [1440, 60],
    religiousContext: ['hindu', 'sikh'],
    color: 'text-sky-500',
  },
  upanayana: {
    type: 'upanayana',
    labelEn: 'Upanayana / Janeu',
    labelHi: 'उपनयन',
    description: 'Sacred thread ceremony initiating Vedic education',
    icon: 'BookOpen',
    defaultReminders: [1440, 120],
    religiousContext: ['hindu'],
    color: 'text-amber-600',
  },
  festival: {
    type: 'festival',
    labelEn: 'Festival',
    labelHi: 'त्योहार',
    description: 'Religious or cultural festival celebration',
    icon: 'PartyPopper',
    defaultReminders: [1440, 60],
    religiousContext: ['all'],
    color: 'text-purple-500',
  },
  mundan: {
    type: 'mundan',
    labelEn: 'Mundan / Tonsure',
    labelHi: 'मुंडन',
    description: 'Head-shaving ceremony for children',
    icon: 'Scissors',
    defaultReminders: [1440, 60],
    religiousContext: ['hindu', 'sikh'],
    color: 'text-teal-500',
  },
  haldi: {
    type: 'haldi',
    labelEn: 'Haldi Ceremony',
    labelHi: 'हल्दी',
    description: 'Turmeric application ceremony before wedding',
    icon: 'Droplets',
    defaultReminders: [1440, 120],
    religiousContext: ['hindu'],
    color: 'text-yellow-600',
  },
  mehndi: {
    type: 'mehndi',
    labelEn: 'Mehndi Ceremony',
    labelHi: 'मेहंदी',
    description: 'Henna application ceremony before wedding',
    icon: 'Palmtree',
    defaultReminders: [1440, 120],
    religiousContext: ['hindu', 'muslim'],
    color: 'text-emerald-600',
  },
  sangeet: {
    type: 'sangeet',
    labelEn: 'Sangeet',
    labelHi: 'संगीत',
    description: 'Musical night celebration before wedding',
    icon: 'Music',
    defaultReminders: [1440, 120],
    religiousContext: ['hindu', 'sikh'],
    color: 'text-fuchsia-500',
  },
  custom: {
    type: 'custom',
    labelEn: 'Custom Event',
    labelHi: 'कस्टम कार्यक्रम',
    description: 'Custom family event',
    icon: 'CalendarPlus',
    defaultReminders: [1440, 60],
    religiousContext: ['all'],
    color: 'text-slate-500',
  },
};

// ── Religious Event Mapping ──────────────────────────────────────────

export const RELIGIOUS_EVENTS: Record<string, IndianEventType[]> = {
  hindu: [
    'puja', 'wedding', 'engagement', 'birthday', 'shraddh',
    'grah_pravesh', 'naming', 'upanayana', 'festival',
    'mundan', 'haldi', 'mehndi', 'sangeet', 'custom',
  ],
  muslim: ['wedding', 'engagement', 'birthday', 'festival', 'mehndi', 'custom'],
  sikh: ['puja', 'wedding', 'engagement', 'birthday', 'naming', 'mundan', 'sangeet', 'festival', 'custom'],
  jain: ['puja', 'wedding', 'engagement', 'birthday', 'grah_pravesh', 'festival', 'custom'],
  christian: ['wedding', 'engagement', 'birthday', 'festival', 'custom'],
  buddhist: ['puja', 'wedding', 'birthday', 'festival', 'custom'],
};

// ── Public Functions ─────────────────────────────────────────────────

/**
 * Get default reminder offsets (in minutes before event) for an event type
 */
export function getDefaultReminders(eventType: string): number[] {
  const def = INDIAN_EVENT_TYPES[eventType as IndianEventType];
  return def?.defaultReminders ?? [1440, 60];
}

/**
 * Get the localized label for an event type
 */
export function getEventTypeLabel(type: string, locale: string = 'en'): string {
  const def = INDIAN_EVENT_TYPES[type as IndianEventType];
  if (!def) return type;
  return locale === 'hi' ? def.labelHi : def.labelEn;
}

/**
 * Get the Lucide icon name for an event type
 */
export function getEventTypeIcon(type: string): string {
  const def = INDIAN_EVENT_TYPES[type as IndianEventType];
  return def?.icon ?? 'Calendar';
}
