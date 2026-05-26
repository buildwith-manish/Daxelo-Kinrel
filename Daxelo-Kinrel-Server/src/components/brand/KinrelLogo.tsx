// src/components/brand/KinrelLogo.tsx
//
// Kinrel logo lockup — icon + wordmark, all variants.
// Identical to Flutter KinrelLogo in proportions, colours, and API shape.
//
// Usage:
//   <KinrelLogo />
//   <KinrelLogo size="lg" layout="vertical" showSubtitle />
//   <KinrelLogo size="sm" palette="light" layout="horizontal" />

import KinrelIcon, { type KinrelPalette } from "./KinrelIcon";

// ── Types ─────────────────────────────────────────────────────────────────────

export type LogoSize    = "xs" | "sm" | "md" | "lg" | "xl";
export type LogoLayout  = "horizontal" | "vertical";

export interface KinrelLogoProps {
  size?:         LogoSize;
  palette?:      KinrelPalette;
  layout?:       LogoLayout;
  showSubtitle?: boolean;
  animated?:     boolean;
  className?:    string;
  style?:        React.CSSProperties;
}

// ── Scale maps ────────────────────────────────────────────────────────────────

const ICON_SIZE: Record<LogoSize, number> = {
  xs: 28, sm: 36, md: 48, lg: 64, xl: 96,
};

const SCALE: Record<LogoSize, number> = {
  xs: 0.6, sm: 0.8, md: 1.0, lg: 1.4, xl: 2.0,
};

// ── Text colour per palette ───────────────────────────────────────────────────

const TEXT_COLOR: Record<KinrelPalette, string> = {
  orange:  "#F5F0EE",
  outline: "#F5F0EE",
  mono:    "#1F2937",
  light:   "#1A0A00",
};

const SUBTITLE_COLOR: Record<KinrelPalette, string> = {
  orange:  "#C9B4A8",
  outline: "#C9B4A8",
  mono:    "#6B7280",
  light:   "#7A5040",
};

// ── Component ─────────────────────────────────────────────────────────────────

export default function KinrelLogo({
  size     = "md",
  palette  = "orange",
  layout   = "horizontal",
  showSubtitle = false,
  animated = false,
  className,
  style,
}: KinrelLogoProps) {
  const iconSize     = ICON_SIZE[size];
  const s            = SCALE[size];
  const isHorizontal = layout === "horizontal";
  const gap          = isHorizontal ? iconSize * 0.25 : iconSize * 0.18;
  const letterSpacing = (size === "xs" || size === "sm") ? "0.08em" : "0.14em";

  const wordmark = (
    <div
      style={{
        display:       "flex",
        flexDirection: "column",
        gap:           `${3 * s}px`,
        alignItems:    isHorizontal ? "flex-start" : "center",
      }}
    >
      <span
        style={{
          fontFamily:    "var(--kinrel-font-display, 'Outfit', sans-serif)",
          fontSize:      `${28 * s}px`,
          fontWeight:    800,
          letterSpacing,
          color:         TEXT_COLOR[palette],
          lineHeight:    1,
          userSelect:    "none",
        }}
      >
        KINREL
      </span>

      {showSubtitle && (
        <span
          style={{
            fontFamily:    "var(--kinrel-font-body, 'DM Sans', sans-serif)",
            fontSize:      `${9 * s}px`,
            fontWeight:    400,
            letterSpacing: "0.26em",
            color:         SUBTITLE_COLOR[palette],
            lineHeight:    1,
            userSelect:    "none",
          }}
        >
          by Daxelo
        </span>
      )}
    </div>
  );

  const icon = (
    <KinrelIcon size={iconSize} palette={palette} animated={animated} />
  );

  const containerStyle: React.CSSProperties = isHorizontal
    ? {
        display:    "flex",
        flexDirection: "row",
        alignItems: "center",
        gap:        `${gap}px`,
        ...style,
      }
    : {
        display:       "flex",
        flexDirection: "column",
        alignItems:    "center",
        gap:           `${gap}px`,
        ...style,
      };

  return (
    <div className={className} style={containerStyle}>
      {icon}
      {wordmark}
    </div>
  );
}
