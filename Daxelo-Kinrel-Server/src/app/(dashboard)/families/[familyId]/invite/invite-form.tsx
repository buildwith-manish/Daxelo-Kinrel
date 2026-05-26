'use client'

import { useState, useEffect } from 'react'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Button } from '@/components/ui/button'
import { Textarea } from '@/components/ui/textarea'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Separator } from '@/components/ui/separator'
import { Loader2, Send, MessageCircle, Mail, RefreshCw, XCircle, Clock, CheckCircle2, X } from 'lucide-react'
import { useToast } from '@/hooks/use-toast'
import { motion, AnimatePresence } from 'framer-motion'

interface Invitation {
  id: string
  token: string
  recipientName: string | null
  recipientEmail: string | null
  recipientPhone: string | null
  role: string
  channel: string
  status: string
  createdAt: string
  expiresAt: string | null
  deepLink?: string
}

interface InviteFormProps {
  familyId: string
  familyName: string
  inviterId: string
  inviterName: string
}

export function InviteForm({ familyId, familyName, inviterId, inviterName }: InviteFormProps) {
  const { toast } = useToast()
  const [loading, setLoading] = useState(false)
  const [invitations, setInvitations] = useState<Invitation[]>([])
  const [invitationsLoading, setInvitationsLoading] = useState(true)

  const [recipientName, setRecipientName] = useState('')
  const [recipientContact, setRecipientContact] = useState('')
  const [role, setRole] = useState('member')
  const [personalMessage, setPersonalMessage] = useState('')

  // Fetch pending invitations
  useEffect(() => {
    async function fetchInvitations() {
      try {
        const res = await fetch(`/api/invitations?familyId=${familyId}`)
        if (res.ok) {
          const data = await res.json()
          setInvitations(data.invitations || [])
        }
      } catch {
        // Silently fail
      } finally {
        setInvitationsLoading(false)
      }
    }
    fetchInvitations()
  }, [familyId])

  const detectChannel = (): 'email' | 'whatsapp' => {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
    return emailRegex.test(recipientContact) ? 'email' : 'whatsapp'
  }

  const handleSendInvitation = async (forceChannel?: 'email' | 'whatsapp') => {
    if (!recipientName.trim() || !recipientContact.trim()) {
      toast({
        title: 'Missing information',
        description: 'Please provide recipient name and contact.',
        variant: 'destructive',
      })
      return
    }

    setLoading(true)
    const channel = forceChannel || detectChannel()

    try {
      const res = await fetch('/api/invitations', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          familyId,
          inviterId,
          recipientName,
          recipientEmail: channel === 'email' ? recipientContact : undefined,
          recipientPhone: channel === 'whatsapp' ? recipientContact : undefined,
          role,
          channel,
        }),
      })

      const data = await res.json()

      if (!res.ok) {
        toast({
          title: 'Error',
          description: data.error || 'Failed to send invitation',
          variant: 'destructive',
        })
        return
      }

      toast({
        title: 'Invitation sent!',
        description: `Invitation sent to ${recipientName} via ${channel}.`,
      })

      // Add to list
      const invitation = data.invitation || data
      setInvitations((prev) => [invitation, ...prev])

      // Open WhatsApp deep link if WhatsApp channel
      if (channel === 'whatsapp' && invitation.deepLink) {
        const phone = recipientContact.replace(/[^0-9]/g, '')
        const message = personalMessage || `${inviterName} has invited you to join the "${familyName}" family on Kinrel! Click here: ${invitation.deepLink}`
        const waUrl = `https://wa.me/${phone}?text=${encodeURIComponent(message)}`
        window.open(waUrl, '_blank')
      }

      // Reset form
      setRecipientName('')
      setRecipientContact('')
      setPersonalMessage('')
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

  const handleResend = async (invitation: Invitation) => {
    try {
      const res = await fetch('/api/invitations', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          familyId,
          inviterId,
          recipientName: invitation.recipientName || '',
          recipientEmail: invitation.recipientEmail || undefined,
          recipientPhone: invitation.recipientPhone || undefined,
          role: invitation.role,
          channel: invitation.channel,
        }),
      })

      if (res.ok) {
        toast({ title: 'Invitation resent!' })
      } else {
        toast({ title: 'Error resending', variant: 'destructive' })
      }
    } catch {
      toast({ title: 'Network error', variant: 'destructive' })
    }
  }

  const handleCancel = async (invitationId: string) => {
    try {
      const res = await fetch(`/api/invitations?id=${invitationId}`, {
        method: 'DELETE',
      })

      if (res.ok) {
        setInvitations((prev) => prev.filter((i) => i.id !== invitationId))
        toast({ title: 'Invitation cancelled' })
      } else {
        toast({ title: 'Error cancelling', variant: 'destructive' })
      }
    } catch {
      toast({ title: 'Network error', variant: 'destructive' })
    }
  }

  const statusIcon = (status: string) => {
    switch (status) {
      case 'pending':
        return <Clock className="h-3.5 w-3.5" style={{ color: 'var(--kinrel-warning)' }} />
      case 'accepted':
        return <CheckCircle2 className="h-3.5 w-3.5" style={{ color: 'var(--kinrel-success)' }} />
      case 'expired':
        return <X className="h-3.5 w-3.5" style={{ color: 'var(--kinrel-dim)' }} />
      case 'cancelled':
        return <XCircle className="h-3.5 w-3.5" style={{ color: 'var(--kinrel-error)' }} />
      default:
        return null
    }
  }

  const statusBadgeVariant = (status: string) => {
    switch (status) {
      case 'pending':
        return 'outline'
      case 'accepted':
        return 'default'
      default:
        return 'secondary'
    }
  }

  return (
    <div className="max-w-2xl mx-auto p-4 sm:p-6 space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-kinrel-white" style={{ fontFamily: 'var(--kinrel-font-display)' }}>
          Invite to {familyName}
        </h1>
        <p className="text-sm mt-1" style={{ color: 'var(--kinrel-silver)' }}>
          Send invitations to add family members.
        </p>
      </div>

      {/* Invite Form */}
      <Card className="border-white/10" style={{ backgroundColor: 'var(--kinrel-card)' }}>
        <CardHeader>
          <CardTitle className="text-kinrel-white flex items-center gap-2">
            <Send className="h-5 w-5" style={{ color: 'var(--kinrel-orange)' }} />
            New Invitation
          </CardTitle>
          <CardDescription className="text-kinrel-silver">
            Enter recipient details and choose how to send the invitation.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {/* Recipient Name */}
          <div className="space-y-2">
            <Label htmlFor="invite-name" style={{ color: 'var(--kinrel-silver)' }}>
              Recipient Name
            </Label>
            <Input
              id="invite-name"
              placeholder="Full name"
              value={recipientName}
              onChange={(e) => setRecipientName(e.target.value)}
              className="border-white/10 bg-kinrel-elevated text-kinrel-white placeholder:text-kinrel-dim"
            />
          </div>

          {/* Contact */}
          <div className="space-y-2">
            <Label htmlFor="invite-contact" style={{ color: 'var(--kinrel-silver)' }}>
              Phone or Email
            </Label>
            <Input
              id="invite-contact"
              placeholder="Phone number or email address"
              value={recipientContact}
              onChange={(e) => setRecipientContact(e.target.value)}
              className="border-white/10 bg-kinrel-elevated text-kinrel-white placeholder:text-kinrel-dim"
            />
          </div>

          {/* Role */}
          <div className="space-y-2">
            <Label style={{ color: 'var(--kinrel-silver)' }}>Role</Label>
            <Select value={role} onValueChange={setRole}>
              <SelectTrigger className="border-white/10 bg-kinrel-elevated text-kinrel-white">
                <SelectValue />
              </SelectTrigger>
              <SelectContent style={{ backgroundColor: 'var(--kinrel-card)' }}>
                <SelectItem value="admin">Admin</SelectItem>
                <SelectItem value="editor">Editor</SelectItem>
                <SelectItem value="member">Member</SelectItem>
                <SelectItem value="viewer">Viewer</SelectItem>
              </SelectContent>
            </Select>
          </div>

          {/* Personal Message */}
          <div className="space-y-2">
            <Label htmlFor="invite-message" style={{ color: 'var(--kinrel-silver)' }}>
              Personal Message (optional)
            </Label>
            <Textarea
              id="invite-message"
              placeholder="Add a personal note to your invitation..."
              value={personalMessage}
              onChange={(e) => setPersonalMessage(e.target.value)}
              className="border-white/10 bg-kinrel-elevated text-kinrel-white placeholder:text-kinrel-dim min-h-[80px]"
            />
          </div>

          {/* Send Buttons */}
          <div className="flex gap-3">
            <Button
              onClick={() => handleSendInvitation('whatsapp')}
              disabled={loading}
              className="flex-1"
              style={{ backgroundColor: '#25D366', color: '#fff' }}
            >
              {loading ? (
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
              ) : (
                <MessageCircle className="mr-2 h-4 w-4" />
              )}
              Send via WhatsApp
            </Button>
            <Button
              onClick={() => handleSendInvitation('email')}
              disabled={loading}
              variant="outline"
              className="flex-1 border-white/10 text-kinrel-white hover:bg-kinrel-elevated"
            >
              {loading ? (
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
              ) : (
                <Mail className="mr-2 h-4 w-4" />
              )}
              Send via Email
            </Button>
          </div>
        </CardContent>
      </Card>

      {/* Pending Invitations */}
      <Card className="border-white/10" style={{ backgroundColor: 'var(--kinrel-card)' }}>
        <CardHeader>
          <CardTitle className="text-kinrel-white flex items-center gap-2">
            <Clock className="h-5 w-5" style={{ color: 'var(--kinrel-warning)' }} />
            Invitations
          </CardTitle>
        </CardHeader>
        <CardContent>
          {invitationsLoading ? (
            <div className="flex items-center justify-center py-8">
              <Loader2 className="h-6 w-6 animate-spin" style={{ color: 'var(--kinrel-orange)' }} />
            </div>
          ) : invitations.length === 0 ? (
            <p className="text-center py-8 text-sm" style={{ color: 'var(--kinrel-dim)' }}>
              No invitations yet. Send your first invitation above.
            </p>
          ) : (
            <div className="space-y-3 max-h-96 overflow-y-auto">
              <AnimatePresence>
                {invitations.map((inv) => (
                  <motion.div
                    key={inv.id}
                    initial={{ opacity: 0, x: -10 }}
                    animate={{ opacity: 1, x: 0 }}
                    exit={{ opacity: 0, x: 10 }}
                    className="flex items-center justify-between gap-3 p-3 rounded-lg border border-white/5"
                    style={{ backgroundColor: 'var(--kinrel-elevated)' }}
                  >
                    <div className="flex items-center gap-3 min-w-0">
                      {statusIcon(inv.status)}
                      <div className="min-w-0">
                        <p className="text-sm font-medium text-kinrel-white truncate">
                          {inv.recipientName || 'Unknown'}
                        </p>
                        <p className="text-xs truncate" style={{ color: 'var(--kinrel-dim)' }}>
                          {inv.recipientEmail || inv.recipientPhone || 'No contact'}
                        </p>
                      </div>
                    </div>
                    <div className="flex items-center gap-2 shrink-0">
                      <Badge variant={statusBadgeVariant(inv.status)} className="text-[10px]">
                        {inv.status}
                      </Badge>
                      <Badge variant="outline" className="text-[10px] border-white/10" style={{ color: 'var(--kinrel-dim)' }}>
                        {inv.role}
                      </Badge>
                      {inv.status === 'pending' && (
                        <>
                          <Button
                            size="sm"
                            variant="ghost"
                            className="h-7 w-7 p-0"
                            onClick={() => handleResend(inv)}
                          >
                            <RefreshCw className="h-3.5 w-3.5" style={{ color: 'var(--kinrel-silver)' }} />
                          </Button>
                          <Button
                            size="sm"
                            variant="ghost"
                            className="h-7 w-7 p-0"
                            onClick={() => handleCancel(inv.id)}
                          >
                            <XCircle className="h-3.5 w-3.5" style={{ color: 'var(--kinrel-error)' }} />
                          </Button>
                        </>
                      )}
                    </div>
                  </motion.div>
                ))}
              </AnimatePresence>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
