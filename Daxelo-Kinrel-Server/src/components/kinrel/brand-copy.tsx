'use client';

/**
 * DAXELO KINREL — Brand Copy Component & useBrandVoice Hook
 *
 * Provides:
 * - `useBrandVoice(context)` hook — returns the appropriate tone for a context
 * - `BrandCopy` component — renders copy from COPY_INVENTORY with the correct tone
 * - Variable interpolation in copy text
 * - Tone badge display (friendly, respectful, warm, etc.)
 *
 * Pack 12: Brand & Motion — Brand Copy
 */

import React, { useMemo } from 'react';
import { motion } from 'framer-motion';
import { cn } from '@/lib/utils';
import { Badge } from '@/components/ui/badge';
import {
  Card, CardContent, CardHeader, CardTitle, CardDescription,
} from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import {
  COPY_INVENTORY,
  TONE_SPECTRUM,
  getTone,
  type ToneSpec,
} from '@/lib/brand/brand-voice';
import {
  LogIn, TreePine, Users, CreditCard, Heart,
} from 'lucide-react';
import { useReducedMotion } from '@/hooks/use-accessibility';

// ── Context → Tone mapping ─────────────────────────────────────────
const CONTEXT_TONE_MAP: Record<string, string> = {
  login: 'Onboarding',
  family_creation: 'Success',
  empty_graph: 'EmptyState',
  paywall: 'UpgradePrompt',
  memorial: 'DeceasedMemorial',
};

// ── Context → icon mapping ─────────────────────────────────────────
const CONTEXT_ICONS: Record<string, React.ElementType> = {
  login: LogIn,
  family_creation: TreePine,
  empty_graph: Users,
  paywall: CreditCard,
  memorial: Heart,
};

// ── Tone → color mapping ───────────────────────────────────────────
const TONE_COLORS: Record<string, { bg: string; text: string; border: string }> = {
  Onboarding: {
    bg: 'bg-[#F0FDF4] dark:bg-[#052E16]',
    text: 'text-[#16A34A]',
    border: 'border-[#BBF7D0] dark:border-[#166534]',
  },
  Success: {
    bg: 'bg-[#FFF7ED] dark:bg-[#431407]',
    text: 'text-[#F97316]',
    border: 'border-[#FED7AA] dark:border-[#9A3412]',
  },
  Error: {
    bg: 'bg-[#FEF2F2] dark:bg-[#450A0A]',
    text: 'text-[#DC2626]',
    border: 'border-[#FECACA] dark:border-[#991B1B]',
  },
  Warning: {
    bg: 'bg-[#FEF3C7] dark:bg-[#451A03]',
    text: 'text-[#D97706]',
    border: 'border-[#FDE68A] dark:border-[#92400E]',
  },
  Feature: {
    bg: 'bg-[#EFF6FF] dark:bg-[#172554]',
    text: 'text-[#2563EB]',
    border: 'border-[#BFDBFE] dark:border-[#1E40AF]',
  },
  EmptyState: {
    bg: 'bg-[#FFF7ED] dark:bg-[#431407]',
    text: 'text-[#EA580C]',
    border: 'border-[#FED7AA] dark:border-[#9A3412]',
  },
  UpgradePrompt: {
    bg: 'bg-[#FEF3C7] dark:bg-[#451A03]',
    text: 'text-[#B45309]',
    border: 'border-[#FDE68A] dark:border-[#92400E]',
  },
  DeceasedMemorial: {
    bg: 'bg-[#F5F5F4] dark:bg-[#292524]',
    text: 'text-[#57534E] dark:text-[#D6D3D1]',
    border: 'border-[#D6D3D1] dark:border-[#44403C]',
  },
  Matrimonial: {
    bg: 'bg-[#FFF1F2] dark:bg-[#4C0519]',
    text: 'text-[#E11D48]',
    border: 'border-[#FECDD3] dark:border-[#9F1239]',
  },
};

// ── Tone label extraction (first word of tone string) ──────────────
function getToneLabel(toneStr: string): string {
  const firstWord = toneStr.split(',')[0]?.trim();
  return firstWord ? firstWord.charAt(0).toUpperCase() + firstWord.slice(1) : 'Warm';
}

