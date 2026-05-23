'use client';

import { useMemo } from 'react';
import { useTheme } from 'next-themes';
import { useSyncExternalStore } from 'react';
import { lightTheme, darkTheme, highContrastColors } from '@/lib/theme';
import { spacing, radius, typography, brandColors } from '@/lib/design-tokens';

type DesignTokenProviderProps = {
  children: React.ReactNode;
  fontScale?: number;       // 1.0 = normal, 1.25 = large, 1.5 = extra large
  highContrast?: boolean;   // override for high contrast mode
};

export function DesignTokenProvider({
  children,
  fontScale = 1.0,
  highContrast = false,
}: DesignTokenProviderProps) {
  const { resolvedTheme } = useTheme();
  const mounted = useSyncExternalStore(
    () => () => {},
    () => true,
    () => false,
  );

  const cssVars = useMemo(() => {
    // During SSR or before hydration, default to light theme
    const theme = resolvedTheme === 'dark' ? darkTheme : lightTheme;
    const colors = theme.colors;

    const vars: Record<string, string> = {
      // ── Brand colors ────────────────────────────────────────────────
      '--kinrel-primary': colors.primary,
      '--kinrel-primary-container': colors.primaryContainer,
      '--kinrel-on-primary': colors.onPrimary,
      '--kinrel-on-primary-container': colors.onPrimaryContainer,
      '--kinrel-secondary': colors.secondary,
      '--kinrel-secondary-container': colors.secondaryContainer,
      '--kinrel-on-secondary': colors.onSecondary,
      '--kinrel-accent': colors.accent,
      '--kinrel-accent-container': colors.accentContainer,

      // ── Semantic colors ─────────────────────────────────────────────
      '--kinrel-success': colors.success,
      '--kinrel-warning': colors.warning,
      '--kinrel-error': colors.error,
      '--kinrel-info': colors.info,

      // ── Surfaces ────────────────────────────────────────────────────
      '--kinrel-background': colors.background,
      '--kinrel-surface': colors.surface,
      '--kinrel-surface-low': colors.surfaceContainerLow,
      '--kinrel-surface-container': colors.surfaceContainer,
      '--kinrel-surface-high': colors.surfaceContainerHigh,
      '--kinrel-surface-highest': colors.surfaceContainerHighest,
      '--kinrel-on-surface': colors.onSurface,
      '--kinrel-on-surface-variant': colors.onSurfaceVariant,

      // ── Outlines ────────────────────────────────────────────────────
      '--kinrel-outline': colors.outline,
      '--kinrel-outline-variant': colors.outlineVariant,

      // ── Inverse ─────────────────────────────────────────────────────
      '--kinrel-inverse-surface': colors.inverseSurface,
      '--kinrel-inverse-on-surface': colors.inverseOnSurface,

      // ── Glass ───────────────────────────────────────────────────────
      '--kinrel-glass-bg': colors.glassBackground,
      '--kinrel-glass-border': colors.glassBorder,

      // ── Shimmer ─────────────────────────────────────────────────────
      '--kinrel-shimmer-base': colors.shimmerBase,
      '--kinrel-shimmer-highlight': colors.shimmerHighlight,

      // ── Premium ─────────────────────────────────────────────────────
      '--kinrel-premium-gold': colors.premiumGold,

      // ── Tree visualization ──────────────────────────────────────────
      '--kinrel-tree-node-bg': colors.treeNodeBackground,
      '--kinrel-tree-node-border': colors.treeNodeBorder,
      '--kinrel-tree-line-parent': colors.treeLineParent,
      '--kinrel-tree-line-spouse': colors.treeLineSpouse,
      '--kinrel-tree-line-sibling': colors.treeLineSibling,

      // ── Avatar ──────────────────────────────────────────────────────
      '--kinrel-avatar-fallback-bg': colors.avatarFallbackBg,
      '--kinrel-avatar-fallback-text': colors.avatarFallbackText,

      // ── Font scale (accessibility) ──────────────────────────────────
      '--kinrel-font-scale': String(fontScale),
    };

    // ── High contrast overrides ─────────────────────────────────────────
    if (highContrast) {
      vars['--kinrel-focus-ring'] = highContrastColors.focusRing;
      vars['--kinrel-error-focus'] = highContrastColors.errorFocus;
      vars['--kinrel-on-surface'] =
        resolvedTheme === 'dark'
          ? highContrastColors.textOnDark
          : highContrastColors.textOnLight;
      vars['--kinrel-on-surface-variant'] =
        resolvedTheme === 'dark'
          ? highContrastColors.textOnDark
          : highContrastColors.textOnLight;
      // Stronger outlines for high contrast
      vars['--kinrel-outline'] =
        resolvedTheme === 'dark'
          ? highContrastColors.textOnDark
          : highContrastColors.textOnLight;
      vars['--kinrel-outline-variant'] =
        resolvedTheme === 'dark'
          ? 'rgba(255,255,255,0.6)'
          : 'rgba(0,0,0,0.6)';
    }

    // ── Spacing tokens ──────────────────────────────────────────────────
    for (const [name, value] of Object.entries(spacing)) {
      vars[`--kinrel-spacing-${name}`] = `${value}px`;
    }

    // ── Radius tokens ───────────────────────────────────────────────────
    for (const [name, value] of Object.entries(radius)) {
      vars[`--kinrel-radius-${name}`] = `${value}px`;
    }

    // ── Typography tokens ───────────────────────────────────────────────
    for (const [name, token] of Object.entries(typography)) {
      const t = token as typeof typography[string];
      // Scale font sizes by fontScale for accessibility
      const scaledSize = Math.round(t.fontSize * fontScale);
      vars[`--kinrel-type-${name}-font-size`] = `${scaledSize}px`;
      vars[`--kinrel-type-${name}-font-weight`] = String(t.fontWeight);
      vars[`--kinrel-type-${name}-line-height`] = String(t.lineHeight);
      vars[`--kinrel-type-${name}-letter-spacing`] = `${t.letterSpacing}px`;
    }

    // ── Brand color shortcuts (always available regardless of theme) ────
    vars['--kinrel-brand-primary'] = brandColors.primary;
    vars['--kinrel-brand-primary-dark'] = brandColors.primaryDark;
    vars['--kinrel-brand-secondary'] = brandColors.secondary;
    vars['--kinrel-brand-accent'] = brandColors.accent;
    vars['--kinrel-brand-success'] = brandColors.success;
    vars['--kinrel-brand-warning'] = brandColors.warning;
    vars['--kinrel-brand-error'] = brandColors.error;
    vars['--kinrel-brand-premium-gold'] = brandColors.premiumGold;

    return vars;
  }, [resolvedTheme, fontScale, highContrast, mounted]);

  // Before client-side hydration, render children without CSS vars
  // to avoid flash of wrong theme
  if (!mounted) {
    return <>{children}</>;
  }

  return (
    <div style={cssVars as React.CSSProperties} className="contents">
      {children}
    </div>
  );
}

// ── Utility hook for consuming design tokens ───────────────────────────
export function useDesignTokens() {
  const { resolvedTheme } = useTheme();
  const isDark = resolvedTheme === 'dark';
  return {
    colors: isDark ? darkTheme.colors : lightTheme.colors,
    spacing,
    radius,
    typography,
    brandColors,
    isDark,
  };
}
