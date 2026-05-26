'use client';

/**
 * DAXELO KINREL — Animated Card Components
 *
 * Framer Motion-powered cards with tap, long-press, elevation,
 * and swipe-to-reveal interactions following KINREL specs.
 *
 * Pack 12: Brand & Motion — Animated Cards
 */

import React, { forwardRef, useState, useCallback } from 'react';
import { motion, type HTMLMotionProps, useMotionValue, useTransform, AnimatePresence } from 'framer-motion';
import { cn } from '@/lib/utils';
import { getCardInteraction, CardInteractions } from '@/lib/brand/micro-interactions';

// ── AnimatedPersonCard ─────────────────────────────────────────────
export interface AnimatedPersonCardProps extends Omit<HTMLMotionProps<'div'>, 'onSelect'> {
  name: string;
  relation?: string;
  avatar?: React.ReactNode;
  selected?: boolean;
  onSelect?: () => void;
  onLongPress?: () => void;
  metadata?: string;
}

const personCardVariant = getCardInteraction('personCard');
const personSpec = CardInteractions.personCard;

export const AnimatedPersonCard = forwardRef<HTMLDivElement, AnimatedPersonCardProps>(
  ({ name, relation, avatar, selected = false, onSelect, onLongPress, metadata, className, children, ...props }, ref) => {
    const [isLongPressed, setIsLongPressed] = useState(false);
    const longPressTimer = React.useRef<ReturnType<typeof setTimeout> | null>(null);

    const handlePointerDown = useCallback(() => {
      longPressTimer.current = setTimeout(() => {
        setIsLongPressed(true);
        onLongPress?.();
        // Reset after showing selection state
        setTimeout(() => setIsLongPressed(false), 600);
      }, personSpec.longPress.duration);
    }, [onLongPress]);

    const handlePointerUp = useCallback(() => {
      if (longPressTimer.current) {
        clearTimeout(longPressTimer.current);
        longPressTimer.current = null;
      }
    }, []);

    const handleClick = useCallback(() => {
      if (!isLongPressed) {
        onSelect?.();
      }
    }, [isLongPressed, onSelect]);

    return (
      <motion.div
        ref={ref}
        variants={personCardVariant}
        whileTap="tap"
        initial="initial"
        animate={isLongPressed ? 'longPress' : 'animate'}
        whileHover="hover"
        onClick={handleClick}
        onPointerDown={handlePointerDown}
        onPointerUp={handlePointerUp}
        onPointerLeave={handlePointerUp}
        className={cn(
          'relative flex items-center gap-3 rounded-2xl border p-4 cursor-pointer',
          'bg-white border-[#D6D3D1] shadow-sm',
          'dark:bg-[#292524] dark:border-[#44403C]',
          selected && 'ring-2 ring-[#F97316] ring-offset-2',
          isLongPressed && 'ring-2 ring-[#F97316]',
          className,
        )}
        {...props}
      >
        {avatar ? (
          <div className="flex-shrink-0">{avatar}</div>
        ) : (
          <div className="flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-full bg-[#FED7AA] text-[#F97316] font-semibold text-sm">
            {name.charAt(0).toUpperCase()}
          </div>
        )}
        <div className="flex flex-col gap-0.5 min-w-0">
          <span className="text-sm font-semibold text-[#1C1917] dark:text-[#F5F5F4] truncate">{name}</span>
          {relation && (
            <span className="text-xs text-[#57534E] dark:text-[#D6D3D1] truncate">{relation}</span>
          )}
          {metadata && (
            <span className="text-xs text-[#A8A29E] dark:text-[#78716C] truncate">{metadata}</span>
          )}
        </div>
        {children as React.ReactNode}
        <AnimatePresence>
          {isLongPressed && (
            <motion.div
              initial={{ scale: 0, opacity: 0 }}
              animate={{ scale: 1, opacity: 1 }}
              exit={{ scale: 0, opacity: 0 }}
              className="absolute -top-2 -right-2 flex h-6 w-6 items-center justify-center rounded-full bg-[#F97316] text-white"
            >
              <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round">
                <polyline points="20 6 9 17 4 12" />
              </svg>
            </motion.div>
          )}
        </AnimatePresence>
      </motion.div>
    );
  },
);
AnimatedPersonCard.displayName = 'AnimatedPersonCard';

// ── AnimatedFamilyCard ─────────────────────────────────────────────
export interface AnimatedFamilyCardProps extends Omit<HTMLMotionProps<'div'>, 'onSwipe'> {
  title: string;
  subtitle?: string;
  memberCount?: number;
  onShare?: () => void;
  onEdit?: () => void;
  onDelete?: () => void;
  onArchive?: () => void;
}

const familySpec = CardInteractions.familyCard;

