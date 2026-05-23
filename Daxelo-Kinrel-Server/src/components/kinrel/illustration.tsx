'use client';

/**
 * DAXELO KINREL — Illustration Component
 *
 * Renders illustration specs as SVG placeholders with:
 * - Category-appropriate icons and colors
 * - Locale-aware alt text (14 Indian languages)
 * - Animated entrance (fade + scale) respecting reduced motion
 * - Three size variants (sm, md, lg)
 *
 * Pack 12: Brand & Motion — Illustration
 */

import React, { useMemo } from 'react';
import { motion } from 'framer-motion';
import { cn } from '@/lib/utils';
import {
  TreePine, Users, Gift, AlertTriangle, Sparkles, Palette,
} from 'lucide-react';
import {
  ILLUSTRATION_CATEGORIES,
  EMPTY_STATE_ILLUSTRATIONS,
  ONBOARDING_ILLUSTRATIONS,
  CELEBRATION_ILLUSTRATIONS,
  ERROR_ILLUSTRATIONS,
  FESTIVAL_ILLUSTRATIONS,
  getIllustrationAltText,
  type IllustrationLocale,
  type IllustrationSpec,
} from '@/lib/brand/illustration-system';
import { useReducedMotion } from '@/hooks/use-accessibility';

// ── Props ──────────────────────────────────────────────────────────
export type IllustrationProps = {
  name: string; // key from ILLUSTRATIONS
  locale?: string;
  size?: 'sm' | 'md' | 'lg';
  className?: string;
};

// ── Size map ───────────────────────────────────────────────────────
const SIZE_MAP = {
  sm: { svg: 80, text: 'text-[10px]', gap: 'gap-2', padding: 'p-3' },
  md: { svg: 140, text: 'text-xs', gap: 'gap-3', padding: 'p-5' },
  lg: { svg: 200, text: 'text-sm', gap: 'gap-4', padding: 'p-6' },
} as const;

// ── Category colors and icons ──────────────────────────────────────
const CATEGORY_CONFIG: Record<
  keyof typeof ILLUSTRATION_CATEGORIES,
  { icon: React.ElementType; bg: string; fg: string; border: string; gradient: [string, string] }
> = {
  emptyStates: {
    icon: Users,
    bg: 'bg-[#FFF7ED] dark:bg-[#431407]',
    fg: 'text-[#EA580C]',
    border: 'border-[#FED7AA] dark:border-[#9A3412]',
    gradient: ['#FFF7ED', '#FFEDD5'],
  },
  onboarding: {
    icon: TreePine,
    bg: 'bg-[#F0FDF4] dark:bg-[#052E16]',
    fg: 'text-[#16A34A]',
    border: 'border-[#BBF7D0] dark:border-[#166534]',
    gradient: ['#F0FDF4', '#DCFCE7'],
  },
  celebration: {
    icon: Gift,
    bg: 'bg-[#FFF7ED] dark:bg-[#431407]',
    fg: 'text-[#F97316]',
    border: 'border-[#FED7AA] dark:border-[#9A3412]',
    gradient: ['#FFF7ED', '#FEF3C7'],
  },
  error: {
    icon: AlertTriangle,
    bg: 'bg-[#FEF2F2] dark:bg-[#450A0A]',
    fg: 'text-[#DC2626]',
    border: 'border-[#FECACA] dark:border-[#991B1B]',
    gradient: ['#FEF2F2', '#FEE2E2'],
  },
  feature: {
    icon: Sparkles,
    bg: 'bg-[#EFF6FF] dark:bg-[#172554]',
    fg: 'text-[#2563EB]',
    border: 'border-[#BFDBFE] dark:border-[#1E40AF]',
    gradient: ['#EFF6FF', '#DBEAFE'],
  },
  culturalFestival: {
    icon: Palette,
    bg: 'bg-[#FEF3C7] dark:bg-[#451A03]',
    fg: 'text-[#D97706]',
    border: 'border-[#FDE68A] dark:border-[#92400E]',
    gradient: ['#FEF3C7', '#FDE68A'],
  },
};

// ── All illustrations flattened ────────────────────────────────────
const ALL_ILLUSTRATIONS: IllustrationSpec[] = [
  ...EMPTY_STATE_ILLUSTRATIONS,
  ...ONBOARDING_ILLUSTRATIONS,
  ...CELEBRATION_ILLUSTRATIONS,
  ...ERROR_ILLUSTRATIONS,
  ...FESTIVAL_ILLUSTRATIONS,
];

function findIllustration(name: string): IllustrationSpec | undefined {
  return ALL_ILLUSTRATIONS.find((s) => s.name === name);
}

