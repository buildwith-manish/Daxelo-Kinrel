'use client'

import { useState } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from '@/components/ui/dialog'
import {
  Drawer,
  DrawerContent,
  DrawerHeader,
  DrawerTitle,
  DrawerDescription,
} from '@/components/ui/drawer'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Textarea } from '@/components/ui/textarea'
import { Label } from '@/components/ui/label'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Loader2, AlertCircle } from 'lucide-react'
import { useIsMobile } from '@/hooks/use-mobile'

// ── Supported Locales ─────────────────────────────────────────────────────

const SUPPORTED_LOCALES = [
  { code: 'en', label: 'English' },
  { code: 'hi', label: 'हिन्दी (Hindi)' },
  { code: 'bn', label: 'বাংলা (Bengali)' },
  { code: 'te', label: 'తెలుగు (Telugu)' },
  { code: 'mr', label: 'मराठी (Marathi)' },
  { code: 'ta', label: 'தமிழ் (Tamil)' },
  { code: 'gu', label: 'ગુજરાતી (Gujarati)' },
  { code: 'kn', label: 'ಕನ್ನಡ (Kannada)' },
  { code: 'ml', label: 'മലയാളം (Malayalam)' },
  { code: 'pa', label: 'ਪੰਜਾਬੀ (Punjabi)' },
  { code: 'or', label: 'ଓଡ଼ିଆ (Odia)' },
  { code: 'as', label: 'অসমীয়া (Assamese)' },
  { code: 'ur', label: 'اردو (Urdu)' },
  { code: 'sa', label: 'संस्कृतम् (Sanskrit)' },
]

// ── Props ─────────────────────────────────────────────────────────────────

interface CreateFamilyFormProps {
  onSuccess: (family: unknown) => void
  onClose: () => void
}

// ── Form Component ────────────────────────────────────────────────────────

