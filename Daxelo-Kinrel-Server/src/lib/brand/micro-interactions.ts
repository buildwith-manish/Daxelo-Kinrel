/**
 * DAXELO KINREL — Micro-Interaction Specifications
 *
 * Defines all micro-interaction specifications for buttons, toggles,
 * cards, forms, navigation, data states, graph, and feedback
 * with Framer Motion variant generators.
 *
 * Pack 12: Brand & Motion — Micro-Interactions
 */

import type { Variants } from 'framer-motion';

// ── Button Interactions ────────────────────────────────────────────
export interface ButtonInteractionSpec {
  press: { scale: number; duration: number };
  release: { scale: number; duration: number; easing: string };
  disabled: { opacity: number; scale: number };
  tapComplete: { scale: number; duration: number; easing: string };
}

export const ButtonInteractions: Record<string, ButtonInteractionSpec> = {
  primary: {
    press: { scale: 0.97, duration: 100 },
    release: { scale: 1, duration: 200, easing: 'cubic-bezier(0.34, 1.56, 0.64, 1)' },
    disabled: { opacity: 0.5, scale: 1 },
    tapComplete: { scale: 1.02, duration: 150, easing: 'cubic-bezier(0.34, 1.56, 0.64, 1)' },
  },
  secondary: {
    press: { scale: 0.97, duration: 100 },
    release: { scale: 1, duration: 200, easing: 'cubic-bezier(0.34, 1.56, 0.64, 1)' },
    disabled: { opacity: 0.5, scale: 1 },
    tapComplete: { scale: 1.02, duration: 150, easing: 'cubic-bezier(0.34, 1.56, 0.64, 1)' },
  },
  outline: {
    press: { scale: 0.97, duration: 100 },
    release: { scale: 1, duration: 200, easing: 'cubic-bezier(0.34, 1.56, 0.64, 1)' },
    disabled: { opacity: 0.5, scale: 1 },
    tapComplete: { scale: 1.01, duration: 150, easing: 'cubic-bezier(0.34, 1.56, 0.64, 1)' },
  },
  ghost: {
    press: { scale: 0.97, duration: 100 },
    release: { scale: 1, duration: 200, easing: 'cubic-bezier(0.25, 0.1, 0.25, 1)' },
    disabled: { opacity: 0.38, scale: 1 },
    tapComplete: { scale: 1, duration: 100, easing: 'cubic-bezier(0.25, 0.1, 0.25, 1)' },
  },
  icon: {
    press: { scale: 0.9, duration: 80 },
    release: { scale: 1, duration: 200, easing: 'cubic-bezier(0.34, 1.56, 0.64, 1)' },
    disabled: { opacity: 0.38, scale: 1 },
    tapComplete: { scale: 1.1, duration: 150, easing: 'cubic-bezier(0.34, 1.56, 0.64, 1)' },
  },
  fab: {
    press: { scale: 0.95, duration: 100 },
    release: { scale: 1, duration: 300, easing: 'cubic-bezier(0.34, 1.56, 0.64, 1)' },
    disabled: { opacity: 0.5, scale: 1 },
    tapComplete: { scale: 1.05, duration: 200, easing: 'cubic-bezier(0.34, 1.56, 0.64, 1)' },
  },
  destructive: {
    press: { scale: 0.97, duration: 100 },
    release: { scale: 1, duration: 200, easing: 'cubic-bezier(0.34, 1.56, 0.64, 1)' },
    disabled: { opacity: 0.5, scale: 1 },
    tapComplete: { scale: 1, duration: 100, easing: 'cubic-bezier(0.4, 0, 0.2, 1)' },
  },
};

