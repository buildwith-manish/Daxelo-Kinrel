/**
 * DAXELO KINREL — Avatar Component
 *
 * Culturally-aware avatar with deterministic color fallback.
 * Supports image, initials, badge, and dark mode.
 *
 * Pack 01: Design System — Icons & Imagery
 */

'use client'

import { cn } from '@/lib/utils'
import { avatarColorForName, getInitials, avatarLightVariant } from '@/lib/avatar-colors'

interface AvatarProps {
  src?: string | null
  name: string
  size?: number
  showBadge?: boolean
  badgeIcon?: React.ReactNode
  className?: string
}

export function Avatar({
  src,
  name,
  size = 40,
  showBadge = false,
  badgeIcon,
  className,
}: AvatarProps) {
  const bgColor = avatarColorForName(name)
  const initials = getInitials(name)

  return (
    <div className={cn('relative inline-flex shrink-0', className)}>
      {src ? (
        <img
          src={src}
          alt={name}
          className="rounded-full object-cover"
          style={{ width: size, height: size }}
          loading="lazy"
        />
      ) : (
        <div
          className="rounded-full flex items-center justify-center font-semibold text-white"
          style={{
            width: size,
            height: size,
            backgroundColor: bgColor,
            fontSize: size * 0.4,
          }}
          aria-label={name}
        >
          {initials}
        </div>
      )}
      {showBadge && (
        <div
          className="absolute -right-0.5 -bottom-0.5 rounded-full bg-primary border-2 border-background flex items-center justify-center text-primary-foreground"
          style={{
            width: size * 0.3,
            height: size * 0.3,
            fontSize: size * 0.15,
          }}
        >
          {badgeIcon || '✓'}
        </div>
      )}
    </div>
  )
}
