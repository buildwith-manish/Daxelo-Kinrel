/**
 * DAXELO KINREL — Screen Reader Announcement Service
 *
 * Manages ARIA live region announcements for screen readers.
 * Supports polite and assertive priorities, navigation cues,
 * loading states, and domain-specific announcements for
 * Indian family relationship context.
 *
 * Pack 06: Accessibility — Screen reader support
 */

// ── Live Region Management ────────────────────────────────────────

const POLITE_REGION_ID = 'a11y-announce-polite';
const ASSERTIVE_REGION_ID = 'a11y-announce-assertive';

/**
 * Ensures the ARIA live region DOM element exists.
 * Creates it if not present, attaches to document.body.
 */
function ensureLiveRegion(
  id: string,
  ariaLive: 'polite' | 'assertive'
): HTMLElement {
  let region = document.getElementById(id);
  if (!region) {
    region = document.createElement('div');
    region.id = id;
    region.setAttribute('aria-live', ariaLive);
    region.setAttribute('aria-atomic', 'true');
    region.setAttribute('role', 'status');
    region.setAttribute('style', [
      'position: absolute',
      'width: 1px',
      'height: 1px',
      'padding: 0',
      'margin: -1px',
      'overflow: hidden',
      'clip: rect(0, 0, 0, 0)',
      'white-space: nowrap',
      'border: 0',
    ].join(';'));
    document.body.appendChild(region);
  }
  return region;
}

/**
 * Announce a message to screen readers via ARIA live region.
 *
 * @param message - Text to announce
 * @param priority - 'polite' waits for current speech, 'assertive' interrupts
 *
 * @example
 * announce('Family tree loaded with 24 members');
 * announce('Error saving person', 'assertive');
 */
export function announce(
  message: string,
  priority: 'polite' | 'assertive' = 'polite'
): void {
  if (typeof document === 'undefined') return;

  const regionId = priority === 'assertive'
    ? ASSERTIVE_REGION_ID
    : POLITE_REGION_ID;

  const region = ensureLiveRegion(regionId, priority);

  // Clear then set — ensures re-announcement of same message
  region.textContent = '';
  // Use requestAnimationFrame to ensure the clear is processed
  // before the new content is set
  requestAnimationFrame(() => {
    region.textContent = message;
  });
}

// ── Navigation Announcements ──────────────────────────────────────

/**
 * Announce a navigation transition between views/pages.
 *
 * @param from - Source view name (e.g., 'Family Tree')
 * @param to - Destination view name (e.g., 'Health Conditions')
 *
 * @example
 * announceNavigation('Family Tree', 'Health Conditions');
 * // Screen reader: "Navigated from Family Tree to Health Conditions"
 */
export function announceNavigation(from: string, to: string): void {
  announce(`Navigated from ${from} to ${to}`, 'polite');
}

// ── Loading State Announcements ───────────────────────────────────

/**
 * Announce that a loading state has begun.
 * Screen readers will inform users that content is being fetched.
 *
 * @example
 * announceLoading();
 * // Screen reader: "Loading, please wait"
 */
export function announceLoading(): void {
  announce('Loading, please wait', 'polite');
}

/**
 * Announce that loading has completed.
 *
 * @example
 * announceLoaded();
 * // Screen reader: "Content loaded"
 */
export function announceLoaded(): void {
  announce('Content loaded', 'polite');
}

// ── Error Announcements ───────────────────────────────────────────

/**
 * Announce an error message assertively so it interrupts.
 *
 * @param message - Human-readable error description
 *
 * @example
 * announceError('Failed to save health condition. Please try again.');
 */
export function announceError(message: string): void {
  announce(`Error: ${message}`, 'assertive');
}

// ── Domain-Specific Announcements ─────────────────────────────────

/**
 * Announce that a health condition was added with its protection level.
 * Respects cultural sensitivity by not revealing condition details
 * in public contexts — the protection level tells the user
 * how the data is being handled.
 *
 * @param conditionName - Name of the health condition added
 * @param protectionLevel - 'standard' | 'elevated' | 'maximum'
 *
 * @example
 * announceConditionAdded('Diabetes', 'standard');
 * // Screen reader: "Added Diabetes with standard privacy protection"
 */
export function announceConditionAdded(
  conditionName: string,
  protectionLevel: 'standard' | 'elevated' | 'maximum'
): void {
  const levelDescriptions: Record<string, string> = {
    standard: 'standard privacy protection',
    elevated: 'elevated privacy protection — sharing is restricted',
    maximum: 'maximum privacy protection — data is highly restricted',
  };
  announce(
    `Added ${conditionName} with ${levelDescriptions[protectionLevel]}`,
    'polite'
  );
}

/**
 * Announce that a person in the family tree is deceased.
 * Uses respectful language appropriate for the context.
 *
 * @param personName - Name of the deceased person
 *
 * @example
 * announcePersonDeceased('Rajesh Kumar');
 * // Screen reader: "Marked Rajesh Kumar as deceased"
 */
export function announcePersonDeceased(personName: string): void {
  announce(`Marked ${personName} as deceased`, 'polite');
}

// ── Label Builders ────────────────────────────────────────────────

/**
 * Create an accessible label from multiple parts.
 * Joins parts with comma and space for clear screen reader output.
 *
 * @param parts - Array of label segments
 * @returns Combined label string
 *
 * @example
 * createA11yLabel(['Rajesh Kumar', 'Father', 'Age 62']);
 * // Returns: "Rajesh Kumar, Father, Age 62"
 */
export function createA11yLabel(parts: string[]): string {
  return parts.filter(Boolean).join(', ');
}

/**
 * Create an accessibility hint for touch/mobile interactions.
 * Uses the standard "Double tap to {action}" pattern.
 *
 * @param action - The action that will be performed
 * @returns Hint string for aria-hint or accessibilityHint
 *
 * @example
 * createA11yHint('view family tree');
 * // Returns: "Double tap to view family tree"
 */
export function createA11yHint(action: string): string {
  return `Double tap to ${action}`;
}