// ── Component ──────────────────────────────────────────────────────
export function Illustration({
  name,
  locale = 'en',
  size = 'md',
  className,
}: IllustrationProps) {
  const prefersReducedMotion = useReducedMotion();
  const config = SIZE_MAP[size];

  const spec = useMemo(() => findIllustration(name), [name]);
  const category = spec?.category ?? 'emptyStates';
  const catConfig = CATEGORY_CONFIG[category] ?? CATEGORY_CONFIG.emptyStates;
  const Icon = catConfig.icon;

  const altText = useMemo(
    () => (spec ? getIllustrationAltText(name, locale as IllustrationLocale) : name),
    [spec, name, locale],
  );

  const svgSize = config.svg;

  // Animated entrance variants
  const entranceVariants = {
    hidden: { opacity: 0, scale: 0.85 },
    visible: {
      opacity: 1,
      scale: 1,
      transition: prefersReducedMotion
        ? { duration: 0 }
        : {
            duration: 0.5,
            ease: [0.0, 0.0, 0.2, 1] as [number, number, number, number],
          },
    },
  };

  return (
    <motion.div
      className={cn(
        'flex flex-col items-center justify-center rounded-2xl',
        catConfig.bg,
        catConfig.border,
        'border',
        config.padding,
        config.gap,
        className,
      )}
      variants={entranceVariants}
      initial="hidden"
      animate="visible"
      role="img"
      aria-label={altText}
    >
      {/* SVG Placeholder Illustration */}
      <svg
        width={svgSize}
        height={svgSize}
        viewBox="0 0 200 200"
        className="overflow-visible"
        aria-hidden="true"
      >
        {/* Background circle with category gradient */}
        <defs>
          <radialGradient id={`grad-${name}`} cx="50%" cy="50%" r="50%">
            <stop offset="0%" stopColor={catConfig.gradient[0]} stopOpacity="0.6" />
            <stop offset="100%" stopColor={catConfig.gradient[1]} stopOpacity="0.3" />
          </radialGradient>
        </defs>
        <circle cx="100" cy="100" r="90" fill={`url(#grad-${name})`} />

        {/* Category icon placeholder — centered geometric shape */}
        {category === 'onboarding' && (
          <>
            {/* Tree shape */}
            <rect x="93" y="115" width="14" height="50" rx="4" fill="#92400E" opacity="0.7" />
            <ellipse cx="100" cy="80" rx="50" ry="45" fill="#22C55E" opacity="0.6" />
            <ellipse cx="80" cy="70" rx="25" ry="22" fill="#4ADE80" opacity="0.5" />
            <ellipse cx="120" cy="75" rx="22" ry="20" fill="#16A34A" opacity="0.5" />
            <circle cx="100" cy="60" r="12" fill="#F97316" opacity="0.6" />
          </>
        )}

        {category === 'emptyStates' && (
          <>
            {/* Empty/faded shape */}
            <ellipse cx="100" cy="130" rx="60" ry="15" fill="#F97316" opacity="0.15" />
            <rect x="80" y="80" width="40" height="50" rx="8" fill="#FED7AA" opacity="0.6" />
            <circle cx="100" cy="68" r="18" fill="#FB923C" opacity="0.4" />
            <line x1="72" y1="105" x2="128" y2="105" stroke="#F97316" strokeWidth="2" strokeDasharray="6 4" opacity="0.3" />
          </>
        )}

        {category === 'celebration' && (
          <>
            {/* Celebration shape */}
            <polygon points="100,30 115,75 160,75 125,100 138,145 100,120 62,145 75,100 40,75 85,75" fill="#FFD700" opacity="0.5" />
            <circle cx="70" cy="50" r="6" fill="#F97316" opacity="0.6" />
            <circle cx="140" cy="45" r="5" fill="#E94560" opacity="0.5" />
            <circle cx="100" cy="160" r="8" fill="#F97316" opacity="0.4" />
            <rect x="60" y="130" width="80" height="4" rx="2" fill="#F97316" opacity="0.2" />
          </>
        )}

        {category === 'error' && (
          <>
            {/* Error shape */}
            <circle cx="100" cy="90" r="45" fill="#FEE2E2" opacity="0.6" stroke="#EF4444" strokeWidth="3" strokeDasharray="8 4" />
            <line x1="78" y1="68" x2="122" y2="112" stroke="#EF4444" strokeWidth="4" strokeLinecap="round" opacity="0.5" />
            <line x1="122" y1="68" x2="78" y2="112" stroke="#EF4444" strokeWidth="4" strokeLinecap="round" opacity="0.5" />
            <ellipse cx="100" cy="155" rx="40" ry="8" fill="#FCA5A5" opacity="0.3" />
          </>
        )}

        {category === 'culturalFestival' && (
          <>
            {/* Festival/cultural shape */}
            <rect x="70" y="60" width="60" height="70" rx="6" fill="#FFD700" opacity="0.4" />
            <path d="M70 60 Q100 30 130 60" fill="#F97316" opacity="0.3" />
            <circle cx="100" cy="90" r="12" fill="#E94560" opacity="0.5" />
            <rect x="85" y="105" width="30" height="3" rx="1.5" fill="#D97706" opacity="0.4" />
            <rect x="90" y="112" width="20" height="3" rx="1.5" fill="#D97706" opacity="0.3" />
            {/* Diya / lamp dots */}
            <circle cx="78" cy="140" r="4" fill="#F97316" opacity="0.6" />
            <circle cx="100" cy="145" r="4" fill="#F97316" opacity="0.6" />
            <circle cx="122" cy="140" r="4" fill="#F97316" opacity="0.6" />
          </>
        )}

        {category === 'feature' && (
          <>
            {/* Feature shape */}
            <rect x="65" y="60" width="70" height="80" rx="12" fill="#DBEAFE" opacity="0.5" stroke="#2563EB" strokeWidth="2" />
            <circle cx="100" cy="85" r="10" fill="#3B82F6" opacity="0.4" />
            <rect x="80" y="105" width="40" height="4" rx="2" fill="#60A5FA" opacity="0.4" />
            <rect x="85" y="114" width="30" height="4" rx="2" fill="#93C5FD" opacity="0.3" />
            {/* Sparkle accent */}
            <path d="M145 55 L148 50 L151 55 L148 60 Z" fill="#F97316" opacity="0.6" />
          </>
        )}
      </svg>

      {/* Alt text below */}
      <p
        className={cn(
          'text-center font-medium leading-snug max-w-[200px]',
          catConfig.fg,
          config.text,
        )}
      >
        {altText}
      </p>

      {/* Category badge */}
      <span
        className={cn(
          'inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-semibold',
          'bg-white/60 dark:bg-black/30',
          catConfig.fg,
        )}
      >
        <Icon className="w-3 h-3" />
        {ILLUSTRATION_CATEGORIES[category]?.name ?? category}
      </span>
    </motion.div>
  );
}
