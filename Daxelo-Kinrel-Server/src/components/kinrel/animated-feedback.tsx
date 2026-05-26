'use client';

/**
 * DAXELO KINREL — Animated Feedback Components
 *
 * Framer Motion-powered feedback animations for success, error,
 * delete, and achievement states following KINREL specs.
 *
 * Pack 12: Brand & Motion — Animated Feedback
 */

import React, { forwardRef, useEffect, useState } from 'react';
import { motion, AnimatePresence, type HTMLMotionProps } from 'framer-motion';
import { cn } from '@/lib/utils';
import { getFeedbackAnimation } from '@/lib/brand/micro-interactions';

// ── SuccessFeedback ────────────────────────────────────────────────
export interface SuccessFeedbackProps extends Omit<HTMLMotionProps<'div'>, 'onAnimationComplete'> {
  message: string;
  visible: boolean;
  onDismiss?: () => void;
  autoDismissMs?: number;
}

export const SuccessFeedback = forwardRef<HTMLDivElement, SuccessFeedbackProps>(
  ({ message, visible, onDismiss, autoDismissMs = 2500, className, ...props }, ref) => {
    const variants = getFeedbackAnimation('saveSuccess');

    useEffect(() => {
      if (visible && autoDismissMs > 0) {
        const timer = setTimeout(() => {
          onDismiss?.();
        }, autoDismissMs);
        return () => clearTimeout(timer);
      }
    }, [visible, autoDismissMs, onDismiss]);

    return (
      <AnimatePresence>
        {visible && (
          <motion.div
            ref={ref}
            variants={variants}
            initial="hidden"
            animate="visible"
            exit="exit"
            className={cn(
              'fixed bottom-6 left-1/2 z-50 -translate-x-1/2',
              'flex items-center gap-2 rounded-xl px-4 py-3 shadow-lg',
              'bg-[#22C55E] text-white',
              className,
            )}
            {...props}
          >
            <motion.svg
              width="20"
              height="20"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="3"
              strokeLinecap="round"
              strokeLinejoin="round"
              initial={{ pathLength: 0 }}
              animate={{ pathLength: 1 }}
              transition={{ duration: 0.3, ease: [0.34, 1.56, 0.64, 1] }}
            >
              <motion.path
                d="M20 6L9 17l-5-5"
                initial={{ pathLength: 0 }}
                animate={{ pathLength: 1 }}
                transition={{ duration: 0.3, ease: [0.34, 1.56, 0.64, 1] }}
              />
            </motion.svg>
            <span className="text-sm font-medium">{message}</span>
          </motion.div>
        )}
      </AnimatePresence>
    );
  },
);
SuccessFeedback.displayName = 'SuccessFeedback';

// ── ErrorFeedback ──────────────────────────────────────────────────
export interface ErrorFeedbackProps extends Omit<HTMLMotionProps<'div'>, 'onAnimationComplete'> {
  message: string;
  visible: boolean;
  onDismiss?: () => void;
  autoDismissMs?: number;
  actionLabel?: string;
  onAction?: () => void;
}

