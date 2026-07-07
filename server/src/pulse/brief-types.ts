// server/src/pulse/brief-types.ts
//
// PULSE — Pure types and constants for the daily brief.
//
// This file has ZERO NestJS dependencies — it can be unit-tested standalone with `bun`.
// (Same pattern as AURA's `graph-metrics.ts` and `archetype-classifier.service.ts`.)
//
// Contents:
//   1. BriefItemType enum (6 item types — the "6-item brief" UX)
//   2. ActionType enum (what happens when the user taps an item)
//   3. InteractionType enum (what the user actually did)
//   4. WeatherType enum (sunny → stormy emotional climate)
//   5. BriefItemData — the pure data shape that collectors return
//   6. BriefCollector — the interface every collector implements
//   7. BriefCollectorContext — the context passed to every collector
//   8. BriefResult — the assembled brief (returned to client + persisted)
//   9. GREETINGS — 8-language "Good morning, {name}" templates
//  10. ACTION_LABELS — 8-language action button labels (Call / Send / See / Listen…)
//  11. ITEM_TYPE_ICONS — emoji icons for each item type (Flutter renders these)
//  12. Helper: localizeGreeting, localizeAction, daysUntilNextBirthday
//
// All collector implementations MUST:
//   - Implement `BriefCollector`
//   - Be defensive: return `[]` on any error (a single collector failure
//     must NOT break the brief — the orchestrator wraps each collector in try/catch)
//   - Use `ctx.userLanguageCode` for localization, fall back to English
//

// ─────────────────────────────────────────────────────────────────────────────
// 1. BriefItemType — the 6 item types in the morning brief
// ─────────────────────────────────────────────────────────────────────────────
//
// Each type maps to a section in the brief UX:
//
//   need_you        💜 "Needs you today"        — elder inactive 4+ days
//   birthday        🎂 "This week"              — upcoming birthdays
//   feed_highlight  📸 "Just happened"          — family posts you missed
//   weather         🌧️ "Relationship weather"   — cloudy/stormy pairs
//   memory_orbit    👵 "New from the elders"    — Pitru memories (stub for now)
//   on_this_day     🔮 "On this day"            — Sparqs/stories from prior years
//
export type BriefItemType =
  | 'need_you'
  | 'birthday'
  | 'feed_highlight'
  | 'weather'
  | 'memory_orbit'
  | 'on_this_day';

export const BRIEF_ITEM_TYPES: BriefItemType[] = [
  'need_you',
  'birthday',
  'feed_highlight',
  'weather',
  'memory_orbit',
  'on_this_day',
];

// ─────────────────────────────────────────────────────────────────────────────
// 2. ActionType — what happens when the user taps the item's action button
// ─────────────────────────────────────────────────────────────────────────────
export type ActionType =
  | 'call'           // open phone dialer
  | 'message'        // open chat / WhatsApp
  | 'view_post'      // open FamilyPost detail
  | 'view_sparq'     // open Sparq detail
  | 'contribute'     // open family gift pool (Phase 2)
  | 'listen_memory'  // play Pitru audio (Phase 4 stub)
  | 'view_memory'    // open Pitru memory detail
  | 'none';          // display-only items (rare)

// ─────────────────────────────────────────────────────────────────────────────
// 3. InteractionType — what the user actually did (recorded in BriefInteraction)
// ─────────────────────────────────────────────────────────────────────────────
export type InteractionType =
  | 'call'
  | 'message'
  | 'view'
  | 'dismiss'
  | 'skip'
  | 'snooze';

// ─────────────────────────────────────────────────────────────────────────────
// 4. WeatherType — per-pair emotional climate
// ─────────────────────────────────────────────────────────────────────────────
//
// Mapping heuristic (used by PulseCronService @ 1am):
//   stormy        — 0 interactions in 60d, OR sentimentScore < 0.3
//   rainy         — 0 interactions in 30d, OR sentimentScore < 0.45
//   cloudy        — 0 interactions in 14d
//   partly_cloudy — 0 interactions in 7d
//   sunny         — recent contact + healthy sentiment
//
export type WeatherType =
  | 'sunny'
  | 'partly_cloudy'
  | 'cloudy'
  | 'rainy'
  | 'stormy';

export const WEATHER_PRIORITY: Record<WeatherType, number> = {
  stormy: 85,
  rainy: 75,
  cloudy: 65,
  partly_cloudy: 40,
  sunny: 0, // sunny is never surfaced as a brief item
};

