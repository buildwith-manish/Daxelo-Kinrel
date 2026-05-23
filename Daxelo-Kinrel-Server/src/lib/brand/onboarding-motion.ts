/**
 * DAXELO KINREL — Onboarding Motion Orchestration
 *
 * Defines the splash sequence, carousel pages, family celebration,
 * and first-graph ceremonial reveal animations.
 *
 * Pack 12: Brand & Motion — Onboarding Motion
 */

import type { Variants } from 'framer-motion';

// ── Animation Step Interface ───────────────────────────────────────
export interface AnimationStep {
  id: string;
  label: string;
  durationMs: number;
  delayAfterMs: number;
  properties: Record<string, unknown>;
  easing: string;
}

// ── Carousel Page Interface ────────────────────────────────────────
export interface CarouselPageSpec {
  index: number;
  title: string;
  subtitle: string;
  illustrationName: string;
  animation: {
    type: string;
    durationMs: number;
    easing: string;
  };
  transition: {
    enter: { x: number; opacity: number; durationMs: number; easing: string };
    exit: { x: number; opacity: number; durationMs: number; easing: string };
  };
}

// ── Splash Sequence ────────────────────────────────────────────────
export const SPLASH_SEQUENCE: AnimationStep[] = [
  {
    id: 'root-nodes',
    label: 'Root nodes appear',
    durationMs: 300,
    delayAfterMs: 100,
    properties: { opacity: [0, 1], scale: [0, 1], y: [20, 0] },
    easing: 'cubic-bezier(0.34, 1.56, 0.64, 1)',
  },
  {
    id: 'trunk',
    label: 'Trunk grows upward',
    durationMs: 400,
    delayAfterMs: 100,
    properties: { scaleY: [0, 1], transformOrigin: 'bottom' },
    easing: 'cubic-bezier(0.0, 0.0, 0.2, 1)',
  },
  {
    id: 'branches',
    label: 'Branches extend',
    durationMs: 400,
    delayAfterMs: 100,
    properties: { scaleX: [0, 1], opacity: [0, 1] },
    easing: 'cubic-bezier(0.0, 0.0, 0.2, 1)',
  },
  {
    id: 'canopy',
    label: 'Canopy fills in',
    durationMs: 500,
    delayAfterMs: 100,
    properties: { scale: [0.8, 1], opacity: [0, 1], borderRadius: ['50%', '45%'] },
    easing: 'cubic-bezier(0.34, 1.56, 0.64, 1)',
  },
  {
    id: 'wordmark',
    label: 'KINREL wordmark fades in',
    durationMs: 400,
    delayAfterMs: 100,
    properties: { opacity: [0, 1], y: [10, 0] },
    easing: 'cubic-bezier(0.0, 0.0, 0.2, 1)',
  },
  {
    id: 'pulse',
    label: 'Canopy pulse — heartbeat of the family',
    durationMs: 600,
    delayAfterMs: 0,
    properties: { scale: [1, 1.03, 1] },
    easing: 'cubic-bezier(0.25, 0.1, 0.25, 1)',
  },
  {
    id: 'fade',
    label: 'Splash fades to app',
    durationMs: 300,
    delayAfterMs: 0,
    properties: { opacity: [1, 0] },
    easing: 'cubic-bezier(0.4, 0.0, 1, 1)',
  },
];

// Total splash duration: sum of all durations + delays
export const SPLASH_TOTAL_DURATION_MS = SPLASH_SEQUENCE.reduce(
  (sum, step) => sum + step.durationMs + step.delayAfterMs,
  0,
);

