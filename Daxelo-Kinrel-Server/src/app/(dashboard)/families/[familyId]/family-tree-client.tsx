'use client'

import { useState, useEffect, useRef, useCallback, useMemo } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import Link from 'next/link'
import { Avatar, AvatarFallback } from '@/components/ui/avatar'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { ScrollArea } from '@/components/ui/scroll-area'
import { AddPersonDrawer } from './add-person-drawer'
import { PersonDetailPanel } from './person-detail-panel'
import { RelationshipPicker } from './relationship-picker'
import { useKinshipBatch } from '@/hooks/use-kinship-batch'
import { avatarColorForName, avatarLightVariant, getInitials } from '@/lib/avatar-colors'
import { useToast } from '@/hooks/use-toast'
import {
  ArrowLeft,
  Plus,
  Link2,
  X,
  UserPlus,
  Loader2,
  Users,
} from 'lucide-react'

// ── Types ──────────────────────────────────────────────────────────────

interface Person {
  id: string
  familyId: string
  name: string
  relationship: string | null
  dateOfBirth: string | null
  gotra: string | null
  occupation: string | null
  city: string | null
  isDeceased: boolean
  privacyLevel: string
  deletedAt: string | null
}

interface Relationship {
  id: string
  familyId: string
  fromPersonId: string
  toPersonId: string
  type: string
  direction: string
}

interface Family {
  id: string
  name: string
  description: string | null
  primaryLanguage: string
  gotra: string | null
  originVillage: string | null
}

interface FamilyTreeClientProps {
  family: Family
  persons: Person[]
  relationships: Relationship[]
}

interface GenerationGroup {
  generation: number
  label: string
  persons: Person[]
}

// ── Generation Mapping ─────────────────────────────────────────────────

const GENERATION_LABELS: Record<number, string> = {
  '-2': 'Grandparents',
  '-1': 'Parents',
  0: 'Self',
  1: 'Children',
  2: 'Grandchildren',
}

function getGenerationLabel(gen: number): string {
  return GENERATION_LABELS[gen] || `Generation ${gen > 0 ? '+' : ''}${gen}`
}

// ── Language Options ────────────────────────────────────────────────────

const LANGUAGE_OPTIONS = [
  { code: 'en', label: 'English' },
  { code: 'hi', label: 'हिन्दी (Hindi)' },
  { code: 'bn', label: 'বাংলা (Bengali)' },
  { code: 'te', label: 'తెలుగు (Telugu)' },
  { code: 'mr', label: 'मराठी (Marathi)' },
  { code: 'ta', label: 'தமிழ் (Tamil)' },
  { code: 'ur', label: 'اردو (Urdu)' },
  { code: 'gu', label: 'ગુજરાતી (Gujarati)' },
  { code: 'kn', label: 'ಕನ್ನಡ (Kannada)' },
  { code: 'ml', label: 'മലയാളം (Malayalam)' },
  { code: 'or', label: 'ଓଡ଼ିଆ (Odia)' },
  { code: 'pa', label: 'ਪੰਜਾਬੀ (Punjabi)' },
  { code: 'as', label: 'অসমীয়া (Assamese)' },
  { code: 'sa', label: 'संस्कृतम् (Sanskrit)' },
]

// ── Edge Colors ─────────────────────────────────────────────────────────

const SPOUSE_TYPES = new Set([
  'wife',
  'husband',
  'spouse',
  'wives_father',
  'wives_mother',
  'husbands_father',
  'husbands_mother',
  'sons_wife',
  'daughters_husband',
  'co_father_in_law_paternal',
  'co_mother_in_law_paternal',
])

function isSpouseType(type: string): boolean {
  return SPOUSE_TYPES.has(type) || type.includes('husband') || type.includes('wife') || type.includes('in_law')
}

// ── Main Component ──────────────────────────────────────────────────────