// ─────────────────────────────────────────────────────────────────────────────
// 5. BriefItemData — pure data shape returned by collectors
// ─────────────────────────────────────────────────────────────────────────────
//
// The orchestrator (BriefGeneratorService) merges all collectors' BriefItemData[]
// into one array, sorts by priority DESC, caps at 6, and persists each as a
// BriefItem row. The same shape is also embedded inside DailyBrief.content JSON.
//
export interface BriefItemData {
  itemType: BriefItemType;
  priority: number; // 0-100, higher = earlier in the brief
  title: string; // e.g. "Dadi hasn't been active in 4 days"
  body: string; // e.g. "She mentioned knee pain in her last voice note."
  actionLabel: string; // e.g. "Call her"
  actionType: ActionType;
  actionData: Record<string, unknown>; // e.g. { phone: "+91..." }
  targetPersonId?: string;
  targetUserId?: string;
  targetSparqId?: string;
  targetPostId?: string;
  relevanceScore?: number; // 0-1, set by Phase 2 graph logic; default 0.5
}

// ─────────────────────────────────────────────────────────────────────────────
// 6. BriefCollector — interface every collector implements
// ─────────────────────────────────────────────────────────────────────────────
export interface BriefCollector {
  /** Stable identifier, e.g. 'birthday', 'inactivity'. Used in logs. */
  readonly name: string;

  /**
   * Collect brief items for the given context.
   * MUST be defensive: return [] on any error (the orchestrator wraps in
   * try/catch too, but collectors should not throw on missing data).
   */
  collect(ctx: BriefCollectorContext): Promise<BriefItemData[]>;
}