// ── Hook: useBrandVoice ────────────────────────────────────────────
export function useBrandVoice(context: string): {
  tone: string;
  toneLabel: string;
  example: string;
  toneSpec: ToneSpec | null;
} {
  return useMemo(() => {
    const toneContext = CONTEXT_TONE_MAP[context] ?? context;
    const { tone, example } = getTone(toneContext);
    const toneSpec = TONE_SPECTRUM.find((t) => t.context === toneContext) ?? null;
    return {
      tone,
      toneLabel: getToneLabel(tone),
      example,
      toneSpec,
    };
  }, [context]);
}

// ── Variable interpolation ─────────────────────────────────────────
function interpolateCopy(
  text: string,
  variables?: Record<string, string>,
): string {
  if (!variables) return text;
  return Object.entries(variables).reduce(
    (acc, [key, value]) => acc.replace(new RegExp(`\\{\\{${key}\\}\\}`, 'g'), value),
    text,
  );
}

// ── Get copy for a context ─────────────────────────────────────────
function getCopyForContext(context: string): Record<string, string> | null {
  const key = context as keyof typeof COPY_INVENTORY;
  return (COPY_INVENTORY[key] as Record<string, string>) ?? null;
}

// ── Props ──────────────────────────────────────────────────────────
export type BrandCopyProps = {
  context: string; // e.g., 'login', 'family_creation'
  variables?: Record<string, string>;
  showTone?: boolean;
  className?: string;
};

