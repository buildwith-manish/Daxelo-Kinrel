'use client';

/**
 * DAXELO KINREL — Onboarding Flow
 *
 * Multi-step onboarding carousel that shows AFTER the BrandSplash completes:
 * - 3 carousel pages (from CAROUSEL_PAGES in onboarding-motion.ts)
 * - Each page: illustration area (SVG placeholder), title, description, pagination dots
 * - Swipe/click navigation between pages
 * - "Get Started" CTA on last page (Orange #F97316)
 * - Uses framer-motion for page transitions (slide left/right)
 * - Respects reduced motion preference
 *
 * Pack 12: Brand & Motion — Onboarding Flow
 */

import React, { useState, useCallback, useRef, useMemo } from 'react';
import { motion, AnimatePresence, type PanInfo } from 'framer-motion';
import { cn } from '@/lib/utils';
import { Button } from '@/components/ui/button';
import { CAROUSEL_PAGES, type CarouselPageSpec } from '@/lib/brand/onboarding-motion';
import { Illustration } from '@/components/kinrel/illustration';
import { useReducedMotion } from '@/hooks/use-accessibility';
import { ChevronLeft, ChevronRight, TreePine, Users, PartyPopper } from 'lucide-react';

// ── Props ──────────────────────────────────────────────────────────
export type OnboardingFlowProps = {
  onComplete: () => void;
  reducedMotion?: boolean;
};

// ── Page icons ─────────────────────────────────────────────────────
const PAGE_ICONS = [TreePine, Users, PartyPopper];

