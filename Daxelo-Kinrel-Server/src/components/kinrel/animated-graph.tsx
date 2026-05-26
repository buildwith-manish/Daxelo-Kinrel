'use client';

/**
 * DAXELO KINREL — Animated Graph Components
 *
 * Framer Motion-powered graph node, edge, and celebration
 * components for the family tree visualization.
 *
 * Pack 12: Brand & Motion — Animated Graph
 */

import React, { forwardRef, useEffect, useState, useCallback } from 'react';
import { motion, AnimatePresence, type HTMLMotionProps } from 'framer-motion';
import { cn } from '@/lib/utils';
import { getGraphInteraction } from '@/lib/brand/micro-interactions';
import { staggerDelay } from '@/lib/brand/motion-system';

// ── AnimatedGraphNode ──────────────────────────────────────────────
export interface AnimatedGraphNodeProps extends Omit<HTMLMotionProps<'div'>, 'onAnimationComplete'> {
  name: string;
  relation?: string;
  index?: number;
  isSelected?: boolean;
  isDeceased?: boolean;
  onClick?: () => void;
  avatarInitial?: string;
  color?: string;
}

export const AnimatedGraphNode = forwardRef<HTMLDivElement, AnimatedGraphNodeProps>(
  ({ name, relation, index = 0, isSelected = false, isDeceased = false, onClick, avatarInitial, color, className, ...props }, ref) => {
    const nodeAppearVariants = getGraphInteraction('nodeAppear');
    const nodeTapVariants = getGraphInteraction('nodeTap');
    const nodePulseVariants = getGraphInteraction('nodePulse');

    return (
      <motion.div
        ref={ref}
        variants={nodeAppearVariants}
        initial="hidden"
        animate="visible"
        whileTap="tap"
        custom={index}
        transition={{ delay: staggerDelay(index, 50) / 1000 }}
        onClick={onClick}
        className={cn(
          'relative flex flex-col items-center gap-1 cursor-pointer select-none',
          className,
        )}
        {...props}
      >
        {/* Pulse ring when selected */}
        {isSelected && (
          <motion.div
            variants={nodePulseVariants}
            animate="animate"
            className="absolute -inset-2 rounded-full border-2 border-[#F97316] opacity-60"
          />
        )}

        {/* Node circle */}
        <motion.div
          whileTap={{ scale: 1.08 }}
          className={cn(
            'flex h-12 w-12 items-center justify-center rounded-full text-sm font-bold shadow-md transition-colors',
            color ?? 'bg-[#F97316] text-white',
            isDeceased && 'opacity-60 border-2 border-[#A8A29E]',
            isSelected && 'ring-2 ring-[#F97316] ring-offset-2',
          )}
        >
          {avatarInitial ?? name.charAt(0).toUpperCase()}
        </motion.div>

        {/* Deceased indicator */}
        {isDeceased && (
          <div className="absolute -top-1 -right-1 flex h-4 w-4 items-center justify-center rounded-full bg-[#A8A29E]">
            <svg width="8" height="8" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="3" strokeLinecap="round">
              <path d="M18 6L6 18M6 6l12 12" />
            </svg>
          </div>
        )}

        {/* Name and relation */}
        <div className="flex flex-col items-center gap-0 max-w-[80px]">
          <span className={cn(
            'text-xs font-semibold truncate w-full text-center',
            isDeceased ? 'text-[#A8A29E]' : 'text-[#1C1917] dark:text-[#F5F5F4]',
          )}>
            {name}
          </span>
          {relation && (
            <span className="text-[10px] text-[#57534E] dark:text-[#A8A29E] truncate w-full text-center">
              {relation}
            </span>
          )}
        </div>
      </motion.div>
    );
  },
);
AnimatedGraphNode.displayName = 'AnimatedGraphNode';

// ── AnimatedGraphEdge ──────────────────────────────────────────────
export interface AnimatedGraphEdgeProps {
  fromX: number;
  fromY: number;
  toX: number;
  toY: number;
  type?: 'parent' | 'spouse' | 'sibling';
  animated?: boolean;
  className?: string;
}

