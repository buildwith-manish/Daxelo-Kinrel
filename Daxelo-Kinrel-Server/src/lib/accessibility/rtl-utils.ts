/**
 * DAXELO KINREL — RTL Support Utilities
 *
 * Right-to-left language support for Urdu and other RTL scripts.
 * Provides direction detection, mirroring, and layout utilities.
 *
 * Pack 06: Accessibility — RTL support
 */

// ── RTL Locale Detection ──────────────────────────────────────────

/**
 * Locales that use right-to-left text direction.
 * Currently supports Urdu (India's official RTL language),
 * Arabic, and Farsi/Persian.
 */
export const RTL_LOCALES: Set<string> = new Set(['ur', 'ar', 'fa']);

/**
 * Check if a locale uses right-to-left text direction.
 *
 * @param locale - ISO 639-1 language code
 * @returns Whether the locale is RTL
 *
 * @example
 * isRtl('ur')  // true
 * isRtl('hi')  // false
 * isRtl('ar')  // true
 */
export function isRtl(locale: string): boolean {
  return RTL_LOCALES.has(locale);
}

/**
 * Get the text direction for a locale.
 *
 * @param locale - ISO 639-1 language code
 * @returns 'rtl' or 'ltr'
 *
 * @example
 * textDirection('ur')  // 'rtl'
 * textDirection('hi')  // 'ltr'
 */
export function textDirection(locale: string): 'ltr' | 'rtl' {
  return isRtl(locale) ? 'rtl' : 'ltr';
}

// ── Value Mirroring ───────────────────────────────────────────────

/**
 * Mirror a value based on locale direction.
 * Useful for CSS properties like `text-align`, `float`, etc.
 *
 * @param locale - ISO 639-1 language code
 * @param ltrValue - The value to use for LTR contexts
 * @param rtlValue - The value to use for RTL contexts
 * @returns The appropriate value for the locale
 *
 * @example
 * mirrorIfRtl('hi', 'left', 'right')   // 'left'
 * mirrorIfRtl('ur', 'left', 'right')   // 'right'
 */
export function mirrorIfRtl(
  locale: string,
  ltrValue: string,
  rtlValue: string
): string {
  return isRtl(locale) ? rtlValue : ltrValue;
}

/**
 * Get the start alignment direction for a locale.
 * In LTR: start = left
 * In RTL: start = right
 *
 * @param locale - ISO 639-1 language code
 * @returns 'left' or 'right'
 *
 * @example
 * startAlignment('hi')  // 'left'
 * startAlignment('ur')  // 'right'
 */
export function startAlignment(locale: string): 'left' | 'right' {
  return isRtl(locale) ? 'right' : 'left';
}

// ── Directional Padding ───────────────────────────────────────────

/**
 * Create directional padding object that respects text direction.
 * For LTR: padding-left = start, padding-right = end
 * For RTL: padding-left = end, padding-right = start
 *
 * @param locale - ISO 639-1 language code
 * @param start - Padding value for the start side (in px)
 * @param end - Padding value for the end side (in px)
 * @returns Object with paddingLeft and paddingRight in px
 *
 * @example
 * directionalPadding('hi', 16, 8)
 * // { paddingLeft: '16px', paddingRight: '8px' }
 *
 * directionalPadding('ur', 16, 8)
 * // { paddingLeft: '8px', paddingRight: '16px' }
 */
export function directionalPadding(
  locale: string,
  start: number,
  end: number
): { paddingLeft: string; paddingRight: string } {
  if (isRtl(locale)) {
    return {
      paddingLeft: `${end}px`,
      paddingRight: `${start}px`,
    };
  }
  return {
    paddingLeft: `${start}px`,
    paddingRight: `${end}px`,
  };
}

/**
 * Create directional margin object that respects text direction.
 * For LTR: margin-left = start, margin-right = end
 * For RTL: margin-left = end, margin-right = start
 *
 * @param locale - ISO 639-1 language code
 * @param start - Margin value for the start side (in px)
 * @param end - Margin value for the end side (in px)
 * @returns Object with marginLeft and marginRight in px
 */
export function directionalMargin(
  locale: string,
  start: number,
  end: number
): { marginLeft: string; marginRight: string } {
  if (isRtl(locale)) {
    return {
      marginLeft: `${end}px`,
      marginRight: `${start}px`,
    };
  }
  return {
    marginLeft: `${start}px`,
    marginRight: `${end}px`,
  };
}

// ── CSS Class Utilities ───────────────────────────────────────────

/**
 * Get the Tailwind CSS class for the text direction.
 * Use this to set `dir` attribute and directional styling.
 *
 * @param locale - ISO 639-1 language code
 * @returns CSS class string for the direction
 *
 * @example
 * rtlClass('hi')  // 'ltr'
 * rtlClass('ur')  // 'rtl'
 */
export function rtlClass(locale: string): string {
  return isRtl(locale) ? 'rtl' : 'ltr';
}

/**
 * Get the HTML `dir` attribute value for a locale.
 *
 * @param locale - ISO 639-1 language code
 * @returns 'rtl' or 'ltr' for the dir attribute
 *
 * @example
 * <div dir={htmlDir('ur')}>اردو میں لکھیں</div>
 */
export function htmlDir(locale: string): 'rtl' | 'ltr' {
  return textDirection(locale);
}

/**
 * Get Tailwind logical property classes for a locale.
 * These use CSS logical properties that automatically
 * handle RTL/LTR without manual mirroring.
 *
 * @param locale - ISO 639-1 language code
 * @returns Object with logical property class mappings
 */
export function logicalPropertyClasses(locale: string): {
  /** Text alignment — ps-4 (padding-inline-start) */
  paddingInlineStart: string;
  /** pe-4 (padding-inline-end) */
  paddingInlineEnd: string;
  /** ms-4 (margin-inline-start) */
  marginInlineStart: string;
  /** me-4 (margin-inline-end) */
  marginInlineEnd: string;
  /** start-0 (inset-inline-start) */
  insetInlineStart: string;
  /** end-0 (inset-inline-end) */
  insetInlineEnd: string;
  /** rounded-s (border-start-start-radius) */
  roundedStart: string;
  /** rounded-e (border-start-end-radius) */
  roundedEnd: string;
  /** text-start */
  textAlignStart: string;
  /** text-end */
  textAlignEnd: string;
  /** Direction class */
  direction: string;
} {
  return {
    paddingInlineStart: 'ps-4',
    paddingInlineEnd: 'pe-4',
    marginInlineStart: 'ms-4',
    marginInlineEnd: 'me-4',
    insetInlineStart: 'start-0',
    insetInlineEnd: 'end-0',
    roundedStart: 'rounded-s',
    roundedEnd: 'rounded-e',
    textAlignStart: 'text-start',
    textAlignEnd: 'text-end',
    direction: rtlClass(locale),
  };
}