// ── SVG Placeholder Illustrations per page ─────────────────────────
function OnboardingIllustration({
  page,
  size,
}: {
  page: CarouselPageSpec;
  size: number;
}) {
  const iconIndex = page.index % 3;

  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 200 200"
      className="overflow-visible"
      aria-hidden="true"
    >
      <defs>
        <radialGradient id={`carousel-grad-${page.index}`} cx="50%" cy="45%" r="55%">
          <stop offset="0%" stopColor="#FFF7ED" stopOpacity="0.9" />
          <stop offset="100%" stopColor="#FEF3C7" stopOpacity="0.5" />
        </radialGradient>
      </defs>

      {/* Background circle */}
      <circle cx="100" cy="95" r="85" fill={`url(#carousel-grad-${page.index})`} />

      {/* Page-specific illustration */}
      {iconIndex === 0 && (
        /* Build Tree — tree growing */
        <>
          <rect x="93" y="115" width="14" height="55" rx="4" fill="#92400E" opacity="0.8" />
          <line x1="100" y1="120" x2="60" y2="90" stroke="#92400E" strokeWidth="4" strokeLinecap="round" />
          <line x1="100" y1="110" x2="140" y2="85" stroke="#92400E" strokeWidth="4" strokeLinecap="round" />
          <line x1="100" y1="130" x2="50" y2="108" stroke="#92400E" strokeWidth="3" strokeLinecap="round" />
          <ellipse cx="100" cy="70" rx="50" ry="42" fill="#22C55E" opacity="0.8" />
          <ellipse cx="80" cy="60" rx="28" ry="23" fill="#4ADE80" opacity="0.7" />
          <ellipse cx="120" cy="65" rx="24" ry="20" fill="#16A34A" opacity="0.6" />
          <ellipse cx="100" cy="50" rx="18" ry="16" fill="#86EFAC" opacity="0.5" />
          {/* Growing seed */}
          <circle cx="100" cy="175" r="5" fill="#F97316" opacity="0.6" />
          <circle cx="85" cy="178" r="3" fill="#FB923C" opacity="0.5" />
          <circle cx="115" cy="178" r="3" fill="#FB923C" opacity="0.5" />
        </>
      )}

      {iconIndex === 1 && (
        /* Invite Family — people connected */
        <>
          {/* Center person */}
          <circle cx="100" cy="65" r="16" fill="#F97316" opacity="0.7" />
          <rect x="88" y="85" width="24" height="30" rx="6" fill="#FB923C" opacity="0.6" />
          {/* Left person */}
          <circle cx="55" cy="75" r="13" fill="#14B8A6" opacity="0.7" />
          <rect x="45" y="92" width="20" height="25" rx="5" fill="#2DD4BF" opacity="0.5" />
          {/* Right person */}
          <circle cx="145" cy="75" r="13" fill="#8B5CF6" opacity="0.7" />
          <rect x="135" y="92" width="20" height="25" rx="5" fill="#A78BFA" opacity="0.5" />
          {/* Connection lines */}
          <line x1="80" y1="78" x2="68" y2="80" stroke="#F97316" strokeWidth="2" strokeDasharray="4 3" opacity="0.5" />
          <line x1="120" y1="78" x2="132" y2="80" stroke="#F97316" strokeWidth="2" strokeDasharray="4 3" opacity="0.5" />
          {/* Speech bubbles */}
          <rect x="35" y="45" width="28" height="16" rx="6" fill="#FEF3C7" opacity="0.7" />
          <rect x="137" y="45" width="28" height="16" rx="6" fill="#FEF3C7" opacity="0.7" />
          <text x="49" y="56" fontSize="7" textAnchor="middle" fill="#D97706" opacity="0.8">हिंदी</text>
          <text x="151" y="56" fontSize="7" textAnchor="middle" fill="#D97706" opacity="0.8">தமிழ்</text>
          {/* Bottom connections */}
          <circle cx="75" cy="140" r="10" fill="#E94560" opacity="0.4" />
          <circle cx="125" cy="140" r="10" fill="#22C55E" opacity="0.4" />
          <line x1="100" y1="115" x2="75" y2="130" stroke="#F97316" strokeWidth="1.5" strokeDasharray="3 3" opacity="0.3" />
          <line x1="100" y1="115" x2="125" y2="130" stroke="#F97316" strokeWidth="1.5" strokeDasharray="3 3" opacity="0.3" />
        </>
      )}

      {iconIndex === 2 && (
        /* Celebrate Together — festive scene */
        <>
          {/* Cake / celebration */}
          <rect x="75" y="100" width="50" height="40" rx="6" fill="#FFD700" opacity="0.5" />
          <rect x="80" y="90" width="40" height="15" rx="4" fill="#F97316" opacity="0.5" />
          {/* Candles */}
          <rect x="88" y="75" width="3" height="18" rx="1" fill="#EA580C" opacity="0.7" />
          <rect x="98" y="70" width="3" height="23" rx="1" fill="#EA580C" opacity="0.7" />
          <rect x="108" y="75" width="3" height="18" rx="1" fill="#EA580C" opacity="0.7" />
          {/* Flames */}
          <circle cx="89" cy="72" r="3" fill="#FFD700" opacity="0.8" />
          <circle cx="99" cy="67" r="3" fill="#FFD700" opacity="0.8" />
          <circle cx="109" cy="72" r="3" fill="#FFD700" opacity="0.8" />
          {/* Confetti / sparkles */}
          <circle cx="55" cy="50" r="4" fill="#E94560" opacity="0.6" />
          <circle cx="145" cy="55" r="3" fill="#14B8A6" opacity="0.6" />
          <circle cx="70" cy="40" r="3" fill="#F97316" opacity="0.5" />
          <circle cx="130" cy="42" r="4" fill="#8B5CF6" opacity="0.5" />
          <path d="M50 80 L53 73 L56 80 L53 87 Z" fill="#FFD700" opacity="0.5" />
          <path d="M148 75 L151 68 L154 75 L151 82 Z" fill="#22C55E" opacity="0.5" />
          {/* People silhouettes at bottom */}
          <circle cx="70" cy="155" r="8" fill="#F97316" opacity="0.3" />
          <circle cx="100" cy="155" r="8" fill="#14B8A6" opacity="0.3" />
          <circle cx="130" cy="155" r="8" fill="#8B5CF6" opacity="0.3" />
          {/* Diya lamps */}
          <ellipse cx="60" cy="170" rx="6" ry="3" fill="#FFD700" opacity="0.4" />
          <ellipse cx="100" cy="172" rx="6" ry="3" fill="#FFD700" opacity="0.4" />
          <ellipse cx="140" cy="170" rx="6" ry="3" fill="#FFD700" opacity="0.4" />
        </>
      )}
    </svg>
  );
}

