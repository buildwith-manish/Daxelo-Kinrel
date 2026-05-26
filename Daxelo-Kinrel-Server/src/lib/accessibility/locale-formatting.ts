/**
 * DAXELO KINREL — Indian Locale Formatting
 *
 * Formatting utilities for Indian number system (lakhs/crores),
 * multi-locale date formatting, currency (INR), and relative time.
 *
 * Pack 06: Accessibility — Locale formatting
 */

// ── Indian Locales ────────────────────────────────────────────────

/**
 * All supported Indian locale codes for Intl APIs.
 * These locale codes work with the Intl.NumberFormat,
 * Intl.DateTimeFormat, and Intl.RelativeTimeFormat APIs.
 */
export const INDIAN_LOCALES: string[] = [
  'en-IN',  // English (India) — bridge language
  'hi-IN',  // Hindi
  'bn-IN',  // Bengali
  'te-IN',  // Telugu
  'mr-IN',  // Marathi
  'ta-IN',  // Tamil
  'gu-IN',  // Gujarati
  'kn-IN',  // Kannada
  'ml-IN',  // Malayalam
  'pa-IN',  // Punjabi (Gurmukhi)
  'or-IN',  // Odia
  'ur-IN',  // Urdu
  'as-IN',  // Assamese
  'sa-IN',  // Sanskrit
] as const;

/**
 * Map from 2-letter ISO 639-1 code to full BCP 47 locale tag.
 */
const LOCALE_MAP: Record<string, string> = {
  en: 'en-IN',
  hi: 'hi-IN',
  bn: 'bn-IN',
  te: 'te-IN',
  mr: 'mr-IN',
  ta: 'ta-IN',
  gu: 'gu-IN',
  kn: 'kn-IN',
  ml: 'ml-IN',
  pa: 'pa-IN',
  or: 'or-IN',
  ur: 'ur-IN',
  as: 'as-IN',
  sa: 'sa-IN',
};

/**
 * Convert a 2-letter language code to a full BCP 47 locale tag.
 * Falls back to 'en-IN' for unknown codes.
 */
function toBcp47(locale: string): string {
  return LOCALE_MAP[locale] || 'en-IN';
}

// ── Indian Number Formatting ──────────────────────────────────────

/**
 * Format a number using the Indian numbering system.
 * Indian system: 1,00,000 (one lakh), 1,00,00,000 (one crore)
 *
 * Rules:
 * - First 3 digits from right are grouped normally (hundreds)
 * - Then every 2 digits are grouped (lakhs, crores, etc.)
 *
 * @param num - The number to format
 * @returns Formatted string in Indian number system
 *
 * @example
 * formatIndianNumber(100)       // '100'
 * formatIndianNumber(1000)      // '1,000'
 * formatIndianNumber(10000)     // '10,000'
 * formatIndianNumber(100000)    // '1,00,000'
 * formatIndianNumber(1000000)   // '10,00,000'
 * formatIndianNumber(10000000)  // '1,00,00,000'
 * formatIndianNumber(123456789) // '12,34,56,789'
 */
export function formatIndianNumber(num: number): string {
  if (num < 0) {
    return '-' + formatIndianNumber(-num);
  }

  const numStr = Math.floor(num).toString();
  const len = numStr.length;

  if (len <= 3) {
    return numStr;
  }

  // Indian grouping: first 3 from right, then every 2
  const result: string[] = [];
  let i = len;

  // First group: 3 digits from right
  result.unshift(numStr.substring(i - 3, i));
  i -= 3;

  // Subsequent groups: 2 digits each
  while (i > 0) {
    const start = Math.max(0, i - 2);
    result.unshift(numStr.substring(start, i));
    i -= 2;
  }

  return result.join(',');
}

/**
 * Parse an Indian-formatted number string back to a number.
 * Handles commas in the Indian number system (1,00,000 format).
 *
 * @param str - The Indian-formatted number string
 * @returns The parsed number, or NaN if invalid
 *
 * @example
 * parseIndianNumber('1,00,000')    // 100000
 * parseIndianNumber('12,34,56,789') // 123456789
 * parseIndianNumber('1,000')        // 1000
 */
export function parseIndianNumber(str: string): number {
  // Remove all commas and parse
  const cleaned = str.replace(/,/g, '').trim();
  return Number(cleaned);
}