// ── Component: BrandCopy ───────────────────────────────────────────
export function BrandCopy({
  context,
  variables,
  showTone = true,
  className,
}: BrandCopyProps) {
  const prefersReducedMotion = useReducedMotion();
  const { tone, toneLabel, toneSpec } = useBrandVoice(context);
  const copy = useMemo(() => getCopyForContext(context), [context]);
  const toneContext = CONTEXT_TONE_MAP[context] ?? context;
  const colors = TONE_COLORS[toneContext] ?? TONE_COLORS.EmptyState;
  const Icon = CONTEXT_ICONS[context] ?? TreePine;

  const animatedProps = prefersReducedMotion
    ? {}
    : {
        initial: { opacity: 0, y: 8 },
        animate: { opacity: 1, y: 0 },
        transition: {
          duration: 0.4,
          ease: [0.0, 0.0, 0.2, 1] as [number, number, number, number],
        },
      };

  if (!copy) {
    return (
      <div className={cn('text-sm text-[#78716C] dark:text-[#A8A29E]', className)}>
        No copy found for context: {context}
      </div>
    );
  }

  return (
    <motion.div {...animatedProps} className={cn('w-full', className)}>
      <Card
        className={cn(
          'rounded-2xl border shadow-lg overflow-hidden',
          colors.border,
          'bg-white dark:bg-[#1C1917]',
        )}
      >
        <CardHeader className="pb-3">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <div
                className={cn(
                  'w-8 h-8 rounded-lg flex items-center justify-center',
                  colors.bg,
                )}
              >
                <Icon className={cn('w-4 h-4', colors.text)} />
              </div>
              <div>
                <CardTitle className="text-base font-bold text-[#1C1917] dark:text-[#F5F5F4]">
                  {interpolateCopy(copy.title ?? '', variables)}
                </CardTitle>
                {copy.subtitle && (
                  <CardDescription className="text-xs text-[#57534E] dark:text-[#A8A29E] mt-0.5">
                    {interpolateCopy(copy.subtitle ?? '', variables)}
                  </CardDescription>
                )}
              </div>
            </div>
            {showTone && (
              <Badge
                variant="outline"
                className={cn(
                  'text-[10px] font-semibold border',
                  colors.bg,
                  colors.text,
                  colors.border,
                )}
              >
                {toneLabel}
              </Badge>
            )}
          </div>
        </CardHeader>
        <CardContent className="pt-0 space-y-3">
          {/* Render the copy fields */}
          <div className="space-y-2">
            {Object.entries(copy)
              .filter(([key]) => !['title', 'subtitle'].includes(key))
              .map(([key, value]) => {
                const interpolated = interpolateCopy(value, variables);
                const isCta = key.toLowerCase().includes('cta') || key.toLowerCase().includes('action');
                const isPrice = key.toLowerCase().includes('price');
                const isFeature = key === 'features';
                const isTip = key.toLowerCase().includes('tip');
                const isGuarantee = key.toLowerCase().includes('guarantee');
                const isLabel = key.toLowerCase().includes('label');
                const isPlaceholder = key.toLowerCase().includes('placeholder');

                if (isFeature && Array.isArray(value)) {
                  return (
                    <div key={key} className="space-y-1.5">
                      <p className="text-[10px] font-semibold uppercase tracking-wider text-[#78716C] dark:text-[#A8A29E]">
                        Features
                      </p>
                      <ul className="space-y-1">
                        {(value as string[]).map((feature, i) => (
                          <li
                            key={i}
                            className="flex items-center gap-2 text-xs text-[#1C1917] dark:text-[#F5F5F4]"
                          >
                            <span className="w-4 h-4 rounded-full bg-[#F97316]/10 flex items-center justify-center shrink-0">
                              <span className="w-1.5 h-1.5 rounded-full bg-[#F97316]" />
                            </span>
                            {interpolateCopy(feature, variables)}
                          </li>
                        ))}
                      </ul>
                    </div>
                  );
                }

                if (isCta) {
                  return (
                    <Button
                      key={key}
                      className={cn(
                        'w-full bg-[#F97316] hover:bg-[#EA580C] text-white font-semibold',
                        'shadow-lg shadow-orange-200 dark:shadow-orange-900/30',
                      )}
                    >
                      {interpolated}
                    </Button>
                  );
                }

                if (isPrice) {
                  return (
                    <div
                      key={key}
                      className="flex items-center gap-2 p-2.5 rounded-xl bg-[#FFF7ED] dark:bg-[#431407] border border-[#FED7AA] dark:border-[#9A3412]"
                    >
                      <span className="text-sm font-bold text-[#F97316]">
                        {interpolated}
                      </span>
                      {key.includes('yearlySavings') && (
                        <Badge className="bg-[#22C55E] text-white border-0 text-[10px]">
                          Save
                        </Badge>
                      )}
                    </div>
                  );
                }

                if (isGuarantee || isTip) {
                  return (
                    <p
                      key={key}
                      className="text-[10px] text-[#78716C] dark:text-[#A8A29E] italic"
                    >
                      {interpolated}
                    </p>
                  );
                }

                if (isPlaceholder) {
                  return (
                    <div
                      key={key}
                      className="px-3 py-2 rounded-lg border border-dashed border-[#FED7AA] dark:border-[#44403C] text-xs text-[#78716C] dark:text-[#A8A29E] bg-[#FFFBFE] dark:bg-[#292524]"
                    >
                      {interpolated}
                    </div>
                  );
                }

                if (isLabel || key === 'relationOptions') {
                  if (key === 'relationOptions' && Array.isArray(value)) {
                    return (
                      <div key={key} className="flex flex-wrap gap-1.5">
                        {(value as string[]).map((opt, i) => (
                          <Badge
                            key={i}
                            variant="outline"
                            className="text-[10px] border-[#FED7AA] dark:border-[#44403C] text-[#1C1917] dark:text-[#F5F5F4]"
                          >
                            {opt}
                          </Badge>
                        ))}
                      </div>
                    );
                  }
                  return (
                    <p key={key} className="text-xs font-medium text-[#1C1917] dark:text-[#F5F5F4]">
                      {interpolated}
                    </p>
                  );
                }

                // Generic copy field
                return (
                  <p key={key} className="text-xs text-[#57534E] dark:text-[#A8A29E]">
                    {interpolated}
                  </p>
                );
              })}
          </div>

          {/* Tone context info */}
          {showTone && toneSpec && (
            <div
              className={cn(
                'mt-3 p-2.5 rounded-xl border',
                colors.bg,
                colors.border,
              )}
            >
              <p className="text-[10px] font-semibold uppercase tracking-wider text-[#78716C] dark:text-[#A8A29E] mb-1">
                Tone — {toneSpec.context}
              </p>
              <p className={cn('text-xs leading-relaxed', colors.text)}>
                {toneSpec.tone}
              </p>
            </div>
          )}
        </CardContent>
      </Card>
    </motion.div>
  );
}
