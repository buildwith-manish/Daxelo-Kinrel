'use client';

import { useState } from 'react';
import { motion } from 'framer-motion';
import {
  Shield, Eye, EyeOff, Lock, ChevronDown, ChevronUp,
  AlertTriangle, Heart, User, Info,
} from 'lucide-react';
import {
  canViewGotra,
  getStigmaProtectionLevel,
  isStigmatizedCondition,
  safeDisplayName,
  requiresConfirmation,
  displayName as getDisplayName,
  STIGMA_PROTECTION,
} from '@/lib/accessibility/cultural-sensitivity';
import { avatarColorForName } from '@/lib/avatar-colors';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Separator } from '@/components/ui/separator';
import { useReducedMotion } from '@/hooks/use-accessibility';

// ── Types ──────────────────────────────────────────────────────────
type PersonData = {
  id: string;
  name: string;
  nickname?: string;
  privacyLevel: 'public' | 'private' | 'restricted';
  gotra?: string;
  healthConditions?: string[];
  relationshipKey?: string;
  religion?: string;
  isDeceased?: boolean;
  birthYear?: number;
};

type ViewerRole = 'self' | 'admin' | 'family' | 'extended' | 'public' | 'search' | 'matrimonial' | 'api';

type PrivacyPersonCardProps = {
  person: PersonData;
  viewerRole: ViewerRole;
  defaultExpand?: boolean;
  className?: string;
};

// ── Protection Level Badge ─────────────────────────────────────────
function ProtectionBadge({ level }: { level: 'standard' | 'elevated' | 'maximum' }) {
  const config = {
    standard: { color: 'bg-[#22C55E] text-white', icon: Shield, label: 'Standard' },
    elevated: { color: 'bg-[#F59E0B] text-white', icon: AlertTriangle, label: 'Elevated' },
    maximum: { color: 'bg-[#EF4444] text-white', icon: Lock, label: 'Maximum' },
  };
  const c = config[level];
  return (
    <Badge className={`${c.color} border-0 text-[10px] gap-1`}>
      <c.icon className="w-3 h-3" />
      {c.label}
    </Badge>
  );
}

