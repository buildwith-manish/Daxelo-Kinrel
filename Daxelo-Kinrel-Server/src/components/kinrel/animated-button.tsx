'use client';

/**
 * DAXELO KINREL — Animated Button Components
 *
 * Framer Motion-powered buttons with press, release, loading,
 * and disabled states following KINREL micro-interaction specs.
 *
 * Pack 12: Brand & Motion — Animated Buttons
 */

import React, { forwardRef } from 'react';
import { motion, type HTMLMotionProps } from 'framer-motion';
import { Loader2 } from 'lucide-react';
import { cn } from '@/lib/utils';
import { getButtonVariant, ButtonInteractions } from '@/lib/brand/micro-interactions';

// ── Shared Types ───────────────────────────────────────────────────
interface AnimatedButtonBaseProps extends HTMLMotionProps<'button'> {
  loading?: boolean;
  icon?: React.ReactNode;
  iconPosition?: 'left' | 'right';
  fullWidth?: boolean;
}

// ── AnimatedPrimaryButton ──────────────────────────────────────────
export type AnimatedPrimaryButtonProps = AnimatedButtonBaseProps;

const primaryVariant = getButtonVariant('primary');

export const AnimatedPrimaryButton = forwardRef<HTMLButtonElement, AnimatedPrimaryButtonProps>(
  ({ children, loading = false, icon, iconPosition = 'left', fullWidth = false, className, disabled, ...props }, ref) => {
    const isDisabled = disabled || loading;
    return (
      <motion.button
        ref={ref}
        variants={primaryVariant}
        whileTap={!isDisabled ? 'tap' : undefined}
        whileHover={!isDisabled ? 'hover' : undefined}
        animate={isDisabled ? 'disabled' : 'animate'}
        initial="initial"
        className={cn(
          'relative inline-flex items-center justify-center gap-2 rounded-lg px-6 py-3 text-sm font-semibold',
          'bg-[#F97316] text-white shadow-md',
          'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F97316] focus-visible:ring-offset-2',
          'transition-colors',
          isDisabled && 'cursor-not-allowed',
          fullWidth && 'w-full',
          className,
        )}
        disabled={isDisabled}
        {...props}
      >
        {loading ? (
          <Loader2 className="h-4 w-4 animate-spin" />
        ) : (
          icon && iconPosition === 'left' && <span className="flex-shrink-0">{icon as React.ReactNode}</span>
        )}
        {children as React.ReactNode}
        {!loading && icon && iconPosition === 'right' && <span className="flex-shrink-0">{icon as React.ReactNode}</span>}
      </motion.button>
    );
  },
);
AnimatedPrimaryButton.displayName = 'AnimatedPrimaryButton';

// ── AnimatedSecondaryButton ────────────────────────────────────────
export interface AnimatedSecondaryButtonProps extends AnimatedButtonBaseProps {
  variant?: 'secondary';
}

const secondaryVariant = getButtonVariant('secondary');

export const AnimatedSecondaryButton = forwardRef<HTMLButtonElement, AnimatedSecondaryButtonProps>(
  ({ children, loading = false, icon, iconPosition = 'left', fullWidth = false, className, disabled, ...props }, ref) => {
    const isDisabled = disabled || loading;
    return (
      <motion.button
        ref={ref}
        variants={secondaryVariant}
        whileTap={!isDisabled ? 'tap' : undefined}
        whileHover={!isDisabled ? 'hover' : undefined}
        animate={isDisabled ? 'disabled' : 'animate'}
        initial="initial"
        className={cn(
          'relative inline-flex items-center justify-center gap-2 rounded-lg px-6 py-3 text-sm font-semibold',
          'border-2 border-[#F97316] text-[#F97316] bg-transparent',
          'hover:bg-[#FFF7ED] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F97316] focus-visible:ring-offset-2',
          'transition-colors',
          isDisabled && 'cursor-not-allowed',
          fullWidth && 'w-full',
          className,
        )}
        disabled={isDisabled}
        {...props}
      >
        {loading ? (
          <Loader2 className="h-4 w-4 animate-spin text-[#F97316]" />
        ) : (
          icon && iconPosition === 'left' && <span className="flex-shrink-0">{icon as React.ReactNode}</span>
        )}
        {children as React.ReactNode}
        {!loading && icon && iconPosition === 'right' && <span className="flex-shrink-0">{icon as React.ReactNode}</span>}
      </motion.button>
    );
  },
);
AnimatedSecondaryButton.displayName = 'AnimatedSecondaryButton';

