'use client';

/**
 * DAXELO KINREL — AccessibilitySettings Panel
 *
 * Comprehensive settings panel for all accessibility features.
 * Provides toggles, sliders, and previews for vision, motion,
 * language, keyboard, screen reader, and cultural sensitivity.
 *
 * Pack 06: Accessibility — Consuming UI
 */

import { useState, useMemo, useCallback, useEffect } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import {
  Eye, Sun, Moon, Palette, Type, Hand, Shield, Accessibility,
  Keyboard, Volume2, Languages, AlertTriangle, ChevronRight,
  Info, Check, XCircle, EyeOff, Move, Clock, Globe, ArrowLeftRight,
  BookOpen, Heart, CircleDot, Zap, RotateCcw,
} from 'lucide-react';
import {
  Card, CardContent, CardHeader, CardTitle, CardDescription,
} from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Separator } from '@/components/ui/separator';
import {
  Select, SelectTrigger, SelectValue, SelectContent, SelectItem,
} from '@/components/ui/select';
import { Switch } from '@/components/ui/switch';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Slider } from '@/components/ui/slider';
import { Button } from '@/components/ui/button';
import { ScrollArea } from '@/components/ui/scroll-area';
import {
  Tooltip, TooltipTrigger, TooltipContent, TooltipProvider,
} from '@/components/ui/tooltip';

// ── Accessibility Hooks ──────────────────────────────────────────
import {
  useReducedMotion,
  useAnnounce,
  useHighContrast,
  useA11yColors,
} from '@/hooks/use-accessibility';

// ── Accessibility Libraries ──────────────────────────────────────
import {
  contrastRatio,
  meetsWcagAA,
  meetsWcagAAA,
  A11Y_COLORS,
  hexToRgb,
} from '@/lib/accessibility/contrast';
import {
  SUPPORTED_LOCALES,
  getRelationshipLabel,
} from '@/lib/accessibility/i18n-relationships';
import {
  GOTRA_VISIBILITY_RULES,
  STIGMA_PROTECTION,
  RELIGIOUS_MEMORIAL_RULES,
  getStigmaProtectionLevel,
} from '@/lib/accessibility/cultural-sensitivity';
import { GRAPH_SHORTCUTS, GRAPH_ARROW_NAV } from '@/lib/accessibility/keyboard-nav';
import { FocusTokens, HighContrastTokens, MotionTokens, duration } from '@/lib/accessibility/a11y-tokens';
import { isRtl, textDirection, htmlDir } from '@/lib/accessibility/rtl-utils';
import { supportedLanguages, formatIndianNumber } from '@/lib/font-loader';

// ── Color Blind Modes ───────────────────────────────────────────
const COLOR_BLIND_MODES = [
  { value: 'none', label: 'None', description: 'No color vision simulation' },
  { value: 'deuteranopia', label: 'Deuteranopia', description: 'Red-green (most common)' },
  { value: 'protanopia', label: 'Protanopia', description: 'Red-blind' },
  { value: 'tritanopia', label: 'Tritanopia', description: 'Blue-yellow' },
] as const;

// ── Keyboard shortcuts for reference ────────────────────────────
const KEYBOARD_SHORTCUT_LIST = [
  { keys: '↑', action: 'Navigate to parent node', category: 'Arrow Keys' },
  { keys: '↓', action: 'Navigate to child node', category: 'Arrow Keys' },
  { keys: '← →', action: 'Navigate between siblings', category: 'Arrow Keys' },
  { keys: 'Enter / Space', action: 'Activate / select node', category: 'Arrow Keys' },
  ...Object.entries(GRAPH_SHORTCUTS).map(([key, label]) => ({
    keys: key === 'Escape' ? 'Esc' : key === '/' ? '/' : key,
    action: label,
    category: 'Shortcuts',
  })),
];

// ── Animation variants ──────────────────────────────────────────
const sectionVariants = {
  hidden: { opacity: 0, y: 12 },
  visible: { opacity: 1, y: 0 },
};

const staggerContainer = {
  hidden: { opacity: 0 },
  visible: {
    opacity: 1,
    transition: { staggerChildren: 0.06 },
  },
};

// ════════════════════════════════════════════════════════════════════
// Sub-Components
// ════════════════════════════════════════════════════════════════════

// ── Contrast Checker ────────────────────────────────────────────
function ContrastChecker() {
  const [fgColor, setFgColor] = useState('#F97316');
  const [bgColor, setBgColor] = useState('#FFFFFF');

  const cr = useMemo(() => {
    try { return contrastRatio(fgColor, bgColor); } catch { return 1; }
  }, [fgColor, bgColor]);

  const passesAA = useMemo(() => {
    try { return meetsWcagAA(fgColor, bgColor); } catch { return false; }
  }, [fgColor, bgColor]);

  const passesAAA = useMemo(() => {
    try { return meetsWcagAAA(fgColor, bgColor); } catch { return false; }
  }, [fgColor, bgColor]);

  return (
    <Card className="rounded-xl border-[#FED7AA] dark:border-[#44403C] bg-white dark:bg-[#1C1917] shadow-lg">
      <CardHeader className="pb-4">
        <CardTitle className="flex items-center gap-2 text-base text-[#1C1917] dark:text-[#F5F5F4]">
          <Eye className="w-4 h-4 text-[#F97316]" />
          WCAG Contrast Checker
        </CardTitle>
        <CardDescription className="text-xs">
          Live contrast ratio calculation between two colors
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="grid grid-cols-2 gap-3">
          <div className="space-y-1.5">
            <Label className="text-xs text-[#57534E] dark:text-[#A8A29E]">Foreground</Label>
            <div className="flex gap-2 items-center">
              <div
                className="w-8 h-8 rounded-lg border border-[#FED7AA] dark:border-[#44403C] shrink-0"
                style={{ backgroundColor: fgColor }}
              />
              <Input
                value={fgColor}
                onChange={(e) => setFgColor(e.target.value)}
                className="font-mono text-xs h-8"
                aria-label="Foreground color hex value"
                maxLength={7}
              />
            </div>
          </div>
          <div className="space-y-1.5">
            <Label className="text-xs text-[#57534E] dark:text-[#A8A29E]">Background</Label>
            <div className="flex gap-2 items-center">
              <div
                className="w-8 h-8 rounded-lg border border-[#FED7AA] dark:border-[#44403C] shrink-0"
                style={{ backgroundColor: bgColor }}
              />
              <Input
                value={bgColor}
                onChange={(e) => setBgColor(e.target.value)}
                className="font-mono text-xs h-8"
                aria-label="Background color hex value"
                maxLength={7}
              />
            </div>
          </div>
        </div>

        {/* Preview */}
        <div
          className="p-3 rounded-lg border border-[#FED7AA] dark:border-[#44403C] text-center"
          style={{ backgroundColor: bgColor, color: fgColor }}
        >
          <p className="text-base font-semibold">Sample Text</p>
          <p className="text-[10px]">This is how the colors look together.</p>
        </div>

        {/* Results */}
        <div className="flex items-center justify-between p-3 rounded-lg bg-[#FFF7ED] dark:bg-[#292524] border border-[#FED7AA] dark:border-[#44403C]">
          <div>
            <div className="text-xl font-extrabold text-[#1C1917] dark:text-[#F5F5F4]">
              {cr.toFixed(2)}:1
            </div>
            <div className="text-[10px] text-[#78716C] dark:text-[#A8A29E]">Contrast Ratio</div>
          </div>
          <div className="flex gap-1.5">
            <Badge className={`${passesAA ? 'bg-[#22C55E] text-white' : 'bg-[#EF4444] text-white'} border-0 text-[10px] px-2 py-0.5`}>
              AA {passesAA ? '✓' : '✗'}
            </Badge>
            <Badge className={`${passesAAA ? 'bg-[#22C55E] text-white' : 'bg-[#EF4444] text-white'} border-0 text-[10px] px-2 py-0.5`}>
              AAA {passesAAA ? '✓' : '✗'}
            </Badge>
          </div>
        </div>
      </CardContent>
    </Card>
  );
}

