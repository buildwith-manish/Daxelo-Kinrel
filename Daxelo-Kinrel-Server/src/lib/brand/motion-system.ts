/**
 * DAXELO KINREL — Motion System
 *
 * Animation system with duration tokens, easing curves,
 * framer-motion variants, and reduced motion support.
 *
 * Pack 12: Brand & Motion — Motion System
 */

import type { Variants, Transition, Spring } from 'framer-motion';

// ── Duration Scale ─────────────────────────────────────────────────
export const DurationScale = {
  instant: 50,
  fast: 100,
  normal: 200,
  moderate: 350,
  slow: 500,
  ceremonial: 800,
  lingering: 1200,
} as const;

export type DurationToken = keyof typeof DurationScale;

// ── Easing Curves ──────────────────────────────────────────────────
export interface EasingCurve {
  name: string;
  css: string;
  framerMotion: number[];
  useCase: string;
}

export const EasingCurves: Record<string, EasingCurve> = {
  standard: {
    name: 'Standard',
    css: 'cubic-bezier(0.4, 0.0, 0.2, 1)',
    framerMotion: [0.4, 0, 0.2, 1],
    useCase: 'General transitions, color changes, opacity',
  },
  decelerate: {
    name: 'Decelerate',
    css: 'cubic-bezier(0.0, 0.0, 0.2, 1)',
    framerMotion: [0, 0, 0.2, 1],
    useCase: 'Elements entering the screen (fade in, slide in)',
  },
  accelerate: {
    name: 'Accelerate',
    css: 'cubic-bezier(0.4, 0.0, 1, 1)',
    framerMotion: [0.4, 0, 1, 1],
    useCase: 'Elements leaving the screen (fade out, slide out)',
  },
  overshoot: {
    name: 'Overshoot',
    css: 'cubic-bezier(0.68, -0.6, 0.32, 1.6)',
    framerMotion: [0.68, -0.6, 0.32, 1.6],
    useCase: 'Playful emphasis, button tap completion, badge unlock',
  },
  gentleBounce: {
    name: 'Gentle Bounce',
    css: 'cubic-bezier(0.34, 1.56, 0.64, 1)',
    framerMotion: [0.34, 1.56, 0.64, 1],
    useCase: 'Node addition, celebration elements, FAB morph',
  },
  smooth: {
    name: 'Smooth',
    css: 'cubic-bezier(0.25, 0.1, 0.25, 1)',
    framerMotion: [0.25, 0.1, 0.25, 1],
    useCase: 'Continuous animations, ambient motion, gentle loops',
  },
};

export type EasingToken = keyof typeof EasingCurves;

// ── Animation Categories ───────────────────────────────────────────
export const ANIMATION_CATEGORIES = {
  structural: {
    name: 'Structural',
    description: 'Layout changes, page transitions, element reordering',
    maxDuration: DurationScale.moderate,
    requiresReducedMotionAlternative: true,
    examples: ['Page transition', 'Tab switch', 'List reorder', 'Drawer open/close'],
  },
  feedback: {
    name: 'Feedback',
    description: 'User action confirmation, state changes, micro-interactions',
    maxDuration: DurationScale.normal,
    requiresReducedMotionAlternative: false,
    examples: ['Button press', 'Toggle switch', 'Checkbox tick', 'Toast appear'],
  },
  dataViz: {
    name: 'DataViz',
    description: 'Graph rendering, chart animations, tree visualizations',
    maxDuration: DurationScale.slow,
    requiresReducedMotionAlternative: true,
    examples: ['Tree node appear', 'Edge draw', 'Chart bar grow', 'Pie slice expand'],
  },
  celebratory: {
    name: 'Celebratory',
    description: 'Festival themes, milestone celebrations, achievement badges',
    maxDuration: DurationScale.ceremonial,
    requiresReducedMotionAlternative: true,
    examples: ['Confetti burst', 'Festival theme transition', 'Badge unlock', 'Birthday animation'],
  },
} as const;

// ── Performance Budget ─────────────────────────────────────────────
export const PERFORMANCE_BUDGET = {
  targetFPS: 60,
  maxMainThreadMs: 5,
  maxAnimationJS: 15, // KB
  maxSimultaneousAnimations: 12,
  willChangeProperties: ['transform', 'opacity'] as const,
  gpuAcceleratedProperties: ['transform', 'opacity', 'filter'] as const,
} as const;

