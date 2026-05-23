'use client'

import { useState, useEffect, useCallback } from 'react'
import { useRouter } from 'next/navigation'
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetDescription,
} from '@/components/ui/sheet'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Button } from '@/components/ui/button'
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip'
import {
  Command,
  CommandInput,
  CommandList,
  CommandEmpty,
  CommandGroup,
  CommandItem,
} from '@/components/ui/command'
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover'
import { Badge } from '@/components/ui/badge'
import { useMediaQuery } from '@/hooks/use-mobile'
import { Loader2, Check, ChevronsUpDown, AlertTriangle, Save } from 'lucide-react'
import { useToast } from '@/hooks/use-toast'

interface KinshipOption {
  key: string
  englishTerm: string
  gender: string
  category: string
}

interface PersonData {
  id: string
  name: string
  relationship: string | null
  dateOfBirth: string | null
  city: string | null
  occupation: string | null
  gotra: string | null
  isDeceased: boolean
  privacyLevel: string
}

interface PersonForm {
  name: string
  relationship: string
  dateOfBirth: string
  city: string
  occupation: string
  gotra: string
  isDeceased: boolean
  privacyLevel: 'family' | 'extended' | 'public'
}

interface EditPersonDrawerProps {
  familyId: string
  person: PersonData | null
  open: boolean
  onOpenChange: (open: boolean) => void
  onSuccess: (person: Record<string, unknown>) => void
}