// ── Toggle Interactions ────────────────────────────────────────────
export const ToggleInteractions = {
  switch: {
    on: { thumbX: 20, duration: 200, easing: 'cubic-bezier(0.34, 1.56, 0.64, 1)' },
    off: { thumbX: 0, duration: 200, easing: 'cubic-bezier(0.4, 0, 0.2, 1)' },
  },
  checkbox: {
    on: { scale: 1.15, duration: 150, easing: 'cubic-bezier(0.34, 1.56, 0.64, 1)', checkDraw: 200 },
    off: { scale: 1, duration: 100, easing: 'cubic-bezier(0.4, 0, 0.2, 1)' },
  },
  radio: {
    on: { dotScale: 1, duration: 150, easing: 'cubic-bezier(0.34, 1.56, 0.64, 1)' },
    off: { dotScale: 0, duration: 100, easing: 'cubic-bezier(0.4, 0, 0.2, 1)' },
  },
} as const;

// ── Card Interactions ──────────────────────────────────────────────
export interface CardInteractionSpec {
  tap: { scale: number; duration: number; elevation: number };
  longPress: { scale: number; duration: number; selectionRing: boolean };
  swipe: { threshold: number; velocity: number };
}

export const CardInteractions: Record<string, CardInteractionSpec> = {
  personCard: {
    tap: { scale: 0.98, duration: 100, elevation: 4 },
    longPress: { scale: 1.02, duration: 300, selectionRing: true },
    swipe: { threshold: 80, velocity: 500 },
  },
  familyCard: {
    tap: { scale: 0.98, duration: 100, elevation: 2 },
    longPress: { scale: 1.01, duration: 400, selectionRing: false },
    swipe: { threshold: 100, velocity: 400 },
  },
};

// ── Form Interactions ──────────────────────────────────────────────
export const FormInteractions = {
  input: {
    focus: { borderWidth: 2, borderColor: '#F97316', duration: 150 },
    error: { shake: { x: [-4, 4, -4, 4, 0], duration: 300 }, borderColor: '#EF4444' },
    valid: { borderColor: '#22C55E', checkDraw: 200 },
    typing: { cursorBlink: 530 },
  },
  dropdown: {
    focus: { borderWidth: 2, borderColor: '#F97316', duration: 150 },
    open: { scaleY: [0.95, 1], opacity: [0, 1], duration: 150 },
    close: { scaleY: [1, 0.95], opacity: [1, 0], duration: 100 },
    select: { highlightBg: '#FFF7ED', duration: 100 },
  },
  textarea: {
    focus: { borderWidth: 2, borderColor: '#F97316', duration: 150 },
    error: { borderColor: '#EF4444', shake: { x: [-4, 4, -4, 4, 0], duration: 300 } },
    valid: { borderColor: '#22C55E' },
    autoResize: { duration: 100, easing: 'cubic-bezier(0.4, 0, 0.2, 1)' },
  },
  datePicker: {
    focus: { borderColor: '#F97316', duration: 150 },
    open: { scale: [0.95, 1], opacity: [0, 1], duration: 200, easing: 'cubic-bezier(0.34, 1.56, 0.64, 1)' },
    select: { highlight: '#FFF7ED', duration: 100 },
  },
} as const;

// ── Navigation Interactions ────────────────────────────────────────
export const NavigationInteractions = {
  bottomNav: {
    morph: { duration: 300, easing: 'cubic-bezier(0.34, 1.56, 0.64, 1)', indicatorWidth: 32 },
    slide: { x: [-20, 0], opacity: [0, 1], duration: 200 },
    fade: { opacity: [0.5, 1], duration: 150 },
  },
  drawer: {
    slideIn: { x: [-280, 0], duration: 300, easing: 'cubic-bezier(0.0, 0.0, 0.2, 1)' },
    slideOut: { x: [0, -280], duration: 250, easing: 'cubic-bezier(0.4, 0.0, 1, 1)' },
    scrimFade: { opacity: [0, 0.32], duration: 300 },
  },
  tabSwitch: {
    morph: { width: 'auto', duration: 250, easing: 'cubic-bezier(0.34, 1.56, 0.64, 1)' },
    contentSlide: { x: [30, 0], opacity: [0, 1], duration: 200, easing: 'cubic-bezier(0.0, 0.0, 0.2, 1)' },
    fade: { opacity: [0, 1], duration: 150 },
  },
  pageTransition: {
    slideRight: { x: ['100%', '0%'], duration: 350, easing: 'cubic-bezier(0.0, 0.0, 0.2, 1)' },
    slideLeft: { x: ['0%', '-30%'], duration: 350, easing: 'cubic-bezier(0.4, 0.0, 1, 1)' },
    fade: { opacity: [0, 1], duration: 200 },
  },
} as const;