export const AnimatedFamilyCard = forwardRef<HTMLDivElement, AnimatedFamilyCardProps>(
  ({ title, subtitle, memberCount, onShare, onEdit, onDelete, onArchive, className, children, ...props }, ref) => {
    const x = useMotionValue(0);
    const [swipeDirection, setSwipeDirection] = useState<'left' | 'right' | null>(null);

    const rightActionOpacity = useTransform(x, [0, familySpec.swipe.threshold], [0, 1]);
    const leftActionOpacity = useTransform(x, [-familySpec.swipe.threshold, 0], [1, 0]);

    const handleDragEnd = useCallback(
      (_: unknown, info: { offset: { x: number }; velocity: { x: number } }) => {
        const threshold = familySpec.swipe.threshold;
        const velocity = Math.abs(info.velocity.x);
        const meetsVelocity = velocity > familySpec.swipe.velocity;

        if (info.offset.x > threshold || (meetsVelocity && info.offset.x > 0)) {
          setSwipeDirection('right');
        } else if (info.offset.x < -threshold || (meetsVelocity && info.offset.x < 0)) {
          setSwipeDirection('left');
        } else {
          setSwipeDirection(null);
        }
      },
      [],
    );

    const handleDismiss = useCallback(() => {
      setSwipeDirection(null);
    }, []);

    return (
      <div className="relative overflow-hidden rounded-2xl">
        {/* Right swipe background — Share / Edit */}
        <motion.div
          style={{ opacity: rightActionOpacity }}
          className="absolute inset-y-0 left-0 flex items-center justify-start gap-2 pl-4 z-0"
        >
          <button
            onClick={() => { onShare?.(); handleDismiss(); }}
            className="flex h-10 w-10 items-center justify-center rounded-full bg-[#14B8A6] text-white"
            aria-label="Share"
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <circle cx="18" cy="5" r="3" /><circle cx="6" cy="12" r="3" /><circle cx="18" cy="19" r="3" /><line x1="8.59" y1="13.51" x2="15.42" y2="17.49" /><line x1="15.41" y1="6.51" x2="8.59" y2="10.49" />
            </svg>
          </button>
          <button
            onClick={() => { onEdit?.(); handleDismiss(); }}
            className="flex h-10 w-10 items-center justify-center rounded-full bg-[#F97316] text-white"
            aria-label="Edit"
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7" /><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z" />
            </svg>
          </button>
        </motion.div>

        {/* Left swipe background — Delete / Archive */}
        <motion.div
          style={{ opacity: leftActionOpacity }}
          className="absolute inset-y-0 right-0 flex items-center justify-end gap-2 pr-4 z-0"
        >
          <button
            onClick={() => { onArchive?.(); handleDismiss(); }}
            className="flex h-10 w-10 items-center justify-center rounded-full bg-[#F59E0B] text-white"
            aria-label="Archive"
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <polyline points="21 8 21 21 3 21 3 8" /><rect x="1" y="3" width="22" height="5" /><line x1="10" y1="12" x2="14" y2="12" />
            </svg>
          </button>
          <button
            onClick={() => { onDelete?.(); handleDismiss(); }}
            className="flex h-10 w-10 items-center justify-center rounded-full bg-[#EF4444] text-white"
            aria-label="Delete"
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <polyline points="3 6 5 6 21 6" /><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2" />
            </svg>
          </button>
        </motion.div>

        {/* Main card */}
        <motion.div
          ref={ref}
          drag="x"
          dragConstraints={{ left: 0, right: 0 }}
          dragElastic={0.2}
          style={{ x }}
          onDragEnd={handleDragEnd}
          className={cn(
            'relative z-10 flex flex-col gap-2 rounded-2xl border p-4 cursor-pointer',
            'bg-white border-[#D6D3D1] shadow-sm',
            'dark:bg-[#292524] dark:border-[#44403C]',
            className,
          )}
          {...(props as Record<string, unknown>)}
        >
          <div className="flex items-center justify-between">
            <h3 className="text-sm font-semibold text-[#1C1917] dark:text-[#F5F5F4]">{title}</h3>
            {memberCount !== undefined && (
              <span className="text-xs bg-[#FFF7ED] text-[#F97316] px-2 py-0.5 rounded-full font-medium dark:bg-[#431407]">
                {memberCount} members
              </span>
            )}
          </div>
          {subtitle && (
            <p className="text-xs text-[#57534E] dark:text-[#D6D3D1] line-clamp-2">{subtitle}</p>
          )}
          {children as React.ReactNode}
          <p className="text-[10px] text-[#A8A29E] dark:text-[#78716C] mt-1">
            ← Swipe for actions →
          </p>
        </motion.div>
      </div>
    );
  },
);
AnimatedFamilyCard.displayName = 'AnimatedFamilyCard';