export function EditPersonDrawer({ familyId, person, open, onOpenChange, onSuccess }: EditPersonDrawerProps) {
  const isDesktop = useMediaQuery('(min-width: 768px)')
  const { toast } = useToast()
  const router = useRouter()

  const [form, setForm] = useState<PersonForm>({
    name: '',
    relationship: '',
    dateOfBirth: '',
    city: '',
    occupation: '',
    gotra: '',
    isDeceased: false,
    privacyLevel: 'family',
  })
  const [errors, setErrors] = useState<Record<string, string>>({})
  const [loading, setLoading] = useState(false)
  const [kinshipOptions, setKinshipOptions] = useState<KinshipOption[]>([])
  const [kinshipSearch, setKinshipSearch] = useState('')
  const [kinshipOpen, setKinshipOpen] = useState(false)

  // Pre-fill form when person data changes
  useEffect(() => {
    if (person) {
      setForm({
        name: person.name || '',
        relationship: person.relationship || '',
        dateOfBirth: person.dateOfBirth ? new Date(person.dateOfBirth).toISOString().split('T')[0] : '',
        city: person.city || '',
        occupation: person.occupation || '',
        gotra: person.gotra || '',
        isDeceased: person.isDeceased || false,
        privacyLevel: (person.privacyLevel as 'family' | 'extended' | 'public') || 'family',
      })
    }
  }, [person])

  // Fetch kinship options
  useEffect(() => {
    async function fetchKinship() {
      try {
        const res = await fetch('/api/v1/kinship')
        if (res.ok) {
          const data = await res.json()
          if (data.relationships) {
            setKinshipOptions(
              data.relationships.map((r: Record<string, unknown>) => ({
                key: r.relationshipKey as string,
                englishTerm: r.englishTerm as string,
                gender: (r.gender as string) || 'neutral',
                category: (r.relationshipCategory as string) || 'core_family',
              }))
            )
          }
        }
      } catch {
        // Silently fail
      }
    }
    if (open) fetchKinship()
  }, [open])

  const filteredOptions = kinshipSearch
    ? kinshipOptions.filter(
        (o) =>
          o.englishTerm.toLowerCase().includes(kinshipSearch.toLowerCase()) ||
          o.key.toLowerCase().includes(kinshipSearch.toLowerCase())
      )
    : kinshipOptions

  const validate = useCallback((): boolean => {
    const newErrors: Record<string, string> = {}
    if (!form.name.trim()) newErrors.name = 'Name is required'
    if (!form.relationship.trim()) newErrors.relationship = 'Relationship is required'
    setErrors(newErrors)
    return Object.keys(newErrors).length === 0
  }, [form.name, form.relationship])

  const handleSubmit = async () => {
    if (!validate() || !person) return
    setLoading(true)

    try {
      const res = await fetch(`/api/families/${familyId}/persons/${person.id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(form),
      })

      const data = await res.json()

      if (!res.ok) {
        toast({
          title: 'Error',
          description: data.error || 'Failed to update person',
          variant: 'destructive',
        })
        return
      }

      toast({
        title: 'Person updated',
        description: `${form.name} has been updated.`,
      })

      onOpenChange(false)
      onSuccess(data.person || data)
      router.refresh()
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

  const formContent = (
    <div className="space-y-5 px-1">
      {/* Full Name */}
      <div className="space-y-2">
        <Label htmlFor="edit-name" style={{ color: 'var(--kinrel-silver)' }}>
          Full Name <span style={{ color: 'var(--kinrel-orange)' }}>*</span>
        </Label>
        <Input
          id="edit-name"
          placeholder="Enter full name"
          value={form.name}
          onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))}
          className="border-white/10 bg-kinrel-elevated text-kinrel-white placeholder:text-kinrel-dim"
          aria-invalid={!!errors.name}
        />
        {errors.name && <p className="text-xs" style={{ color: 'var(--kinrel-error)' }}>{errors.name}</p>}
      </div>

      {/* Relationship — Searchable Picker */}
      <div className="space-y-2">
        <Label style={{ color: 'var(--kinrel-silver)' }}>
          Relationship <span style={{ color: 'var(--kinrel-orange)' }}>*</span>
        </Label>
        <Popover open={kinshipOpen} onOpenChange={setKinshipOpen}>
          <PopoverTrigger asChild>
            <Button
              variant="outline"
              role="combobox"
              aria-expanded={kinshipOpen}
              className="w-full justify-between border-white/10 bg-kinrel-elevated text-kinrel-white hover:bg-kinrel-elevated/80"
            >
              {form.relationship
                ? kinshipOptions.find((o) => o.key === form.relationship)?.englishTerm || form.relationship
                : 'Select relationship...'}
              <ChevronsUpDown className="ml-2 h-4 w-4 shrink-0 opacity-50" />
            </Button>
          </PopoverTrigger>
          <PopoverContent className="w-[var(--radix-popover-trigger-width)] p-0" style={{ backgroundColor: 'var(--kinrel-card)', borderColor: 'rgba(255,255,255,0.1)' }}>
            <Command>
              <CommandInput
                placeholder="Search kinship terms..."
                value={kinshipSearch}
                onValueChange={setKinshipSearch}
              />
              <CommandList className="max-h-64">
                <CommandEmpty>No relationship found.</CommandEmpty>
                <CommandGroup>
                  {filteredOptions.slice(0, 50).map((option) => (
                    <CommandItem
                      key={option.key}
                      value={option.englishTerm}
                      onSelect={() => {
                        setForm((f) => ({ ...f, relationship: option.key }))
                        setKinshipSearch('')
                        setKinshipOpen(false)
                      }}
                      className="text-kinrel-white"
                    >
                      <Check
                        className={`mr-2 h-4 w-4 ${form.relationship === option.key ? 'opacity-100' : 'opacity-0'}`}
                      />
                      <span>{option.englishTerm}</span>
                      <Badge variant="outline" className="ml-auto text-[10px] border-white/10" style={{ color: 'var(--kinrel-dim)' }}>
                        {option.gender}
                      </Badge>
                    </CommandItem>
                  ))}
                </CommandGroup>
              </CommandList>
            </Command>
          </PopoverContent>
        </Popover>
        {errors.relationship && <p className="text-xs" style={{ color: 'var(--kinrel-error)' }}>{errors.relationship}</p>}
      </div>

      {/* Date of Birth */}
      <div className="space-y-2">
        <Label htmlFor="edit-dob" style={{ color: 'var(--kinrel-silver)' }}>
          Date of Birth
        </Label>
        <Input
          id="edit-dob"
          type="date"
          value={form.dateOfBirth}
          onChange={(e) => setForm((f) => ({ ...f, dateOfBirth: e.target.value }))}
          className="border-white/10 bg-kinrel-elevated text-kinrel-white"
        />
      </div>

      {/* City */}
      <div className="space-y-2">
        <Label htmlFor="edit-city" style={{ color: 'var(--kinrel-silver)' }}>
          City
        </Label>
        <Input
          id="edit-city"
          placeholder="City"
          value={form.city}
          onChange={(e) => setForm((f) => ({ ...f, city: e.target.value }))}
          className="border-white/10 bg-kinrel-elevated text-kinrel-white placeholder:text-kinrel-dim"
        />
      </div>

      {/* Occupation */}
      <div className="space-y-2">
        <Label htmlFor="edit-occupation" style={{ color: 'var(--kinrel-silver)' }}>
          Occupation
        </Label>
        <Input
          id="edit-occupation"
          placeholder="Occupation"
          value={form.occupation}
          onChange={(e) => setForm((f) => ({ ...f, occupation: e.target.value }))}
          className="border-white/10 bg-kinrel-elevated text-kinrel-white placeholder:text-kinrel-dim"
        />
      </div>

      {/* Gotra */}
      <div className="space-y-2">
        <div className="flex items-center gap-2">
          <Label htmlFor="edit-gotra" style={{ color: 'var(--kinrel-silver)' }}>
            Gotra
          </Label>
          <TooltipProvider>
            <Tooltip>
              <TooltipTrigger asChild>
                <AlertTriangle className="h-3.5 w-3.5" style={{ color: 'var(--kinrel-warning)' }} />
              </TooltipTrigger>
              <TooltipContent>
                <p>Gotra is sensitive — family only</p>
              </TooltipContent>
            </Tooltip>
          </TooltipProvider>
        </div>
        <Input
          id="edit-gotra"
          placeholder="Gotra (family only)"
          value={form.gotra}
          onChange={(e) => setForm((f) => ({ ...f, gotra: e.target.value }))}
          className="border-white/10 bg-kinrel-elevated text-kinrel-white placeholder:text-kinrel-dim"
        />
      </div>

      {/* Alive / Deceased */}
      <div className="space-y-2">
        <Label style={{ color: 'var(--kinrel-silver)' }}>Status</Label>
        <RadioGroup
          value={form.isDeceased ? 'deceased' : 'alive'}
          onValueChange={(v) => setForm((f) => ({ ...f, isDeceased: v === 'deceased' }))}
          className="flex gap-4"
        >
          <div className="flex items-center space-x-2">
            <RadioGroupItem value="alive" id="edit-alive" />
            <Label htmlFor="edit-alive" style={{ color: 'var(--kinrel-white)' }}>Alive</Label>
          </div>
          <div className="flex items-center space-x-2">
            <RadioGroupItem value="deceased" id="edit-deceased" />
            <Label htmlFor="edit-deceased" style={{ color: 'var(--kinrel-white)' }}>Deceased</Label>
          </div>
        </RadioGroup>
      </div>

      {/* Privacy Level */}
      <div className="space-y-2">
        <Label style={{ color: 'var(--kinrel-silver)' }}>Privacy Level</Label>
        <Select
          value={form.privacyLevel}
          onValueChange={(v) => setForm((f) => ({ ...f, privacyLevel: v as 'family' | 'extended' | 'public' }))}
        >
          <SelectTrigger className="border-white/10 bg-kinrel-elevated text-kinrel-white">
            <SelectValue />
          </SelectTrigger>
          <SelectContent style={{ backgroundColor: 'var(--kinrel-card)' }}>
            <SelectItem value="family">Family Only</SelectItem>
            <SelectItem value="extended">Extended Family</SelectItem>
            <SelectItem value="public">Public</SelectItem>
          </SelectContent>
        </Select>
      </div>

      {/* Submit */}
      <Button
        onClick={handleSubmit}
        disabled={loading}
        className="w-full"
        style={{
          background: 'var(--kinrel-grad-ignite)',
          color: 'var(--kinrel-white)',
        }}
      >
        {loading ? (
          <>
            <Loader2 className="mr-2 h-4 w-4 animate-spin" />
            Saving...
          </>
        ) : (
          <>
            <Save className="mr-2 h-4 w-4" />
            Save Changes
          </>
        )}
      </Button>
    </div>
  )

  if (isDesktop) {
    return (
      <Dialog open={open} onOpenChange={onOpenChange}>
        <DialogContent className="sm:max-w-[480px] max-h-[85vh] overflow-y-auto" style={{ backgroundColor: 'var(--kinrel-card)', borderColor: 'rgba(255,255,255,0.1)' }}>
          <DialogHeader>
            <DialogTitle className="text-kinrel-white">Edit Person</DialogTitle>
            <DialogDescription className="text-kinrel-silver">
              Update family member details.
            </DialogDescription>
          </DialogHeader>
          {formContent}
        </DialogContent>
      </Dialog>
    )
  }

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent
        side="bottom"
        className="max-h-[85vh] overflow-y-auto rounded-t-2xl"
        style={{ backgroundColor: 'var(--kinrel-card)' }}
      >
        <SheetHeader>
          <SheetTitle className="text-kinrel-white">Edit Person</SheetTitle>
          <SheetDescription className="text-kinrel-silver">
            Update family member details.
          </SheetDescription>
        </SheetHeader>
        {formContent}
      </SheetContent>
    </Sheet>
  )
}