// ── Data State Interactions ────────────────────────────────────────
export const DataStateInteractions = {
  loading: {
    shimmer: { duration: 1500, easing: 'linear', direction: 'alternate' as const },
    skeletonPulse: { opacity: [0.4, 1], duration: 800, repeatType: 'reverse' as const },
    spinner: { rotate: 360, duration: 1000, repeat: Infinity },
  },
  loaded: {
    fadeIn: { opacity: [0, 1], duration: 200, easing: 'cubic-bezier(0.0, 0.0, 0.2, 1)' },
    staggerIn: { y: [10, 0], opacity: [0, 1], duration: 200, stagger: 30 },
  },
  empty: {
    fadeIn: { opacity: [0, 1], duration: 300, easing: 'cubic-bezier(0.25, 0.1, 0.25, 1)' },
    gentleFloat: { y: [-5, 5], duration: 2000, repeatType: 'reverse' as const, easing: 'cubic-bezier(0.25, 0.1, 0.25, 1)' },
  },
  pullToRefresh: {
    pullDown: { y: 0, stiffness: 300, damping: 25 },
    release: { y: [0, -40, 0], duration: 500, easing: 'cubic-bezier(0.34, 1.56, 0.64, 1)' },
    refreshIndicator: { rotate: 360, duration: 800, repeat: Infinity },
  },
  refreshComplete: {
    checkmark: { pathLength: [0, 1], duration: 300, easing: 'cubic-bezier(0.34, 1.56, 0.64, 1)' },
    fadeOut: { opacity: [1, 0], duration: 200, delay: 500 },
  },
  infiniteScroll: {
    loaderAppear: { opacity: [0, 1], duration: 200 },
    loaderDisappear: { opacity: [1, 0], duration: 150 },
  },
} as const;

// ── Graph Interactions ─────────────────────────────────────────────
export interface GraphInteractionSpec {
  type: string;
  animation: { property: string; from: number; to: number; duration: number; easing: string };
  trigger: string;
}

export const GraphInteractions: GraphInteractionSpec[] = [
  {
    type: 'nodeAppear',
    animation: { property: 'scale+opacity', from: 0, to: 1, duration: 350, easing: 'cubic-bezier(0.34, 1.56, 0.64, 1)' },
    trigger: 'node added to graph',
  },
  {
    type: 'nodeTap',
    animation: { property: 'scale', from: 1, to: 1.08, duration: 100, easing: 'cubic-bezier(0.34, 1.56, 0.64, 1)' },
    trigger: 'user taps node',
  },
  {
    type: 'nodePulse',
    animation: { property: 'scale', from: 1, to: 1.05, duration: 600, easing: 'cubic-bezier(0.25, 0.1, 0.25, 1)' },
    trigger: 'node is selected/highlighted',
  },
  {
    type: 'edgeDraw',
    animation: { property: 'strokeDashoffset', from: 100, to: 0, duration: 500, easing: 'cubic-bezier(0.0, 0.0, 0.2, 1)' },
    trigger: 'edge appears',
  },
  {
    type: 'graphAutoFit',
    animation: { property: 'transform', from: 0, to: 1, duration: 500, easing: 'cubic-bezier(0.0, 0.0, 0.2, 1)' },
    trigger: 'after adding nodes',
  },
  {
    type: 'graphDrag',
    animation: { property: 'translate', from: 0, to: 0, duration: 0, easing: 'linear' },
    trigger: 'user drags canvas',
  },
  {
    type: 'ambientBob',
    animation: { property: 'y', from: -2, to: 2, duration: 3000, easing: 'cubic-bezier(0.25, 0.1, 0.25, 1)' },
    trigger: 'idle state after 5s',
  },
];