// ── Date Formatting ───────────────────────────────────────────────

/**
 * Format a date for a specific Indian locale.
 * Uses the Intl.DateTimeFormat API with locale-appropriate
 * date formatting.
 *
 * @param date - The date to format
 * @param locale - 2-letter language code
 * @returns Formatted date string
 *
 * @example
 * formatDate(new Date('2024-01-15'), 'en')  // '15/1/2024'
 * formatDate(new Date('2024-01-15'), 'hi')  // '15/1/2024' in Devanagari
 */
export function formatDate(date: Date, locale: string): string {
  const bcp47 = toBcp47(locale);
  try {
    const formatter = new Intl.DateTimeFormat(bcp47, {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
    });
    return formatter.format(date);
  } catch {
    // Fallback to ISO format
    return date.toLocaleDateString('en-IN');
  }
}

// ── Currency Formatting ───────────────────────────────────────────

/**
 * Format a currency amount for a specific Indian locale.
 * Defaults to INR (Indian Rupees).
 *
 * Uses the Indian number system for en-IN locale
 * (₹1,00,000.00 format).
 *
 * @param amount - The amount to format
 * @param locale - 2-letter language code
 * @param currency - ISO 4217 currency code (default: 'INR')
 * @returns Formatted currency string
 *
 * @example
 * formatCurrency(100000, 'en')    // '₹1,00,000.00'
 * formatCurrency(100000, 'hi')    // '₹1,00,000.00'
 * formatCurrency(50.5, 'en')      // '₹50.50'
 */
export function formatCurrency(
  amount: number,
  locale: string,
  currency: string = 'INR'
): string {
  const bcp47 = toBcp47(locale);
  try {
    const formatter = new Intl.NumberFormat(bcp47, {
      style: 'currency',
      currency,
      minimumFractionDigits: 0,
      maximumFractionDigits: 2,
    });
    return formatter.format(amount);
  } catch {
    // Fallback: Indian number format with ₹ symbol
    return `₹${formatIndianNumber(Math.round(amount))}`;
  }
}

// ── Relative Time Formatting ──────────────────────────────────────

/**
 * Hindi relative time units for fallback when Intl.RelativeTimeFormat
 * is not available or for consistent formatting.
 */
const HINDI_RELATIVE_TIME: Record<string, (value: number) => string> = {
  seconds: (v) => v === 1 ? 'कुछ सेकंड पहले' : `${v} सेकंड पहले`,
  minutes: (v) => v === 1 ? 'एक मिनट पहले' : `${v} मिनट पहले`,
  hours: (v) => v === 1 ? 'एक घंटा पहले' : `${v} घंटे पहले`,
  days: (v) => v === 1 ? 'एक दिन पहले' : `${v} दिन पहले`,
  weeks: (v) => v === 1 ? 'एक सप्ताह पहले' : `${v} सप्ताह पहले`,
  months: (v) => v === 1 ? 'एक महीना पहले' : `${v} महीने पहले`,
  years: (v) => v === 1 ? 'एक साल पहले' : `${v} साल पहले`,
};

/**
 * Format a date as relative time (e.g., "3 days ago", "2 hours ago").
 * Uses Intl.RelativeTimeFormat when available, with Hindi fallback.
 *
 * @param date - The date to format relative to now
 * @param locale - 2-letter language code
 * @returns Relative time string
 *
 * @example
 * formatRelativeTime(new Date(Date.now() - 60000), 'en')  // '1 minute ago'
 * formatRelativeTime(new Date(Date.now() - 60000), 'hi')  // 'एक मिनट पहले'
 */
