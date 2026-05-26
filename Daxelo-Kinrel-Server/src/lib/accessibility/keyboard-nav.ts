/**
 * DAXELO KINREL — Keyboard Navigation Utilities
 *
 * Keyboard navigation support for the family tree graph,
 * shortcuts, focus management, and focus trapping.
 *
 * Pack 06: Accessibility — Keyboard navigation
 */

// ── Graph Keyboard Shortcuts ──────────────────────────────────────

/**
 * Single-key shortcuts for the graph view.
 * Only active when no input/textarea is focused.
 */
export const GRAPH_SHORTCUTS: Record<string, string> = {
  g: 'Graph',
  h: 'Health',
  p: 'Person',
  '/': 'Search',
  Escape: 'Back',
  '?': 'Shortcuts',
} as const;

/**
 * Arrow key navigation mapping for the family tree graph.
 * Uses genealogical navigation model:
 * - Up = navigate to parent
 * - Down = navigate to child
 * - Left/Right = navigate to siblings
 * - Enter/Space = activate/select node
 */
export const GRAPH_ARROW_NAV = {
  ArrowUp: 'parent',
  ArrowDown: 'child',
  ArrowLeft: 'sibling-prev',
  ArrowRight: 'sibling-next',
  Enter: 'activate',
  Space: 'activate',
} as const;

// ── Graph Data Types ──────────────────────────────────────────────

export interface GraphNode {
  id: string;
  parentId?: string | null;
  childrenIds: string[];
  siblingIds: string[];
}

export interface GraphData {
  nodes: Record<string, GraphNode>;
  rootId: string;
}

export type GraphNavAction =
  | 'navigate-parent'
  | 'navigate-child'
  | 'navigate-sibling-prev'
  | 'navigate-sibling-next'
  | 'activate'
  | 'shortcut-graph'
  | 'shortcut-health'
  | 'shortcut-person'
  | 'shortcut-search'
  | 'shortcut-back'
  | 'shortcut-help'
  | 'none';

export interface GraphNavResult {
  action: GraphNavAction;
  targetId: string | null;
}

/**
 * Handle keyboard events in the graph view.
 * Returns the action to perform and the target node ID.
 *
 * @param event - The keyboard event
 * @param currentNodeId - The currently focused node ID
 * @param graphData - The full graph structure
 * @returns Navigation result with action and target
 *
 * @example
 * const result = handleGraphKeyDown(event, 'node-5', graphData);
 * if (result.targetId) {
 *   focusElementById(`graph-node-${result.targetId}`);
 * }
 */
export function handleGraphKeyDown(
  event: KeyboardEvent,
  currentNodeId: string,
  graphData: GraphData
): GraphNavResult {
  const currentNode = graphData.nodes[currentNodeId];
  if (!currentNode) {
    return { action: 'none', targetId: null };
  }

  // Don't handle shortcuts when typing in inputs
  const target = event.target as HTMLElement;
  const isInputFocused =
    target.tagName === 'INPUT' ||
    target.tagName === 'TEXTAREA' ||
    target.tagName === 'SELECT' ||
    target.isContentEditable;

  // Arrow key navigation (works even in inputs for graph)
  const arrowAction = GRAPH_ARROW_NAV[event.key as keyof typeof GRAPH_ARROW_NAV];

  if (arrowAction) {
    event.preventDefault();

    switch (arrowAction) {
      case 'parent': {
        const parentId = currentNode.parentId;
        if (parentId && graphData.nodes[parentId]) {
          return { action: 'navigate-parent', targetId: parentId };
        }
        return { action: 'none', targetId: null };
      }

      case 'child': {
        const firstChildId = currentNode.childrenIds[0];
        if (firstChildId && graphData.nodes[firstChildId]) {
          return { action: 'navigate-child', targetId: firstChildId };
        }
        return { action: 'none', targetId: null };
      }

      case 'sibling-prev': {
        const siblingIndex = currentNode.siblingIds.indexOf(currentNodeId);
        if (siblingIndex > 0) {
          const prevSiblingId = currentNode.siblingIds[siblingIndex - 1];
          if (graphData.nodes[prevSiblingId]) {
            return { action: 'navigate-sibling-prev', targetId: prevSiblingId };
          }
        }
        // Wrap around to last sibling
        if (currentNode.siblingIds.length > 1) {
          const lastSiblingId = currentNode.siblingIds[currentNode.siblingIds.length - 1];
          if (graphData.nodes[lastSiblingId]) {
            return { action: 'navigate-sibling-prev', targetId: lastSiblingId };
          }
        }
        return { action: 'none', targetId: null };
      }

      case 'sibling-next': {
        const sibIndex = currentNode.siblingIds.indexOf(currentNodeId);
        if (sibIndex < currentNode.siblingIds.length - 1) {
          const nextSiblingId = currentNode.siblingIds[sibIndex + 1];
          if (graphData.nodes[nextSiblingId]) {
            return { action: 'navigate-sibling-next', targetId: nextSiblingId };
          }
        }
        // Wrap around to first sibling
        if (currentNode.siblingIds.length > 1) {
          const firstSiblingId = currentNode.siblingIds[0];
          if (graphData.nodes[firstSiblingId]) {
            return { action: 'navigate-sibling-next', targetId: firstSiblingId };
          }
        }
        return { action: 'none', targetId: null };
      }

      case 'activate': {
        return { action: 'activate', targetId: currentNodeId };
      }

      default:
        return { action: 'none', targetId: null };
    }
  }

  // Single-key shortcuts (only when not in an input)
  if (!isInputFocused) {
    const shortcut = GRAPH_SHORTCUTS[event.key];
    if (shortcut) {
      event.preventDefault();
      switch (event.key) {
        case 'g':
          return { action: 'shortcut-graph', targetId: null };
        case 'h':
          return { action: 'shortcut-health', targetId: null };
        case 'p':
          return { action: 'shortcut-person', targetId: null };
        case '/':
          return { action: 'shortcut-search', targetId: null };
        case 'Escape':
          return { action: 'shortcut-back', targetId: null };
        case '?':
          return { action: 'shortcut-help', targetId: null };
        default:
          return { action: 'none', targetId: null };
      }
    }
  }

  // Escape always works to go back
  if (event.key === 'Escape') {
    return { action: 'shortcut-back', targetId: null };
  }

  return { action: 'none', targetId: null };
}

