/**
 * DAXELO KINREL — Font Loader
 *
 * Dynamic font loading for Next.js — only loads the font for the user's language.
 * Supports 14 Indian scripts with Google Fonts CDN.
 *
 * Pack 01: Design System — Typography
 */

import { scriptFonts, rtlScripts } from './design-tokens'

// ── Font Family CSS Class Map ───────────────────────────────────────
export const fontClassMap: Record<string, string> = {
  en: 'font-inter',
  hi: 'font-noto-devanagari',
  mr: 'font-noto-devanagari',
  sa: 'font-noto-devanagari',
  bn: 'font-noto-bengali',
  as: 'font-noto-bengali',
  ta: 'font-noto-tamil',
  te: 'font-noto-telugu',
  kn: 'font-noto-kannada',
  ml: 'font-noto-malayalam',
  gu: 'font-noto-gujarati',
  pa: 'font-noto-gurmukhi',
  or: 'font-noto-oriya',
  ur: 'font-noto-arabic',
}

// ── Font Family Name Map ────────────────────────────────────────────
export const fontFamilyMap: Record<string, string> = {
  en: 'Inter, sans-serif',
  hi: '"Noto Sans Devanagari", sans-serif',
  mr: '"Noto Sans Devanagari", sans-serif',
  sa: '"Noto Sans Devanagari", sans-serif',
  bn: '"Noto Sans Bengali", sans-serif',
  as: '"Noto Sans Bengali", sans-serif',
  ta: '"Noto Sans Tamil", sans-serif',
  te: '"Noto Sans Telugu", sans-serif',
  kn: '"Noto Sans Kannada", sans-serif',
  ml: '"Noto Sans Malayalam", sans-serif',
  gu: '"Noto Sans Gujarati", sans-serif',
  pa: '"Noto Sans Gurmukhi", sans-serif',
  or: '"Noto Sans Oriya", sans-serif',
  ur: '"Noto Sans Arabic", sans-serif',
}

// ── Get Font Class for Language ─────────────────────────────────────
export function getFontClassForLanguage(lang: string): string {
  return fontClassMap[lang] ?? 'font-inter'
}

// ── Get Font Family for Language ────────────────────────────────────
export function getFontFamilyForLanguage(lang: string): string {
  return fontFamilyMap[lang] ?? 'Inter, sans-serif'
}

// ── Check if Language is RTL ────────────────────────────────────────
export function isRTLLanguage(lang: string): boolean {
  return rtlScripts.has(lang)
}

// ── Get Text Direction ──────────────────────────────────────────────
export function textDirectionForLanguage(lang: string): 'ltr' | 'rtl' {
  return isRTLLanguage(lang) ? 'rtl' : 'ltr'
}

// ── Supported Languages ─────────────────────────────────────────────
export const supportedLanguages = [
  { code: 'en', name: 'English', nativeName: 'English', script: 'Latin' },
  { code: 'hi', name: 'Hindi', nativeName: 'हिन्दी', script: 'Devanagari' },
  { code: 'bn', name: 'Bengali', nativeName: 'বাংলা', script: 'Bengali' },
  { code: 'ta', name: 'Tamil', nativeName: 'தமிழ்', script: 'Tamil' },
  { code: 'te', name: 'Telugu', nativeName: 'తెలుగు', script: 'Telugu' },
  { code: 'kn', name: 'Kannada', nativeName: 'ಕನ್ನಡ', script: 'Kannada' },
  { code: 'ml', name: 'Malayalam', nativeName: 'മലയാളം', script: 'Malayalam' },
  { code: 'gu', name: 'Gujarati', nativeName: 'ગુજરાતી', script: 'Gujarati' },
  { code: 'mr', name: 'Marathi', nativeName: 'मराठी', script: 'Devanagari' },
  { code: 'pa', name: 'Punjabi', nativeName: 'ਪੰਜਾਬੀ', script: 'Gurmukhi' },
  { code: 'or', name: 'Odia', nativeName: 'ଓଡ଼ିଆ', script: 'Oriya' },
  { code: 'ur', name: 'Urdu', nativeName: 'اردو', script: 'Arabic' },
  { code: 'as', name: 'Assamese', nativeName: 'অসমীয়া', script: 'Bengali' },
  { code: 'sa', name: 'Sanskrit', nativeName: 'संस्कृतम्', script: 'Devanagari' },
] as const

// ── Indian Number Formatting ────────────────────────────────────────
/**
 * Format number in Indian style: lakhs/crores
 * Example: 100000 → "1,00,000" (not "100,000")
 */
export function formatIndianNumber(num: number): string {
  const str = num.toString()
  const [integerPart, decimalPart] = str.split('.')

  let lastThree = integerPart.slice(-3)
  const otherNumbers = integerPart.slice(0, -3)

  if (otherNumbers !== '') {
    lastThree = ',' + lastThree
  }

  const formatted = otherNumbers.replace(/\B(?=(\d{2})+(?!\d))/g, ',') + lastThree

  return decimalPart ? `${formatted}.${decimalPart}` : formatted
}

/**
 * Format currency in Indian style
 * Example: 150000 → "₹1,50,000"
 */
export function formatIndianCurrency(amount: number, symbol: string = '₹'): string {
  return `${symbol}${formatIndianNumber(amount)}`
}