export function formatRelativeTime(date: Date, locale: string): string {
  const now = Date.now();
  const diffMs = now - date.getTime();
  const diffSeconds = Math.floor(diffMs / 1000);
  const diffMinutes = Math.floor(diffSeconds / 60);
  const diffHours = Math.floor(diffMinutes / 60);
  const diffDays = Math.floor(diffHours / 24);
  const diffWeeks = Math.floor(diffDays / 7);
  const diffMonths = Math.floor(diffDays / 30);
  const diffYears = Math.floor(diffDays / 365);

  // Try Intl.RelativeTimeFormat
  const bcp47 = toBcp47(locale);
  try {
    const rtf = new Intl.RelativeTimeFormat(bcp47, { numeric: 'auto' });

    if (diffYears > 0) return rtf.format(-diffYears, 'year');
    if (diffMonths > 0) return rtf.format(-diffMonths, 'month');
    if (diffWeeks > 0) return rtf.format(-diffWeeks, 'week');
    if (diffDays > 0) return rtf.format(-diffDays, 'day');
    if (diffHours > 0) return rtf.format(-diffHours, 'hour');
    if (diffMinutes > 0) return rtf.format(-diffMinutes, 'minute');
    return rtf.format(-diffSeconds, 'second');
  } catch {
    // Fallback for Hindi
    if (locale === 'hi') {
      if (diffYears > 0) return HINDI_RELATIVE_TIME.years(diffYears);
      if (diffMonths > 0) return HINDI_RELATIVE_TIME.months(diffMonths);
      if (diffWeeks > 0) return HINDI_RELATIVE_TIME.weeks(diffWeeks);
      if (diffDays > 0) return HINDI_RELATIVE_TIME.days(diffDays);
      if (diffHours > 0) return HINDI_RELATIVE_TIME.hours(diffHours);
      if (diffMinutes > 0) return HINDI_RELATIVE_TIME.minutes(diffMinutes);
      return HINDI_RELATIVE_TIME.seconds(diffSeconds);
    }

    // English fallback
    if (diffYears > 0) return `${diffYears} year${diffYears > 1 ? 's' : ''} ago`;
    if (diffMonths > 0) return `${diffMonths} month${diffMonths > 1 ? 's' : ''} ago`;
    if (diffWeeks > 0) return `${diffWeeks} week${diffWeeks > 1 ? 's' : ''} ago`;
    if (diffDays > 0) return `${diffDays} day${diffDays > 1 ? 's' : ''} ago`;
    if (diffHours > 0) return `${diffHours} hour${diffHours > 1 ? 's' : ''} ago`;
    if (diffMinutes > 0) return `${diffMinutes} minute${diffMinutes > 1 ? 's' : ''} ago`;
    return 'just now';
  }
}

// ── Number Words (Indian) ─────────────────────────────────────────

/**
 * Convert a number to its Indian English word representation.
 * Supports up to crores.
 *
 * @param num - The number to convert
 * @returns Number in words (Indian system)
 *
 * @example
 * numberToIndianWords(100000)   // 'One Lakh'
 * numberToIndianWords(10000000) // 'One Crore'
 * numberToIndianWords(1500000)  // 'Fifteen Lakh'
 */
export function numberToIndianWords(num: number): string {
  if (num === 0) return 'Zero';
  if (num < 0) return 'Minus ' + numberToIndianWords(-num);

  const ones = [
    '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six',
    'Seven', 'Eight', 'Nine', 'Ten', 'Eleven', 'Twelve',
    'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen',
    'Eighteen', 'Nineteen',
  ];
  const tens = [
    '', '', 'Twenty', 'Thirty', 'Forty', 'Fifty',
    'Sixty', 'Seventy', 'Eighty', 'Ninety',
  ];

  function convertBelowThousand(n: number): string {
    if (n < 20) return ones[n];
    if (n < 100) {
      return tens[Math.floor(n / 10)] + (n % 10 ? ' ' + ones[n % 10] : '');
    }
    return (
      ones[Math.floor(n / 100)] +
      ' Hundred' +
      (n % 100 ? ' and ' + convertBelowThousand(n % 100) : '')
    );
  }

  let result = '';
  let remaining = Math.floor(num);

  // Crores (1,00,00,000)
  if (remaining >= 10000000) {
    result += convertBelowThousand(Math.floor(remaining / 10000000)) + ' Crore ';
    remaining %= 10000000;
  }

  // Lakhs (1,00,000)
  if (remaining >= 100000) {
    result += convertBelowThousand(Math.floor(remaining / 100000)) + ' Lakh ';
    remaining %= 100000;
  }

  // Thousands
  if (remaining >= 1000) {
    result += convertBelowThousand(Math.floor(remaining / 1000)) + ' Thousand ';
    remaining %= 1000;
  }

  // Hundreds and below
  if (remaining > 0) {
    result += convertBelowThousand(remaining);
  }

  return result.trim();
}