// ── Focus Ring Demo ─────────────────────────────────────────────
function FocusRingDemo() {
  const isHC = useHighContrast();
  const focusColor = isHC ? HighContrastTokens.focusRing : FocusTokens.color;

  return (
    <div className="space-y-3">
      <div className="flex items-center gap-3 flex-wrap">
        <button
          className="px-4 py-2 rounded-lg text-sm font-medium text-[#1C1917] dark:text-[#F5F5F4] border-2 transition-all focus:outline-none"
          style={{
            borderColor: 'transparent',
          }}
          onFocus={(e) => {
            e.currentTarget.style.borderColor = focusColor;
            e.currentTarget.style.boxShadow = `0 0 0 ${FocusTokens.offset}px ${isHC ? '#000' : 'white'}, 0 0 0 ${FocusTokens.offset + FocusTokens.width}px ${focusColor}`;
          }}
          onBlur={(e) => {
            e.currentTarget.style.borderColor = 'transparent';
            e.currentTarget.style.boxShadow = 'none';
          }}
          aria-label="Demo focusable button — tab here to see focus ring"
        >
          Tab to me
        </button>
        <Input
          className="max-w-[200px] h-9 text-sm"
          placeholder="Focus me too"
          aria-label="Demo focusable input — tab here to see focus ring"
          onFocus={(e) => {
            e.currentTarget.style.boxShadow = `0 0 0 ${FocusTokens.offset}px ${isHC ? '#000' : 'white'}, 0 0 0 ${FocusTokens.offset + FocusTokens.width}px ${focusColor}`;
          }}
          onBlur={(e) => {
            e.currentTarget.style.boxShadow = '';
          }}
        />
        <a
          href="#focus-demo-link"
          className="text-sm underline text-[#1565C0] dark:text-[#60A5FA] focus:outline-none"
          onFocus={(e) => {
            e.currentTarget.style.outline = `${FocusTokens.width}px solid ${focusColor}`;
            e.currentTarget.style.outlineOffset = `${FocusTokens.offset}px`;
          }}
          onBlur={(e) => {
            e.currentTarget.style.outline = 'none';
          }}
          onClick={(e) => e.preventDefault()}
          aria-label="Demo focusable link"
        >
          Focusable Link
        </a>
      </div>
      <p className="text-[10px] text-[#78716C] dark:text-[#A8A29E]">
        Focus ring: {focusColor} • Width: {FocusTokens.width}px • Offset: {FocusTokens.offset}px
        {isHC && ' • High contrast mode active'}
      </p>
    </div>
  );
}

// ════════════════════════════════════════════════════════════════════
// Main Component
// ════════════════════════════════════════════════════════════════════
type AccessibilitySettingsProps = {
  fontScale?: number;
  onFontScaleChange?: (scale: number) => void;
  highContrast?: boolean;
  onHighContrastChange?: (enabled: boolean) => void;
};

