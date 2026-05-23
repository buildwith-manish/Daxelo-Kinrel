'use client';

/**
 * DAXELO KINREL — Festival Theme Provider
 *
 * Wraps children with context. Auto-detects active festivals
 * by date. Applies festival color extensions to CSS variables.
 * Provides useFestivalTheme() hook.
 *
 * Pack 12: Brand & Motion — Festival Theme Provider
 */

import React, { createContext, useContext, useEffect, useState, useCallback, useMemo } from 'react';
import {
  FESTIVAL_EXTENSIONS,
  isFestivalActive,
  type FestivalTheme,
} from '@/lib/brand/color-system';

// ── Types ──────────────────────────────────────────────────────────
export interface FestivalThemeContextValue {
  activeFestival: string | null;
  festivalTheme: FestivalTheme | null;
  isFestivalActive: (festival: string) => boolean;
  overrideFestival: (festival: string | null) => void;
  festivalNames: string[];
}

// ── Context ────────────────────────────────────────────────────────
const FestivalThemeContext = createContext<FestivalThemeContextValue>({
  activeFestival: null,
  festivalTheme: null,
  isFestivalActive: () => false,
  overrideFestival: () => {},
  festivalNames: [],
});

// ── Hook ───────────────────────────────────────────────────────────
export function useFestivalTheme(): FestivalThemeContextValue {
  return useContext(FestivalThemeContext);
}

// ── Festival CSS Variable Mapping ──────────────────────────────────
function applyFestivalCSSVars(theme: FestivalTheme | null): void {
  if (typeof document === 'undefined') return;

  const root = document.documentElement;

  if (theme) {
    root.style.setProperty('--festival-primary', theme.primary);
    root.style.setProperty('--festival-secondary', theme.secondary);
    root.style.setProperty('--festival-accent', theme.accent);
    root.style.setProperty('--festival-gradient-start', theme.gradient[0]);
    root.style.setProperty('--festival-gradient-mid', theme.gradient[1]);
    root.style.setProperty('--festival-gradient-end', theme.gradient[2]);
    root.setAttribute('data-festival', 'active');
  } else {
    root.style.removeProperty('--festival-primary');
    root.style.removeProperty('--festival-secondary');
    root.style.removeProperty('--festival-accent');
    root.style.removeProperty('--festival-gradient-start');
    root.style.removeProperty('--festival-gradient-mid');
    root.style.removeProperty('--festival-gradient-end');
    root.removeAttribute('data-festival');
  }
}

// ── Detect Active Festival ─────────────────────────────────────────
function detectActiveFestival(): string | null {
  const festivals = Object.keys(FESTIVAL_EXTENSIONS);
  for (const f of festivals) {
    if (isFestivalActive(f)) return f;
  }
  return null;
}

// ── Provider Component ─────────────────────────────────────────────
export interface FestivalThemeProviderProps {
  children: React.ReactNode;
  /** Override auto-detection with a specific festival */
  forcedFestival?: string | null;
  /** Check interval in milliseconds (default: 3600000 = 1 hour) */
  checkIntervalMs?: number;
}

export function FestivalThemeProvider({
  children,
  forcedFestival,
  checkIntervalMs = 3600000,
}: FestivalThemeProviderProps) {
  const [autoDetected, setAutoDetected] = useState<string | null>(detectActiveFestival);
  const [manualOverride, setManualOverride] = useState<string | null>(null);

  // Auto-detect festival periodically
  useEffect(() => {
    const check = () => {
      const detected = detectActiveFestival();
      setAutoDetected(detected);
    };

    const interval = setInterval(check, checkIntervalMs);
    return () => clearInterval(interval);
  }, [checkIntervalMs]);

  // Apply CSS variables whenever the resolved festival changes
  const activeFestival = manualOverride ?? forcedFestival ?? autoDetected;

  useEffect(() => {
    const theme = activeFestival ? FESTIVAL_EXTENSIONS[activeFestival] ?? null : null;
    applyFestivalCSSVars(theme);
  }, [activeFestival]);

  const handleOverride = useCallback((festival: string | null) => {
    setManualOverride(festival);
  }, []);

  const handleIsFestivalActive = useCallback((festival: string) => {
    return activeFestival === festival || isFestivalActive(festival);
  }, [activeFestival]);

  const festivalTheme = useMemo(
    () => (activeFestival ? FESTIVAL_EXTENSIONS[activeFestival] ?? null : null),
    [activeFestival],
  );

  const festivalNames = useMemo(() => Object.keys(FESTIVAL_EXTENSIONS), []);

  const value = useMemo<FestivalThemeContextValue>(
    () => ({
      activeFestival,
      festivalTheme,
      isFestivalActive: handleIsFestivalActive,
      overrideFestival: handleOverride,
      festivalNames,
    }),
    [activeFestival, festivalTheme, handleIsFestivalActive, handleOverride, festivalNames],
  );

  return (
    <FestivalThemeContext.Provider value={value}>
      {children}
    </FestivalThemeContext.Provider>
  );
}

// ── Festival Banner Component ──────────────────────────────────────
export interface FestivalBannerProps {
  className?: string;
}

export function FestivalBanner({ className }: FestivalBannerProps) {
  const { activeFestival, festivalTheme, overrideFestival } = useFestivalTheme();

  if (!activeFestival || !festivalTheme) return null;

  return (
    <div
      className={className}
      style={{
        background: `linear-gradient(135deg, ${festivalTheme.gradient[0]}, ${festivalTheme.gradient[1]}, ${festivalTheme.gradient[2]})`,
      }}
    >
      <div className="flex items-center justify-between px-4 py-2 text-white">
        <span className="text-sm font-medium">{festivalTheme.name}</span>
        <button
          onClick={() => overrideFestival(null)}
          className="text-xs opacity-80 hover:opacity-100 transition-opacity"
          aria-label="Dismiss festival theme"
        >
          ✕
        </button>
      </div>
    </div>
  );
}