// ── Carousel Pages ─────────────────────────────────────────────────
export const CAROUSEL_PAGES: CarouselPageSpec[] = [
  {
    index: 0,
    title: 'Build Your Family Tree',
    subtitle: 'Start with your name, and watch your family\'s story unfold branch by branch.',
    illustrationName: 'onboarding-build-tree',
    animation: {
      type: 'fadeInUp',
      durationMs: 600,
      easing: 'cubic-bezier(0.0, 0.0, 0.2, 1)',
    },
    transition: {
      enter: { x: 60, opacity: 0, durationMs: 350, easing: 'cubic-bezier(0.0, 0.0, 0.2, 1)' },
      exit: { x: -60, opacity: 0, durationMs: 250, easing: 'cubic-bezier(0.4, 0.0, 1, 1)' },
    },
  },
  {
    index: 1,
    title: 'Invite Your Family',
    subtitle: 'Share in any of 14 languages — even Daadi can join on WhatsApp.',
    illustrationName: 'onboarding-invite-family',
    animation: {
      type: 'scaleIn',
      durationMs: 500,
      easing: 'cubic-bezier(0.34, 1.56, 0.64, 1)',
    },
    transition: {
      enter: { x: 60, opacity: 0, durationMs: 350, easing: 'cubic-bezier(0.0, 0.0, 0.2, 1)' },
      exit: { x: -60, opacity: 0, durationMs: 250, easing: 'cubic-bezier(0.4, 0.0, 1, 1)' },
    },
  },
  {
    index: 2,
    title: 'Celebrate Together',
    subtitle: 'Birthdays, festivals, milestones — KINREL keeps your family connected across every occasion.',
    illustrationName: 'onboarding-celebrate',
    animation: {
      type: 'fadeInUp',
      durationMs: 600,
      easing: 'cubic-bezier(0.0, 0.0, 0.2, 1)',
    },
    transition: {
      enter: { x: 60, opacity: 0, durationMs: 350, easing: 'cubic-bezier(0.0, 0.0, 0.2, 1)' },
      exit: { x: -60, opacity: 0, durationMs: 250, easing: 'cubic-bezier(0.4, 0.0, 1, 1)' },
    },
  },
];

// ── Family Celebration ─────────────────────────────────────────────
export const FAMILY_CELEBRATION = {
  type: 'scale+fade' as const,
  durationMs: 800,
  easing: 'cubic-bezier(0.68, -0.6, 0.32, 1.6)', // elasticOut
  properties: {
    scale: [0.8, 1.1, 1],
    opacity: [0, 1],
  },
} as const;

// ── First Graph Sequence ───────────────────────────────────────────
export const FIRST_GRAPH_SEQUENCE: AnimationStep[] = [
  {
    id: 'canvas-reveal',
    label: 'Canvas fades in with subtle gradient',
    durationMs: 300,
    delayAfterMs: 100,
    properties: { opacity: [0, 1] },
    easing: 'cubic-bezier(0.0, 0.0, 0.2, 1)',
  },
  {
    id: 'center-node',
    label: 'Center node (you) appears with gentle bounce',
    durationMs: 500,
    delayAfterMs: 200,
    properties: { scale: [0, 1.15, 1], opacity: [0, 1] },
    easing: 'cubic-bezier(0.34, 1.56, 0.64, 1)',
  },
  {
    id: 'members-branch',
    label: 'Family members branch outward with stagger',
    durationMs: 600,
    delayAfterMs: 150,
    properties: { scale: [0.5, 1], opacity: [0, 1], x: [0, 'auto'] },
    easing: 'cubic-bezier(0.0, 0.0, 0.2, 1)',
  },
  {
    id: 'labels-appear',
    label: 'Relationship labels fade in below nodes',
    durationMs: 400,
    delayAfterMs: 100,
    properties: { opacity: [0, 1], y: [5, 0] },
    easing: 'cubic-bezier(0.0, 0.0, 0.2, 1)',
  },
  {
    id: 'auto-fit',
    label: 'Graph auto-fits to show all nodes',
    durationMs: 500,
    delayAfterMs: 0,
    properties: { scale: [1.2, 1], x: [20, 0], y: [10, 0] },
    easing: 'cubic-bezier(0.0, 0.0, 0.2, 1)',
  },
  {
    id: 'ambient-bob',
    label: 'Nodes enter gentle ambient bob — the tree is alive',
    durationMs: 3000,
    delayAfterMs: 0,
    properties: { y: [-2, 2, -2] },
    easing: 'cubic-bezier(0.25, 0.1, 0.25, 1)',
  },
];

// ── Getter Functions ───────────────────────────────────────────────

export function getSplashSequence(): AnimationStep[] {
  return SPLASH_SEQUENCE;
}

export function getCarouselPage(index: number): CarouselPageSpec {
  return CAROUSEL_PAGES[index] ?? CAROUSEL_PAGES[0];
}

export function getFamilyCelebration(): Variants {
  return {
    hidden: {
      scale: 0.8,
      opacity: 0,
    },
    visible: {
      scale: [0.8, 1.1, 1],
      opacity: 1,
      transition: {
        duration: FAMILY_CELEBRATION.durationMs / 1000,
        ease: [0.68, -0.6, 0.32, 1.6] as [number, number, number, number],
      },
    },
  };
}

export function getFirstGraphSequence(): AnimationStep[] {
  return FIRST_GRAPH_SEQUENCE;
}
