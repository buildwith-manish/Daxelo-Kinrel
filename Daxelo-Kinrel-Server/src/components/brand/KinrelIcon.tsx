// src/components/brand/KinrelIcon.tsx
//
// Kinrel K-graph icon — React / Next.js component.
// The icon is a directed graph shaped like the letter K,
// representing family kinship connections.
//
// Usage:
//   <KinrelIcon size={64} palette="orange" animated />
//   <KinrelIcon size={20} />      // auto mini
//   <KinrelIcon palette="light" />

"use client";

import { useEffect, useId, useState } from "react";

export type KinrelPalette = "orange" | "light" | "mono" | "outline";

export interface KinrelIconProps {
  size?: number;
  palette?: KinrelPalette;
  animated?: boolean;
  className?: string;
  style?: React.CSSProperties;
}

// ── Palette token resolver ─────────────────────────────────────────────────────

interface PaletteColors {
  bg: string;
  bgInner: string;
  primary: string;
  secondary: string;
  accent: string;
  showBg: boolean;
  showGlow: boolean;
  isOutline: boolean;
}

function resolvePalette(palette: KinrelPalette): PaletteColors {
  switch (palette) {
    case "orange":
      return {
        bg: "#191B2C", bgInner: "#23263E",
        primary: "#E8612A", secondary: "#F59240", accent: "#C44A18",
        showBg: true, showGlow: true, isOutline: false,
      };
    case "light":
      return {
        bg: "#FFFFFF", bgInner: "#FFF0E8",
        primary: "#C44A18", secondary: "#D9700F", accent: "#A83A10",
        showBg: true, showGlow: true, isOutline: false,
      };
    case "mono":
      return {
        bg: "#111827", bgInner: "#1F2937",
        primary: "#F9FAFB", secondary: "#9CA3AF", accent: "#6B7280",
        showBg: true, showGlow: false, isOutline: false,
      };
    case "outline":
      return {
        bg: "transparent", bgInner: "transparent",
        primary: "#E8612A", secondary: "#F59240", accent: "#C44A18",
        showBg: false, showGlow: false, isOutline: true,
      };
  }
}

// ── Simplified mini icon (≤24px) ──────────────────────────────────────────────

function KinrelIconMini({
  size,
  color,
  bg,
}: {
  size: number;
  color: string;
  bg: string;
}) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 100 100"
      fill="none"
      style={{ display: "block" }}
      aria-hidden="true"
    >
      <rect width="100" height="100" rx="22" ry="22" fill={bg} />
      <line x1="32" y1="18" x2="32" y2="82" stroke={color} strokeWidth="11" strokeLinecap="round" />
      <line x1="32" y1="50" x2="74" y2="18" stroke={color} strokeWidth="9"  strokeLinecap="round" />
      <line x1="32" y1="50" x2="74" y2="82" stroke={color} strokeWidth="9"  strokeLinecap="round" />
    </svg>
  );
}

// ── Main icon component ────────────────────────────────────────────────────────