function CreateFamilyFormInner({
  onSuccess,
  onClose,
}: CreateFamilyFormProps) {
  const [name, setName] = useState('')
  const [description, setDescription] = useState('')
  const [primaryLanguage, setPrimaryLanguage] = useState('en')
  const [gotra, setGotra] = useState('')
  const [originVillage, setOriginVillage] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setError('')

    if (!name.trim()) {
      setError('Family name is required')
      return
    }

    setLoading(true)

    try {
      const res = await fetch('/api/families', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          name: name.trim(),
          description: description.trim() || undefined,
          primaryLanguage,
          gotra: gotra.trim() || undefined,
          originVillage: originVillage.trim() || undefined,
        }),
      })

      const data = await res.json()

      if (!res.ok) {
        setError(data.error || 'Failed to create family')
        return
      }

      onSuccess(data.family)
    } catch {
      setError('Something went wrong. Please try again.')
    } finally {
      setLoading(false)
    }
  }

  return (
    <motion.form
      onSubmit={handleSubmit}
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.25 }}
      className="space-y-4"
    >
      {error && (
        <div className="flex items-center gap-2 rounded-lg bg-destructive/10 border border-destructive/30 px-4 py-3 text-sm text-destructive">
          <AlertCircle className="h-4 w-4 shrink-0" />
          {error}
        </div>
      )}

      <div className="space-y-2">
        <Label htmlFor="family-name" className="text-kinrel-silver">
          Family name <span className="text-kinrel-orange">*</span>
        </Label>
        <Input
          id="family-name"
          placeholder="e.g., Sharma Family"
          value={name}
          onChange={(e) => setName(e.target.value)}
          required
          autoFocus
          className="bg-kinrel-elevated border-white/10 text-kinrel-white placeholder:text-kinrel-dim"
        />
      </div>

      <div className="space-y-2">
        <Label htmlFor="family-description" className="text-kinrel-silver">
          Description
        </Label>
        <Textarea
          id="family-description"
          placeholder="A short description of your family..."
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          rows={3}
          className="bg-kinrel-elevated border-white/10 text-kinrel-white placeholder:text-kinrel-dim resize-none"
        />
      </div>

      <div className="space-y-2">
        <Label htmlFor="family-language" className="text-kinrel-silver">
          Primary language
        </Label>
        <Select value={primaryLanguage} onValueChange={setPrimaryLanguage}>
          <SelectTrigger className="bg-kinrel-elevated border-white/10 text-kinrel-white w-full">
            <SelectValue placeholder="Select language" />
          </SelectTrigger>
          <SelectContent className="bg-kinrel-card border-white/10 max-h-64">
            {SUPPORTED_LOCALES.map((locale) => (
              <SelectItem
                key={locale.code}
                value={locale.code}
                className="text-kinrel-white focus:bg-kinrel-elevated focus:text-kinrel-white"
              >
                {locale.label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <div className="space-y-2">
          <Label htmlFor="family-gotra" className="text-kinrel-silver">
            Gotra
          </Label>
          <Input
            id="family-gotra"
            placeholder="e.g., Bharadwaj"
            value={gotra}
            onChange={(e) => setGotra(e.target.value)}
            className="bg-kinrel-elevated border-white/10 text-kinrel-white placeholder:text-kinrel-dim"
          />
        </div>

        <div className="space-y-2">
          <Label htmlFor="family-village" className="text-kinrel-silver">
            Origin village
          </Label>
          <Input
            id="family-village"
            placeholder="e.g., Rampur"
            value={originVillage}
            onChange={(e) => setOriginVillage(e.target.value)}
            className="bg-kinrel-elevated border-white/10 text-kinrel-white placeholder:text-kinrel-dim"
          />
        </div>
      </div>

      <div className="flex gap-3 pt-2">
        <Button
          type="button"
          variant="outline"
          onClick={onClose}
          disabled={loading}
          className="flex-1 border-white/10 text-kinrel-silver hover:text-kinrel-white hover:bg-white/5"
        >
          Cancel
        </Button>
        <Button
          type="submit"
          disabled={loading || !name.trim()}
          className="flex-1 bg-kinrel-orange hover:bg-kinrel-amber text-kinrel-white font-semibold"
        >
          {loading ? (
            <>
              <Loader2 className="h-4 w-4 mr-2 animate-spin" />
              Creating...
            </>
          ) : (
            'Create Family'
          )}
        </Button>
      </div>
    </motion.form>
  )
}

// ── Responsive Wrapper ────────────────────────────────────────────────────

export function CreateFamilyForm({
  onSuccess,
  onClose,
}: CreateFamilyFormProps) {
  const isMobile = useIsMobile()

  if (isMobile) {
    return (
      <Drawer open onOpenChange={(open) => !open && onClose()}>
        <DrawerContent className="bg-kinrel-card border-white/10 max-h-[85vh]">
          <DrawerHeader className="text-left">
            <DrawerTitle className="text-kinrel-white font-display">
              Create New Family
            </DrawerTitle>
            <DrawerDescription className="text-kinrel-silver">
              Start building your family tree by creating a family group.
            </DrawerDescription>
          </DrawerHeader>
          <div className="px-4 pb-6 overflow-y-auto">
            <CreateFamilyFormInner onSuccess={onSuccess} onClose={onClose} />
          </div>
        </DrawerContent>
      </Drawer>
    )
  }

  return (
    <Dialog open onOpenChange={(open) => !open && onClose()}>
      <DialogContent className="bg-kinrel-card border-white/10 sm:max-w-lg max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="text-kinrel-white font-display">
            Create New Family
          </DialogTitle>
          <DialogDescription className="text-kinrel-silver">
            Start building your family tree by creating a family group.
          </DialogDescription>
        </DialogHeader>
        <CreateFamilyFormInner onSuccess={onSuccess} onClose={onClose} />
      </DialogContent>
    </Dialog>
  )
}
