/**
 * DAXELO KINREL — Accessibility React Hooks
 *
 * React hooks for accessibility features:
 * - useReducedMotion: respects prefers-reduced-motion
 * - useFocusTrap: traps focus within a container (modals, dialogs)
 * - useAnnounce: screen reader announcements via ARIA live regions
 * - useKeyboardNavigation: declarative keyboard shortcut binding
 * - useHighContrast: detects high contrast / forced colors mode
 *
 * Pack 06: Accessibility — React hooks
 */

'use client';

import { useEffect, useRef, useCallback, useSyncExternalStore } from 'react';
import { announce as srAnnounce } from '@/lib/accessibility/screen-reader';
import { trapFocus, getFocusableElements } from '@/lib/accessibility/keyboard-nav';

// ── Media Query Hook Utility ──────────────────────────────────────

/**
 * Subscribe to a media query and return its current value.
 * Uses useSyncExternalStore to avoid the "setState in effect" lint error.
 */
function useMediaQuery(query: string): boolean {
  const subscribe = useCallback(
    (callback: () => void) => {
      if (typeof window === 'undefined') return () => {};
      const mql = window.matchMedia(query);
      mql.addEventListener('change', callback);
      return () => mql.removeEventListener('change', callback);
    },
    [query]
  );

  const getSnapshot = useCallback(() => {
    if (typeof window === 'undefined') return false;
    return window.matchMedia(query).matches;
  }, [query]);

  const getServerSnapshot = useCallback(() => false, []);

  return useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
}

// ── useReducedMotion ──────────────────────────────────────────────

/**
 * React hook that detects the user's prefers-reduced-motion setting.
 *
 * Returns true if the user has requested reduced motion.
 * Use this to conditionally apply animations and transitions.
 *
 * @returns Whether reduced motion is preferred
 *
 * @example
 * const prefersReduced = useReducedMotion();
 * const transitionDuration = prefersReduced ? '0ms' : '300ms';
 */
export function useReducedMotion(): boolean {
  return useMediaQuery('(prefers-reduced-motion: reduce)');
}

// ── useFocusTrap ──────────────────────────────────────────────────

/**
 * React hook that traps focus within a container element.
 * Essential for modal dialogs, drawers, and any overlay
 * that should prevent focus from escaping.
 *
 * Automatically activates when `active` is true and
 * cleans up when `active` becomes false or the component unmounts.
 *
 * @param active - Whether the focus trap is currently active
 * @returns Object with containerRef to attach to the container element
 *
 * @example
 * function Modal({ isOpen, onClose, children }) {
 *   const { containerRef } = useFocusTrap(isOpen);
 *
 *   return isOpen ? (
 *     <div ref={containerRef} role="dialog" aria-modal="true">
 *       {children}
 *       <button onClick={onClose}>Close</button>
 *     </div>
 *   ) : null;
 * }
 */
export function useFocusTrap(active: boolean): {
  containerRef: React.RefObject<HTMLDivElement | null>;
} {
  const containerRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    if (!active || !containerRef.current) return;

    const { cleanup } = trapFocus(containerRef.current);
    return cleanup;
  }, [active]);

  return { containerRef };
}

// ── useAnnounce ───────────────────────────────────────────────────

/**
 * React hook for screen reader announcements.
 * Wraps the announce function from screen-reader.ts
 * for convenient use in React components.
 *
 * @returns Object with announce function
 *
 * @example
 * function SaveButton() {
 *   const { announce } = useAnnounce();
 *
 *   const handleSave = async () => {
 *     await saveData();
 *     announce('Data saved successfully');
 *   };
 *
 *   return <button onClick={handleSave}>Save</button>;
 * }
 */
export function useAnnounce(): {
  announce: (message: string, priority?: 'polite' | 'assertive') => void;
} {
  const announce = useCallback(
    (message: string, priority: 'polite' | 'assertive' = 'polite') => {
      srAnnounce(message, priority);
    },
    []
  );

  return { announce };
}

// ── useKeyboardNavigation ─────────────────────────────────────────