export function FamilyTreeClient({
  family,
  persons: initialPersons,
  relationships: initialRelationships,
}: FamilyTreeClientProps) {
  // ── State ────────────────────────────────────────────────────────────
  const [persons, setPersons] = useState<Person[]>(initialPersons)
  const [relationships, setRelationships] = useState<Relationship[]>(initialRelationships)
  const [selectedPersonId, setSelectedPersonId] = useState<string | null>(null)
  const [mode, setMode] = useState<'view' | 'connect'>('view')
  const [connectFrom, setConnectFrom] = useState<string | null>(null)
  const [locale, setLocale] = useState(family.primaryLanguage || 'hi')
  const [addPersonOpen, setAddPersonOpen] = useState(false)
  const [relationshipPickerOpen, setRelationshipPickerOpen] = useState(false)
  const [connectTo, setConnectTo] = useState<string | null>(null)
  const [generationMap, setGenerationMap] = useState<Record<string, number>>({})

  const { toast } = useToast()
  const treeContainerRef = useRef<HTMLDivElement>(null)
  const nodeRefs = useRef<Record<string, HTMLDivElement | null>>({})

  // ── Kinship Batch Fetching ───────────────────────────────────────────
  const relationshipKeys = useMemo(
    () => persons.map((p) => p.relationship).filter(Boolean) as string[],
    [persons]
  )

  const { getTerm, loading: kinshipLoading, refetch: refetchKinship } = useKinshipBatch(
    relationshipKeys,
    locale
  )

  // ── Fetch generation data ────────────────────────────────────────────
  useEffect(() => {
    async function fetchGenerations() {
      const genMap: Record<string, number> = {}
      const uniqueKeys = [...new Set(relationshipKeys)]

      await Promise.all(
        uniqueKeys.map(async (key) => {
          try {
            const res = await fetch(`/api/v1/kinship?key=${encodeURIComponent(key)}`)
            if (res.ok) {
              const data = await res.json()
              if (data.relationship?.generation !== undefined) {
                genMap[key] = data.relationship.generation
              }
            }
          } catch {
            // ignore
          }
        })
      )

      setGenerationMap(genMap)
    }

    if (relationshipKeys.length > 0) {
      fetchGenerations()
    }
  }, [persons.map((p) => p.relationship).join(',')])

  // ── Refetch kinship when locale changes ──────────────────────────────
  useEffect(() => {
    refetchKinship()
  }, [locale])

  // ── Group persons by generation ──────────────────────────────────────
  const generationGroups = useMemo((): GenerationGroup[] => {
    if (persons.length === 0) return []

    const groups: Record<number, Person[]> = {}

    for (const person of persons) {
      const gen = generationMap[person.relationship || ''] ?? 0
      if (!groups[gen]) groups[gen] = []
      groups[gen].push(person)
    }

    // Sort generations: oldest first
    const sortedGens = Object.keys(groups)
      .map(Number)
      .sort((a, b) => a - b)

    return sortedGens.map((gen) => ({
      generation: gen,
      label: getGenerationLabel(gen),
      persons: groups[gen],
    }))
  }, [persons, generationMap])

  // ── Edge positions ───────────────────────────────────────────────────
  const [edges, setEdges] = useState<
    { x1: number; y1: number; x2: number; y2: number; type: string }[]
  >([])

  const calculateEdges = useCallback(() => {
    if (!treeContainerRef.current) return

    const containerRect = treeContainerRef.current.getBoundingClientRect()
    const newEdges: { x1: number; y1: number; x2: number; y2: number; type: string }[] = []

    for (const rel of relationships) {
      const fromNode = nodeRefs.current[rel.fromPersonId]
      const toNode = nodeRefs.current[rel.toPersonId]

      if (!fromNode || !toNode) continue

      const fromRect = fromNode.getBoundingClientRect()
      const toRect = toNode.getBoundingClientRect()

      newEdges.push({
        x1: fromRect.left + fromRect.width / 2 - containerRect.left + treeContainerRef.current.scrollLeft,
        y1: fromRect.top + fromRect.height / 2 - containerRect.top + treeContainerRef.current.scrollTop,
        x2: toRect.left + toRect.width / 2 - containerRect.left + treeContainerRef.current.scrollLeft,
        y2: toRect.top + toRect.height / 2 - containerRect.top + treeContainerRef.current.scrollTop,
        type: rel.type,
      })
    }

    setEdges(newEdges)
  }, [relationships])

  useEffect(() => {
    // Calculate edges after a short delay to let DOM render
    const timer = setTimeout(calculateEdges, 300)
    return () => clearTimeout(timer)
  }, [persons, relationships, calculateEdges, locale])

  useEffect(() => {
    window.addEventListener('resize', calculateEdges)
    return () => window.removeEventListener('resize', calculateEdges)
  }, [calculateEdges])

  // ── Selected person ──────────────────────────────────────────────────
  const selectedPerson = useMemo(
    () => persons.find((p) => p.id === selectedPersonId) || null,
    [persons, selectedPersonId]
  )

  // ── Handlers ─────────────────────────────────────────────────────────
  const handleNodeClick = (personId: string) => {
    if (mode === 'connect') {
      if (!connectFrom) {
        setConnectFrom(personId)
      } else if (personId !== connectFrom) {
        setConnectTo(personId)
        setRelationshipPickerOpen(true)
      }
      return
    }

    setSelectedPersonId(personId === selectedPersonId ? null : personId)
  }

  const handleRelationshipSelect = async (type: string) => {
    if (!connectFrom || !connectTo) return

    try {
      const res = await fetch(`/api/families/${family.id}/relationships`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          fromPersonId: connectFrom,
          toPersonId: connectTo,
          type,
        }),
      })

      const data = await res.json()

      if (!res.ok) {
        toast({
          title: 'Error',
          description: data.error || 'Failed to create relationship',
          variant: 'destructive',
        })
        return
      }

      toast({
        title: 'Relationship created',
        description: 'The connection has been added to the family tree.',
      })

      // Add the new relationship(s) to local state
      if (data.data) {
        setRelationships((prev) => [...prev, data.data])
        // Also fetch the inverse that was auto-created
        const relsRes = await fetch(`/api/families/${family.id}/relationships?limit=100`)
        if (relsRes.ok) {
          const relsData = await relsRes.json()
          if (relsData.data) {
            setRelationships(relsData.data)
          }
        }
      }

      // Reset connect mode
      setMode('view')
      setConnectFrom(null)
      setConnectTo(null)

      // Recalculate edges
      setTimeout(calculateEdges, 400)
    } catch {
      toast({
        title: 'Error',
        description: 'Network error. Please try again.',
        variant: 'destructive',
      })
    }
  }

  const handleAddPersonSuccess = (newPerson: Record<string, unknown>) => {
    setPersons((prev) => [...prev, newPerson as Person])
    setTimeout(calculateEdges, 400)
  }

  const handleConnectFromPanel = (personId: string) => {
    setSelectedPersonId(null)
    setMode('connect')
    setConnectFrom(personId)
  }

  const handleEditPerson = (personId: string) => {
    // Could open an edit drawer - for now, show a toast
    toast({
      title: 'Edit Person',
      description: 'Edit functionality coming soon.',
    })
  }

  const handleRemovePerson = async (personId: string) => {
    try {
      const res = await fetch(`/api/families/${family.id}/persons/${personId}`, {
        method: 'DELETE',
      })

      if (!res.ok) {
        const data = await res.json()
        toast({
          title: 'Error',
          description: data.error || 'Failed to remove person',
          variant: 'destructive',
        })
        return
      }

      toast({
        title: 'Person removed',
        description: 'The person has been removed from the family tree.',
      })

      setPersons((prev) => prev.filter((p) => p.id !== personId))
      setRelationships((prev) =>
        prev.filter((r) => r.fromPersonId !== personId && r.toPersonId !== personId)
      )
      setSelectedPersonId(null)
      setTimeout(calculateEdges, 400)
    } catch {
      toast({
        title: 'Error',
        description: 'Network error. Please try again.',
        variant: 'destructive',
      })
    }
  }

  const handleCancelConnect = () => {
    setMode('view')
    setConnectFrom(null)
    setConnectTo(null)
  }

  // ── Connect mode info bar ────────────────────────────────────────────
  const connectFromPerson = connectFrom ? persons.find((p) => p.id === connectFrom) : null
  const connectToPerson = connectTo ? persons.find((p) => p.id === connectTo) : null

  // ── Render ───────────────────────────────────────────────────────────
  return (
    <div className="flex flex-col h-[calc(100dvh-3.5rem)] md:h-[calc(100dvh-2rem)] -m-4 md:-m-6 lg:-m-8">
      {/* ── Header ─────────────────────────────────────────────────────── */}
      <div className="flex items-center gap-3 px-4 py-3 bg-kinrel-card border-b border-white/10 shrink-0">
        <Link
          href="/families"
          className="p-1.5 rounded-md text-kinrel-silver hover:text-kinrel-white hover:bg-white/5 transition-colors"
          aria-label="Back to families"
        >
          <ArrowLeft className="h-5 w-5" />
        </Link>

        <div className="flex-1 min-w-0">
          <h1 className="text-base md:text-lg font-semibold text-kinrel-white truncate">
            {family.name} Tree
          </h1>
          <p className="text-xs text-kinrel-dim">
            {persons.length} member{persons.length !== 1 ? 's' : ''} · {relationships.length / 2 || 0} connection{(relationships.length / 2) !== 1 ? 's' : ''}
          </p>
        </div>

        {/* Language Selector */}
        <Select value={locale} onValueChange={setLocale}>
          <SelectTrigger className="w-[140px] md:w-[160px] border-white/10 bg-kinrel-elevated text-kinrel-white text-xs h-8">
            <SelectValue />
          </SelectTrigger>
          <SelectContent style={{ backgroundColor: 'var(--kinrel-card)' }}>
            {LANGUAGE_OPTIONS.map((lang) => (
              <SelectItem key={lang.code} value={lang.code}>
                {lang.label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>

        {/* Add Person Button */}
        <Button
          onClick={() => setAddPersonOpen(true)}
          size="sm"
          className="shrink-0"
          style={{
            background: 'var(--kinrel-grad-ignite)',
            color: 'var(--kinrel-white)',
          }}
        >
          <Plus className="h-4 w-4 mr-1" />
          <span className="hidden sm:inline">Add</span>
        </Button>
      </div>

      {/* ── Connect Mode Bar ───────────────────────────────────────────── */}
      <AnimatePresence>
        {mode === 'connect' && (
          <motion.div
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: 'auto', opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            transition={{ duration: 0.2 }}
            className="overflow-hidden"
          >
            <div className="flex items-center gap-3 px-4 py-2 bg-kinrel-orange/10 border-b border-kinrel-orange/20">
              <Link2 className="h-4 w-4 text-kinrel-orange shrink-0" />
              <p className="text-xs text-kinrel-orange flex-1">
                {!connectFrom
                  ? 'Click the first person to connect from'
                  : !connectTo
                  ? `Now click the second person to connect to ${connectFromPerson?.name}`
                  : 'Select relationship type...'}
              </p>
              <Button
                variant="ghost"
                size="sm"
                onClick={handleCancelConnect}
                className="text-kinrel-silver hover:text-kinrel-white h-7 px-2"
              >
                <X className="h-3.5 w-3.5 mr-1" />
                Cancel
              </Button>
            </div>
          </motion.div>
        )}
      </AnimatePresence>

      {/* ── Tree Canvas ────────────────────────────────────────────────── */}
      <div className="flex-1 overflow-auto relative" ref={treeContainerRef}>
        {persons.length === 0 ? (
          /* Empty State */
          <div className="flex flex-col items-center justify-center h-full gap-4 p-8">
            <div className="w-16 h-16 rounded-2xl bg-kinrel-elevated flex items-center justify-center">
              <Users className="h-8 w-8 text-kinrel-dim" />
            </div>
            <div className="text-center">
              <h3 className="text-lg font-semibold text-kinrel-white mb-1">
                No family members yet
              </h3>
              <p className="text-sm text-kinrel-silver max-w-xs">
                Add your first family member to start building the tree.
              </p>
            </div>
            <Button
              onClick={() => setAddPersonOpen(true)}
              style={{
                background: 'var(--kinrel-grad-ignite)',
                color: 'var(--kinrel-white)',
              }}
            >
              <UserPlus className="h-4 w-4 mr-2" />
              Add First Member
            </Button>
          </div>
        ) : (
          /* Tree with nodes and edges */
          <div className="relative p-6 min-w-fit">
            {/* SVG Edges Layer */}
            <svg
              className="absolute inset-0 w-full h-full pointer-events-none"
              style={{ zIndex: 0 }}
            >
              {edges.map((edge, i) => (
                <line
                  key={`edge-${i}`}
                  x1={edge.x1}
                  y1={edge.y1}
                  x2={edge.x2}
                  y2={edge.y2}
                  stroke={
                    isSpouseType(edge.type)
                      ? 'rgba(232, 97, 42, 0.3)'
                      : 'rgba(201, 180, 168, 0.25)'
                  }
                  strokeWidth={2}
                  strokeDasharray={isSpouseType(edge.type) ? '6 4' : 'none'}
                />
              ))}
            </svg>

            {/* Generation Rows */}
            <div className="relative" style={{ zIndex: 1 }}>
              {generationGroups.map((group) => (
                <div key={group.generation} className="mb-8 last:mb-0">
                  {/* Generation Label */}
                  <div className="flex items-center gap-3 mb-3">
                    <Badge
                      variant="outline"
                      className="text-[10px] uppercase tracking-wider border-white/10 text-kinrel-dim"
                    >
                      {group.label}
                    </Badge>
                    <div className="flex-1 h-px bg-white/5" />
                    <span className="text-[10px] text-kinrel-dim">
                      {group.persons.length} member{group.persons.length !== 1 ? 's' : ''}
                    </span>
                  </div>

                  {/* Person Nodes */}
                  <div className="flex flex-wrap gap-4 justify-center md:justify-start">
                    {group.persons.map((person) => {
                      const kinshipTerm = person.relationship
                        ? getTerm(person.relationship)
                        : null
                      const isSelected = selectedPersonId === person.id
                      const isConnectFrom = connectFrom === person.id
                      const avatarColor = avatarColorForName(person.name)
                      const initials = getInitials(person.name)

                      return (
                        <motion.div
                          key={person.id}
                          ref={(el) => {
                            nodeRefs.current[person.id] = el
                          }}
                          whileHover={{ scale: 1.03, y: -2 }}
                          whileTap={{ scale: 0.98 }}
                          onClick={() => handleNodeClick(person.id)}
                          className={`
                            relative cursor-pointer rounded-xl p-3 w-36 md:w-40
                            bg-kinrel-card border transition-all duration-200
                            ${isSelected ? 'border-kinrel-orange shadow-lg shadow-kinrel-orange/10' : 'border-white/10 hover:border-kinrel-orange/40'}
                            ${isConnectFrom ? 'border-kinrel-orange shadow-lg shadow-kinrel-orange/20 ring-2 ring-kinrel-orange/30' : ''}
                            ${mode === 'connect' ? 'hover:border-kinrel-orange/60 hover:shadow-md hover:shadow-kinrel-orange/5' : ''}
                          `}
                          style={{
                            boxShadow: isConnectFrom
                              ? '0 0 24px 0 rgba(232, 97, 42, 0.2)'
                              : isSelected
                              ? '0 0 16px 0 rgba(232, 97, 42, 0.1)'
                              : undefined,
                          }}
                        >
                          {/* Avatar + Name */}
                          <div className="flex items-center gap-2.5 mb-2">
                            <Avatar
                              className="h-9 w-9 shrink-0"
                              style={{
                                backgroundColor: avatarLightVariant(avatarColor, 0.15),
                                border: `1.5px solid ${avatarColor}`,
                              }}
                            >
                              <AvatarFallback
                                style={{ color: avatarColor, backgroundColor: 'transparent' }}
                                className="text-xs font-bold"
                              >
                                {initials}
                              </AvatarFallback>
                            </Avatar>
                            <div className="flex-1 min-w-0">
                              <p className="text-sm font-medium text-kinrel-white truncate">
                                {person.name}
                              </p>
                            </div>
                          </div>

                          {/* Kinship Term */}
                          {person.relationship && (
                            <p
                              className="text-xs truncate"
                              style={{ color: 'var(--kinrel-orange)' }}
                            >
                              {kinshipLoading
                                ? '...'
                                : kinshipTerm?.native ||
                                  person.relationship.replace(/_/g, ' ')}
                            </p>
                          )}

                          {/* Deceased indicator */}
                          {person.isDeceased && (
                            <div className="absolute top-1.5 right-1.5 text-[10px]">
                              🕯️
                            </div>
                          )}
                        </motion.div>
                      )
                    })}
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>

      {/* ── Person Detail Panel ────────────────────────────────────────── */}
      <PersonDetailPanel
        person={selectedPerson}
        locale={locale}
        onClose={() => setSelectedPersonId(null)}
        onConnect={handleConnectFromPanel}
        onEdit={handleEditPerson}
        onRemove={handleRemovePerson}
      />

      {/* ── Add Person Drawer ──────────────────────────────────────────── */}
      <AddPersonDrawer
        familyId={family.id}
        open={addPersonOpen}
        onOpenChange={setAddPersonOpen}
        onSuccess={handleAddPersonSuccess}
      />

      {/* ── Relationship Picker ────────────────────────────────────────── */}
      <RelationshipPicker
        open={relationshipPickerOpen}
        onClose={() => {
          setRelationshipPickerOpen(false)
          setConnectTo(null)
        }}
        onSelect={handleRelationshipSelect}
        fromName={connectFromPerson?.name || ''}
        toName={connectToPerson?.name || ''}
        locale={locale}
      />
    </div>
  )
}