// ─────────────────────────────────────────────────────────────────────────────
// 7. BriefCollectorContext — passed to every collector
// ─────────────────────────────────────────────────────────────────────────────
//
// The orchestrator builds this once per brief generation, then passes the same
// context to all collectors (which run in parallel). Collectors must NOT mutate it.
//
export interface BriefCollectorContext {
  userId: string;
  familyId: string;
  briefDate: Date; // the day this brief is for (DATE, 00:00 local)
  userLanguageCode: string; // ISO-639-1 ('en', 'hi', 'ta', 'te', 'kn', 'mr', 'gu', 'bn')
  userDisplayName: string | null; // for greeting personalization
  familyArchetype: string; // from AURA, or 'unknown' if AURA hasn't run yet
  /** The user's Person node, if linked. null if user has no linkedPerson. */
  userPersonId: string | null;
  /** The user's AURA role in this family, if computed. null if no AURA yet. */
  userRoleKey: string | null;
  /**
   * Phase 2: Personalization service (with cached family graph loaded).
   * Collectors can call ctx.personalization?.computeClosenessForTarget(personId)
   * to get a 0-1 closeness score for setting BriefItemData.relevanceScore.
   * Optional — collectors that don't use it can ignore the field.
   */
  personalization?: {
    computeClosenessForTarget: (targetPersonId: string) => {
      total: number;
      graphDistance: number;
      generationDistance: number;
      relationshipSemantic: number;
      auraRoleMatch: number;
      sharedConnections: number;
      hopCount: number | null;
      notes: string[];
    };
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// 8. BriefResult — the assembled brief returned to client + persisted
// ─────────────────────────────────────────────────────────────────────────────
export interface BriefResult {
  id: string; // DailyBrief.id
  userId: string;
  familyId: string;
  briefDate: string; // ISO date 'YYYY-MM-DD'
  greeting: string;
  familyArchetype: string;
  languageCode: string;
  items: BriefItemData[];
  summary: string; // one-sentence summary like "3 things need you today"
  generatedAt: string; // ISO timestamp
}

// ─────────────────────────────────────────────────────────────────────────────
// 9. GREETINGS — 8-language "Good morning, {name}" templates
// ─────────────────────────────────────────────────────────────────────────────
//
// Supported languages (matches AURA's language distribution):
//   en — English     (default fallback)
//   hi — Hindi       (Devanagari)
//   ta — Tamil
//   te — Telugu
//   kn — Kannada
//   mr — Marathi
//   gu — Gujarati
//   bn — Bengali
//
// Each template has two parts:
//   greeting:  the "Good morning" prefix
//   suffix:    the "Here's your family today." suffix
// The user's name is inserted between them. If name is null, the generic form
// (no name) is used.
//
export interface GreetingTemplate {
  greeting: string; // e.g. "Good morning"
  suffixWithFamily: string; // e.g. ". Here's your family today."
  generic: string; // e.g. "Good morning! Here's your family today."
}

export const GREETINGS: Record<string, GreetingTemplate> = {
  en: {
    greeting: 'Good morning',
    suffixWithFamily: ". Here's your family today.",
    generic: "Good morning! Here's your family today.",
  },
  hi: {
    greeting: 'सुप्रभात',
    suffixWithFamily: '। आपका परिवार आज यहाँ है।',
    generic: 'सुप्रभात! आपका परिवार आज यहाँ है।',
  },
  ta: {
    greeting: 'காலை வணக்கம்',
    suffixWithFamily: '. இன்று உங்கள் குடும்பம் இங்கே.',
    generic: 'காலை வணக்கம்! இன்று உங்கள் குடும்பம் இங்கே.',
  },
  te: {
    greeting: 'శుభోదయం',
    suffixWithFamily: '. మీ కుటుంబం ఈ రోజు ఇక్కడ ఉంది.',
    generic: 'శుభోదయం! మీ కుటుంబం ఈ రోజు ఇక్కడ ఉంది.',
  },
  kn: {
    greeting: 'ಶುಭೋದಯ',
    suffixWithFamily: '. ಇಂದು ನಿಮ್ಮ ಕುಟುಂಬ ಇಲ್ಲಿದೆ.',
    generic: 'ಶುಭೋದಯ! ಇಂದು ನಿಮ್ಮ ಕುಟುಂಬ ಇಲ್ಲಿದೆ.',
  },
  mr: {
    greeting: 'सुप्रभात',
    suffixWithFamily: '. आज तुमचे कुटुंब इथे आहे.',
    generic: 'सुप्रभात! आज तुमचे कुटुंब इथे आहे.',
  },
  gu: {
    greeting: 'સુપ્રભાત',
    suffixWithFamily: '. આજે તમારું પરિવાર અહીં છે.',
    generic: 'સુપ્રભાત! આજે તમારું પરિવાર અહીં છે.',
  },
  bn: {
    greeting: 'সুপ্রভাত',
    suffixWithFamily: '। আজ আপনার পরিবার এখানে।',
    generic: 'সুপ্রভাত! আজ আপনার পরিবার এখানে।',
  },
};

// ─────────────────────────────────────────────────────────────────────────────
// 10. ACTION_LABELS — 8-language action button labels
// ─────────────────────────────────────────────────────────────────────────────
//
// Keyed by ActionType. Each entry is a map of language → label.
// Collectors pass the ActionType; the orchestrator localizes the label using
// the user's preferredLanguage before persisting.
//
export const ACTION_LABELS: Record<ActionType, Record<string, string>> = {
  call: {
    en: 'Call',
    hi: 'कॉल करें',
    ta: 'அழை',
    te: 'కాల్ చేయండి',
    kn: 'ಕಾಲ್ ಮಾಡಿ',
    mr: 'कॉल करा',
    gu: 'કૉલ કરો',
    bn: 'কল করুন',
  },
  message: {
    en: 'Send a message',
    hi: 'संदेश भेजें',
    ta: 'செய்தி அனுப்பு',
    te: 'సందేశం పంపండి',
    kn: 'ಸಂದೇಶ ಕಳುಹಿಸಿ',
    mr: 'संदेश पाठवा',
    gu: 'સંદેશ મોકલો',
    bn: 'বার্তা পাঠান',
  },
  view_post: {
    en: 'See photos',
    hi: 'फ़ोटो देखें',
    ta: 'படங்களைப் பார்',
    te: 'ఫోటోలు చూడండి',
    kn: 'ಫೋಟೋಗಳನ್ನು ನೋಡಿ',
    mr: 'फोटो पहा',
    gu: 'ફોટો જુઓ',
    bn: 'ছবি দেখুন',
  },
  view_sparq: {
    en: 'See moment',
    hi: 'पल देखें',
    ta: 'தருணத்தைப் பார்',
    te: 'క్షణం చూడండి',
    kn: 'ಕ್ಷಣವನ್ನು ನೋಡಿ',
    mr: 'क्षण पहा',
    gu: 'ક્ષણ જુઓ',
    bn: 'মুহূর্ত দেখুন',
  },
  contribute: {
    en: 'Contribute',
    hi: 'योगदान दें',
    ta: 'பங்களிப்பு',
    te: 'సహకరించండి',
    kn: 'ಕೊಡುಗೆ ನೀಡಿ',
    mr: 'योगदान द्या',
    gu: 'યોગદાન આપો',
    bn: 'অবদান রাখুন',
  },
  listen_memory: {
    en: 'Listen',
    hi: 'सुनें',
    ta: 'கேள்',
    te: 'వినండి',
    kn: 'ಕೇಳಿ',
    mr: 'ऐका',
    gu: 'સાંભળો',
    bn: 'শুনুন',
  },
  view_memory: {
    en: 'View memory',
    hi: 'स्मृति देखें',
    ta: 'நினைவைப் பார்',
    te: 'జ్ఞాపకం చూడండి',
    kn: 'ನೆನಪನ್ನು ನೋಡಿ',
    mr: 'स्मृती पहा',
    gu: 'સ્મૃતિ જુઓ',
    bn: 'স্মৃতি দেখুন',
  },
  none: {
    en: 'OK',
    hi: 'ठीक है',
    ta: 'சரி',
    te: 'సరే',
    kn: 'ಸರಿ',
    mr: 'ठीक',
    gu: 'બરાબર',
    bn: 'ঠিক আছে',
  },
};

// ─────────────────────────────────────────────────────────────────────────────
// 11. ITEM_TYPE_ICONS — emoji icons for each item type (rendered by Flutter)
// ─────────────────────────────────────────────────────────────────────────────
export const ITEM_TYPE_ICONS: Record<BriefItemType, string> = {
  need_you: '💜',
  birthday: '🎂',
  feed_highlight: '📸',
  weather: '🌧️',
  memory_orbit: '👵',
  on_this_day: '🔮',
};

// ─────────────────────────────────────────────────────────────────────────────
// 12. Helpers (pure functions)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Localize the greeting for the given language and user name.
 * Falls back to English if the language is unsupported.
 * Returns the generic form (no name) if name is null/empty.
 */
export function localizeGreeting(
  languageCode: string,
  userName: string | null,
): string {
  const tpl = GREETINGS[languageCode] ?? GREETINGS.en;
  if (!userName || userName.trim().length === 0) {
    return tpl.generic;
  }
  return `${tpl.greeting}, ${userName.trim()}${tpl.suffixWithFamily}`;
}

/**
 * Localize an action label for the given language.
 * Falls back to English if the language is unsupported.
 */
export function localizeAction(
  actionType: ActionType,
  languageCode: string,
): string {
  const labels = ACTION_LABELS[actionType] ?? ACTION_LABELS.none;
  return labels[languageCode] ?? labels.en;
}

/**
 * Compute the number of days until the next occurrence of a birthday.
 *
 * Handles two input shapes:
 *   - full Date (year, month, day) → standard next-birthday computation
 *   - year-only (birthYear integer, month/day default to Jan 1) → also returns
 *     days-until-Jan-1 so we still surface "birthday this week"
 *
 * Returns an integer in [0, 365]. Returns null if dob is null/invalid.
 * Returns 0 if the birthday is today.
 */
export function daysUntilNextBirthday(dob: Date | null, birthYear?: number | null): number | null {
  // Year-only fallback: treat as Jan 1 of that year, but for "days until" we
  // only care about month/day — so synthesize a Date at year=2000, month=0, day=1.
  // (Year=2000 is a leap year so Feb 29 birthdays are handled correctly.)
  if (!dob && (birthYear === null || birthYear === undefined)) {
    return null;
  }

  let month: number;
  let day: number;
  if (dob) {
    month = dob.getUTCMonth(); // 0-11
    day = dob.getUTCDate(); // 1-31
  } else {
    month = 0;
    day = 1;
  }

  const now = new Date();
  const nowUtc = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));

