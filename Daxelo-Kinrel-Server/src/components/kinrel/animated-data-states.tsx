'use client'

import React from 'react'
import { motion } from 'framer-motion'

// ── Shimmer Skeleton ──────────────────────────────────────────────────
interface ShimmerSkeletonProps {
  className?: string
  count?: number
  variant?: 'rectangular' | 'circular' | 'text'
}

export function ShimmerSkeleton({
  className = '',
  count = 1,
  variant = 'rectangular',
}: ShimmerSkeletonProps) {
  const baseClass = variant === 'circular'
    ? 'rounded-full'
    : variant === 'text'
      ? 'rounded h-4'
      : 'rounded-lg'

  return (
    <>
      {Array.from({ length: count }).map((_, i) => (
        <div
          key={i}
          className={`relative overflow-hidden bg-stone-200 dark:bg-stone-700 ${baseClass} ${className}`}
        >
          <motion.div
            className="absolute inset-0 bg-gradient-to-r from-transparent via-white/30 dark:via-white/10 to-transparent"
            initial={{ x: '-200%' }}
            animate={{ x: '200%' }}
            transition={{ duration: 1.5, repeat: Infinity, ease: 'linear' }}
          />
        </div>
      ))}
    </>
  )
}

// ── Data Loaded Transition ─────────────────────────────────────────────
interface DataLoadedTransitionProps {
  children: React.ReactNode
  delay?: number
}

export function DataLoadedTransition({ children, delay = 0 }: DataLoadedTransitionProps) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.25, delay, ease: [0.25, 0.1, 0.25, 1] }}
    >
      {children}
    </motion.div>
  )
}

// ── Empty State Widget ─────────────────────────────────────────────────
interface EmptyStateWidgetProps {
  title: string
  description?: string
  icon?: React.ReactNode
  action?: React.ReactNode
}

export function EmptyStateWidget({ title, description, icon, action }: EmptyStateWidgetProps) {
  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      className="flex flex-col items-center justify-center py-12 px-4 text-center"
    >
      {icon && (
        <motion.div
          animate={{ y: [0, -6, 0] }}
          transition={{ duration: 2, repeat: Infinity, ease: 'easeInOut' }}
          className="mb-4 text-stone-300 dark:text-stone-600"
        >
          {icon}
        </motion.div>
      )}
      <h3 className="text-lg font-semibold text-foreground mb-1">{title}</h3>
      {description && (
        <p className="text-sm text-muted-foreground max-w-xs">{description}</p>
      )}
      {action && <div className="mt-4">{action}</div>}
    </motion.div>
  )
}

// ── Pull-to-Refresh Indicator ──────────────────────────────────────────
interface PullToRefreshProps {
  isRefreshing: boolean
  onRefresh: () => void
  children: React.ReactNode
}

export function PullToRefreshTree({ isRefreshing, onRefresh, children }: PullToRefreshProps) {
  return (
    <div className="relative">
      <AnimatePresence>
        {isRefreshing && (
          <motion.div
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: 48, opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            transition={{ duration: 0.3 }}
            className="flex items-center justify-center overflow-hidden"
          >
            <motion.div
              animate={{ rotate: 360 }}
              transition={{ duration: 1, repeat: Infinity, ease: 'linear' }}
              className="w-5 h-5 border-2 border-orange-500 border-t-transparent rounded-full"
            />
          </motion.div>
        )}
      </AnimatePresence>
      {children}
    </div>
  )
}

// ── Infinite Scroll Item ───────────────────────────────────────────────
interface InfiniteScrollItemProps {
  children: React.ReactNode
  index: number
}

export function InfiniteScrollItem({ children, index }: InfiniteScrollItemProps) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{
        duration: 0.25,
        delay: index * 0.05,
        ease: [0.25, 0.1, 0.25, 1],
      }}
    >
      {children}
    </motion.div>
  )
}

// ── Stagger List ───────────────────────────────────────────────────────
interface StaggerListProps {
  children: React.ReactNode
  staggerMs?: number
}

export function StaggerList({ children, staggerMs = 50 }: StaggerListProps) {
  return (
    <motion.div
      initial="hidden"
      animate="visible"
      variants={{
        hidden: {},
        visible: {
          transition: { staggerChildren: staggerMs / 1000 },
        },
      }}
    >
      {React.Children.map(children, (child) => (
        <motion.div
          variants={{
            hidden: { opacity: 0, y: 16 },
            visible: { opacity: 1, y: 0, transition: { duration: 0.25 } },
          }}
        >
          {child}
        </motion.div>
      ))}
    </motion.div>
  )
}

// Need AnimatePresence import at top
import { AnimatePresence } from 'framer-motion'
