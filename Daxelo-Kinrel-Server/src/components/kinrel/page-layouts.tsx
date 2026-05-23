/**
 * DAXELO KINREL — Page Layout Components
 *
 * Layout templates matching Flutter page templates for cross-platform consistency.
 * StandardPage, DetailPage, FormPage, TwoPaneLayout patterns.
 *
 * Pack 01: Design System — Layout & Spacing
 */

'use client'

import { cn } from '@/lib/utils'
import { spacing, radius } from '@/lib/design-tokens'
import { Separator } from '@/components/ui/separator'

// ── Page Layout ─────────────────────────────────────────────────────
interface PageLayoutProps {
  children: React.ReactNode
  title?: string
  actions?: React.ReactNode
  maxWidth?: 'sm' | 'md' | 'lg' | 'xl' | 'full'
  className?: string
}

const maxWidthMap = {
  sm: 'max-w-screen-sm',
  md: 'max-w-screen-md',
  lg: 'max-w-screen-lg',
  xl: 'max-w-screen-xl',
  full: 'max-w-full',
}

export function PageLayout({
  children,
  title,
  actions,
  maxWidth = 'lg',
  className,
}: PageLayoutProps) {
  return (
    <div className={cn('mx-auto w-full px-4 md:px-6 lg:px-8', maxWidthMap[maxWidth], className)}>
      {(title || actions) && (
        <div className="flex items-center justify-between py-6">
          {title && <h1 className="text-2xl font-bold">{title}</h1>}
          {actions && <div className="flex gap-2">{actions}</div>}
        </div>
      )}
      <main className="pb-16">{children}</main>
    </div>
  )
}

// ── Section Header ──────────────────────────────────────────────────
interface SectionHeaderProps {
  title: string
  subtitle?: string
  trailing?: React.ReactNode
  className?: string
}

export function SectionHeader({
  title,
  subtitle,
  trailing,
  className,
}: SectionHeaderProps) {
  return (
    <div className={cn('flex items-center justify-between', className)}>
      <div>
        <h2 className="text-lg font-semibold">{title}</h2>
        {subtitle && (
          <p className="text-sm text-muted-foreground mt-0.5">{subtitle}</p>
        )}
      </div>
      {trailing}
    </div>
  )
}

// ── Detail Section ──────────────────────────────────────────────────
interface DetailSectionProps {
  title: string
  subtitle?: string
  trailing?: React.ReactNode
  children: React.ReactNode
  isGrid?: boolean
  columns?: number
  className?: string
}

export function DetailSection({
  title,
  subtitle,
  trailing,
  children,
  isGrid = false,
  columns = 2,
  className,
}: DetailSectionProps) {
  return (
    <section className={cn('space-y-3', className)}>
      <SectionHeader title={title} subtitle={subtitle} trailing={trailing} />
      <Separator />
      {isGrid ? (
        <div
          className="grid gap-3"
          style={{ gridTemplateColumns: `repeat(${columns}, minmax(0, 1fr))` }}
        >
          {children}
        </div>
      ) : (
        <div className="space-y-2">{children}</div>
      )}
    </section>
  )
}

// ── Two Pane Layout (Tablet/Desktop) ────────────────────────────────
interface TwoPaneLayoutProps {
  listPane: React.ReactNode
  detailPane: React.ReactNode
  listPaneWidth?: number
  className?: string
}

export function TwoPaneLayout({
  listPane,
  detailPane,
  listPaneWidth = 320,
  className,
}: TwoPaneLayoutProps) {
  return (
    <div className={cn('flex h-full', className)}>
      {/* List Pane */}
      <div
        className="hidden md:block border-r border-border overflow-y-auto"
        style={{ width: listPaneWidth, minWidth: listPaneWidth }}
      >
        {listPane}
      </div>

      {/* Mobile: show list only */}
      <div className="md:hidden flex-1 overflow-y-auto">
        {listPane}
      </div>

      {/* Detail Pane */}
      <div className="hidden md:flex flex-1 overflow-y-auto">
        {detailPane}
      </div>
    </div>
  )
}

// ── Form Layout ─────────────────────────────────────────────────────
interface FormLayoutProps {
  children: React.ReactNode
  submitLabel?: string
  onSubmit?: () => void
  isLoading?: boolean
  disclaimer?: string
  className?: string
}

export function FormLayout({
  children,
  disclaimer,
  className,
}: FormLayoutProps) {
  return (
    <div className={cn('flex flex-col h-full', className)}>
      <div className="flex-1 overflow-y-auto p-4 md:p-6">
        <div className="space-y-4 max-w-lg mx-auto">
          {children}
          {disclaimer && (
            <p className="text-xs text-muted-foreground mt-6">{disclaimer}</p>
          )}
        </div>
      </div>
    </div>
  )
}

// ── Responsive Grid ─────────────────────────────────────────────────
interface ResponsiveGridProps {
  children: React.ReactNode
  columns?: {
    default?: number
    sm?: number
    md?: number
    lg?: number
    xl?: number
  }
  gap?: number
  className?: string
}

export function ResponsiveGrid({
  children,
  columns = { default: 1, sm: 2, md: 2, lg: 3, xl: 4 },
  gap = spacing.sm,
  className,
}: ResponsiveGridProps) {
  const colStyles = Object.entries(columns).reduce((acc, [breakpoint, count]) => {
    if (breakpoint === 'default') {
      acc['gridTemplateColumns'] = `repeat(${count}, minmax(0, 1fr))`
    }
    return acc
  }, {} as React.CSSProperties)

  const responsiveClasses = Object.entries(columns)
    .filter(([bp]) => bp !== 'default')
    .map(([bp, count]) => {
      const prefix = bp === 'sm' ? 'sm' : bp === 'md' ? 'md' : bp === 'lg' ? 'lg' : 'xl'
      return `${prefix}:grid-cols-${count}`
    })
    .join(' ')

  return (
    <div
      className={cn('grid', responsiveClasses, className)}
      style={{ gap: `${gap}px`, ...colStyles }}
    >
      {children}
    </div>
  )
}

// ── Safe Area Wrapper ───────────────────────────────────────────────
interface SafeAreaWrapperProps {
  children: React.ReactNode
  className?: string
  applyBottom?: boolean
  applyTop?: boolean
}

export function SafeAreaWrapper({
  children,
  className,
  applyBottom = true,
  applyTop = false,
}: SafeAreaWrapperProps) {
  return (
    <div
      className={cn(className)}
      style={{
        paddingTop: applyTop ? 'env(safe-area-inset-top)' : undefined,
        paddingBottom: applyBottom ? 'env(safe-area-inset-bottom)' : undefined,
      }}
    >
      {children}
    </div>
  )
}