// ── Component ──────────────────────────────────────────────────────
export function PrivacyPersonCard({
  person,
  viewerRole,
  defaultExpand = false,
  className = '',
}: PrivacyPersonCardProps) {
  const [expanded, setExpanded] = useState(defaultExpand);
  const [gotraConsent, setGotraConsent] = useState(false);
  const [confirmSensitive, setConfirmSensitive] = useState(false);
  const [showHealthDetails, setShowHealthDetails] = useState(false);
  const prefersReducedMotion = useReducedMotion();

  // Computed display name
  const display = getDisplayName(viewerRole, {
    name: person.name,
    nickname: person.nickname,
    privacyLevel: person.privacyLevel,
  });

  // Gotra visibility
  const canSeeGotra = canViewGotra(viewerRole, gotraConsent);

  // Relationship display
  const relationshipDisplay = person.relationshipKey
    ? safeDisplayName(person.relationshipKey, true)
    : null;
  const needsConfirm = person.relationshipKey
    ? requiresConfirmation(person.relationshipKey)
    : false;

  // Health condition protection
  const protectedConditions = (person.healthConditions || []).map((c) => ({
    condition: c,
    isStigmatized: isStigmatizedCondition(c),
    level: getStigmaProtectionLevel(c),
  }));

  // Avatar color
  const avatarColor = avatarColorForName(person.name);
  const initials = person.name.split(' ').map((n) => n[0]).join('').slice(0, 2).toUpperCase();

  // Whether current viewer can see health conditions
  const canSeeHealth = viewerRole === 'self' || viewerRole === 'admin' || viewerRole === 'family';

  return (
    <motion.div
      initial={prefersReducedMotion ? false : { opacity: 0, y: 8 }}
      animate={prefersReducedMotion ? undefined : { opacity: 1, y: 0 }}
      transition={{ duration: 0.3, ease: [0, 0, 0.2, 1] }}
    >
      <Card className={`rounded-2xl border-[#FED7AA] dark:border-[#44403C] bg-white dark:bg-[#1C1917] shadow-lg overflow-hidden ${className}`}>
        <CardContent className="p-4">
          {/* ── Header: Avatar + Name + Badges ────────────────────── */}
          <div className="flex items-start gap-3">
            {/* Avatar */}
            <div
              className="w-12 h-12 rounded-xl flex items-center justify-center text-white font-bold text-sm shrink-0 shadow-md"
              style={{ backgroundColor: avatarColor }}
            >
              {person.isDeceased ? '✦' : initials}
            </div>

            {/* Name & relationship */}
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2 flex-wrap">
                <h3 className="font-bold text-[#1C1917] dark:text-[#F5F5F4] truncate">
                  {display}
                </h3>
                {person.isDeceased && (
                  <Badge className="bg-[#78716C] text-white border-0 text-[10px]">Late</Badge>
                )}
                {person.privacyLevel === 'private' && (
                  <Lock className="w-3.5 h-3.5 text-[#78716C] dark:text-[#A8A29E]" />
                )}
              </div>

              {relationshipDisplay && (
                <p className="text-xs text-[#F97316] font-medium mt-0.5">
                  {needsConfirm && !confirmSensitive ? (
                    <button
                      onClick={() => setConfirmSensitive(true)}
                      className="flex items-center gap-1 underline decoration-dotted underline-offset-2 hover:text-[#EA580C] transition-colors"
                    >
                      <AlertTriangle className="w-3 h-3" />
                      Tap to reveal relationship
                    </button>
                  ) : (
                    relationshipDisplay
                  )}
                </p>
              )}

              {person.birthYear && (
                <p className="text-[10px] text-[#78716C] dark:text-[#A8A29E] mt-0.5">
                  Born {person.birthYear}
                </p>
              )}
            </div>

            {/* Viewer role badge */}
            <Badge variant="outline" className="text-[10px] border-[#FED7AA] dark:border-[#44403C] text-[#57534E] dark:text-[#A8A29E] shrink-0">
              {viewerRole}
            </Badge>
          </div>

          {/* ── Expand Button ────────────────────────────────────── */}
          <button
            onClick={() => setExpanded(!expanded)}
            className="flex items-center gap-1 text-xs text-[#F97316] font-medium mt-3 hover:text-[#EA580C] transition-colors"
            aria-expanded={expanded}
            aria-label={`${expanded ? 'Hide' : 'Show'} privacy details`}
          >
            {expanded ? <ChevronUp className="w-3.5 h-3.5" /> : <ChevronDown className="w-3.5 h-3.5" />}
            {expanded ? 'Hide' : 'Show'} privacy details
          </button>

          {/* ── Expanded Details ──────────────────────────────────── */}
          {expanded && (
            <motion.div
              initial={prefersReducedMotion ? false : { height: 0, opacity: 0 }}
              animate={prefersReducedMotion ? undefined : { height: 'auto', opacity: 1 }}
              transition={{ duration: 0.3, ease: [0, 0, 0.2, 1] }}
              className="mt-3 space-y-3"
            >
              {/* Gotra Section */}
              {person.gotra && (
                <div className="p-3 rounded-xl bg-[#FFF7ED] dark:bg-[#292524] border border-[#FED7AA] dark:border-[#44403C]">
                  <div className="flex items-center justify-between mb-1">
                    <span className="text-xs font-semibold text-[#1C1917] dark:text-[#F5F5F4]">Gotra</span>
                    {canSeeGotra ? (
                      <Eye className="w-3.5 h-3.5 text-[#22C55E]" />
                    ) : (
                      <EyeOff className="w-3.5 h-3.5 text-[#EF4444]" />
                    )}
                  </div>
                  {canSeeGotra ? (
                    <p className="text-sm text-[#1C1917] dark:text-[#F5F5F4] font-medium">{person.gotra}</p>
                  ) : (
                    <div className="space-y-2">
                      <p className="text-sm text-[#78716C] dark:text-[#A8A29E]">
                        Gotra is hidden for your viewing context
                      </p>
                      {viewerRole === 'family' && (
                        <Button
                          size="sm"
                          variant="outline"
                          className="text-xs h-7 border-[#FED7AA] dark:border-[#44403C]"
                          onClick={() => setGotraConsent(true)}
                        >
                          <Shield className="w-3 h-3 mr-1" />
                          Provide Consent to View
                        </Button>
                      )}
                    </div>
                  )}
                </div>
              )}

              {/* Health Conditions Section */}
              {protectedConditions.length > 0 && (
                <div className="p-3 rounded-xl bg-[#FFF7ED] dark:bg-[#292524] border border-[#FED7AA] dark:border-[#44403C]">
                  <div className="flex items-center justify-between mb-2">
                    <span className="text-xs font-semibold text-[#1C1917] dark:text-[#F5F5F4]">
                      Health Conditions ({protectedConditions.length})
                    </span>
                    {canSeeHealth ? (
                      <Button
                        size="sm"
                        variant="ghost"
                        className="text-xs h-6 text-[#F97316]"
                        onClick={() => setShowHealthDetails(!showHealthDetails)}
                      >
                        {showHealthDetails ? 'Hide' : 'Reveal'}
                      </Button>
                    ) : (
                      <EyeOff className="w-3.5 h-3.5 text-[#EF4444]" />
                    )}
                  </div>

                  {canSeeHealth ? (
                    <div className="space-y-2">
                      {protectedConditions.map(({ condition, isStigmatized, level }) => (
                        <div
                          key={condition}
                          className="flex items-center justify-between py-1"
                        >
                          <span className="text-xs text-[#1C1917] dark:text-[#F5F5F4]">
                            {showHealthDetails || level === 'standard'
                              ? condition.replace(/_/g, ' ')
                              : '••••••'}
                          </span>
                          {isStigmatized && <ProtectionBadge level={level} />}
                        </div>
                      ))}

                      {showHealthDetails && (
                        <div className="mt-2 p-2 rounded-lg bg-[#FEF3C7] dark:bg-[#431407] border border-[#FED7AA] dark:border-[#EA580C]">
                          <div className="flex items-start gap-1.5">
                            <Info className="w-3.5 h-3.5 text-[#F97316] mt-0.5 shrink-0" />
                            <p className="text-[10px] text-[#57534E] dark:text-[#A8A29E]">
                              Stigmatized conditions have enhanced privacy protection.
                              Data is excluded from search, patterns, and exports based on protection level.
                            </p>
                          </div>
                        </div>
                      )}
                    </div>
                  ) : (
                    <p className="text-xs text-[#78716C] dark:text-[#A8A29E]">
                      Health information is private — only visible to self, admin, and family.
                    </p>
                  )}
                </div>
              )}

              {/* Privacy Summary */}
              <div className="p-3 rounded-xl bg-[#FFFBFE] dark:bg-[#1C1917] border border-[#FED7AA] dark:border-[#44403C]">
                <span className="text-xs font-semibold text-[#1C1917] dark:text-[#F5F5F4]">
                  What {viewerRole} can see:
                </span>
                <div className="flex flex-wrap gap-1.5 mt-2">
                  <Badge variant="outline" className="text-[10px] border-[#22C55E] text-[#22C55E]">
                    <User className="w-2.5 h-2.5 mr-0.5" /> Name
                  </Badge>
                  <Badge
                    variant="outline"
                    className={`text-[10px] ${canSeeGotra ? 'border-[#22C55E] text-[#22C55E]' : 'border-[#EF4444] text-[#EF4444]'}`}
                  >
                    <Shield className="w-2.5 h-2.5 mr-0.5" /> Gotra
                  </Badge>
                  <Badge
                    variant="outline"
                    className={`text-[10px] ${canSeeHealth ? 'border-[#22C55E] text-[#22C55E]' : 'border-[#EF4444] text-[#EF4444]'}`}
                  >
                    <Heart className="w-2.5 h-2.5 mr-0.5" /> Health
                  </Badge>
                </div>
              </div>
            </motion.div>
          )}
        </CardContent>
      </Card>
    </motion.div>
  );
}