export function AccessibilitySettings({
  fontScale: externalFontScale,
  onFontScaleChange,
  highContrast: externalHighContrast,
  onHighContrastChange,
}: AccessibilitySettingsProps = {}) {
  // ── Accessibility hooks ────────────────────────────────────────
  const prefersReducedMotion = useReducedMotion();
  const { announce } = useAnnounce();
  const isHighContrastOS = useHighContrast();
  const { getFocusColor, getSeverityColor, isHighContrast: hcActive } = useA11yColors();

  // ── Local state (falls back to external if provided) ────────────
  const [localFontScale, setLocalFontScale] = useState(1.0);
  const [localHighContrast, setLocalHighContrast] = useState(false);
  const fontScale = externalFontScale ?? localFontScale;
  const setFontScale = onFontScaleChange ?? setLocalFontScale;
  const highContrastEnabled = externalHighContrast ?? localHighContrast;
  const setHighContrastEnabled = onHighContrastChange ?? setLocalHighContrast;
  const [colorBlindMode, setColorBlindMode] = useState('none');
  const [reducedMotionOverride, setReducedMotionOverride] = useState(false);
  const [animationSpeed, setAnimationSpeed] = useState(1.0);
  const [selectedLocale, setSelectedLocale] = useState('en');
  const [announcePriority, setAnnouncePriority] = useState<'polite' | 'assertive'>('polite');
  const [lastAnnouncement, setLastAnnouncement] = useState('');

  // ── Derived values ─────────────────────────────────────────────
  const effectiveReducedMotion = prefersReducedMotion || reducedMotionOverride;
  const isRTL = isRtl(selectedLocale);
  const currentDir = textDirection(selectedLocale);

  // ── Apply CSS variables ────────────────────────────────────────
  useEffect(() => {
    if (typeof document === 'undefined') return;
    document.documentElement.style.setProperty('--kinrel-font-scale', fontScale.toString());
  }, [fontScale]);

  useEffect(() => {
    if (typeof document === 'undefined') return;
    if (highContrastEnabled) {
      document.documentElement.style.setProperty('--kinrel-high-contrast', '1');
    } else {
      document.documentElement.style.removeProperty('--kinrel-high-contrast');
    }
  }, [highContrastEnabled]);

  useEffect(() => {
    if (typeof document === 'undefined') return;
    document.documentElement.style.setProperty('--kinrel-animation-speed', animationSpeed.toString());
  }, [animationSpeed]);

  // ── Handlers ───────────────────────────────────────────────────
  const handleAnnounce = useCallback(() => {
    const msg = announcePriority === 'assertive'
      ? 'Urgent: This is an assertive announcement from KINREL!'
      : 'This is a polite screen reader announcement from KINREL.';
    announce(msg, announcePriority);
    setLastAnnouncement(msg);
    setTimeout(() => setLastAnnouncement(''), 3000);
  }, [announce, announcePriority]);

  const handleReset = useCallback(() => {
    setFontScale(1.0);
    setHighContrastEnabled(false);
    setColorBlindMode('none');
    setReducedMotionOverride(false);
    setAnimationSpeed(1.0);
    setSelectedLocale('en');
    setAnnouncePriority('polite');
    announce('Accessibility settings reset to defaults', 'polite');
  }, [announce]);

  // ── Locale date preview ────────────────────────────────────────
  const datePreview = useMemo(() => {
    try {
      const date = new Date(2025, 0, 15); // Jan 15, 2025
      return new Intl.DateTimeFormat(selectedLocale === 'sa' ? 'hi-IN' : `${selectedLocale}-IN`, {
        year: 'numeric',
        month: 'long',
        day: 'numeric',
      }).format(date);
    } catch {
      return '15 January 2025';
    }
  }, [selectedLocale]);

  // ── Number preview ─────────────────────────────────────────────
  const numberPreview = useMemo(() => {
    return formatIndianNumber(123456789);
  }, []);

  // ── Current language info ──────────────────────────────────────
  const currentLang = useMemo(() => {
    return supportedLanguages.find(l => l.code === selectedLocale) ?? supportedLanguages[0];
  }, [selectedLocale]);

  // ── Stigma protection descriptions ─────────────────────────────
  const stigmaDescriptions: Record<string, string> = {
    standard: 'Default privacy — aggregate insights allowed',
    elevated: 'Restricted sharing — 365-day retention, excluded from search & export',
    maximum: 'Maximum protection — 90-day retention, no sharing, double consent required',
  };

  // ── Selected religion for memorial rules ───────────────────────
  const [selectedReligion, setSelectedReligion] = useState('hindu');

  return (
    <TooltipProvider>
      <motion.section
        initial="hidden"
        whileInView="visible"
        viewport={{ once: true, margin: '-50px' }}
        variants={staggerContainer}
        className="py-12 md:py-16 bg-[#FFF7ED] dark:bg-[#292524]"
        aria-label="Accessibility Settings"
      >
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          {/* ── Section Header ─────────────────────────────────────── */}
          <motion.div variants={sectionVariants} className="text-center mb-10">
            <Badge className="bg-white dark:bg-[#431407] text-[#F97316] border-[#FED7AA] dark:border-[#EA580C] mb-4">
              <Accessibility className="w-3 h-3 mr-1" />
              Pack 06 — Accessibility Settings
            </Badge>
            <h2 className="text-3xl sm:text-4xl font-extrabold text-[#1C1917] dark:text-[#F5F5F4] mb-3">
              Accessibility <span className="text-[#F97316]">Settings</span>
            </h2>
            <p className="text-[#57534E] dark:text-[#A8A29E] max-w-xl mx-auto text-sm sm:text-base">
              Full control over vision, motion, language, keyboard, screen reader, and cultural sensitivity features.
            </p>
          </motion.div>

          {/* ── Reset Button ───────────────────────────────────────── */}
          <motion.div variants={sectionVariants} className="flex justify-end mb-4">
            <Button
              variant="outline"
              size="sm"
              onClick={handleReset}
              className="text-xs border-[#FED7AA] dark:border-[#44403C] text-[#78716C] dark:text-[#A8A29E] hover:text-[#F97316]"
              aria-label="Reset all accessibility settings to defaults"
            >
              <RotateCcw className="w-3 h-3 mr-1" />
              Reset All
            </Button>
          </motion.div>

          {/* ── Tabs ───────────────────────────────────────────────── */}
          <motion.div variants={sectionVariants}>
            <Tabs defaultValue="vision" className="w-full">
              <TabsList className="mx-auto flex flex-wrap w-full max-w-3xl mb-6 bg-white dark:bg-[#1C1917] border border-[#FED7AA] dark:border-[#44403C] h-auto gap-1 p-1">
                {[
                  { value: 'vision', icon: Eye, label: 'Vision' },
                  { value: 'motion', icon: Move, label: 'Motion' },
                  { value: 'language', icon: Globe, label: 'Language' },
                  { value: 'keyboard', icon: Keyboard, label: 'Keyboard' },
                  { value: 'screenreader', icon: Volume2, label: 'Screen Reader' },
                  { value: 'cultural', icon: Shield, label: 'Cultural' },
                ].map(({ value, icon: Icon, label }) => (
                  <TabsTrigger
                    key={value}
                    value={value}
                    className="flex-1 min-w-0 data-[state=active]:bg-[#FFF7ED] data-[state=active]:text-[#F97316] dark:data-[state=active]:bg-[#431407] text-xs sm:text-sm py-2 px-2"
                  >
                    <Icon className="w-3.5 h-3.5 mr-1 shrink-0" />
                    <span className="truncate">{label}</span>
                  </TabsTrigger>
                ))}
              </TabsList>

              {/* ═══════════════════════════════════════════════════════
                  VISION TAB
                  ═══════════════════════════════════════════════════════ */}
              <TabsContent value="vision" className="mt-0">
                <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                  {/* ── Vision Settings Card ──────────────────────── */}
                  <Card className="rounded-xl border-[#FED7AA] dark:border-[#44403C] bg-white dark:bg-[#1C1917] shadow-lg">
                    <CardHeader className="pb-4">
                      <CardTitle className="flex items-center gap-2 text-base text-[#1C1917] dark:text-[#F5F5F4]">
                        <Sun className="w-4 h-4 text-[#F97316]" />
                        Vision Settings
                      </CardTitle>
                      <CardDescription className="text-xs">
                        Adjust font size, contrast, and color vision support
                      </CardDescription>
                    </CardHeader>
                    <CardContent className="space-y-6">
                      {/* Font Scale */}
                      <div className="space-y-3">
                        <div className="flex items-center justify-between">
                          <Label className="text-sm font-medium text-[#1C1917] dark:text-[#F5F5F4]" htmlFor="font-scale-slider">
                            <Type className="w-3.5 h-3.5 inline mr-1.5 text-[#F97316]" />
                            Font Scale
                          </Label>
                          <Badge variant="outline" className="text-xs border-[#FED7AA] dark:border-[#44403C] text-[#F97316] font-mono">
                            {fontScale.toFixed(1)}×
                          </Badge>
                        </div>
                        <Slider
                          id="font-scale-slider"
                          min={1.0}
                          max={2.0}
                          step={0.1}
                          value={[fontScale]}
                          onValueChange={([v]) => setFontScale(v)}
                          aria-label="Font scale from 1.0 to 2.0"
                          className="w-full"
                        />
                        <div className="flex justify-between text-[10px] text-[#78716C] dark:text-[#A8A29E]">
                          <span>1.0× Normal</span>
                          <span>1.5× Large</span>
                          <span>2.0× Extra Large</span>
                        </div>
                        {/* Font preview */}
                        <div
                          className="p-3 rounded-lg bg-[#FFF7ED] dark:bg-[#292524] border border-[#FED7AA] dark:border-[#44403C]"
                          style={{ fontSize: `${16 * fontScale}px` }}
                        >
                          <p className="text-[#1C1917] dark:text-[#F5F5F4] font-medium">
                            Preview: राम कुमार — Father
                          </p>
                        </div>
                      </div>

                      <Separator className="bg-[#FED7AA] dark:bg-[#44403C]" />

                      {/* High Contrast Mode */}
                      <div className="flex items-center justify-between">
                        <div className="space-y-0.5">
                          <Label
                            htmlFor="high-contrast-toggle"
                            className="text-sm font-medium text-[#1C1917] dark:text-[#F5F5F4]"
                          >
                            <CircleDot className="w-3.5 h-3.5 inline mr-1.5 text-[#F97316]" />
                            High Contrast Mode
                          </Label>
                          <p className="text-[10px] text-[#78716C] dark:text-[#A8A29E]">
                            {isHighContrastOS
                              ? 'OS high contrast detected — override available'
                              : 'Enhance contrast for better visibility'}
                          </p>
                        </div>
                        <Switch
                          id="high-contrast-toggle"
                          checked={highContrastEnabled}
                          onCheckedChange={setHighContrastEnabled}
                          aria-label="Toggle high contrast mode"
                        />
                      </div>

                      {/* High contrast preview */}
                      <AnimatePresence>
                        {highContrastEnabled && (
                          <motion.div
                            initial={{ opacity: 0, height: 0 }}
                            animate={{ opacity: 1, height: 'auto' }}
                            exit={{ opacity: 0, height: 0 }}
                            className="overflow-hidden"
                          >
                            <div
                              className="p-3 rounded-lg border space-y-1"
                              style={{
                                backgroundColor: HighContrastTokens.background,
                                borderColor: HighContrastTokens.focusRing,
                              }}
                            >
                              <p style={{ color: HighContrastTokens.textOnBlack }} className="text-sm font-semibold">
                                High Contrast Preview
                              </p>
                              <div className="flex gap-2 flex-wrap text-xs">
                                <span style={{ color: HighContrastTokens.success }}>✓ Success</span>
                                <span style={{ color: HighContrastTokens.warning }}>⚠ Warning</span>
                                <span style={{ color: HighContrastTokens.error }}>✗ Error</span>
                                <span style={{ color: HighContrastTokens.info }}>ℹ Info</span>
                                <span style={{ color: HighContrastTokens.link }}>🔗 Link</span>
                                <span style={{ color: HighContrastTokens.disabled }}>Disabled</span>
                              </div>
                            </div>
                          </motion.div>
                        )}
                      </AnimatePresence>

                      <Separator className="bg-[#FED7AA] dark:bg-[#44403C]" />

                      {/* Color Blind Mode */}
                      <div className="space-y-2">
                        <Label className="text-sm font-medium text-[#1C1917] dark:text-[#F5F5F4]">
                          <Palette className="w-3.5 h-3.5 inline mr-1.5 text-[#F97316]" />
                          Color Vision Deficiency Mode
                        </Label>
                        <Select value={colorBlindMode} onValueChange={setColorBlindMode}>
                          <SelectTrigger className="w-full text-sm h-9" aria-label="Select color blind mode">
                            <SelectValue placeholder="Select mode" />
                          </SelectTrigger>
                          <SelectContent>
                            {COLOR_BLIND_MODES.map((mode) => (
                              <SelectItem key={mode.value} value={mode.value}>
                                <div className="flex flex-col">
                                  <span className="font-medium">{mode.label}</span>
                                  <span className="text-[10px] text-[#78716C]">{mode.description}</span>
                                </div>
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                        {colorBlindMode !== 'none' && (
                          <p className="text-[10px] text-[#F97316] flex items-center gap-1">
                            <Info className="w-3 h-3" />
                            Color blind mode active — UI will use Wong CVD-safe palette with icon pairing
                          </p>
                        )}
                      </div>
                    </CardContent>
                  </Card>

                  {/* ── Contrast Checker Card ──────────────────────── */}
                  <ContrastChecker />
                </div>
              </TabsContent>

              {/* ═══════════════════════════════════════════════════════
                  MOTION TAB
                  ═══════════════════════════════════════════════════════ */}
              <TabsContent value="motion" className="mt-0">
                <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                  {/* ── Motion Settings Card ──────────────────────── */}
                  <Card className="rounded-xl border-[#FED7AA] dark:border-[#44403C] bg-white dark:bg-[#1C1917] shadow-lg">
                    <CardHeader className="pb-4">
                      <CardTitle className="flex items-center gap-2 text-base text-[#1C1917] dark:text-[#F5F5F4]">
                        <Move className="w-4 h-4 text-[#F97316]" />
                        Motion Settings
                      </CardTitle>
                      <CardDescription className="text-xs">
                        Control animation behavior and speed
                      </CardDescription>
                    </CardHeader>
                    <CardContent className="space-y-6">
                      {/* Reduced Motion */}
                      <div className="flex items-center justify-between">
                        <div className="space-y-0.5">
                          <Label
                            htmlFor="reduced-motion-toggle"
                            className="text-sm font-medium text-[#1C1917] dark:text-[#F5F5F4]"
                          >
                            <Hand className="w-3.5 h-3.5 inline mr-1.5 text-[#F97316]" />
                            Reduced Motion
                          </Label>
                          <p className="text-[10px] text-[#78716C] dark:text-[#A8A29E]">
                            {prefersReducedMotion
                              ? 'OS preference detected — animations already reduced'
                              : 'Manually reduce animations for vestibular comfort'}
                          </p>
                        </div>
                        <Switch
                          id="reduced-motion-toggle"
                          checked={effectiveReducedMotion}
                          onCheckedChange={setReducedMotionOverride}
                          aria-label="Toggle reduced motion"
                        />
                      </div>

                      {/* Motion status badges */}
                      <div className="flex flex-wrap gap-2">
                        {prefersReducedMotion && (
                          <Badge className="bg-[#22C55E]/10 text-[#22C55E] border-[#22C55E]/20 text-[10px]">
                            OS: prefers-reduced-motion
                          </Badge>
                        )}
                        {reducedMotionOverride && (
                          <Badge className="bg-[#F97316]/10 text-[#F97316] border-[#F97316]/20 text-[10px]">
                            Manual override active
                          </Badge>
                        )}
                      </div>

                      <Separator className="bg-[#FED7AA] dark:bg-[#44403C]" />

                      {/* Animation Speed */}
                      <div className="space-y-3">
                        <div className="flex items-center justify-between">
                          <Label className="text-sm font-medium text-[#1C1917] dark:text-[#F5F5F4]" htmlFor="animation-speed-slider">
                            <Zap className="w-3.5 h-3.5 inline mr-1.5 text-[#F97316]" />
                            Animation Speed
                          </Label>
                          <Badge variant="outline" className="text-xs border-[#FED7AA] dark:border-[#44403C] text-[#F97316] font-mono">
                            {animationSpeed.toFixed(1)}×
                          </Badge>
                        </div>
                        <Slider
                          id="animation-speed-slider"
                          min={0.5}
                          max={2.0}
                          step={0.1}
                          value={[animationSpeed]}
                          onValueChange={([v]) => setAnimationSpeed(v)}
                          aria-label="Animation speed from 0.5x to 2.0x"
                          disabled={effectiveReducedMotion}
                          className="w-full"
                        />
                        <div className="flex justify-between text-[10px] text-[#78716C] dark:text-[#A8A29E]">
                          <span>0.5× Slow</span>
                          <span>1.0× Normal</span>
                          <span>2.0× Fast</span>
                        </div>
                        {effectiveReducedMotion && (
                          <p className="text-[10px] text-[#F97316] flex items-center gap-1">
                            <Info className="w-3 h-3" />
                            Speed slider disabled — reduced motion is active
                          </p>
                        )}
                      </div>
                    </CardContent>
                  </Card>

                  {/* ── Motion Tokens Card ────────────────────────── */}
                  <Card className="rounded-xl border-[#FED7AA] dark:border-[#44403C] bg-white dark:bg-[#1C1917] shadow-lg">
                    <CardHeader className="pb-4">
                      <CardTitle className="flex items-center gap-2 text-base text-[#1C1917] dark:text-[#F5F5F4]">
                        <Clock className="w-4 h-4 text-[#F97316]" />
                        Motion Tokens
                      </CardTitle>
                      <CardDescription className="text-xs">
                        Standard vs. reduced motion durations
                      </CardDescription>
                    </CardHeader>
                    <CardContent>
                      <ScrollArea className="max-h-72">
                        <div className="space-y-2">
                          {(['instant', 'fast', 'normal', 'slow'] as const).map((level) => {
                            const standard = duration(level, false);
                            const reduced = duration(level, true);
                            const effective = duration(level, effectiveReducedMotion);
                            const barWidth = Math.min((effective / 500) * 100, 100);

                            return (
                              <div
                                key={level}
                                className="flex items-center gap-3 p-2.5 rounded-lg bg-[#FFF7ED] dark:bg-[#292524] border border-[#FED7AA]/50 dark:border-[#44403C]/50"
                              >
                                <div className="w-16 text-xs font-mono font-semibold text-[#F97316] capitalize">
                                  {level}
                                </div>
                                <div className="flex-1 min-w-0">
                                  <div className="flex gap-2 text-[10px] text-[#78716C] dark:text-[#A8A29E] mb-1">
                                    <span>Std: {standard}ms</span>
                                    <span>•</span>
                                    <span>Reduced: {reduced}ms</span>
                                  </div>
                                  <div className="h-2 rounded-full bg-[#FED7AA] dark:bg-[#44403C] overflow-hidden">
                                    <motion.div
                                      className="h-full rounded-full bg-[#F97316]"
                                      initial={{ width: 0 }}
                                      animate={{ width: `${barWidth}%` }}
                                      transition={{ duration: effectiveReducedMotion ? 0.1 : 0.6 }}
                                    />
                                  </div>
                                </div>
                                <Badge
                                  variant="outline"
                                  className="text-[10px] shrink-0 border-[#FED7AA] dark:border-[#44403C] font-mono"
                                >
                                  {effective}ms
                                </Badge>
                              </div>
                            );
                          })}
                        </div>
                      </ScrollArea>

                      {/* Animation Demo */}
                      <Separator className="my-4 bg-[#FED7AA] dark:bg-[#44403C]" />
                      <div className="space-y-2">
                        <Label className="text-xs font-medium text-[#1C1917] dark:text-[#F5F5F4]">
                          Animation Preview
                        </Label>
                        <div className="flex items-center gap-4">
                          <motion.div
                            className="w-12 h-12 rounded-xl bg-gradient-to-br from-[#F97316] to-[#EA580C]"
                            animate={{
                              scale: [1, 1.15, 1],
                              rotate: effectiveReducedMotion ? 0 : [0, 5, -5, 0],
                            }}
                            transition={{
                              duration: duration('normal', effectiveReducedMotion) / 1000 * animationSpeed,
                              repeat: Infinity,
                              repeatDelay: 1,
                            }}
                          />
                          <div className="text-[10px] text-[#78716C] dark:text-[#A8A29E]">
                            <p>Duration: {duration('normal', effectiveReducedMotion)}ms</p>
                            <p>Speed: {animationSpeed}×</p>
                            <p>Rotation: {effectiveReducedMotion ? 'Disabled' : 'Enabled'}</p>
                          </div>
                        </div>
                      </div>
                    </CardContent>
                  </Card>
                </div>
              </TabsContent>

              {/* ═══════════════════════════════════════════════════════
                  LANGUAGE & REGION TAB
                  ═══════════════════════════════════════════════════════ */}
              <TabsContent value="language" className="mt-0">
                <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                  {/* ── Language Selector Card ────────────────────── */}
                  <Card className="rounded-xl border-[#FED7AA] dark:border-[#44403C] bg-white dark:bg-[#1C1917] shadow-lg">
                    <CardHeader className="pb-4">
                      <CardTitle className="flex items-center gap-2 text-base text-[#1C1917] dark:text-[#F5F5F4]">
                        <Languages className="w-4 h-4 text-[#F97316]" />
                        Language & Region
                      </CardTitle>
                      <CardDescription className="text-xs">
                        14 Indian languages with native script support
                      </CardDescription>
                    </CardHeader>
                    <CardContent className="space-y-5">
                      {/* Language Selector */}
                      <div className="space-y-2">
                        <Label className="text-sm font-medium text-[#1C1917] dark:text-[#F5F5F4]" htmlFor="locale-select">
                          <Globe className="w-3.5 h-3.5 inline mr-1.5 text-[#F97316]" />
                          Language
                        </Label>
                        <Select value={selectedLocale} onValueChange={setSelectedLocale}>
                          <SelectTrigger id="locale-select" className="w-full text-sm h-9" aria-label="Select language">
                            <SelectValue placeholder="Select language" />
                          </SelectTrigger>
                          <SelectContent>
                            {supportedLanguages.map((lang) => (
                              <SelectItem key={lang.code} value={lang.code}>
                                <div className="flex items-center gap-2">
                                  <span className="font-medium">{lang.nativeName}</span>
                                  <span className="text-[10px] text-[#78716C]">({lang.name})</span>
                                </div>
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      </div>

                      {/* Current language info */}
                      <div className="p-3 rounded-lg bg-[#FFF7ED] dark:bg-[#292524] border border-[#FED7AA] dark:border-[#44403C] space-y-2">
                        <div className="flex items-center justify-between">
                          <span className="text-xs text-[#78716C] dark:text-[#A8A29E]">Language</span>
                          <span className="text-sm font-semibold text-[#1C1917] dark:text-[#F5F5F4]">
                            {currentLang.name}
                          </span>
                        </div>
                        <div className="flex items-center justify-between">
                          <span className="text-xs text-[#78716C] dark:text-[#A8A29E]">Native</span>
                          <span className="text-sm font-semibold text-[#1C1917] dark:text-[#F5F5F4]">
                            {currentLang.nativeName}
                          </span>
                        </div>
                        <div className="flex items-center justify-between">
                          <span className="text-xs text-[#78716C] dark:text-[#A8A29E]">Script</span>
                          <span className="text-sm font-semibold text-[#1C1917] dark:text-[#F5F5F4]">
                            {currentLang.script}
                          </span>
                        </div>
                        <div className="flex items-center justify-between">
                          <span className="text-xs text-[#78716C] dark:text-[#A8A29E]">Direction</span>
                          <div className="flex items-center gap-1.5">
                            <Badge
                              className={`border-0 text-[10px] px-2 py-0.5 ${
                                isRTL
                                  ? 'bg-[#F97316]/10 text-[#F97316]'
                                  : 'bg-[#22C55E]/10 text-[#22C55E]'
                              }`}
                            >
                              <ArrowLeftRight className="w-2.5 h-2.5 mr-1" />
                              {currentDir.toUpperCase()}
                            </Badge>
                          </div>
                        </div>
                      </div>

                      {/* RTL indicator */}
                      <AnimatePresence>
                        {isRTL && (
                          <motion.div
                            initial={{ opacity: 0, y: -8 }}
                            animate={{ opacity: 1, y: 0 }}
                            exit={{ opacity: 0, y: -8 }}
                            className="p-3 rounded-lg bg-[#F97316]/5 border border-[#F97316]/20"
                            dir="rtl"
                          >
                            <p className="text-xs text-[#F97316] font-medium mb-1">
                              ← Right-to-Left Language Detected
                            </p>
                            <p className="text-[10px] text-[#78716C] dark:text-[#A8A29E]" dir="ltr">
                              UI layout will automatically mirror for RTL support.
                              Logical CSS properties handle padding, margins, and alignment.
                            </p>
                          </motion.div>
                        )}
                      </AnimatePresence>
                    </CardContent>
                  </Card>

                  {/* ── Formatting Previews Card ─────────────────── */}
                  <Card className="rounded-xl border-[#FED7AA] dark:border-[#44403C] bg-white dark:bg-[#1C1917] shadow-lg">
                    <CardHeader className="pb-4">
                      <CardTitle className="flex items-center gap-2 text-base text-[#1C1917] dark:text-[#F5F5F4]">
                        <BookOpen className="w-4 h-4 text-[#F97316]" />
                        Formatting Preview
                      </CardTitle>
                      <CardDescription className="text-xs">
                        Number and date formatting for Indian locale
                      </CardDescription>
                    </CardHeader>
                    <CardContent className="space-y-5">
                      {/* Number Format */}
                      <div className="space-y-2">
                        <Label className="text-xs font-medium text-[#57534E] dark:text-[#A8A29E]">
                          Indian Number Format (Lakhs / Crores)
                        </Label>
                        <div className="p-3 rounded-lg bg-[#FFF7ED] dark:bg-[#292524] border border-[#FED7AA] dark:border-[#44403C] space-y-2">
                          {[
                            { raw: 100000, label: '1 Lakh' },
                            { raw: 1500000, label: '15 Lakhs' },
                            { raw: 10000000, label: '1 Crore' },
                            { raw: 123456789, label: '12.34 Crores' },
                          ].map(({ raw, label }) => (
                            <div key={raw} className="flex items-center justify-between">
                              <span className="text-xs text-[#78716C] dark:text-[#A8A29E]">{label}</span>
                              <span className="text-sm font-mono font-semibold text-[#1C1917] dark:text-[#F5F5F4]">
                                {formatIndianNumber(raw)}
                              </span>
                            </div>
                          ))}
                        </div>
                      </div>

                      <Separator className="bg-[#FED7AA] dark:bg-[#44403C]" />

                      {/* Date Format */}
                      <div className="space-y-2">
                        <Label className="text-xs font-medium text-[#57534E] dark:text-[#A8A29E]">
                          Date Format in Selected Locale
                        </Label>
                        <div className="p-3 rounded-lg bg-[#FFF7ED] dark:bg-[#292524] border border-[#FED7AA] dark:border-[#44403C]">
                          <div className="flex items-center justify-between mb-1">
                            <span className="text-xs text-[#78716C] dark:text-[#A8A29E]">English (en)</span>
                            <span className="text-sm font-mono text-[#1C1917] dark:text-[#F5F5F4]">
                              15 January 2025
                            </span>
                          </div>
                          <div className="flex items-center justify-between">
                            <span className="text-xs text-[#78716C] dark:text-[#A8A29E]">
                              {currentLang.name} ({selectedLocale})
                            </span>
                            <span
                              className="text-sm font-mono font-semibold text-[#F97316]"
                              dir={currentDir}
                            >
                              {datePreview}
                            </span>
                          </div>
                        </div>
                      </div>

                      <Separator className="bg-[#FED7AA] dark:bg-[#44403C]" />

                      {/* Relationship name preview */}
                      <div className="space-y-2">
                        <Label className="text-xs font-medium text-[#57534E] dark:text-[#A8A29E]">
                          Relationship Names in {currentLang.name}
                        </Label>
                        <ScrollArea className="max-h-48">
                          <div className="space-y-1.5">
                            {['father', 'mother', 'spouse', 'bua', 'chacha', 'mama', 'devar', 'nanad'].map((rel) => (
                              <div
                                key={rel}
                                className="flex items-center justify-between p-2 rounded-md bg-[#FFF7ED] dark:bg-[#292524] border border-[#FED7AA]/30 dark:border-[#44403C]/30"
                              >
                                <span className="text-xs text-[#78716C] dark:text-[#A8A29E] capitalize">
                                  {rel.replace(/_/g, ' ')}
                                </span>
                                <span
                                  className="text-sm font-medium text-[#1C1917] dark:text-[#F5F5F4]"
                                  dir={currentDir}
                                >
                                  {getRelationshipLabel(rel, selectedLocale)}
                                </span>
                              </div>
                            ))}
                          </div>
                        </ScrollArea>
                      </div>
                    </CardContent>
                  </Card>
                </div>
              </TabsContent>

              {/* ═══════════════════════════════════════════════════════
                  KEYBOARD NAVIGATION TAB
                  ═══════════════════════════════════════════════════════ */}
              <TabsContent value="keyboard" className="mt-0">
                <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                  {/* ── Keyboard Shortcuts Card ───────────────────── */}
                  <Card className="rounded-xl border-[#FED7AA] dark:border-[#44403C] bg-white dark:bg-[#1C1917] shadow-lg">
                    <CardHeader className="pb-4">
                      <CardTitle className="flex items-center gap-2 text-base text-[#1C1917] dark:text-[#F5F5F4]">
                        <Keyboard className="w-4 h-4 text-[#F97316]" />
                        Keyboard Shortcuts
                      </CardTitle>
                      <CardDescription className="text-xs">
                        All keyboard shortcuts for graph navigation
                      </CardDescription>
                    </CardHeader>
                    <CardContent>
                      <ScrollArea className="max-h-80">
                        <div className="space-y-1.5">
                          {KEYBOARD_SHORTCUT_LIST.map((shortcut, i) => (
                            <div
                              key={i}
                              className="flex items-center justify-between p-2.5 rounded-lg bg-[#FFF7ED] dark:bg-[#292524] border border-[#FED7AA]/50 dark:border-[#44403C]/50"
                            >
                              <span className="text-xs text-[#78716C] dark:text-[#A8A29E]">
                                {shortcut.action}
                              </span>
                              <div className="flex gap-1">
                                {shortcut.keys.split(' / ').map((key, ki) => (
                                  <kbd
                                    key={ki}
                                    className="inline-flex items-center justify-center min-w-[28px] h-6 px-1.5 rounded border border-[#FED7AA] dark:border-[#44403C] bg-white dark:bg-[#1C1917] text-xs font-mono font-semibold text-[#1C1917] dark:text-[#F5F5F4]"
                                  >
                                    {key}
                                  </kbd>
                                ))}
                              </div>
                            </div>
                          ))}
                        </div>
                      </ScrollArea>
                    </CardContent>
                  </Card>

                  {/* ── Focus Indicators Card ─────────────────────── */}
                  <Card className="rounded-xl border-[#FED7AA] dark:border-[#44403C] bg-white dark:bg-[#1C1917] shadow-lg">
                    <CardHeader className="pb-4">
                      <CardTitle className="flex items-center gap-2 text-base text-[#1C1917] dark:text-[#F5F5F4]">
                        <CircleDot className="w-4 h-4 text-[#F97316]" />
                        Focus Indicators
                      </CardTitle>
                      <CardDescription className="text-xs">
                        Visual demo of focus rings — use Tab to navigate
                      </CardDescription>
                    </CardHeader>
                    <CardContent className="space-y-5">
                      <FocusRingDemo />

                      <Separator className="bg-[#FED7AA] dark:bg-[#44403C]" />

                      {/* Focus tokens display */}
                      <div className="space-y-2">
                        <Label className="text-xs font-medium text-[#57534E] dark:text-[#A8A29E]">
                          Focus Token Values
                        </Label>
                        <div className="grid grid-cols-2 gap-2">
                          {[
                            { label: 'Color', value: FocusTokens.color, type: 'color' },
                            { label: 'Width', value: `${FocusTokens.width}px`, type: 'text' },
                            { label: 'Offset', value: `${FocusTokens.offset}px`, type: 'text' },
                            { label: 'Radius', value: `${FocusTokens.borderRadius}px`, type: 'text' },
                            { label: 'Keyboard Only', value: FocusTokens.keyboardOnly ? 'Yes' : 'No', type: 'text' },
                            { label: 'HC Color', value: HighContrastTokens.focusRing, type: 'color' },
                          ].map((token) => (
                            <div
                              key={token.label}
                              className="flex items-center gap-2 p-2 rounded-md bg-[#FFF7ED] dark:bg-[#292524] border border-[#FED7AA]/30 dark:border-[#44403C]/30"
                            >
                              {token.type === 'color' && (
                                <div
                                  className="w-4 h-4 rounded-sm border border-black/10 dark:border-white/10 shrink-0"
                                  style={{ backgroundColor: token.value as string }}
                                />
                              )}
                              <div className="min-w-0">
                                <div className="text-[10px] text-[#78716C] dark:text-[#A8A29E]">{token.label}</div>
                                <div className="text-xs font-mono font-semibold text-[#1C1917] dark:text-[#F5F5F4] truncate">
                                  {token.value}
                                </div>
                              </div>
                            </div>
                          ))}
                        </div>
                      </div>

                      <Separator className="bg-[#FED7AA] dark:bg-[#44403C]" />

                      {/* Severity colors */}
                      <div className="space-y-2">
                        <Label className="text-xs font-medium text-[#57534E] dark:text-[#A8A29E]">
                          A11y Severity Colors
                        </Label>
                        <div className="grid grid-cols-2 gap-2">
                          {(['mild', 'moderate', 'severe', 'critical'] as const).map((level) => (
                            <div
                              key={level}
                              className="flex items-center gap-2 p-2 rounded-md bg-[#FFF7ED] dark:bg-[#292524] border border-[#FED7AA]/30 dark:border-[#44403C]/30"
                            >
                              <div
                                className="w-4 h-4 rounded-sm shrink-0"
                                style={{ backgroundColor: getSeverityColor(level) }}
                              />
                              <span className="text-xs font-medium text-[#1C1917] dark:text-[#F5F5F4] capitalize">
                                {level}
                              </span>
                              <span className="text-[10px] font-mono text-[#78716C] dark:text-[#A8A29E] ml-auto">
                                {getSeverityColor(level)}
                              </span>
                            </div>
                          ))}
                        </div>
                      </div>
                    </CardContent>
                  </Card>
                </div>
              </TabsContent>

              {/* ═══════════════════════════════════════════════════════
                  SCREEN READER TAB
                  ═══════════════════════════════════════════════════════ */}
              <TabsContent value="screenreader" className="mt-0">
                <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                  {/* ── Screen Reader Demo Card ──────────────────── */}
                  <Card className="rounded-xl border-[#FED7AA] dark:border-[#44403C] bg-white dark:bg-[#1C1917] shadow-lg">
                    <CardHeader className="pb-4">
                      <CardTitle className="flex items-center gap-2 text-base text-[#1C1917] dark:text-[#F5F5F4]">
                        <Volume2 className="w-4 h-4 text-[#F97316]" />
                        Screen Reader Announcements
                      </CardTitle>
                      <CardDescription className="text-xs">
                        Test ARIA live region announcements
                      </CardDescription>
                    </CardHeader>
                    <CardContent className="space-y-5">
                      {/* Priority toggle */}
                      <div className="space-y-2">
                        <Label className="text-sm font-medium text-[#1C1917] dark:text-[#F5F5F4]">
                          Announcement Priority
                        </Label>
                        <div className="flex items-center gap-3 p-3 rounded-lg bg-[#FFF7ED] dark:bg-[#292524] border border-[#FED7AA] dark:border-[#44403C]">
                          <button
                            className={`flex-1 py-2 px-3 rounded-lg text-xs font-medium transition-all ${
                              announcePriority === 'polite'
                                ? 'bg-[#F97316] text-white shadow-md'
                                : 'bg-white dark:bg-[#1C1917] text-[#78716C] dark:text-[#A8A29E] border border-[#FED7AA] dark:border-[#44403C]'
                            }`}
                            onClick={() => setAnnouncePriority('polite')}
                            role="radio"
                            aria-checked={announcePriority === 'polite'}
                          >
                            Polite
                          </button>
                          <button
                            className={`flex-1 py-2 px-3 rounded-lg text-xs font-medium transition-all ${
                              announcePriority === 'assertive'
                                ? 'bg-[#EF4444] text-white shadow-md'
                                : 'bg-white dark:bg-[#1C1917] text-[#78716C] dark:text-[#A8A29E] border border-[#FED7AA] dark:border-[#44403C]'
                            }`}
                            onClick={() => setAnnouncePriority('assertive')}
                            role="radio"
                            aria-checked={announcePriority === 'assertive'}
                          >
                            Assertive
                          </button>
                        </div>
                        <p className="text-[10px] text-[#78716C] dark:text-[#A8A29E]">
                          {announcePriority === 'polite'
                            ? 'Polite: waits for current speech to finish before announcing'
                            : 'Assertive: interrupts current speech immediately'}
                        </p>
                      </div>

                      {/* Demo button */}
                      <Button
                        onClick={handleAnnounce}
                        className="w-full bg-[#F97316] hover:bg-[#EA580C] text-white"
                        aria-label={`Trigger ${announcePriority} screen reader announcement`}
                      >
                        <Volume2 className="w-4 h-4 mr-2" />
                        Announce ({announcePriority})
                      </Button>

                      {/* Last announcement display */}
                      <AnimatePresence>
                        {lastAnnouncement && (
                          <motion.div
                            initial={{ opacity: 0, y: 8 }}
                            animate={{ opacity: 1, y: 0 }}
                            exit={{ opacity: 0, y: -8 }}
                            className="p-3 rounded-lg bg-[#22C55E]/5 border border-[#22C55E]/20"
                          >
                            <div className="flex items-center gap-2 mb-1">
                              <Check className="w-3 h-3 text-[#22C55E]" />
                              <span className="text-[10px] font-medium text-[#22C55E]">
                                Announcement sent
                              </span>
                              <Badge className="text-[8px] border-0 px-1.5 py-0 ml-auto bg-[#F97316]/10 text-[#F97316]">
                                {announcePriority}
                              </Badge>
                            </div>
                            <p className="text-xs text-[#1C1917] dark:text-[#F5F5F4]">
                              &ldquo;{lastAnnouncement}&rdquo;
                            </p>
                          </motion.div>
                        )}
                      </AnimatePresence>
                    </CardContent>
                  </Card>

                  {/* ── ARIA Live Regions Info Card ──────────────── */}
                  <Card className="rounded-xl border-[#FED7AA] dark:border-[#44403C] bg-white dark:bg-[#1C1917] shadow-lg">
                    <CardHeader className="pb-4">
                      <CardTitle className="flex items-center gap-2 text-base text-[#1C1917] dark:text-[#F5F5F4]">
                        <Info className="w-4 h-4 text-[#F97316]" />
                        How Screen Readers Work
                      </CardTitle>
                      <CardDescription className="text-xs">
                        Understanding ARIA live regions in KINREL
                      </CardDescription>
                    </CardHeader>
                    <CardContent>
                      <ScrollArea className="max-h-80">
                        <div className="space-y-3">
                          {[
                            {
                              title: 'Polite Live Region',
                              description: 'Announces when the screen reader is idle. Best for non-urgent updates like "Family tree loaded with 24 members".',
                              id: 'a11y-announce-polite',
                              color: '#F97316',
                            },
                            {
                              title: 'Assertive Live Region',
                              description: 'Immediately interrupts. Used for errors and critical updates like "Error: Failed to save health condition".',
                              id: 'a11y-announce-assertive',
                              color: '#EF4444',
                            },
                            {
                              title: 'Navigation Announcements',
                              description: 'Announces view transitions: "Navigated from Family Tree to Health Conditions".',
                              id: 'nav-announce',
                              color: '#1565C0',
                            },
                            {
                              title: 'Condition Privacy',
                              description: 'Health conditions include protection level: "Added condition with elevated privacy protection — sharing is restricted".',
                              id: 'condition-announce',
                              color: '#22C55E',
                            },
                            {
                              title: 'Deceased Respect',
                              description: 'Uses respectful language: "Marked [Name] as deceased" with appropriate cultural sensitivity.',
                              id: 'deceased-announce',
                              color: '#78716C',
                            },
                          ].map((item) => (
                            <div
                              key={item.id}
                              className="p-3 rounded-lg bg-[#FFF7ED] dark:bg-[#292524] border border-[#FED7AA]/50 dark:border-[#44403C]/50"
                            >
                              <div className="flex items-center gap-2 mb-1">
                                <div
                                  className="w-2 h-2 rounded-full shrink-0"
                                  style={{ backgroundColor: item.color }}
                                />
                                <span className="text-xs font-semibold text-[#1C1917] dark:text-[#F5F5F4]">
                                  {item.title}
                                </span>
                              </div>
                              <p className="text-[10px] text-[#78716C] dark:text-[#A8A29E] leading-relaxed pl-4">
                                {item.description}
                              </p>
                            </div>
                          ))}
                        </div>
                      </ScrollArea>
                    </CardContent>
                  </Card>
                </div>
              </TabsContent>

              {/* ═══════════════════════════════════════════════════════
                  CULTURAL SENSITIVITY TAB
                  ═══════════════════════════════════════════════════════ */}
              <TabsContent value="cultural" className="mt-0">
                <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                  {/* ── Gotra Visibility Card ────────────────────── */}
                  <Card className="rounded-xl border-[#FED7AA] dark:border-[#44403C] bg-white dark:bg-[#1C1917] shadow-lg">
                    <CardHeader className="pb-4">
                      <CardTitle className="flex items-center gap-2 text-base text-[#1C1917] dark:text-[#F5F5F4]">
                        <Shield className="w-4 h-4 text-[#F97316]" />
                        Gotra Visibility Rules
                      </CardTitle>
                      <CardDescription className="text-xs">
                        3-tier visibility for Hindu lineage data
                      </CardDescription>
                    </CardHeader>
                    <CardContent>
                      <div className="space-y-2">
                        {Object.entries(GOTRA_VISIBILITY_RULES).map(([context, rule]) => {
                          const ruleColor =
                            rule === true
                              ? '#22C55E'
                              : rule === false
                                ? '#EF4444'
                                : rule === 'consent_required'
                                  ? '#F97316'
                                  : '#EAB308';

                          const ruleLabel =
                            rule === true
                              ? 'Always Visible'
                              : rule === false
                                ? 'Never Visible'
                                : rule === 'consent_required'
                                  ? 'Consent Required'
                                  : 'Restricted (Audit)';

                          return (
                            <div
                              key={context}
                              className="flex items-center justify-between p-2.5 rounded-lg bg-[#FFF7ED] dark:bg-[#292524] border border-[#FED7AA]/50 dark:border-[#44403C]/50"
                            >
                              <div className="flex items-center gap-2">
                                <div
                                  className="w-2.5 h-2.5 rounded-full shrink-0"
                                  style={{ backgroundColor: ruleColor }}
                                />
                                <span className="text-xs font-medium text-[#1C1917] dark:text-[#F5F5F4] capitalize">
                                  {context.replace(/_/g, ' ')}
                                </span>
                              </div>
                              <Badge
                                className="text-[10px] border-0 px-2 py-0.5"
                                style={{
                                  backgroundColor: `${ruleColor}15`,
                                  color: ruleColor,
                                }}
                              >
                                {ruleLabel}
                              </Badge>
                            </div>
                          );
                        })}
                      </div>
                      <p className="mt-3 text-[10px] text-[#78716C] dark:text-[#A8A29E] leading-relaxed">
                        Gotra is a Hindu lineage system affecting matrimonial decisions.
                        Revealing it inappropriately can cause social issues.
                        Three tiers: Never visible (red), Consent required (orange), Always visible (green).
                      </p>
                    </CardContent>
                  </Card>

                  {/* ── Stigma Protection Card ───────────────────── */}
                  <Card className="rounded-xl border-[#FED7AA] dark:border-[#44403C] bg-white dark:bg-[#1C1917] shadow-lg">
                    <CardHeader className="pb-4">
                      <CardTitle className="flex items-center gap-2 text-base text-[#1C1917] dark:text-[#F5F5F4]">
                        <Heart className="w-4 h-4 text-[#F97316]" />
                        Stigma Protection Levels
                      </CardTitle>
                      <CardDescription className="text-xs">
                        Privacy tiers for stigmatized health conditions
                      </CardDescription>
                    </CardHeader>
                    <CardContent>
                      <div className="space-y-3">
                        {(['standard', 'elevated', 'maximum'] as const).map((level) => {
                          const protection = STIGMA_PROTECTION[level];
                          const levelColor = level === 'standard' ? '#22C55E' : level === 'elevated' ? '#F97316' : '#EF4444';
                          const exampleConditions =
                            level === 'standard'
                              ? 'diabetes, hypertension'
                              : level === 'elevated'
                                ? 'depression, epilepsy, PCOS'
                                : 'HIV, suicidal ideation, leprosy';

                          return (
                            <div
                              key={level}
                              className="p-3 rounded-lg border"
                              style={{
                                backgroundColor: `${levelColor}05`,
                                borderColor: `${levelColor}20`,
                              }}
                            >
                              <div className="flex items-center gap-2 mb-2">
                                <div
                                  className="w-2.5 h-2.5 rounded-full shrink-0"
                                  style={{ backgroundColor: levelColor }}
                                />
                                <span className="text-xs font-bold capitalize text-[#1C1917] dark:text-[#F5F5F4]">
                                  {level}
                                </span>
                                <Badge
                                  className="text-[8px] border-0 px-1.5 py-0 ml-auto"
                                  style={{ backgroundColor: `${levelColor}15`, color: levelColor }}
                                >
                                  {protection.retentionDays ?? '∞'} days
                                </Badge>
                              </div>
                              <div className="grid grid-cols-2 gap-x-4 gap-y-1 text-[10px]">
                                <div className="flex items-center gap-1">
                                  {protection.defaultPrivate ? <Check className="w-2.5 h-2.5 text-[#22C55E]" /> : <XCircle className="w-2.5 h-2.5 text-[#EF4444]" />}
                                  <span className="text-[#78716C] dark:text-[#A8A29E]">Private by default</span>
                                </div>
                                <div className="flex items-center gap-1">
                                  {protection.shareInPatterns ? <Check className="w-2.5 h-2.5 text-[#22C55E]" /> : <XCircle className="w-2.5 h-2.5 text-[#EF4444]" />}
                                  <span className="text-[#78716C] dark:text-[#A8A29E]">Pattern sharing</span>
                                </div>
                                <div className="flex items-center gap-1">
                                  {protection.aggregateInsights ? <Check className="w-2.5 h-2.5 text-[#22C55E]" /> : <XCircle className="w-2.5 h-2.5 text-[#EF4444]" />}
                                  <span className="text-[#78716C] dark:text-[#A8A29E]">Aggregate insights</span>
                                </div>
                                <div className="flex items-center gap-1">
                                  {protection.requireDoubleConsent ? <Check className="w-2.5 h-2.5 text-[#F97316]" /> : <XCircle className="w-2.5 h-2.5 text-[#78716C]" />}
                                  <span className="text-[#78716C] dark:text-[#A8A29E]">Double consent</span>
                                </div>
                                <div className="flex items-center gap-1">
                                  {protection.excludeFromSearch ? <Check className="w-2.5 h-2.5 text-[#F97316]" /> : <XCircle className="w-2.5 h-2.5 text-[#78716C]" />}
                                  <span className="text-[#78716C] dark:text-[#A8A29E]">Excluded from search</span>
                                </div>
                                <div className="flex items-center gap-1">
                                  {protection.excludeFromExport ? <Check className="w-2.5 h-2.5 text-[#F97316]" /> : <XCircle className="w-2.5 h-2.5 text-[#78716C]" />}
                                  <span className="text-[#78716C] dark:text-[#A8A29E]">Excluded from export</span>
                                </div>
                              </div>
                              <p className="mt-2 text-[9px] text-[#78716C] dark:text-[#A8A29E] italic">
                                Examples: {exampleConditions}
                              </p>
                            </div>
                          );
                        })}
                      </div>
                    </CardContent>
                  </Card>

                  {/* ── Memorial Customs Card ────────────────────── */}
                  <Card className="rounded-xl border-[#FED7AA] dark:border-[#44403C] bg-white dark:bg-[#1C1917] shadow-lg lg:col-span-2">
                    <CardHeader className="pb-4">
                      <CardTitle className="flex items-center gap-2 text-base text-[#1C1917] dark:text-[#F5F5F4]">
                        <BookOpen className="w-4 h-4 text-[#F97316]" />
                        Religious Memorial Customs
                      </CardTitle>
                      <CardDescription className="text-xs">
                        Culturally respectful handling of deceased person information
                      </CardDescription>
                    </CardHeader>
                    <CardContent>
                      {/* Religion selector */}
                      <div className="flex flex-wrap gap-2 mb-4">
                        {Object.keys(RELIGIOUS_MEMORIAL_RULES).map((religion) => (
                          <button
                            key={religion}
                            onClick={() => setSelectedReligion(religion)}
                            className={`px-3 py-1.5 rounded-lg text-xs font-medium transition-all capitalize ${
                              selectedReligion === religion
                                ? 'bg-[#F97316] text-white shadow-md'
                                : 'bg-[#FFF7ED] dark:bg-[#292524] text-[#78716C] dark:text-[#A8A29E] border border-[#FED7AA] dark:border-[#44403C] hover:text-[#F97316]'
                            }`}
                            role="tab"
                            aria-selected={selectedReligion === religion}
                            aria-label={`View ${religion} memorial customs`}
                          >
                            {religion}
                          </button>
                        ))}
                      </div>

                      {/* Selected religion details */}
                      <AnimatePresence mode="wait">
                        {(() => {
                          const rules = RELIGIOUS_MEMORIAL_RULES[selectedReligion as keyof typeof RELIGIOUS_MEMORIAL_RULES];
                          if (!rules) return null;
                          return (
                            <motion.div
                              key={selectedReligion}
                              initial={{ opacity: 0, y: 8 }}
                              animate={{ opacity: 1, y: 0 }}
                              exit={{ opacity: 0, y: -8 }}
                              transition={{ duration: effectiveReducedMotion ? 0 : 0.2 }}
                              className="grid grid-cols-1 md:grid-cols-3 gap-4"
                            >
                              {/* Guidelines */}
                              <div className="p-4 rounded-lg bg-[#FFF7ED] dark:bg-[#292524] border border-[#FED7AA] dark:border-[#44403C]">
                                <h4 className="text-xs font-bold text-[#22C55E] mb-2 flex items-center gap-1.5">
                                  <Check className="w-3 h-3" />
                                  Guidelines
                                </h4>
                                <ul className="space-y-1.5">
                                  {rules.guidelines.map((g, i) => (
                                    <li key={i} className="text-[10px] text-[#57534E] dark:text-[#A8A29E] flex items-start gap-1.5">
                                      <ChevronRight className="w-2.5 h-2.5 text-[#F97316] shrink-0 mt-0.5" />
                                      {g}
                                    </li>
                                  ))}
                                </ul>
                              </div>

                              {/* Memorial Period */}
                              <div className="p-4 rounded-lg bg-[#FFF7ED] dark:bg-[#292524] border border-[#FED7AA] dark:border-[#44403C]">
                                <h4 className="text-xs font-bold text-[#F97316] mb-2 flex items-center gap-1.5">
                                  <Clock className="w-3 h-3" />
                                  Memorial Period
                                </h4>
                                <p className="text-sm font-semibold text-[#1C1917] dark:text-[#F5F5F4] mb-2">
                                  {rules.memorialPeriod}
                                </p>
                                <p className="text-[10px] text-[#78716C] dark:text-[#A8A29E]">
                                  The period during which special handling of the deceased person&apos;s information is required.
                                </p>
                              </div>

                              {/* Restrictions */}
                              <div className="p-4 rounded-lg bg-[#FFF7ED] dark:bg-[#292524] border border-[#FED7AA] dark:border-[#44403C]">
                                <h4 className="text-xs font-bold text-[#EF4444] mb-2 flex items-center gap-1.5">
                                  <AlertTriangle className="w-3 h-3" />
                                  Restrictions
                                </h4>
                                <ul className="space-y-1.5">
                                  {rules.restrictions.map((r, i) => (
                                    <li key={i} className="text-[10px] text-[#57534E] dark:text-[#A8A29E] flex items-start gap-1.5">
                                      <XCircle className="w-2.5 h-2.5 text-[#EF4444] shrink-0 mt-0.5" />
                                      {r}
                                    </li>
                                  ))}
                                </ul>
                              </div>
                            </motion.div>
                          );
                        })()}
                      </AnimatePresence>
                    </CardContent>
                  </Card>
                </div>
              </TabsContent>
            </Tabs>
          </motion.div>
        </div>
      </motion.section>
    </TooltipProvider>
  );
}
