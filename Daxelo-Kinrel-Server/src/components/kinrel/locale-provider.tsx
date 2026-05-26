'use client';

import { createContext, useContext, useState, useCallback, useMemo } from 'react';
import {
  supportedLanguages,
  getFontClassForLanguage,
  getFontFamilyForLanguage,
  isRTLLanguage,
  textDirectionForLanguage
} from '@/lib/font-loader';
import { isRtl, htmlDir, directionalPadding, directionalMargin } from '@/lib/accessibility/rtl-utils';
import { formatDate, formatCurrency, formatIndianNumber, formatRelativeTime } from '@/lib/accessibility/locale-formatting';

type LocaleInfo = {
  code: string;              // e.g., 'hi'
  name: string;              // e.g., 'Hindi'
  nativeName: string;        // e.g., 'हिन्दी'
  script: string;            // e.g., 'Devanagari'
  fontClass: string;         // e.g., 'font-noto-devanagari'
  fontFamily: string;        // e.g., '"Noto Sans Devanagari", sans-serif'
  direction: 'ltr' | 'rtl';  // text direction
  isRTL: boolean;            // is right-to-left
};

type LocaleContextValue = {
  locale: string;
  setLocale: (code: string) => void;
  localeInfo: LocaleInfo;
  supportedLanguages: typeof supportedLanguages;
  // Formatting functions bound to current locale
  formatDate: (date: Date) => string;
  formatCurrency: (amount: number, currency?: string) => string;
  formatNumber: (num: number) => string;
  formatRelativeTime: (date: Date) => string;
  // RTL utilities bound to current locale
  htmlDir: () => 'ltr' | 'rtl';
  directionalPadding: (start: number, end: number) => { paddingLeft: string; paddingRight: string };
  directionalMargin: (start: number, end: number) => { marginLeft: string; marginRight: string };
};

// Create context with undefined default
const LocaleContext = createContext<LocaleContextValue | undefined>(undefined);

// Provider component
export function LocaleProvider({ children }: { children: React.ReactNode }) {
  const [locale, setLocale] = useState('en');

  const localeInfo = useMemo<LocaleInfo>(() => {
    const lang = supportedLanguages.find(l => l.code === locale) || supportedLanguages[0];
    return {
      code: lang.code,
      name: lang.name,
      nativeName: lang.nativeName,
      script: lang.script,
      fontClass: getFontClassForLanguage(lang.code),
      fontFamily: getFontFamilyForLanguage(lang.code),
      direction: textDirectionForLanguage(lang.code),
      isRTL: isRTLLanguage(lang.code),
    };
  }, [locale]);

  // Bound formatting functions
  const boundFormatDate = useCallback((date: Date) => formatDate(date, locale), [locale]);
  const boundFormatCurrency = useCallback((amount: number, currency?: string) => formatCurrency(amount, locale, currency), [locale]);
  const boundFormatNumber = useCallback((num: number) => formatIndianNumber(num), [locale]);
  const boundFormatRelativeTime = useCallback((date: Date) => formatRelativeTime(date, locale), [locale]);
  const boundHtmlDir = useCallback(() => htmlDir(locale), [locale]);
  const boundDirPadding = useCallback((start: number, end: number) => directionalPadding(locale, start, end), [locale]);
  const boundDirMargin = useCallback((start: number, end: number) => directionalMargin(locale, start, end), [locale]);
  const boundSetLocale = useCallback((code: string) => setLocale(code), []);

  const value = useMemo<LocaleContextValue>(() => ({
    locale,
    setLocale: boundSetLocale,
    localeInfo,
    supportedLanguages,
    formatDate: boundFormatDate,
    formatCurrency: boundFormatCurrency,
    formatNumber: boundFormatNumber,
    formatRelativeTime: boundFormatRelativeTime,
    htmlDir: boundHtmlDir,
    directionalPadding: boundDirPadding,
    directionalMargin: boundDirMargin,
  }), [locale, localeInfo, boundFormatDate, boundFormatCurrency, boundFormatNumber, boundFormatRelativeTime, boundHtmlDir, boundDirPadding, boundDirMargin, boundSetLocale]);

  return (
    <LocaleContext.Provider value={value}>
      <div dir={localeInfo.direction} className={localeInfo.fontClass} style={{ fontFamily: localeInfo.fontFamily }}>
        {children}
      </div>
    </LocaleContext.Provider>
  );
}

// Hook
export function useLocale(): LocaleContextValue {
  const context = useContext(LocaleContext);
  if (!context) {
    throw new Error('useLocale must be used within a LocaleProvider');
  }
  return context;
}