  // This year's birthday (in UTC)
  let thisYearBday = new Date(Date.UTC(nowUtc.getUTCFullYear(), month, day));

  // If it already passed this year, look at next year
  if (thisYearBday.getTime() < nowUtc.getTime()) {
    thisYearBday = new Date(Date.UTC(nowUtc.getUTCFullYear() + 1, month, day));
  }

  const msPerDay = 1000 * 60 * 60 * 24;
  return Math.round((thisYearBday.getTime() - nowUtc.getTime()) / msPerDay);
}

/**
 * Estimate a person's age (in years) given their DOB or birthYear.
 * Returns null if neither is available.
 */
export function estimateAge(dob: Date | null, birthYear?: number | null): number | null {
  if (dob) {
    const now = new Date();
    let age = now.getUTCFullYear() - dob.getUTCFullYear();
    const m = now.getUTCMonth() - dob.getUTCMonth();
    if (m < 0 || (m === 0 && now.getUTCDate() < dob.getUTCDate())) {
      age--;
    }
    return age >= 0 && age < 150 ? age : null;
  }
  if (birthYear !== null && birthYear !== undefined) {
    const now = new Date();
    const age = now.getUTCFullYear() - birthYear;
    return age >= 0 && age < 150 ? age : null;
  }
  return null;
}

/**
 * Default priority for each item type (used when collector doesn't override).
 * These match the implementation prompt's section §7 priorities.
 */
export const DEFAULT_PRIORITY: Record<BriefItemType, number> = {
  need_you: 95,
  birthday: 90,
  feed_highlight: 60,
  weather: 65,
  memory_orbit: 70,
  on_this_day: 70,
};

/**
 * Default action type for each item type.
 */
export const DEFAULT_ACTION_TYPE: Record<BriefItemType, ActionType> = {
  need_you: 'call',
  birthday: 'contribute',
  feed_highlight: 'view_post',
  weather: 'message',
  memory_orbit: 'listen_memory',
  on_this_day: 'view_sparq',
};