// ── Feedback Interactions ──────────────────────────────────────────
export const FeedbackInteractions = {
  saveSuccess: {
    checkmark: { pathLength: [0, 1], duration: 300, easing: 'cubic-bezier(0.34, 1.56, 0.64, 1)' },
    text: { opacity: [0, 1], y: [5, 0], duration: 200, delay: 100 },
    fadeOut: { opacity: [1, 0], y: [0, -10], duration: 200, delay: 2000 },
  },
  deleteSuccess: {
    slideLeft: { x: [0, -300], opacity: [1, 0], duration: 300, easing: 'cubic-bezier(0.4, 0.0, 1, 1)' },
    listCollapse: { height: 'auto', duration: 200, easing: 'cubic-bezier(0.4, 0, 0.2, 1)' },
  },
  errorBanner: {
    slideDown: { y: [-60, 0], opacity: [0, 1], duration: 300, easing: 'cubic-bezier(0.0, 0.0, 0.2, 1)' },
    slideUp: { y: [0, -60], opacity: [1, 0], duration: 200, easing: 'cubic-bezier(0.4, 0.0, 1, 1)' },
    shake: { x: [-4, 4, -4, 4, 0], duration: 300 },
  },
  validationError: {
    shake: { x: [-4, 4, -4, 4, 0], duration: 300 },
    borderFlash: { borderColor: '#EF4444', duration: 200 },
    labelAppear: { opacity: [0, 1], y: [-5, 0], duration: 200 },
  },
  undo: {
    slideBack: { x: [-300, 0], opacity: [0, 1], duration: 300, easing: 'cubic-bezier(0.0, 0.0, 0.2, 1)' },
  },
  achievement: {
    badgeDrop: { scale: [0, 1.2, 1], duration: 500, easing: 'cubic-bezier(0.34, 1.56, 0.64, 1)' },
    sparkle: { scale: [0, 1.5, 0], opacity: [0, 1, 0], duration: 600, stagger: 50 },
    textAppear: { opacity: [0, 1], y: [10, 0], duration: 200, delay: 300 },
  },
} as const;

// ── Framer Motion Variant Generators ───────────────────────────────

export function getButtonVariant(variant: string): Variants {
  const spec = ButtonInteractions[variant];
  if (!spec) return {};

  return {
    tap: {
      scale: spec.press.scale,
      transition: { duration: spec.press.duration / 1000 },
    },
    hover: {
      scale: 1.01,
      transition: { duration: 0.15 },
    },
    disabled: {
      opacity: spec.disabled.opacity,
      scale: spec.disabled.scale,
    },
    initial: {
      scale: 1,
    },
    animate: {
      scale: 1,
      transition: {
        duration: spec.release.duration / 1000,
        ease: [0.34, 1.56, 0.64, 1] as [number, number, number, number],
      },
    },
  };
}

export function getCardInteraction(type: string): Variants {
  const spec = CardInteractions[type];
  if (!spec) return {};

  return {
    tap: {
      scale: spec.tap.scale,
      transition: { duration: spec.tap.duration / 1000 },
    },
    longPress: {
      scale: spec.longPress.scale,
      boxShadow: spec.longPress.selectionRing
        ? '0 0 0 3px #F97316'
        : undefined,
      transition: { duration: spec.longPress.duration / 1000 },
    },
    hover: {
      y: -2,
      boxShadow: '0 4px 12px rgba(0,0,0,0.1)',
      transition: { duration: 0.2 },
    },
    initial: { scale: 1 },
    animate: { scale: 1 },
  };
}

