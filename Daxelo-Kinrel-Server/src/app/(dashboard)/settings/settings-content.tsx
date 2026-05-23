'use client'

import { useState } from 'react'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Button } from '@/components/ui/button'
import { Switch } from '@/components/ui/switch'
import { Separator } from '@/components/ui/separator'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from '@/components/ui/alert-dialog'
import { Loader2, User, Globe, Bell, Shield, Trash2, Save } from 'lucide-react'
import { useToast } from '@/hooks/use-toast'
import { motion } from 'framer-motion'
import { LANGUAGE_CODE_MAP, type LocaleCode } from '@/lib/kinship'

interface UserProfile {
  id: string
  email: string
  name: string | null
  phone: string | null
  preferredLanguage: string
  role: string
  createdAt: string
}

interface NotificationPref {
  id: string
  eventType: string
  whatsapp: boolean
  push: boolean
  inApp: boolean
  email: boolean
}

interface SettingsContentProps {
  user: UserProfile
  notificationPrefs: NotificationPref[]
}

const LANGUAGE_OPTIONS: { code: string; label: string }[] = [
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

// Default event types if user has no prefs yet
const DEFAULT_EVENT_TYPES = [
  'family_update',
  'birthday_reminder',
  'relationship_discovery',
  'invitation_received',
  'whatsapp_message',
]

export function SettingsContent({ user, notificationPrefs }: SettingsContentProps) {
  const { toast } = useToast()
  const [savingProfile, setSavingProfile] = useState(false)
  const [savingLanguage, setSavingLanguage] = useState(false)
  const [deleting, setDeleting] = useState(false)

  const [name, setName] = useState(user.name || '')
  const [phone, setPhone] = useState(user.phone || '')
  const [preferredLanguage, setPreferredLanguage] = useState(user.preferredLanguage)

  // Build notification prefs state
  const [prefs, setPrefs] = useState<Record<string, { whatsapp: boolean; push: boolean; inApp: boolean; email: boolean }>>(() => {
    const initial: Record<string, { whatsapp: boolean; push: boolean; inApp: boolean; email: boolean }> = {}
    for (const pref of notificationPrefs) {
      initial[pref.eventType] = {
        whatsapp: pref.whatsapp,
        push: pref.push,
        inApp: pref.inApp,
        email: pref.email,
      }
    }
    // Ensure defaults exist
    for (const eventType of DEFAULT_EVENT_TYPES) {
      if (!initial[eventType]) {
        initial[eventType] = { whatsapp: true, push: true, inApp: true, email: false }
      }
    }
    return initial
  })

  const handleSaveProfile = async () => {
    setSavingProfile(true)
    try {
      const res = await fetch('/api/users/me', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name, phone }),
      })

      if (res.ok) {
        toast({ title: 'Profile updated' })
      } else {
        const data = await res.json()
        toast({ title: 'Error', description: data.error || 'Failed to update', variant: 'destructive' })
      }
    } catch {
      toast({ title: 'Network error', variant: 'destructive' })
    } finally {
      setSavingProfile(false)
    }
  }

  const handleLanguageChange = async (newLang: string) => {
    setPreferredLanguage(newLang)
    setSavingLanguage(true)
    try {
      const res = await fetch('/api/users/me', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ preferredLanguage: newLang }),
      })

      if (res.ok) {
        toast({ title: 'Language updated', description: `Preferred language set to ${LANGUAGE_OPTIONS.find(l => l.code === newLang)?.label || newLang}` })
      } else {
        toast({ title: 'Error updating language', variant: 'destructive' })
        setPreferredLanguage(user.preferredLanguage)
      }
    } catch {
      toast({ title: 'Network error', variant: 'destructive' })
      setPreferredLanguage(user.preferredLanguage)
    } finally {
      setSavingLanguage(false)
    }
  }

  const handleToggleNotification = (eventType: string, channel: 'whatsapp' | 'push' | 'inApp' | 'email', value: boolean) => {
    setPrefs((prev) => ({
      ...prev,
      [eventType]: {
        ...prev[eventType],
        [channel]: value,
      },
    }))
  }

  const handleDeleteAccount = async () => {
    setDeleting(true)
    try {
      const res = await fetch('/api/users/me', { method: 'DELETE' })
      if (res.ok) {
        toast({ title: 'Account deleted', description: 'Your account has been deleted.' })
        window.location.href = '/'
      } else {
        const data = await res.json()
        toast({ title: 'Error', description: data.error || 'Failed to delete account', variant: 'destructive' })
      }
    } catch {
      toast({ title: 'Network error', variant: 'destructive' })
    } finally {
      setDeleting(false)
    }
  }

  const sectionAnimation = {
    initial: { opacity: 0, y: 20 },
    animate: { opacity: 1, y: 0 },
    transition: { duration: 0.4 },
  }

  return (
    <div className="max-w-2xl mx-auto p-4 sm:p-6 space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-kinrel-white" style={{ fontFamily: 'var(--kinrel-font-display)' }}>
          Settings
        </h1>
        <p className="text-sm mt-1" style={{ color: 'var(--kinrel-silver)' }}>
          Manage your profile, language, and notifications.
        </p>
      </div>

      {/* ── Profile Section ──────────────────────────────────────── */}
      <motion.div {...sectionAnimation}>
        <Card className="border-white/10" style={{ backgroundColor: 'var(--kinrel-card)' }}>
          <CardHeader>
            <CardTitle className="text-kinrel-white flex items-center gap-2">
              <User className="h-5 w-5" style={{ color: 'var(--kinrel-orange)' }} />
              Profile
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="settings-name" style={{ color: 'var(--kinrel-silver)' }}>Name</Label>
              <Input
                id="settings-name"
                value={name}
                onChange={(e) => setName(e.target.value)}
                className="border-white/10 bg-kinrel-elevated text-kinrel-white"
              />
            </div>
            <div className="space-y-2">
              <Label style={{ color: 'var(--kinrel-silver)' }}>Email</Label>
              <Input
                value={user.email}
                disabled
                className="border-white/10 bg-kinrel-elevated text-kinrel-dim cursor-not-allowed"
              />
              <p className="text-xs" style={{ color: 'var(--kinrel-dim)' }}>Email cannot be changed.</p>
            </div>
            <div className="space-y-2">
              <Label htmlFor="settings-phone" style={{ color: 'var(--kinrel-silver)' }}>Phone</Label>
              <Input
                id="settings-phone"
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
                placeholder="+91 98765 43210"
                className="border-white/10 bg-kinrel-elevated text-kinrel-white placeholder:text-kinrel-dim"
              />
            </div>
            <Button
              onClick={handleSaveProfile}
              disabled={savingProfile}
              className="w-full"
              style={{ background: 'var(--kinrel-grad-ignite)', color: 'var(--kinrel-white)' }}
            >
              {savingProfile ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <Save className="mr-2 h-4 w-4" />}
              Save Profile
            </Button>
          </CardContent>
        </Card>
      </motion.div>

      {/* ── Language Section ──────────────────────────────────────── */}
      <motion.div {...sectionAnimation} transition={{ duration: 0.4, delay: 0.1 }}>
        <Card className="border-white/10" style={{ backgroundColor: 'var(--kinrel-card)' }}>
          <CardHeader>
            <CardTitle className="text-kinrel-white flex items-center gap-2">
              <Globe className="h-5 w-5" style={{ color: 'var(--kinrel-orange)' }} />
              Language
            </CardTitle>
            <CardDescription className="text-kinrel-silver">
              Choose your preferred language for kinship terms and UI.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <Select value={preferredLanguage} onValueChange={handleLanguageChange}>
              <SelectTrigger className="border-white/10 bg-kinrel-elevated text-kinrel-white" disabled={savingLanguage}>
                {savingLanguage && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
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
          </CardContent>
        </Card>
      </motion.div>

      {/* ── Notifications Section ─────────────────────────────────── */}
      <motion.div {...sectionAnimation} transition={{ duration: 0.4, delay: 0.2 }}>
        <Card className="border-white/10" style={{ backgroundColor: 'var(--kinrel-card)' }}>
          <CardHeader>
            <CardTitle className="text-kinrel-white flex items-center gap-2">
              <Bell className="h-5 w-5" style={{ color: 'var(--kinrel-orange)' }} />
              Notifications
            </CardTitle>
            <CardDescription className="text-kinrel-silver">
              Control how you receive notifications for each event type.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <div className="space-y-4">
              {/* Header row */}
              <div className="grid grid-cols-[1fr_repeat(4,56px)] gap-2 items-center text-xs font-medium" style={{ color: 'var(--kinrel-dim)' }}>
                <span>Event</span>
                <span className="text-center">WA</span>
                <span className="text-center">Push</span>
                <span className="text-center">App</span>
                <span className="text-center">Email</span>
              </div>
              <Separator className="bg-white/5" />
              {Object.entries(prefs).map(([eventType, channels]) => (
                <div key={eventType} className="grid grid-cols-[1fr_repeat(4,56px)] gap-2 items-center">
                  <span className="text-sm text-kinrel-white capitalize truncate">
                    {eventType.replace(/_/g, ' ')}
                  </span>
                  <div className="flex justify-center">
                    <Switch
                      checked={channels.whatsapp}
                      onCheckedChange={(v) => handleToggleNotification(eventType, 'whatsapp', v)}
                      className="data-[state=checked]:bg-green-600"
                    />
                  </div>
                  <div className="flex justify-center">
                    <Switch
                      checked={channels.push}
                      onCheckedChange={(v) => handleToggleNotification(eventType, 'push', v)}
                      className="data-[state=checked]:bg-kinrel-orange"
                    />
                  </div>
                  <div className="flex justify-center">
                    <Switch
                      checked={channels.inApp}
                      onCheckedChange={(v) => handleToggleNotification(eventType, 'inApp', v)}
                      className="data-[state=checked]:bg-blue-600"
                    />
                  </div>
                  <div className="flex justify-center">
                    <Switch
                      checked={channels.email}
                      onCheckedChange={(v) => handleToggleNotification(eventType, 'email', v)}
                      className="data-[state=checked]:bg-purple-600"
                    />
                  </div>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      </motion.div>

      {/* ── Privacy Section ───────────────────────────────────────── */}
      <motion.div {...sectionAnimation} transition={{ duration: 0.4, delay: 0.3 }}>
        <Card className="border-white/10" style={{ backgroundColor: 'var(--kinrel-card)' }}>
          <CardHeader>
            <CardTitle className="text-kinrel-white flex items-center gap-2">
              <Shield className="h-5 w-5" style={{ color: 'var(--kinrel-orange)' }} />
              Privacy
            </CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-sm" style={{ color: 'var(--kinrel-silver)' }}>
              Your data is protected under the Digital Personal Data Protection (DPDP) Act, 2023. Kinrel follows strict data handling practices:
            </p>
            <ul className="mt-3 space-y-2 text-sm" style={{ color: 'var(--kinrel-silver)' }}>
              <li className="flex items-start gap-2">
                <span style={{ color: 'var(--kinrel-success)' }}>✓</span>
                All sensitive data (Gotra, health info) is family-only by default
              </li>
              <li className="flex items-start gap-2">
                <span style={{ color: 'var(--kinrel-success)' }}>✓</span>
                WhatsApp messaging requires explicit opt-in consent
              </li>
              <li className="flex items-start gap-2">
                <span style={{ color: 'var(--kinrel-success)' }}>✓</span>
                You can export or delete all your data at any time
              </li>
              <li className="flex items-start gap-2">
                <span style={{ color: 'var(--kinrel-success)' }}>✓</span>
                Child data requires parental consent per POCSO guidelines
              </li>
            </ul>
          </CardContent>
        </Card>
      </motion.div>

      {/* ── Danger Zone ───────────────────────────────────────────── */}
      <motion.div {...sectionAnimation} transition={{ duration: 0.4, delay: 0.4 }}>
        <Card className="border-red-500/20" style={{ backgroundColor: 'var(--kinrel-card)' }}>
          <CardHeader>
            <CardTitle className="text-red-400 flex items-center gap-2">
              <Trash2 className="h-5 w-5" />
              Danger Zone
            </CardTitle>
            <CardDescription className="text-kinrel-silver">
              Permanently delete your account and all associated data.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <AlertDialog>
              <AlertDialogTrigger asChild>
                <Button variant="destructive" className="w-full" disabled={deleting}>
                  {deleting ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <Trash2 className="mr-2 h-4 w-4" />}
                  Delete Account
                </Button>
              </AlertDialogTrigger>
              <AlertDialogContent style={{ backgroundColor: 'var(--kinrel-card)', borderColor: 'rgba(255,255,255,0.1)' }}>
                <AlertDialogHeader>
                  <AlertDialogTitle className="text-kinrel-white">Are you absolutely sure?</AlertDialogTitle>
                  <AlertDialogDescription className="text-kinrel-silver">
                    This action cannot be undone. This will permanently delete your account and remove all your data from our servers, including family trees, persons, and relationships you&apos;ve created.
                  </AlertDialogDescription>
                </AlertDialogHeader>
                <AlertDialogFooter>
                  <AlertDialogCancel className="border-white/10 text-kinrel-white">Cancel</AlertDialogCancel>
                  <AlertDialogAction
                    onClick={handleDeleteAccount}
                    className="bg-red-600 hover:bg-red-700 text-white"
                    disabled={deleting}
                  >
                    {deleting ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : null}
                    Delete permanently
                  </AlertDialogAction>
                </AlertDialogFooter>
              </AlertDialogContent>
            </AlertDialog>
          </CardContent>
        </Card>
      </motion.div>
    </div>
  )
}
