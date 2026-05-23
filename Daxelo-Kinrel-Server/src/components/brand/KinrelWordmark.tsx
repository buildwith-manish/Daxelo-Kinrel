// src/components/brand/KinrelWordmark.tsx
//
// KinrelWordmark — "KINREL" text only, all variants.
// Use when the icon is already present nearby or in space-constrained UIs.
//
// Usage:
//   <KinrelWordmark />                              // gradient, md
//   <KinrelWordmark size="lg" variant="gradient" showSubtitle />
//   <KinrelWordmark size="sm" variant="solidOrange" />
//   <KinrelWordmark size="xs" variant="solidWhite" />

import type { LogoSize } from "./KinrelLogo";

// ── Types ─────────────────────────────────────────────────────────────────────

export type WordmarkVariant =
  | "gradient"      // white → orange (hero / splash)
  | "solidOrange"   // #E8612A flat
  | "solidWhite"    // #F5F0EE flat
  | "solidDark"     // #1A0A00 for light backgrounds
  | "mono";         // #F9FAFB for greyscale contexts

export interface KinrelWordmarkProps {
  size?:         LogoSize;
  variant?:      WordmarkVariant;
  showSubtitle?: boolean;
  className?:    string;
  style?:        React.CSSProperties;
}

// ── Scale / spacing maps ──────────────────────────────────────────────────────

const SCALE: Record<LogoSize, number> = {
  xs: 0.6, sm: 0.8, md: 1.0, lg: 1.4, xl: 2.0,
};

const SOLID_COLOR: Record<WordmarkVariant, string> = {
  gradient:    "#F5F0EE",   // base colour before gradient overlay
  solidOrange: "#E8612A",
  solidWhite:  "#F5F0EE",
  solidDark:   "#1A0A00",
  mono:        "#F9FAFB",
};

const SUBTITLE_COLOR: Record<WordmarkVariant, string> = {
  gradient:    "#C9B4A8",
  solidOrange: "#C9B4A8",
  solidWhite:  "#C9B4A8",
  solidDark:   "#7A5040",
  mono:        "#9CA3AF",
};

// ── Component ─────────────────────────────────────────────────────────────────

export default function KinrelWordmark({
  size     = "md",
  variant  = "gradient",
  showSubtitle = false,
  className,
  style,
}: KinrelWordmarkProps) {
  const s             = SCALE[size];
  const letterSpacing = (size === "xs" || size === "sm") ? "0.08em" : "0.14em";

  // Base text style
  const textStyle: React.CSSProperties = {
    fontFamily:    "var(--kinrel-font-display, 'Outfit', sans-serif)",
    fontSize:      `${28 * s}px`,
    fontWeight:    800,
    letterSpacing,
    lineHeight:    1,
    userSelect:    "none" as const,
    color:         SOLID_COLOR[variant],
    ...(variant === "gradient" && {
      background:            "linear-gradient(135deg, #F5F0EE 0%, #E8612A 100%)",
      WebkitBackgroundClip:  "text",
      WebkitTextFillColor:   "transparent",
      backgroundClip:        "text",
    }),
  };

  return (
    <div
      className={className}
      style={{
        display:       "flex",
        flexDirection: "column",
        gap:           `${3 * s}px`,
        alignItems:    "center",
        ...style,
      }}
    >
      <span style={textStyle}>KINREL</span>

      {showSubtitle && (
        <span
          style={{
            fontFamily:    "var(--kinrel-font-body, 'DM Sans', sans-serif)",
            fontSize:      `${9 * s}px`,
            fontWeight:    400,
            letterSpacing: "0.26em",
            color:         SUBTITLE_COLOR[variant],
            lineHeight:    1,
            userSelect:    "none",
          }}
        >
          by Daxelo
        </span>
      )}
    </div>
  );
}
