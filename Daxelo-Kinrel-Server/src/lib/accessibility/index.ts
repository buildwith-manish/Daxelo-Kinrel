/**
 * DAXELO KINREL — Accessibility Module
 *
 * Central export point for all accessibility utilities.
 * Pack 06: Accessibility
 */

// ── Tokens ────────────────────────────────────────────────────────
export {
  FocusTokens,
  TouchTargetTokens,
  SpacingTokens,
  MotionTokens,
  duration,
  HighContrastTokens,
  ColorBlindSafeTokens,
  a11yTokens,
} from './a11y-tokens';

// ── Screen Reader ─────────────────────────────────────────────────
export {
  announce,
  announceNavigation,
  announceLoading,
  announceLoaded,
  announceError,
  announceConditionAdded,
  announcePersonDeceased,
  createA11yLabel,
  createA11yHint,
} from './screen-reader';

// ── Keyboard Navigation ───────────────────────────────────────────
export {
  GRAPH_SHORTCUTS,
  GRAPH_ARROW_NAV,
  handleGraphKeyDown,
  FOCUS_RING_CLASS,
  focusElementById,
  trapFocus,
  getFocusableElements,
} from './keyboard-nav';

export type {
  GraphNode,
  GraphData,
  GraphNavAction,
  GraphNavResult,
} from './keyboard-nav';

// ── Contrast ──────────────────────────────────────────────────────
export {
  hexToRgb,
  relativeLuminance,
  contrastRatio,
  meetsWcagAA,
  meetsWcagAAA,
  KNOWN_VIOLATIONS,
  A11Y_COLORS,
} from './contrast';

// ── Cultural Sensitivity ──────────────────────────────────────────
export {
  GOTRA_VISIBILITY_RULES,
  canViewGotra,
  STIGMATIZED_CONDITIONS,
  STIGMA_PROTECTION,
  getStigmaProtectionLevel,
  isStigmatizedCondition,
  HIGH_SENSITIVITY_RELATIONSHIPS,
  requiresConfirmation,
  safeDisplayName,
  RELIGIOUS_MEMORIAL_RULES,
  anonymizeForPublic,
  displayName,
} from './cultural-sensitivity';

export type { StigmaProtectionLevel } from './cultural-sensitivity';

// ── i18n Relationships ────────────────────────────────────────────
export {
  SUPPORTED_LOCALES,
  RELATIONSHIP_NAMES,
  getRelationshipLabel,
  getRelationshipTypeFromLabel,
} from './i18n-relationships';

export type { LocaleInfo, RelationshipType } from './i18n-relationships';

// ── RTL ───────────────────────────────────────────────────────────
export {
  RTL_LOCALES,
  isRtl,
  textDirection,
  mirrorIfRtl,
  startAlignment,
  directionalPadding,
  directionalMargin,
  rtlClass,
  htmlDir,
  logicalPropertyClasses,
} from './rtl-utils';

// ── Locale Formatting ─────────────────────────────────────────────
export {
  INDIAN_LOCALES,
  formatIndianNumber,
  formatDate,
  formatCurrency,
  formatRelativeTime,
  parseIndianNumber,
  numberToIndianWords,
} from './locale-formatting';
