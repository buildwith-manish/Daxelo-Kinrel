'use client';

/**
 * DAXELO KINREL — Brand Splash Screen
 *
 * 2.5s animated splash sequence with Banyan tree concept.
 * Root nodes → trunk → branches → canopy → wordmark → pulse → fade.
 * Respects reduced motion preference.
 *
 * Pack 12: Brand & Motion — Brand Splash
 */

import React, { forwardRef, useEffect, useState, useCallback } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { cn } from '@/lib/utils';
import { SPLASH_SEQUENCE, SPLASH_TOTAL_DURATION_MS } from '@/lib/brand/onboarding-motion';

export interface BrandSplashProps {
  onComplete?: () => void;
  durationMs?: number;
  reducedMotion?: boolean;
  className?: string;
}

export const BrandSplash = forwardRef<HTMLDivElement, BrandSplashProps>(
  ({ onComplete, durationMs = SPLASH_TOTAL_DURATION_MS, reducedMotion = false, className }, ref) => {
    const [phase, setPhase] = useState<
      'root-nodes' | 'trunk' | 'branches' | 'canopy' | 'wordmark' | 'pulse' | 'fade'
    >('root-nodes');
    const [visible, setVisible] = useState(true);

    const phases = SPLASH_SEQUENCE.map((s) => s.id) as Array<typeof phase>;

    useEffect(() => {
      if (reducedMotion) {
        // Skip to wordmark instantly
        setPhase('wordmark');
        const timer = setTimeout(() => {
          setVisible(false);
          onComplete?.();
        }, 800);
        return () => clearTimeout(timer);
      }

      let elapsed = 0;
      const timers: ReturnType<typeof setTimeout>[] = [];

      for (let i = 0; i < SPLASH_SEQUENCE.length; i++) {
        const step = SPLASH_SEQUENCE[i];
        elapsed += step.durationMs + step.delayAfterMs;

        const timer = setTimeout(() => {
          if (i < SPLASH_SEQUENCE.length - 1) {
            setPhase(phases[i + 1] as typeof phase);
          }
          if (step.id === 'fade') {
            setVisible(false);
            setTimeout(() => onComplete?.(), 300);
          }
        }, elapsed);

        timers.push(timer);
      }

      // Safety fallback
      const fallback = setTimeout(() => {
        setVisible(false);
        onComplete?.();
      }, durationMs + 500);
      timers.push(fallback);

      return () => timers.forEach(clearTimeout);
    }, [reducedMotion, durationMs, onComplete, phases]);

    const getPhaseIndex = useCallback((p: typeof phase) => phases.indexOf(p), [phases]);
    const currentIndex = getPhaseIndex(phase);

    return (
      <AnimatePresence>
        {visible && (
          <motion.div
            ref={ref}
            className={cn(
              'fixed inset-0 z-[100] flex flex-col items-center justify-center',
              'bg-gradient-to-b from-[#FFFBFE] to-[#FFF7ED]',
              'dark:from-[#1C1917] dark:to-[#292524]',
              className,
            )}
            animate={phase === 'fade' ? { opacity: 0 } : { opacity: 1 }}
            transition={{ duration: 0.3 }}
          >
            {/* Tree SVG */}
            <div className="relative flex flex-col items-center">
              <svg width="200" height="200" viewBox="0 0 200 200" className="overflow-visible">
                {/* Root nodes */}
                <motion.g
                  initial={{ opacity: 0, scale: 0 }}
                  animate={currentIndex >= 0 ? { opacity: 1, scale: 1 } : {}}
                  transition={{ duration: 0.3, ease: [0.34, 1.56, 0.64, 1] as [number, number, number, number] }}
                >
                  <circle cx="85" cy="195" r="4" fill="#F97316" />
                  <circle cx="100" cy="198" r="3" fill="#FB923C" />
                  <circle cx="115" cy="195" r="4" fill="#F97316" />
                </motion.g>

                {/* Trunk */}
                <motion.rect
                  x="95"
                  y="110"
                  width="10"
                  height="80"
                  rx="3"
                  fill="#92400E"
                  initial={{ scaleY: 0, originY: 1 }}
                  animate={currentIndex >= 1 ? { scaleY: 1, originY: 1 } : {}}
                  transition={{ duration: 0.4, ease: [0, 0, 0.2, 1] as [number, number, number, number] }}
                />

                {/* Branches */}
                <motion.g
                  initial={{ scaleX: 0, opacity: 0 }}
                  animate={currentIndex >= 2 ? { scaleX: 1, opacity: 1 } : {}}
                  transition={{ duration: 0.4, ease: [0, 0, 0.2, 1] as [number, number, number, number] }}
                  style={{ transformOrigin: '100px 110px' }}
                >
                  <line x1="100" y1="120" x2="55" y2="85" stroke="#92400E" strokeWidth="4" strokeLinecap="round" />
                  <line x1="100" y1="110" x2="145" y2="80" stroke="#92400E" strokeWidth="4" strokeLinecap="round" />
                  <line x1="100" y1="125" x2="40" y2="100" stroke="#92400E" strokeWidth="3" strokeLinecap="round" />
                  <line x1="100" y1="115" x2="160" y2="95" stroke="#92400E" strokeWidth="3" strokeLinecap="round" />
                </motion.g>

                {/* Canopy */}
                <motion.g
                  initial={{ scale: 0.8, opacity: 0 }}
                  animate={currentIndex >= 3 ? {
                    scale: currentIndex >= 5 ? [1, 1.03, 1] : 1,
                    opacity: 1,
                  } : {}}
                  transition={
                    currentIndex >= 5
                      ? { duration: 0.6, ease: [0.25, 0.1, 0.25, 1] as [number, number, number, number] }
                      : { duration: 0.5, ease: [0.34, 1.56, 0.64, 1] as [number, number, number, number] }
                  }
                  style={{ transformOrigin: '100px 70px' }}
                >
                  <ellipse cx="100" cy="65" rx="55" ry="45" fill="#22C55E" opacity="0.9" />
                  <ellipse cx="80" cy="55" rx="30" ry="25" fill="#4ADE80" opacity="0.8" />
                  <ellipse cx="120" cy="60" rx="25" ry="22" fill="#16A34A" opacity="0.7" />
                  <ellipse cx="100" cy="45" rx="20" ry="18" fill="#86EFAC" opacity="0.6" />
                </motion.g>
              </svg>

              {/* Wordmark */}
              <motion.div
                initial={{ opacity: 0, y: 10 }}
                animate={currentIndex >= 4 ? { opacity: 1, y: 0 } : {}}
                transition={{ duration: 0.4, ease: [0, 0, 0.2, 1] as [number, number, number, number] }}
                className="mt-4 flex flex-col items-center"
              >
                <h1 className="text-3xl font-extrabold tracking-tight">
                  <span className="text-[#F97316]">KIN</span>
                  <span className="text-[#1C1917] dark:text-[#F5F5F4]">REL</span>
                </h1>
                <p className="mt-1 text-xs text-[#57534E] dark:text-[#A8A29E] font-medium tracking-wider">
                  YOUR FAMILY&apos;S LIVING ARCHIVE
                </p>
              </motion.div>
            </div>

            {/* Decorative dots pattern */}
            <div className="absolute bottom-8 left-0 right-0 flex justify-center gap-1.5">
              {[0, 1, 2].map((i) => (
                <motion.div
                  key={i}
                  className="h-1.5 w-1.5 rounded-full bg-[#F97316] opacity-40"
                  animate={{ scale: [1, 1.5, 1], opacity: [0.4, 0.8, 0.4] }}
                  transition={{
                    duration: 1.2,
                    repeat: Infinity,
                    delay: i * 0.2,
                    ease: 'easeInOut' as const,
                  }}
                />
              ))}
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    );
  },
);
BrandSplash.displayName = 'BrandSplash';