// ── Focus Ring CSS Class ──────────────────────────────────────────

/**
 * Tailwind CSS class string for the accessible focus ring.
 * Uses focus-visible to only show on keyboard navigation.
 * Color matches FocusTokens.color (#1565C0).
 */
export const FOCUS_RING_CLASS =
  'focus-visible:ring-[3px] focus-visible:ring-[#1565C0] focus-visible:ring-offset-2 focus-visible:rounded-sm';

/**
 * Focus an element by its ID.
 * Safely handles missing elements and calls focus() with
 * preventScroll option to avoid jarring jumps.
 *
 * @param id - DOM element ID
 * @returns Whether the element was found and focused
 */
export function focusElementById(id: string): boolean {
  if (typeof document === 'undefined') return false;
  const element = document.getElementById(id);
  if (element) {
    element.focus({ preventScroll: false });
    return true;
  }
  return false;
}

/**
 * Trap focus within a container element.
 * Tab and Shift+Tab cycle through focusable elements within
 * the container, preventing focus from escaping.
 *
 * Essential for modal dialogs and dropdown menus.
 *
 * @param container - The container element to trap focus within
 * @returns Cleanup function to remove the trap
 *
 * @example
 * const cleanup = trapFocus(modalRef.current);
 * // Later...
 * cleanup();
 */
export function trapFocus(container: HTMLElement): { cleanup: () => void } {
  const handleKeyDown = (event: KeyboardEvent) => {
    if (event.key !== 'Tab') return;

    const focusable = getFocusableElements(container);
    if (focusable.length === 0) return;

    const first = focusable[0];
    const last = focusable[focusable.length - 1];

    if (event.shiftKey) {
      // Shift+Tab: if on first element, wrap to last
      if (document.activeElement === first) {
        event.preventDefault();
        last.focus();
      }
    } else {
      // Tab: if on last element, wrap to first
      if (document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    }
  };

  container.addEventListener('keydown', handleKeyDown);

  // Focus the first focusable element on trap activation
  const focusable = getFocusableElements(container);
  if (focusable.length > 0) {
    focusable[0].focus();
  }

  return {
    cleanup: () => {
      container.removeEventListener('keydown', handleKeyDown);
    },
  };
}

/**
 * Selector for focusable elements.
 * Excludes hidden, disabled, and non-interactive elements.
 */
const FOCUSABLE_SELECTOR = [
  'a[href]',
  'button:not([disabled])',
  'input:not([disabled])',
  'select:not([disabled])',
  'textarea:not([disabled])',
  '[tabindex]:not([tabindex="-1"])',
  '[contenteditable="true"]',
  'details > summary',
  'audio[controls]',
  'video[controls]',
].join(', ');

/**
 * Get all focusable elements within a container.
 * Returns elements in DOM order, excluding those that are
 * visually hidden or disabled.
 *
 * @param container - Parent element to search within
 * @returns Array of focusable HTMLElements
 */
export function getFocusableElements(container: HTMLElement): HTMLElement[] {
  const elements = container.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTOR);
  return Array.from(elements).filter((el) => {
    // Exclude elements that are not visible
    if (el.offsetParent === null && el.style.position !== 'fixed') return false;
    // Exclude elements with display:none or visibility:hidden
    const style = window.getComputedStyle(el);
    if (style.display === 'none' || style.visibility === 'hidden') return false;
    // Exclude elements with aria-hidden="true"
    if (el.getAttribute('aria-hidden') === 'true') return false;
    return true;
  });
}