export function AnimatedGraphEdge({
  fromX,
  fromY,
  toX,
  toY,
  type = 'parent',
  animated = true,
  className,
}: AnimatedGraphEdgeProps) {
  const edgeDrawVariants = getGraphInteraction('edgeDraw');

  const colorMap = {
    parent: '#F97316',
    spouse: '#E94560',
    sibling: '#14B8A6',
  };

  const dashMap = {
    parent: '',
    spouse: '6,3',
    sibling: '2,4',
  };

  const midY = (fromY + toY) / 2;
  const pathData = `M ${fromX} ${fromY} C ${fromX} ${midY}, ${toX} ${midY}, ${toX} ${toY}`;

  return (
    <motion.svg
      className={cn('absolute inset-0 pointer-events-none', className)}
      style={{ overflow: 'visible' }}
    >
      <motion.path
        d={pathData}
        fill="none"
        stroke={colorMap[type]}
        strokeWidth={2}
        strokeDasharray={dashMap[type] || undefined}
        variants={animated ? edgeDrawVariants : undefined}
        initial={animated ? 'hidden' : undefined}
        animate={animated ? 'visible' : undefined}
        style={!animated ? { opacity: 1, pathLength: 1 } : undefined}
      />
    </motion.svg>
  );
}

// ── NewNodeCelebration ─────────────────────────────────────────────
export interface NewNodeCelebrationProps {
  x: number;
  y: number;
  visible: boolean;
  onDismiss?: () => void;
  color?: string;
}

interface ConfettiParticle {
  id: number;
  angle: number;
  distance: number;
  size: number;
  color: string;
  delay: number;
}

export function NewNodeCelebration({
  x,
  y,
  visible,
  onDismiss,
  color = '#F97316',
}: NewNodeCelebrationProps) {
  const [particles] = useState<ConfettiParticle[]>(() => {
    const colors = ['#F97316', '#FFD700', '#E94560', '#14B8A6', '#22C55E'];
    return Array.from({ length: 12 }, (_, i) => ({
      id: i,
      angle: (i * 360) / 12,
      distance: 40 + Math.random() * 30,
      size: 4 + Math.random() * 4,
      color: colors[i % colors.length],
      delay: i * 30,
    }));
  });

  useEffect(() => {
    if (visible) {
      const timer = setTimeout(() => {
        onDismiss?.();
      }, 800);
      return () => clearTimeout(timer);
    }
  }, [visible, onDismiss]);

  return (
    <AnimatePresence>
      {visible && (
        <div className="absolute pointer-events-none" style={{ left: x, top: y, zIndex: 50 }}>
          {particles.map((particle) => {
            const rad = (particle.angle * Math.PI) / 180;
            const tx = Math.cos(rad) * particle.distance;
            const ty = Math.sin(rad) * particle.distance;

            return (
              <motion.div
                key={particle.id}
                className="absolute rounded-full"
                style={{
                  width: particle.size,
                  height: particle.size,
                  backgroundColor: particle.color,
                  left: -particle.size / 2,
                  top: -particle.size / 2,
                }}
                initial={{ x: 0, y: 0, scale: 0, opacity: 1 }}
                animate={{ x: tx, y: ty, scale: 1, opacity: 0 }}
                transition={{
                  duration: 0.6,
                  delay: particle.delay / 1000,
                  ease: [0.34, 1.56, 0.64, 1] as [number, number, number, number],
                }}
              />
            );
          })}
        </div>
      )}
    </AnimatePresence>
  );
}

// ── AnimatedGraphContainer ─────────────────────────────────────────
export interface AnimatedGraphContainerProps extends HTMLMotionProps<'div'> {
  children: React.ReactNode;
  autoFit?: boolean;
}

export const AnimatedGraphContainer = forwardRef<HTMLDivElement, AnimatedGraphContainerProps>(
  ({ children, autoFit = true, className, ...props }, ref) => {
    const [isReady, setIsReady] = useState(false);

    useEffect(() => {
      const timer = setTimeout(() => setIsReady(true), 100);
      return () => clearTimeout(timer);
    }, []);

    return (
      <motion.div
        ref={ref}
        initial={{ opacity: 0 }}
        animate={isReady ? { opacity: 1, scale: autoFit ? [1.1, 1] : 1 } : { opacity: 0 }}
        transition={{
          duration: 0.5,
          ease: [0, 0, 0.2, 1] as [number, number, number, number],
        }}
        className={cn('relative overflow-hidden', className)}
        {...props}
      >
        {children}
      </motion.div>
    );
  },
);
AnimatedGraphContainer.displayName = 'AnimatedGraphContainer';
