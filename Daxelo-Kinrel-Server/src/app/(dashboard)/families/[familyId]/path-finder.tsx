'use client'

import { useState, useEffect } from 'react'
import { Button } from '@/components/ui/button'
import { Label } from '@/components/ui/label'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Loader2, Route, ArrowRight, Users } from 'lucide-react'
import { useToast } from '@/hooks/use-toast'
import { motion, AnimatePresence } from 'framer-motion'

interface PersonOption {
  id: string
  name: string
  relationship: string | null
}

interface PathStep {
  relationshipId: string
  type: string
  direction: 'from' | 'to'
  localizedType?: string
  fromPerson: { id: string; name: string }
  toPerson: { id: string; name: string }
}

interface PathResult {
  from: { id: string; name: string }
  to: { id: string; name: string }
  path: PathStep[] | null
  length: number
  relationshipDescription: string
  localizedDescription: string
  locale: string
  message?: string
}

interface PathFinderProps {
  familyId: string
  locale?: string
}

export function PathFinder({ familyId, locale = 'en' }: PathFinderProps) {
  const { toast } = useToast()
  const [persons, setPersons] = useState<PersonOption[]>([])
  const [personA, setPersonA] = useState<string>('')
  const [personB, setPersonB] = useState<string>('')
  const [loading, setLoading] = useState(false)
  const [pathResult, setPathResult] = useState<PathResult | null>(null)
  const [personsLoading, setPersonsLoading] = useState(true)

  // Fetch family persons
  useEffect(() => {
    async function fetchPersons() {
      try {
        const res = await fetch(`/api/families/${familyId}/persons?limit=200`)
        if (res.ok) {
          const data = await res.json()
          setPersons(
            (data.persons || []).map((p: Record<string, unknown>) => ({
              id: p.id as string,
              name: p.name as string,
              relationship: (p.relationship as string) || null,
            }))
          )
        }
      } catch {
        // Silently fail
      } finally {
        setPersonsLoading(false)
      }
    }
    fetchPersons()
  }, [familyId])

  const handleFindPath = async () => {
    if (!personA || !personB) {
      toast({
        title: 'Select both persons',
        description: 'Please select Person A and Person B to find their relationship.',
        variant: 'destructive',
      })
      return
    }

    if (personA === personB) {
      toast({
        title: 'Same person',
        description: 'Please select two different persons.',
        variant: 'destructive',
      })
      return
    }

    setLoading(true)
    setPathResult(null)

    try {
      const res = await fetch(
        `/api/v1/graph/${familyId}?from=${personA}&to=${personB}&locale=${locale}`
      )

      if (!res.ok) {
        const data = await res.json()
        toast({
          title: 'Error',
          description: data.error?.message || 'Failed to find path',
          variant: 'destructive',
        })
        return
      }

      const data = await res.json()
      setPathResult(data.data || data)
    } catch {
      toast({
        title: 'Error',
        description: 'Network error. Please try again.',
        variant: 'destructive',
      })
    } finally {
      setLoading(false)
    }
  }

  const personAName = persons.find((p) => p.id === personA)?.name || 'Person A'
  const personBName = persons.find((p) => p.id === personB)?.name || 'Person B'

  return (
    <Card
      className="border-white/10"
      style={{ backgroundColor: 'var(--kinrel-card)' }}
    >
      <CardHeader>
        <CardTitle className="flex items-center gap-2 text-kinrel-white">
          <Route className="h-5 w-5" style={{ color: 'var(--kinrel-orange)' }} />
          How are they related?
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-6">
        {/* Person selectors */}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div className="space-y-2">
            <Label style={{ color: 'var(--kinrel-silver)' }}>Person A</Label>
            <Select value={personA} onValueChange={setPersonA}>
              <SelectTrigger className="border-white/10 bg-kinrel-elevated text-kinrel-white">
                <SelectValue placeholder="Select person..." />
              </SelectTrigger>
              <SelectContent style={{ backgroundColor: 'var(--kinrel-card)' }}>
                {persons.map((p) => (
                  <SelectItem key={p.id} value={p.id}>
                    {p.name}
                    {p.relationship && (
                      <span className="ml-2 text-xs" style={{ color: 'var(--kinrel-dim)' }}>
                        ({p.relationship})
                      </span>
                    )}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-2">
            <Label style={{ color: 'var(--kinrel-silver)' }}>Person B</Label>
            <Select value={personB} onValueChange={setPersonB}>
              <SelectTrigger className="border-white/10 bg-kinrel-elevated text-kinrel-white">
                <SelectValue placeholder="Select person..." />
              </SelectTrigger>
              <SelectContent style={{ backgroundColor: 'var(--kinrel-card)' }}>
                {persons.map((p) => (
                  <SelectItem key={p.id} value={p.id}>
                    {p.name}
                    {p.relationship && (
                      <span className="ml-2 text-xs" style={{ color: 'var(--kinrel-dim)' }}>
                        ({p.relationship})
                      </span>
                    )}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        </div>

        {/* Find Path Button */}
        <Button
          onClick={handleFindPath}
          disabled={loading || !personA || !personB || personsLoading}
          className="w-full"
          style={{
            background: 'var(--kinrel-grad-ignite)',
            color: 'var(--kinrel-white)',
          }}
        >
          {loading ? (
            <>
              <Loader2 className="mr-2 h-4 w-4 animate-spin" />
              Finding path...
            </>
          ) : (
            <>
              <Users className="mr-2 h-4 w-4" />
              Find Path
            </>
          )}
        </Button>

        {/* Results */}
        <AnimatePresence>
          {pathResult && (
            <motion.div
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -10 }}
              transition={{ duration: 0.3 }}
              className="rounded-xl p-4 border border-white/10"
              style={{ backgroundColor: 'var(--kinrel-elevated)' }}
            >
              {pathResult.path === null ? (
                <div className="text-center py-4">
                  <p style={{ color: 'var(--kinrel-silver)' }}>
                    No relationship path found between{' '}
                    <strong className="text-kinrel-white">{pathResult.from?.name || personAName}</strong> and{' '}
                    <strong className="text-kinrel-white">{pathResult.to?.name || personBName}</strong>.
                  </p>
                  <p className="text-sm mt-2" style={{ color: 'var(--kinrel-dim)' }}>
                    Try adding more relationships to connect them.
                  </p>
                </div>
              ) : (
                <div className="space-y-4">
                  {/* Path Steps */}
                  <div className="flex items-center gap-2 flex-wrap">
                    {pathResult.path.length === 0 ? (
                      <Badge
                        variant="outline"
                        className="border-white/10 text-kinrel-white"
                      >
                        Same person
                      </Badge>
                    ) : (
                      <>
                        <span className="font-medium text-kinrel-white">
                          {pathResult.from?.name || personAName}
                        </span>
                        {pathResult.path.map((step, idx) => (
                          <span key={idx} className="flex items-center gap-2">
                            <ArrowRight className="h-4 w-4" style={{ color: 'var(--kinrel-orange)' }} />
                            <Badge
                              variant="outline"
                              className="border-white/10"
                              style={{ color: 'var(--kinrel-orange)' }}
                            >
                              {step.localizedType || step.type}
                            </Badge>
                          </span>
                        ))}
                        <ArrowRight className="h-4 w-4" style={{ color: 'var(--kinrel-orange)' }} />
                        <span className="font-medium text-kinrel-white">
                          {pathResult.to?.name || personBName}
                        </span>
                      </>
                    )}
                  </div>

                  {/* Localized Description */}
                  {pathResult.localizedDescription && pathResult.length > 0 && (
                    <div
                      className="rounded-lg p-3 border border-white/5"
                      style={{ backgroundColor: 'rgba(232, 97, 42, 0.08)' }}
                    >
                      <p className="text-sm" style={{ color: 'var(--kinrel-silver)' }}>
                        <strong className="text-kinrel-white">{personAName}</strong> is{' '}
                        <strong className="text-kinrel-white">{pathResult.to?.name || personBName}</strong>&apos;s{' '}
                        <span style={{ color: 'var(--kinrel-orange)' }} className="font-semibold">
                          {pathResult.localizedDescription}
                        </span>
                      </p>
                      {pathResult.relationshipDescription && (
                        <p className="text-xs mt-1" style={{ color: 'var(--kinrel-dim)' }}>
                          ({pathResult.relationshipDescription})
                        </p>
                      )}
                    </div>
                  )}

                  {/* Path Length */}
                  <div className="flex items-center gap-2">
                    <span className="text-xs" style={{ color: 'var(--kinrel-dim)' }}>
                      Degrees of separation: {pathResult.length}
                    </span>
                  </div>
                </div>
              )}
            </motion.div>
          )}
        </AnimatePresence>
      </CardContent>
    </Card>
  )
}