export default function KinrelIcon({
  size = 64,
  palette = "orange",
  animated = false,
  className,
  style,
}: KinrelIconProps) {
  const uid = useId().replace(/:/g, "");
  const [pulse, setPulse] = useState(false);

  useEffect(() => {
    if (!animated) { return; }
    const t = setTimeout(() => setPulse(true), 600);
    return () => clearTimeout(t);
  }, [animated]);

  const pc = resolvePalette(palette);

  // Auto-switch to mini at ≤24px
  if (size <= 24) {
    return (
      <KinrelIconMini
        size={size}
        color={pc.primary}
        bg={pc.showBg ? pc.bg : "#191B2C"}
      />
    );
  }

  const nodes = [
    { x: 28, y: 22, r: 4.5, c: pc.primary   },
    { x: 28, y: 50, r: 6,   c: pc.primary   },
    { x: 28, y: 78, r: 4.5, c: pc.primary   },
    { x: 70, y: 17, r: 4,   c: pc.secondary },
    { x: 70, y: 83, r: 4,   c: pc.secondary },
    { x: 50, y: 34, r: 3,   c: pc.accent    },
    { x: 50, y: 66, r: 3,   c: pc.accent    },
  ];

  const edges = [
    { x1: 28, y1: 22, x2: 28, y2: 50, c: pc.primary,   w: 1.6              },
    { x1: 28, y1: 50, x2: 28, y2: 78, c: pc.primary,   w: 1.6              },
    { x1: 28, y1: 50, x2: 50, y2: 34, c: pc.secondary, w: 1.4              },
    { x1: 50, y1: 34, x2: 70, y2: 17, c: pc.secondary, w: 1.4              },
    { x1: 28, y1: 50, x2: 50, y2: 66, c: pc.accent,    w: 1.4              },
    { x1: 50, y1: 66, x2: 70, y2: 83, c: pc.accent,    w: 1.4              },
    { x1: 50, y1: 34, x2: 50, y2: 66, c: pc.primary,   w: 0.8, dash: "3,3" },
    { x1: 28, y1: 22, x2: 50, y2: 34, c: pc.secondary, w: 0.7, dash: "2,4" },
    { x1: 28, y1: 78, x2: 50, y2: 66, c: pc.accent,    w: 0.7, dash: "2,4" },
  ];

  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 100 100"
      fill="none"
      className={className}
      style={{ display: "block", ...style }}
    >
      <title>Kinrel K-graph icon</title>
      <desc>Kinrel relationship graph icon representing family kinship connections</desc>

      <defs>
        <linearGradient id={`grad-${uid}`} x1="20%" y1="10%" x2="80%" y2="90%">
          <stop offset="0%"   stopColor={pc.primary}/>
          <stop offset="100%" stopColor={pc.secondary}/>
        </linearGradient>
        <radialGradient id={`rbg-${uid}`} cx="35%" cy="50%" r="65%">
          <stop offset="0%"   stopColor={pc.bgInner}/>
          <stop offset="100%" stopColor={pc.bg}/>
        </radialGradient>
        <clipPath id={`clip-${uid}`}>
          <rect width="100" height="100" rx="22" ry="22"/>
        </clipPath>
        {animated && (
          <style>{`
            @keyframes ki-ripple-${uid} {
              0%   { transform: scale(1);   opacity: 0.55; }
              100% { transform: scale(3.4); opacity: 0;    }
            }
            @keyframes ki-pulse-${uid} {
              from { opacity: 0.75; transform: scale(0.96); }
              to   { opacity: 1;    transform: scale(1.05); }
            }
          `}</style>
        )}
      </defs>

      {/* Background */}
      {pc.showBg && (
        <rect width="100" height="100" rx="22" ry="22" fill={`url(#rbg-${uid})`}/>
      )}
      {pc.isOutline && (
        <rect width="100" height="100" rx="22" ry="22"
          stroke={pc.primary} strokeWidth="2" fill="transparent"/>
      )}

      {/* Orbit ring */}
      {pc.showGlow && (
        <circle cx="49" cy="50" r="38"
          stroke={pc.primary} strokeWidth="0.5" strokeOpacity="0.18"
          strokeDasharray="4 6" fill="none"/>
      )}

      <g clipPath={`url(#clip-${uid})`}>
        {/* Edges */}
        {edges.map((e, i) => (
          <line key={i} x1={e.x1} y1={e.y1} x2={e.x2} y2={e.y2}
            stroke={e.c} strokeWidth={e.w}
            strokeOpacity={e.dash ? 0.35 : 0.75}
            strokeDasharray={e.dash}
            strokeLinecap="round"/>
        ))}

        {/* Nodes */}
        {nodes.map((n, i) => (
          <g key={i}>
            {pc.showGlow && (
              <circle cx={n.x} cy={n.y} r={n.r + 3.5} fill={n.c} fillOpacity="0.12"/>
            )}
            <circle
              cx={n.x} cy={n.y} r={n.r}
              fill={pc.isOutline ? "transparent" : n.c}
              stroke={n.c} strokeWidth={pc.isOutline ? 1.5 : 0}
              style={animated && pulse ? {
                transformBox: "fill-box",
                transformOrigin: "center",
                animation: `ki-pulse-${uid} ${1.2 + i * 0.15}s ease-in-out infinite alternate`,
              } : undefined}
            />
            {pc.showGlow && (
              <circle
                cx={n.x - n.r * 0.25}
                cy={n.y - n.r * 0.25}
                r={n.r * 0.35}
                fill="white" fillOpacity="0.38"/>
            )}
          </g>
        ))}

        {/* Center hub orbit ring */}
        {pc.showGlow && (
          <circle cx="28" cy="50" r="9"
            stroke={`url(#grad-${uid})`} strokeWidth="1.2"
            fill="none" strokeOpacity="0.55"/>
        )}
      </g>

      {/* Ripple animation */}
      {animated && pc.showGlow && (
        <circle cx="28" cy="50" r="14"
          stroke={pc.secondary} strokeWidth="1" fill="none" strokeOpacity="0.4"
          style={{
            transformBox: "fill-box",
            transformOrigin: "center",
            animation: `ki-ripple-${uid} 2.5s ease-out infinite`,
          }}
        />
      )}
    </svg>
  );
}