// ── Utility Functions ──────────────────────────────────────────────

export function getDuration(token: DurationToken, prefersReducedMotion: boolean): number {
  if (prefersReducedMotion) return 0;
  return DurationScale[token];
}

export function getCurve(token: EasingToken, prefersReducedMotion: boolean): string {
  if (prefersReducedMotion) return 'linear';
  return EasingCurves[token].css;
}

export function shouldReduceMotion(): boolean {
  if (typeof window === 'undefined') return false;
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches;
}

export function staggerDelay(index: number, base: number = 30): number {
  return index * base;
}

export function createSpring(config: {
  stiffness?: number;
  damping?: number;
  mass?: number;
}): Transition {
  return {
    type: 'spring',
    stiffness: config.stiffness ?? 300,
    damping: config.damping ?? 25,
    mass: config.mass ?? 1,
  };
}

// ── Framer Motion Variants ─────────────────────────────────────────

export function fadeInUp(delay: number = 0): Variants {
  return {
    hidden: {
      opacity: 0,
      y: 20,
    },
    visible: {
      opacity: 1,
      y: 0,
      transition: {
        duration: DurationScale.normal / 1000,
        ease: EasingCurves.decelerate.framerMotion as [number, number, number, number],
        delay,
      },
    },
  };
}

export function fadeOut(delay: number = 0): Variants {
  return {
    visible: {
      opacity: 1,
    },
    hidden: {
      opacity: 0,
      transition: {
        duration: DurationScale.fast / 1000,
        ease: EasingCurves.accelerate.framerMotion as [number, number, number, number],
        delay,
      },
    },
  };
}

export function scaleIn(delay: number = 0): Variants {
  return {
    hidden: {
      opacity: 0,
      scale: 0.5,
    },
    visible: {
      opacity: 1,
      scale: 1,
      transition: {
        duration: DurationScale.moderate / 1000,
        ease: EasingCurves.gentleBounce.framerMotion as [number, number, number, number],
        delay,
      },
    },
  };
}

export function slideInRight(delay: number = 0): Variants {
  return {
    hidden: {
      opacity: 0,
      x: 60,
    },
    visible: {
      opacity: 1,
      x: 0,
      transition: {
        duration: DurationScale.moderate / 1000,
        ease: EasingCurves.decelerate.framerMotion as [number, number, number, number],
        delay,
      },
    },
  };
}

export function slideInLeft(delay: number = 0): Variants {
  return {
    hidden: {
      opacity: 0,
      x: -60,
    },
    visible: {
      opacity: 1,
      x: 0,
      transition: {
        duration: DurationScale.moderate / 1000,
        ease: EasingCurves.decelerate.framerMotion as [number, number, number, number],
        delay,
      },
    },
  };
}

export const staggerContainer: Variants = {
  hidden: { opacity: 0 },
  visible: {
    opacity: 1,
    transition: {
      staggerChildren: 0.03,
      delayChildren: 0.05,
    },
  },
};

export const celebrationBurst: Variants = {
  hidden: {
    opacity: 0,
    scale: 0,
  },
  visible: {
    opacity: 1,
    scale: 1,
    transition: {
      type: 'spring' as const,
      stiffness: 400,
      damping: 15,
      mass: 0.8,
    },
  },
  exit: {
    opacity: 0,
    scale: 0,
    transition: {
      duration: DurationScale.fast / 1000,
    },
  },
};

// ── Transition Helpers ─────────────────────────────────────────────

export function createTransition(
  durationToken: DurationToken = 'normal',
  curveToken: EasingToken = 'standard',
  delayMs: number = 0,
): Transition {
  return {
    duration: DurationScale[durationToken] / 1000,
    ease: EasingCurves[curveToken].framerMotion as [number, number, number, number],
    delay: delayMs / 1000,
  };
}

export function createSpringTransition(
  stiffness: number = 300,
  damping: number = 25,
): Transition {
  return {
    type: 'spring' as const,
    stiffness,
    damping,
  };
}
