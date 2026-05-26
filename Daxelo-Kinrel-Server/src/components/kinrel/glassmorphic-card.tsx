/**
 * DAXELO KINREL — Glassmorphic Card Component
 *
 * Dark-mode safe glassmorphism with context-aware backgrounds.
 * Uses backdrop-blur with proper light/dark mode support.
 *
 * Pack 01: Design System — Theming & Dark Mode
 */

'use client'

import { cn } from '@/lib/utils'
import { motion } from 'framer-motion'
import { radius, spacing } from '@/lib/design-tokens'

interface GlassmorphicCardProps {
  children: React.ReactNode
  className?: string
  blur?: number
  opacity?: number
  padding?: number
  borderRadius?: number
  hover?: boolean
  onClick?: () => void
}

export function GlassmorphicCard({
  children,
  className,
  blur = 10,
  opacity = 0.15,
  padding = spacing.md,
  borderRadius = radius.lg,
  hover = false,
  onClick,
}: GlassmorphicCardProps) {
  return (
    <motion.div
      onClick={onClick}
      whileHover={hover ? { scale: 1.02, y: -2 } : undefined}
      whileTap={onClick ? { scale: 0.98 } : undefined}
      className={cn(
        'relative overflow-hidden backdrop-blur-md border',
        'bg-white/[0.15] dark:bg-black/[0.15]',
        'border-white/[0.33] dark:border-white/[0.1]',
        onClick && 'cursor-pointer',
        className
      )}
      style={{
        padding: `${padding}px`,
        borderRadius: `${borderRadius}px`,
        backdropFilter: `blur(${blur}px)`,
        WebkitBackdropFilter: `blur(${blur}px)`,
      }}
    >
      {children}
    </motion.div>
  )
}
