'use client'

import { useMemo, useState } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { useQuery } from '@tanstack/react-query'
import {
  Sheet,
  SheetContent,
} from '@/components/ui/sheet'
import { Avatar, AvatarFallback } from '@/components/ui/avatar'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Separator } from '@/components/ui/separator'
import { ScrollArea } from '@/components/ui/scroll-area'
import { useMediaQuery } from '@/hooks/use-mobile'
import {
  X,
  Calendar,
  MapPin,
  Briefcase,
  Flame,
  Heart,
  Languages,
  ChevronDown,
  ChevronUp,
  Link2,
  Pencil,
  Trash2,
} from 'lucide-react'
import { avatarColorForName, avatarLightVariant, getInitials } from '@/lib/avatar-colors'

interface Person {
  id: string
  name: string
  relationship: string | null
  dateOfBirth: string | null
  gotra: string | null
  occupation: string | null
  city: string | null
  isDeceased: boolean
  privacyLevel: string
}

interface PersonDetailPanelProps {
  person: Person | null
  locale: string
  onClose: () => void
  onConnect: (personId: string) => void
  onEdit: (personId: string) => void
  onRemove: (personId: string) => void
}

interface TranslationEntry {
  language: string
  localeCode: string
  native: string
  latin: string
}

const LANGUAGE_NAMES: Record<string, string> = {
  en: 'English',
  hi: 'Hindi',
  bn: 'Bengali',
  te: 'Telugu',
  mr: 'Marathi',
  ta: 'Tamil',
  ur: 'Urdu',
  gu: 'Gujarati',
  kn: 'Kannada',
  ml: 'Malayalam',
  or: 'Odia',
  pa: 'Punjabi',
  as: 'Assamese',
  sa: 'Sanskrit',
}

