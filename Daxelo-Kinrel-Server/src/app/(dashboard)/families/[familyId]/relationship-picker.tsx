'use client'

import { useState, useEffect, useMemo } from 'react'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from '@/components/ui/dialog'
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetDescription,
} from '@/components/ui/sheet'
import {
  Command,
  CommandInput,
  CommandList,
  CommandEmpty,
  CommandGroup,
  CommandItem,
} from '@/components/ui/command'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { ScrollArea } from '@/components/ui/scroll-area'
import { useMediaQuery } from '@/hooks/use-mobile'
import { Loader2 } from 'lucide-react'

interface KinshipOption {
  key: string
  englishTerm: string
  gender: string
  category: string
  generation: number
}

interface RelationshipPickerProps {
  open: boolean
  onClose: () => void
  onSelect: (type: string) => void
  fromName: string
  toName: string
  locale: string
}

const CATEGORY_LABELS: Record<string, string> = {
  core_family: 'Core Family',
  in_laws: 'In-Laws',
  grandparents: 'Grandparents',
  cousins: 'Cousins',
  extended: 'Extended Family',
  step_family: 'Step Family',
  adoptive_family: 'Adoptive Family',
  direct_ancestor: 'Direct Ancestors',
  direct_descendant: 'Direct Descendants',
}

export function RelationshipPicker({
  open,
  onClose,
  onSelect,
  fromName,
  toName,
  locale,
}: RelationshipPickerProps) {
  const isDesktop = useMediaQuery('(min-width: 768px)')
  const [options, setOptions] = useState<KinshipOption[]>([])
  const [loading, setLoading] = useState(false)
  const [search, setSearch] = useState('')

  useEffect(() => {
    if (!open) return

    setLoading(true)
    // Fetch all relationships by searching with a broad query
    // We'll fetch by categories to get all 523 items
    async function fetchAll() {
      try {
        const categories = [
          'core_family',
          'in_laws',
          'grandparents',
          'cousins',
          'extended',
          'step_family',
          'adoptive_family',
          'direct_ancestor',
          'direct_descendant',
        ]

        const allOptions: KinshipOption[] = []

        const results = await Promise.all(
          categories.map((cat) =>
            fetch(`/api/v1/kinship?category=${cat}`)
              .then((r) => (r.ok ? r.json() : { results: [] }))
              .catch(() => ({ results: [] }))
          )
        )

        for (const result of results) {
          if (result.results) {
            for (const r of result.results) {
              allOptions.push({
                key: r.relationshipKey,
                englishTerm: r.englishTerm,
                gender: r.gender || 'neutral',
                category: r.relationshipCategory || 'core_family',
                generation: r.generation ?? 0,
              })
            }
          }
        }

        setOptions(allOptions)
      } catch {
        // Silently fail
      } finally {
        setLoading(false)
      }
    }

    fetchAll()
  }, [open])

  const grouped = useMemo(() => {
    const filtered = search
      ? options.filter(
          (o) =>
            o.englishTerm.toLowerCase().includes(search.toLowerCase()) ||
            o.key.toLowerCase().includes(search.toLowerCase())
        )
      : options

    const groups: Record<string, KinshipOption[]> = {}
    for (const opt of filtered) {
      const cat = opt.category || 'core_family'
      if (!groups[cat]) groups[cat] = []
      groups[cat].push(opt)
    }
    return groups
  }, [options, search])

  const handleSelect = (key: string) => {
    onSelect(key)
    onClose()
    setSearch('')
  }

  const pickerContent = (
    <div className="flex flex-col gap-3">
      {loading ? (
        <div className="flex items-center justify-center py-12">
          <Loader2 className="h-6 w-6 animate-spin text-kinrel-orange" />
          <span className="ml-2 text-sm text-kinrel-silver">Loading relationships...</span>
        </div>
      ) : (
        <Command className="bg-transparent">
          <CommandInput
            placeholder="Search by English term or key..."
            value={search}
            onValueChange={setSearch}
            className="border-white/10 bg-kinrel-elevated text-kinrel-white"
          />
          <CommandList className="max-h-[50vh]">
            <CommandEmpty className="py-6 text-center text-sm text-kinrel-silver">
              No relationship found.
            </CommandEmpty>
            {Object.entries(grouped).map(([category, items]) => (
              <CommandGroup
                key={category}
                heading={
                  <span className="text-xs font-semibold uppercase tracking-wider text-kinrel-orange">
                    {CATEGORY_LABELS[category] || category}
                  </span>
                }
              >
                {items.map((option) => (
                  <CommandItem
                    key={option.key}
                    value={option.englishTerm}
                    onSelect={() => handleSelect(option.key)}
                    className="flex items-center gap-2 px-3 py-2 text-kinrel-white hover:bg-white/5 cursor-pointer"
                  >
                    <span className="flex-1 text-sm">{option.englishTerm}</span>
                    <Badge
                      variant="outline"
                      className="text-[10px] border-white/10 capitalize"
                      style={{ color: 'var(--kinrel-dim)' }}
                    >
                      {option.gender}
                    </Badge>
                  </CommandItem>
                ))}
              </CommandGroup>
            ))}
          </CommandList>
        </Command>
      )}

      <div className="flex justify-end gap-2 pt-2 border-t border-white/10">
        <Button
          variant="ghost"
          onClick={() => {
            onClose()
            setSearch('')
          }}
          className="text-kinrel-silver hover:text-kinrel-white hover:bg-white/5"
        >
          Cancel
        </Button>
      </div>
    </div>
  )

  if (isDesktop) {
    return (
      <Dialog open={open} onOpenChange={(v) => !v && onClose()}>
        <DialogContent
          className="sm:max-w-[520px] max-h-[80vh]"
          style={{
            backgroundColor: 'var(--kinrel-card)',
            borderColor: 'rgba(255,255,255,0.1)',
          }}
        >
          <DialogHeader>
            <DialogTitle className="text-kinrel-white">
              How is {fromName} related to {toName}?
            </DialogTitle>
            <DialogDescription className="text-kinrel-silver">
              Choose the relationship type. The inverse will be created automatically.
            </DialogDescription>
          </DialogHeader>
          {pickerContent}
        </DialogContent>
      </Dialog>
    )
  }

  return (
    <Sheet open={open} onOpenChange={(v) => !v && onClose()}>
      <SheetContent
        side="bottom"
        className="max-h-[85vh] rounded-t-2xl"
        style={{ backgroundColor: 'var(--kinrel-card)' }}
      >
        <SheetHeader>
          <SheetTitle className="text-kinrel-white">
            How is {fromName} related to {toName}?
          </SheetTitle>
          <SheetDescription className="text-kinrel-silver">
            Choose the relationship type. The inverse will be created automatically.
          </SheetDescription>
        </SheetHeader>
        {pickerContent}
      </SheetContent>
    </Sheet>
  )
}