// ── AnimatedIconButton ─────────────────────────────────────────────
export interface AnimatedIconButtonProps extends Omit<HTMLMotionProps<'button'>, 'children'> {
  children: React.ReactNode;
  label: string;
  size?: 'sm' | 'md' | 'lg';
}

const iconSpec = ButtonInteractions.icon;

export const AnimatedIconButton = forwardRef<HTMLButtonElement, AnimatedIconButtonProps>(
  ({ children, label, size = 'md', className, disabled, ...props }, ref) => {
    const sizeClasses = {
      sm: 'h-8 w-8',
      md: 'h-10 w-10',
      lg: 'h-12 w-12',
    };
    const iconSizes = {
      sm: 'h-4 w-4',
      md: 'h-5 w-5',
      lg: 'h-6 w-6',
    };
    return (
      <motion.button
        ref={ref}
        whileTap={!disabled ? { scale: iconSpec.press.scale } : undefined}
        whileHover={!disabled ? { scale: 1.05, backgroundColor: 'rgba(249, 115, 22, 0.1)' } : undefined}
        initial={{ scale: 1 }}
        animate={{ scale: 1 }}
        className={cn(
          'inline-flex items-center justify-center rounded-full',
          'text-[#57534E] hover:text-[#F97316]',
          'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F97316] focus-visible:ring-offset-2',
          'transition-colors',
          sizeClasses[size],
          disabled && 'cursor-not-allowed opacity-38',
          className,
        )}
        disabled={disabled}
        aria-label={label}
        {...props}
      >
        <span className={iconSizes[size]}>{children}</span>
      </motion.button>
    );
  },
);
AnimatedIconButton.displayName = 'AnimatedIconButton';

// ── AnimatedFAB ────────────────────────────────────────────────────
export interface AnimatedFABProps extends Omit<HTMLMotionProps<'button'>, 'children'> {
  children: React.ReactNode;
  label: string;
  actionComplete?: boolean;
  color?: 'primary' | 'secondary' | 'accent';
}

const fabSpec = ButtonInteractions.fab;

export const AnimatedFAB = forwardRef<HTMLButtonElement, AnimatedFABProps>(
  ({ children, label, actionComplete = false, color = 'primary', className, disabled, ...props }, ref) => {
    const colorMap = {
      primary: 'bg-[#F97316] text-white shadow-lg shadow-orange-300/40',
      secondary: 'bg-[#E94560] text-white shadow-lg shadow-rose-300/40',
      accent: 'bg-[#14B8A6] text-white shadow-lg shadow-teal-300/40',
    };
    return (
      <motion.button
        ref={ref}
        whileTap={!disabled ? { scale: fabSpec.press.scale } : undefined}
        initial={{ scale: 0, opacity: 0 }}
        animate={
          actionComplete
            ? { scale: [1, 1.15, 1], opacity: 1 }
            : { scale: 1, opacity: 1 }
        }
        transition={
          actionComplete
            ? { duration: fabSpec.tapComplete.duration / 1000, ease: [0.34, 1.56, 0.64, 1] as [number, number, number, number] }
            : { type: 'spring', stiffness: 300, damping: 25 }
        }
        className={cn(
          'fixed bottom-6 right-6 z-50 flex h-14 w-14 items-center justify-center rounded-full',
          colorMap[color],
          'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-offset-2',
          disabled && 'cursor-not-allowed opacity-50',
          className,
        )}
        disabled={disabled}
        aria-label={label}
        {...props}
      >
        {children}
      </motion.button>
    );
  },
);
AnimatedFAB.displayName = 'AnimatedFAB';