/**
 * React hook for declarative keyboard shortcut binding.
 *
 * Binds keydown event listeners for the specified key → handler mappings.
 * Automatically ignores events from input/textarea/select elements
 * unless the handler is explicitly registered for that context.
 *
 * Cleans up all listeners on unmount.
 *
 * @param handlers - Map of key names to handler functions
 *
 * @example
 * useKeyboardNavigation({
 *   Escape: () => closeModal(),
 *   '?': () => toggleHelp(),
 *   '/': () => focusSearch(),
 *   g: () => navigateToGraph(),
 * });
 */
export function useKeyboardNavigation(
  handlers: Record<string, () => void>
): void {
  const handlersRef = useRef(handlers);

  // Keep handlers reference up to date without re-attaching listener
  useEffect(() => {
    handlersRef.current = handlers;
  }, [handlers]);

  useEffect(() => {
    if (typeof window === 'undefined') return;

    const handleKeyDown = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement;
      const isInputFocused =
        target.tagName === 'INPUT' ||
        target.tagName === 'TEXTAREA' ||
        target.tagName === 'SELECT' ||
        target.isContentEditable;

      // Allow Escape even in inputs
      const key = event.key;
      if (key === 'Escape') {
        const handler = handlersRef.current['Escape'];
        if (handler) {
          event.preventDefault();
          handler();
        }
        return;
      }

      // Skip single-key shortcuts when in input fields
      if (isInputFocused && key.length === 1) return;

      const handler = handlersRef.current[key];
      if (handler) {
        event.preventDefault();
        handler();
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, []);
}

// ── useHighContrast ───────────────────────────────────────────────

/**
 * React hook that detects if the user has enabled high contrast mode
 * or forced colors mode in their OS settings.
 *
 * Uses the `prefers-contrast` media query (modern browsers)
 * and falls back to `forced-colors` detection.
 *
 * @returns Whether high contrast mode is active
 *
 * @example
 * const isHighContrast = useHighContrast();
 * const focusRingColor = isHighContrast ? '#FFFF00' : '#1565C0';
 */
export function useHighContrast(): boolean {
  const prefersMore = useMediaQuery('(prefers-contrast: more)');
  const forcedColors = useMediaQuery('(forced-colors: active)');
  return prefersMore || forcedColors;
}

// ── useA11yColors ─────────────────────────────────────────────────

/**
 * React hook that provides accessibility-aware color values.
 * Automatically switches between standard and high-contrast colors.
 *
 * @returns Object with color getters that respect high contrast mode
 *
 * @example
 * const { getSeverityColor, getFocusColor } = useA11yColors();
 * const mildColor = getSeverityColor('mild'); // adapts to high contrast
 */
export function useA11yColors() {
  const isHighContrast = useHighContrast();

  const getFocusColor = useCallback(() => {
    return isHighContrast ? '#FFFF00' : '#1565C0';
  }, [isHighContrast]);

  const getSeverityColor = useCallback(
    (level: 'mild' | 'moderate' | 'severe' | 'critical') => {
      if (isHighContrast) {
        const hcColors: Record<string, string> = {
          mild: '#00FF00',
          moderate: '#FF8800',
          severe: '#FF0000',
          critical: '#FFFF00',
        };
        return hcColors[level];
      }
      const stdColors: Record<string, string> = {
        mild: '#2E7D32',
        moderate: '#E65100',
        severe: '#C62828',
        critical: '#1A1A1A',
      };
      return stdColors[level];
    },
    [isHighContrast]
  );

  return { getFocusColor, getSeverityColor, isHighContrast };
}

// ── useFocusOnMount ───────────────────────────────────────────────

/**
 * React hook that focuses the first focusable element within
 * a container when it mounts. Useful for modal dialogs and
 * dynamic content that needs initial focus.
 *
 * @param shouldFocus - Whether to focus on mount (default: true)
 * @returns Ref to attach to the container element
 *
 * @example
 * function Dialog({ isOpen }) {
 *   const containerRef = useFocusOnMount(isOpen);
 *   return <div ref={containerRef}>...</div>;
 * }
 */
export function useFocusOnMount(
  shouldFocus: boolean = true
): React.RefObject<HTMLDivElement | null> {
  const containerRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    if (!shouldFocus || !containerRef.current) return;

    const focusable = getFocusableElements(containerRef.current);
    if (focusable.length > 0) {
      // Small delay to ensure DOM is ready
      requestAnimationFrame(() => {
        focusable[0].focus();
      });
    }
  }, [shouldFocus]);

  return containerRef;
}