export function getFormInteraction(state: string): Variants {
  switch (state) {
    case 'focus':
      return {
        initial: { borderColor: '#A8A29E' },
        animate: {
          borderColor: '#F97316',
          transition: { duration: 0.15 },
        },
      };
    case 'error':
      return {
        animate: {
          x: [-4, 4, -4, 4, 0],
          borderColor: '#EF4444',
          transition: { duration: 0.3 },
        },
      };
    case 'valid':
      return {
        animate: {
          borderColor: '#22C55E',
          transition: { duration: 0.2 },
        },
      };
    case 'typing':
      return {
        animate: {
          transition: { duration: 0.1 },
        },
      };
    default:
      return {};
  }
}

export function getGraphInteraction(type: string): Variants {
  switch (type) {
    case 'nodeAppear':
      return {
        hidden: { opacity: 0, scale: 0.5 },
        visible: {
          opacity: 1,
          scale: 1,
          transition: {
            duration: 0.35,
            ease: [0.34, 1.56, 0.64, 1] as [number, number, number, number],
          },
        },
      };
    case 'nodeTap':
      return {
        tap: {
          scale: 1.08,
          transition: { duration: 0.1 },
        },
        animate: {
          scale: 1,
          transition: { duration: 0.2, ease: [0.34, 1.56, 0.64, 1] as [number, number, number, number] },
        },
      };
    case 'nodePulse':
      return {
        animate: {
          scale: [1, 1.05, 1],
          transition: {
            duration: 0.6,
            repeat: Infinity,
            ease: 'easeInOut' as const,
          },
        },
      };
    case 'edgeDraw':
      return {
        hidden: { pathLength: 0, opacity: 0 },
        visible: {
          pathLength: 1,
          opacity: 1,
          transition: {
            pathLength: { duration: 0.5, ease: [0, 0, 0.2, 1] as [number, number, number, number] },
            opacity: { duration: 0.2 },
          },
        },
      };
    case 'ambientBob':
      return {
        animate: {
          y: [-2, 2, -2],
          transition: {
            duration: 3,
            repeat: Infinity,
            ease: 'easeInOut' as const,
          },
        },
      };
    default:
      return {};
  }
}

export function getFeedbackAnimation(type: string): Variants {
  switch (type) {
    case 'saveSuccess':
      return {
        hidden: { opacity: 0, y: 10 },
        visible: {
          opacity: 1,
          y: 0,
          transition: { duration: 0.3, ease: [0.34, 1.56, 0.64, 1] as [number, number, number, number] },
        },
        exit: {
          opacity: 0,
          y: -10,
          transition: { duration: 0.2, delay: 2 },
        },
      };
    case 'deleteSuccess':
      return {
        initial: { x: 0, opacity: 1 },
        animate: {
          x: -300,
          opacity: 0,
          transition: { duration: 0.3, ease: [0.4, 0, 1, 1] as [number, number, number, number] },
        },
      };
    case 'errorBanner':
      return {
        hidden: { y: -60, opacity: 0 },
        visible: {
          y: 0,
          opacity: 1,
          transition: { duration: 0.3, ease: [0, 0, 0.2, 1] as [number, number, number, number] },
        },
        exit: {
          y: -60,
          opacity: 0,
          transition: { duration: 0.2, ease: [0.4, 0, 1, 1] as [number, number, number, number] },
        },
      };
    case 'validationError':
      return {
        animate: {
          x: [-4, 4, -4, 4, 0],
          transition: { duration: 0.3 },
        },
      };
    case 'undo':
      return {
        hidden: { x: -300, opacity: 0 },
        visible: {
          x: 0,
          opacity: 1,
          transition: { duration: 0.3, ease: [0, 0, 0.2, 1] as [number, number, number, number] },
        },
      };
    case 'achievement':
      return {
        hidden: { scale: 0, opacity: 0 },
        visible: {
          scale: [0, 1.2, 1],
          opacity: 1,
          transition: { duration: 0.5, ease: [0.34, 1.56, 0.64, 1] as [number, number, number, number] },
        },
        exit: {
          scale: 0,
          opacity: 0,
          transition: { duration: 0.2 },
        },
      };
    default:
      return {};
  }
}