// ── Component ──────────────────────────────────────────────────────
export function OnboardingFlow({ onComplete, reducedMotion = false }: OnboardingFlowProps) {
  const prefersReducedMotion = useReducedMotion();
  const isReduced = reducedMotion || prefersReducedMotion;
  const [currentPage, setCurrentPage] = useState(0);
  const [direction, setDirection] = useState<number>(0); // 1 = forward, -1 = backward
  const containerRef = useRef<HTMLDivElement>(null);

  const totalPages = CAROUSEL_PAGES.length;
  const isLastPage = currentPage === totalPages - 1;

  // ── Navigation ───────────────────────────────────────────────────
  const goToPage = useCallback(
    (page: number) => {
      if (page < 0 || page >= totalPages) return;
      setDirection(page > currentPage ? 1 : -1);
      setCurrentPage(page);
    },
    [currentPage, totalPages],
  );

  const goNext = useCallback(() => {
    if (isLastPage) {
      onComplete();
    } else {
      goToPage(currentPage + 1);
    }
  }, [currentPage, isLastPage, goToPage, onComplete]);

  const goPrev = useCallback(() => {
    goToPage(currentPage - 1);
  }, [currentPage, goToPage]);

  // ── Swipe handler ────────────────────────────────────────────────
  const handleDragEnd = useCallback(
    (_event: MouseEvent | TouchEvent | PointerEvent, info: PanInfo) => {
      const threshold = 50;
      if (info.offset.x < -threshold) {
        goNext();
      } else if (info.offset.x > threshold) {
        goPrev();
      }
    },
    [goNext, goPrev],
  );

  // ── Animation variants ───────────────────────────────────────────
  const pageVariants = useMemo(() => {
    if (isReduced) {
      return {
        enter: { opacity: 0 },
        center: { opacity: 1 },
        exit: { opacity: 0 },
      };
    }

    const currentSpec = CAROUSEL_PAGES[currentPage];
    const enterX = currentSpec?.transition.enter.x ?? 60;
    const exitX = currentSpec?.transition.exit.x ?? -60;
    const enterDuration = (currentSpec?.transition.enter.durationMs ?? 350) / 1000;
    const exitDuration = (currentSpec?.transition.exit.durationMs ?? 250) / 1000;

    return {
      enter: (dir: number) => ({
        x: dir >= 0 ? enterX : -enterX,
        opacity: 0,
      }),
      center: {
        x: 0,
        opacity: 1,
      },
      exit: (dir: number) => ({
        x: dir >= 0 ? exitX : -exitX,
        opacity: 0,
      }),
    };
  }, [isReduced, currentPage]);

  const pageTransition = useMemo(() => {
    if (isReduced) return { duration: 0 };
    const currentSpec = CAROUSEL_PAGES[currentPage];
    return {
      x: {
        duration: (currentSpec?.transition.enter.durationMs ?? 350) / 1000,
        ease: [0.0, 0.0, 0.2, 1] as [number, number, number, number],
      },
      opacity: {
        duration: (currentSpec?.transition.exit.durationMs ?? 250) / 1000,
        ease: [0.4, 0.0, 1, 1] as [number, number, number, number],
      },
    };
  }, [isReduced, currentPage]);

  const currentPageSpec = CAROUSEL_PAGES[currentPage];

  return (
    <div
      ref={containerRef}
      className="relative flex flex-col items-center justify-center min-h-[70vh] w-full max-w-md mx-auto px-4 select-none"
      role="region"
      aria-label="Onboarding carousel"
      aria-roledescription="carousel"
    >
      {/* ── Carousel content ──────────────────────────────────────── */}
      <div className="relative w-full overflow-hidden rounded-3xl">
        <AnimatePresence initial={false} custom={direction} mode="wait">
          <motion.div
            key={currentPage}
            custom={direction}
            variants={pageVariants}
            initial="enter"
            animate="center"
            exit="exit"
            transition={pageTransition}
            drag={isReduced ? false : 'x'}
            dragConstraints={{ left: 0, right: 0 }}
            dragElastic={0.15}
            onDragEnd={handleDragEnd}
            className="w-full touch-pan-y"
          >
            <div className="flex flex-col items-center py-8 px-4 bg-gradient-to-b from-[#FFFBFE] to-[#FFF7ED] dark:from-[#1C1917] dark:to-[#292524] rounded-3xl border border-[#FED7AA] dark:border-[#44403C] shadow-xl">
              {/* Illustration area */}
              <div className="mb-6">
                <OnboardingIllustration page={currentPageSpec} size={180} />
              </div>

              {/* Title */}
              <h2 className="text-2xl sm:text-3xl font-extrabold text-[#1C1917] dark:text-[#F5F5F4] text-center mb-2">
                {currentPageSpec.title}
              </h2>

              {/* Subtitle / Description */}
              <p className="text-sm sm:text-base text-[#57534E] dark:text-[#A8A29E] text-center max-w-xs leading-relaxed">
                {currentPageSpec.subtitle}
              </p>

              {/* CTA on last page */}
              {isLastPage && (
                <motion.div
                  initial={isReduced ? { opacity: 1 } : { opacity: 0, scale: 0.9 }}
                  animate={{ opacity: 1, scale: 1 }}
                  transition={{ delay: 0.3, duration: 0.4, ease: [0.0, 0.0, 0.2, 1] as [number, number, number, number] }}
                  className="mt-8 w-full max-w-xs"
                >
                  <Button
                    onClick={onComplete}
                    className={cn(
                      'w-full py-4 text-base font-bold',
                      'bg-[#F97316] hover:bg-[#EA580C] text-white',
                      'shadow-xl shadow-orange-200 dark:shadow-orange-900/30',
                      'rounded-2xl',
                      'transition-transform active:scale-[0.97]',
                    )}
                    size="lg"
                  >
                    Get Started
                  </Button>
                </motion.div>
              )}
            </div>
          </motion.div>
        </AnimatePresence>
      </div>

      {/* ── Pagination dots + navigation ──────────────────────────── */}
      <div className="flex items-center gap-4 mt-8">
        {/* Previous button */}
        <button
          onClick={goPrev}
          disabled={currentPage === 0}
          className={cn(
            'w-10 h-10 rounded-xl flex items-center justify-center transition-all duration-200',
            'border border-[#FED7AA] dark:border-[#44403C]',
            currentPage === 0
              ? 'opacity-30 cursor-not-allowed bg-[#FFFBFE] dark:bg-[#1C1917]'
              : 'bg-white dark:bg-[#292524] hover:bg-[#FFF7ED] dark:hover:bg-[#431407] shadow-sm cursor-pointer',
          )}
          aria-label="Previous page"
        >
          <ChevronLeft className="w-5 h-5 text-[#F97316]" />
        </button>

        {/* Dots */}
        <div className="flex items-center gap-2" role="tablist" aria-label="Carousel pages">
          {CAROUSEL_PAGES.map((page, i) => {
            const Icon = PAGE_ICONS[i] ?? TreePine;
            const isActive = i === currentPage;
            return (
              <button
                key={page.index}
                onClick={() => goToPage(i)}
                role="tab"
                aria-selected={isActive}
                aria-label={`Page ${i + 1}: ${page.title}`}
                className={cn(
                  'transition-all duration-300 rounded-full flex items-center justify-center',
                  isActive
                    ? 'w-10 h-3 bg-[#F97316] shadow-md shadow-orange-200 dark:shadow-orange-900/30'
                    : 'w-3 h-3 bg-[#FED7AA] dark:bg-[#44403C] hover:bg-[#FB923C] hover:dark:bg-[#9A3412]',
                )}
              />
            );
          })}
        </div>

        {/* Next button */}
        <button
          onClick={goNext}
          className={cn(
            'w-10 h-10 rounded-xl flex items-center justify-center transition-all duration-200',
            'border border-[#FED7AA] dark:border-[#44403C]',
            'bg-white dark:bg-[#292524] hover:bg-[#FFF7ED] dark:hover:bg-[#431407]',
            'shadow-sm cursor-pointer',
          )}
          aria-label={isLastPage ? 'Get Started' : 'Next page'}
        >
          {isLastPage ? (
            <PartyPopper className="w-5 h-5 text-[#F97316]" />
          ) : (
            <ChevronRight className="w-5 h-5 text-[#F97316]" />
          )}
        </button>
      </div>

      {/* ── Skip button ───────────────────────────────────────────── */}
      <button
        onClick={onComplete}
        className="mt-4 text-xs font-medium text-[#78716C] dark:text-[#A8A29E] hover:text-[#F97316] transition-colors underline underline-offset-2"
      >
        Skip for now
      </button>
    </div>
  );
}