export const ErrorFeedback = forwardRef<HTMLDivElement, ErrorFeedbackProps>(
  ({ message, visible, onDismiss, autoDismissMs = 4000, actionLabel, onAction, className, ...props }, ref) => {
    const variants = getFeedbackAnimation('errorBanner');

    useEffect(() => {
      if (visible && autoDismissMs > 0) {
        const timer = setTimeout(() => {
          onDismiss?.();
        }, autoDismissMs);
        return () => clearTimeout(timer);
      }
    }, [visible, autoDismissMs, onDismiss]);

    return (
      <AnimatePresence>
        {visible && (
          <motion.div
            ref={ref}
            variants={variants}
            initial="hidden"
            animate="visible"
            exit="exit"
            className={cn(
              'fixed top-0 left-0 right-0 z-50',
              'flex items-center justify-between gap-3 px-4 py-3 shadow-md',
              'bg-[#EF4444] text-white',
              className,
            )}
            {...props}
          >
            <div className="flex items-center gap-2">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <circle cx="12" cy="12" r="10" />
                <line x1="15" y1="9" x2="9" y2="15" />
                <line x1="9" y1="9" x2="15" y2="15" />
              </svg>
              <span className="text-sm font-medium">{message}</span>
            </div>
            <div className="flex items-center gap-2">
              {actionLabel && onAction && (
                <button
                  onClick={onAction}
                  className="text-sm font-semibold underline underline-offset-2 hover:no-underline"
                >
                  {actionLabel}
                </button>
              )}
              <button
                onClick={onDismiss}
                className="flex h-6 w-6 items-center justify-center rounded-full hover:bg-white/20 transition-colors"
                aria-label="Dismiss"
              >
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                  <line x1="18" y1="6" x2="6" y2="18" /><line x1="6" y1="6" x2="18" y2="18" />
                </svg>
              </button>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    );
  },
);
ErrorFeedback.displayName = 'ErrorFeedback';

// ── DeleteFeedback ─────────────────────────────────────────────────
export interface DeleteFeedbackProps extends Omit<HTMLMotionProps<'div'>, 'onAnimationComplete'> {
  message: string;
  visible: boolean;
  onUndo?: () => void;
  onDismiss?: () => void;
  autoDismissMs?: number;
}

export const DeleteFeedback = forwardRef<HTMLDivElement, DeleteFeedbackProps>(
  ({ message, visible, onUndo, onDismiss, autoDismissMs = 5000, className, ...props }, ref) => {
    const undoVariants = getFeedbackAnimation('undo');

    useEffect(() => {
      if (visible && autoDismissMs > 0) {
        const timer = setTimeout(() => {
          onDismiss?.();
        }, autoDismissMs);
        return () => clearTimeout(timer);
      }
    }, [visible, autoDismissMs, onDismiss]);

    return (
      <AnimatePresence>
        {visible && (
          <motion.div
            ref={ref}
            variants={undoVariants}
            initial="hidden"
            animate="visible"
            exit={{ opacity: 0, y: 10, transition: { duration: 0.2 } }}
            className={cn(
              'fixed bottom-6 left-1/2 z-50 -translate-x-1/2',
              'flex items-center gap-3 rounded-xl px-4 py-3 shadow-lg',
              'bg-[#1C1917] text-white dark:bg-[#F5F5F4] dark:text-[#1C1917]',
              className,
            )}
            {...props}
          >
            <span className="text-sm">{message}</span>
            {onUndo && (
              <button
                onClick={onUndo}
                className="text-sm font-bold text-[#F97316] hover:underline"
              >
                UNDO
              </button>
            )}
          </motion.div>
        )}
      </AnimatePresence>
    );
  },
);
DeleteFeedback.displayName = 'DeleteFeedback';

// ── AchievementBadge ───────────────────────────────────────────────
export interface AchievementBadgeProps extends Omit<HTMLMotionProps<'div'>, 'onAnimationComplete'> {
  title: string;
  description?: string;
  visible: boolean;
  onDismiss?: () => void;
  autoDismissMs?: number;
}

export const AchievementBadge = forwardRef<HTMLDivElement, AchievementBadgeProps>(
  ({ title, description, visible, onDismiss, autoDismissMs = 4000, className, ...props }, ref) => {
    const variants = getFeedbackAnimation('achievement');

    useEffect(() => {
      if (visible && autoDismissMs > 0) {
        const timer = setTimeout(() => {
          onDismiss?.();
        }, autoDismissMs);
        return () => clearTimeout(timer);
      }
    }, [visible, autoDismissMs, onDismiss]);

    // Sparkle particles
    const sparkles = Array.from({ length: 6 }, (_, i) => i);

    return (
      <AnimatePresence>
        {visible && (
          <motion.div
            ref={ref}
            variants={variants}
            initial="hidden"
            animate="visible"
            exit="exit"
            className={cn(
              'fixed inset-0 z-50 flex items-center justify-center',
              'bg-black/30 backdrop-blur-sm',
              className,
            )}
            onClick={onDismiss}
            {...props}
          >
            <div className="relative flex flex-col items-center gap-3 p-6" onClick={(e) => e.stopPropagation()}>
              {/* Sparkle effects */}
              {sparkles.map((i) => (
                <motion.div
                  key={i}
                  className="absolute h-2 w-2 rounded-full bg-[#FFD700]"
                  style={{
                    left: `${50 + 40 * Math.cos((i * Math.PI * 2) / 6)}%`,
                    top: `${50 + 40 * Math.sin((i * Math.PI * 2) / 6)}%`,
                  }}
                  initial={{ scale: 0, opacity: 0 }}
                  animate={{
                    scale: [0, 1.5, 0],
                    opacity: [0, 1, 0],
                  }}
                  transition={{
                    duration: 0.6,
                    delay: i * 0.05 + 0.3,
                    ease: 'easeOut' as const,
                  }}
                />
              ))}

              {/* Badge */}
              <motion.div
                className="flex h-20 w-20 items-center justify-center rounded-full bg-gradient-to-br from-[#F97316] to-[#FFD700] shadow-xl"
                initial={{ scale: 0, rotate: -20 }}
                animate={{ scale: [0, 1.2, 1], rotate: 0 }}
                transition={{ duration: 0.5, ease: [0.34, 1.56, 0.64, 1] as [number, number, number, number] }}
              >
                <svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                  <polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2" />
                </svg>
              </motion.div>

              {/* Text */}
              <motion.div
                className="flex flex-col items-center gap-1 text-center"
                initial={{ opacity: 0, y: 10 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.2, delay: 0.3 }}
              >
                <h3 className="text-lg font-bold text-white drop-shadow-lg">{title}</h3>
                {description && (
                  <p className="text-sm text-white/80 drop-shadow-md max-w-xs">{description}</p>
                )}
              </motion.div>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    );
  },
);
AchievementBadge.displayName = 'AchievementBadge';