export function PersonDetailPanel({
  person,
  locale,
  onClose,
  onConnect,
  onEdit,
  onRemove,
}: PersonDetailPanelProps) {
  const isDesktop = useMediaQuery('(min-width: 768px)')
  const [showAllLanguages, setShowAllLanguages] = useState(false)

  const isOpen = person !== null
  const currentRelationship = person?.relationship || null

  // Fetch all translations using TanStack Query
  const { data: translationData, isLoading: translationsLoading } = useQuery({
    queryKey: ['kinship-all-translations', currentRelationship, locale],
    queryFn: async () => {
      if (!currentRelationship) return null

      const res = await fetch(`/api/v1/kinship?key=${encodeURIComponent(currentRelationship)}`)
      if (!res.ok) return null
      return res.json()
    },
    enabled: !!currentRelationship && isOpen,
    staleTime: 5 * 60 * 1000,
    gcTime: 30 * 60 * 1000,
  })

  // Derived translations from query data
  const { translations, localTerm, englishTerm } = useMemo(() => {
    if (!currentRelationship) {
      return { translations: [] as TranslationEntry[], localTerm: '', englishTerm: '' }
    }

    if (!translationData) {
      return {
        translations: [] as TranslationEntry[],
        localTerm: currentRelationship.replace(/_/g, ' '),
        englishTerm: currentRelationship.replace(/_/g, ' '),
      }
    }

    const engTerm = translationData.relationship?.englishTerm || currentRelationship
    const locTerm =
      locale === 'en'
        ? engTerm
        : translationData.localizedLabel || engTerm

    const allTranslations: TranslationEntry[] = [
      {
        language: 'English',
        localeCode: 'en',
        native: engTerm,
        latin: engTerm.toLowerCase(),
      },
    ]

    if (translationData.translations) {
      for (const [langCode, term] of Object.entries(translationData.translations)) {
        const t = term as { native: string; latin: string }
        allTranslations.push({
          language: LANGUAGE_NAMES[langCode] || langCode,
          localeCode: langCode,
          native: t.native,
          latin: t.latin,
        })
      }
    }

    return { translations: allTranslations, localTerm: locTerm, englishTerm: engTerm }
  }, [translationData, currentRelationship, locale])

  const visibleTranslations = useMemo(
    () => (showAllLanguages ? translations : translations.slice(0, 5)),
    [translations, showAllLanguages]
  )

  const avatarColor = person ? avatarColorForName(person.name) : '#E8612A'
  const initials = person ? getInitials(person.name) : '?'

  const formatDate = (dateStr: string | null) => {
    if (!dateStr) return null
    try {
      return new Date(dateStr).toLocaleDateString('en-IN', {
        year: 'numeric',
        month: 'long',
        day: 'numeric',
      })
    } catch {
      return dateStr
    }
  }

  const panelContent = person && (
    <div className="flex flex-col h-full">
      {/* Header */}
      <div className="flex items-start gap-4 p-4 md:p-0 md:pb-4">
        <div className="relative">
          <Avatar
            className="h-16 w-16 text-lg font-bold shrink-0"
            style={{
              backgroundColor: avatarLightVariant(avatarColor, 0.2),
              border: `2px solid ${avatarColor}`,
            }}
          >
            <AvatarFallback
              style={{ color: avatarColor, backgroundColor: 'transparent' }}
              className="text-lg font-bold"
            >
              {initials}
            </AvatarFallback>
          </Avatar>
          {person.isDeceased && (
            <div
              className="absolute -bottom-1 -right-1 w-5 h-5 rounded-full flex items-center justify-center text-[10px]"
              style={{
                backgroundColor: '#6C5B7B',
                border: '2px solid var(--kinrel-card)',
              }}
              title="Deceased"
            >
              🕯️
            </div>
          )}
        </div>

        <div className="flex-1 min-w-0">
          <h2 className="text-lg font-semibold text-kinrel-white truncate">
            {person.name}
          </h2>
          {localTerm && (
            <p className="text-sm mt-0.5" style={{ color: 'var(--kinrel-orange)' }}>
              {localTerm}
            </p>
          )}
          {englishTerm && englishTerm !== localTerm && (
            <p className="text-xs text-kinrel-dim mt-0.5">{englishTerm}</p>
          )}
          <div className="flex items-center gap-2 mt-1.5">
            {person.isDeceased && (
              <Badge
                variant="outline"
                className="text-[10px] border-purple-400/30 text-purple-300"
              >
                Deceased
              </Badge>
            )}
            <Badge
              variant="outline"
              className="text-[10px] border-white/10 text-kinrel-dim capitalize"
            >
              {person.privacyLevel}
            </Badge>
          </div>
        </div>
      </div>

      <Separator className="bg-white/10" />

      {/* Details */}
      <ScrollArea className="flex-1 -mx-4 md:mx-0">
        <div className="p-4 md:p-0 space-y-4">
          {/* Info Fields */}
          <div className="space-y-3">
            {person.dateOfBirth && (
              <div className="flex items-center gap-3 text-sm">
                <Calendar className="h-4 w-4 shrink-0 text-kinrel-dim" />
                <span className="text-kinrel-silver">
                  {formatDate(person.dateOfBirth)}
                </span>
              </div>
            )}

            {person.city && (
              <div className="flex items-center gap-3 text-sm">
                <MapPin className="h-4 w-4 shrink-0 text-kinrel-dim" />
                <span className="text-kinrel-silver">{person.city}</span>
              </div>
            )}

            {person.occupation && (
              <div className="flex items-center gap-3 text-sm">
                <Briefcase className="h-4 w-4 shrink-0 text-kinrel-dim" />
                <span className="text-kinrel-silver">{person.occupation}</span>
              </div>
            )}

            {person.gotra && (
              <div className="flex items-center gap-3 text-sm">
                <Flame className="h-4 w-4 shrink-0 text-kinrel-dim" />
                <span className="text-kinrel-silver">
                  Gotra: {person.gotra}
                </span>
              </div>
            )}
          </div>

          {/* Multilingual Section */}
          {translations.length > 0 && (
            <>
              <Separator className="bg-white/10" />
              <div>
                <div className="flex items-center gap-2 mb-3">
                  <Languages className="h-4 w-4 text-kinrel-orange" />
                  <h3 className="text-sm font-semibold text-kinrel-white">
                    Kinship Terms
                  </h3>
                </div>

                <div className="space-y-2">
                  {visibleTranslations.map((t) => (
                    <div
                      key={t.localeCode}
                      className="flex items-center justify-between px-3 py-2 rounded-lg bg-kinrel-elevated/50"
                    >
                      <span className="text-xs text-kinrel-dim w-20 shrink-0">
                        {t.language}
                      </span>
                      <span className="text-sm text-kinrel-white text-right flex-1 truncate">
                        {t.native}
                      </span>
                      {t.latin !== t.native && (
                        <span className="text-xs text-kinrel-dim ml-2 text-right flex-1 truncate">
                          ({t.latin})
                        </span>
                      )}
                    </div>
                  ))}
                </div>

                {translations.length > 5 && (
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => setShowAllLanguages(!showAllLanguages)}
                    className="w-full mt-2 text-kinrel-silver hover:text-kinrel-orange hover:bg-white/5"
                  >
                    {showAllLanguages ? (
                      <>
                        <ChevronUp className="h-3.5 w-3.5 mr-1" />
                        Show less
                      </>
                    ) : (
                      <>
                        <ChevronDown className="h-3.5 w-3.5 mr-1" />
                        Show all {translations.length} languages
                      </>
                    )}
                  </Button>
                )}
              </div>
            </>
          )}

          {translationsLoading && (
            <div className="flex items-center justify-center py-4">
              <div className="h-4 w-4 animate-spin rounded-full border-2 border-kinrel-orange border-t-transparent" />
              <span className="ml-2 text-xs text-kinrel-dim">
                Loading translations...
              </span>
            </div>
          )}

          {/* Deceased Memorial */}
          {person.isDeceased && (
            <>
              <Separator className="bg-white/10" />
              <div className="p-3 rounded-lg bg-purple-500/5 border border-purple-400/10">
                <div className="flex items-center gap-2 mb-1">
                  <Heart className="h-3.5 w-3.5 text-purple-300" />
                  <span className="text-xs font-medium text-purple-300">
                    In Loving Memory
                  </span>
                </div>
                <p className="text-xs text-purple-200/60">
                  This family member has passed away. Their memory lives on in the
                  family tree.
                </p>
              </div>
            </>
          )}

          {/* Action Buttons */}
          <Separator className="bg-white/10" />
          <div className="flex flex-col gap-2">
            <Button
              variant="outline"
              onClick={() => onConnect(person.id)}
              className="w-full justify-start border-white/10 bg-kinrel-elevated text-kinrel-silver hover:text-kinrel-orange hover:bg-kinrel-elevated/80 hover:border-kinrel-orange/30"
            >
              <Link2 className="h-4 w-4 mr-2" />
              Connect to another person
            </Button>
            <Button
              variant="outline"
              onClick={() => onEdit(person.id)}
              className="w-full justify-start border-white/10 bg-kinrel-elevated text-kinrel-silver hover:text-kinrel-white hover:bg-kinrel-elevated/80"
            >
              <Pencil className="h-4 w-4 mr-2" />
              Edit Person
            </Button>
            <Button
              variant="outline"
              onClick={() => onRemove(person.id)}
              className="w-full justify-start border-white/10 bg-kinrel-elevated text-red-300 hover:text-red-400 hover:bg-red-500/5 hover:border-red-400/30"
            >
              <Trash2 className="h-4 w-4 mr-2" />
              Remove
            </Button>
          </div>
        </div>
      </ScrollArea>
    </div>
  )

  // Desktop: right-side panel
  if (isDesktop) {
    return (
      <AnimatePresence>
        {isOpen && person && (
          <motion.div
            initial={{ x: 320, opacity: 0 }}
            animate={{ x: 0, opacity: 1 }}
            exit={{ x: 320, opacity: 0 }}
            transition={{ type: 'spring', damping: 25, stiffness: 250 }}
            className="fixed top-0 right-0 bottom-0 z-30 w-80 bg-kinrel-card border-l border-white/10 shadow-2xl"
          >
            <div className="flex items-center justify-between p-4 border-b border-white/10">
              <h3 className="text-sm font-semibold text-kinrel-silver uppercase tracking-wider">
                Person Details
              </h3>
              <button
                onClick={onClose}
                className="p-1.5 rounded-md text-kinrel-dim hover:text-kinrel-white hover:bg-white/5 transition-colors"
                aria-label="Close detail panel"
              >
                <X className="h-4 w-4" />
              </button>
            </div>
            <div className="flex-1 overflow-hidden p-4">{panelContent}</div>
          </motion.div>
        )}
      </AnimatePresence>
    )
  }

  // Mobile: bottom sheet
  return (
    <Sheet open={isOpen} onOpenChange={(v) => !v && onClose()}>
      <SheetContent
        side="bottom"
        className="max-h-[80vh] rounded-t-2xl"
        style={{ backgroundColor: 'var(--kinrel-card)' }}
      >
        {panelContent}
      </SheetContent>
    </Sheet>
  )
}
