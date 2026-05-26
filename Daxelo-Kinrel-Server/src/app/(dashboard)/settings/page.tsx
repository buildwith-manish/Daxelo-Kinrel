// DAXELO KINREL — Pack 09: Settings Page (Server Component)
// Fetches user profile + notification preferences, passes to client form

import { getServerSession } from 'next-auth'
import { redirect } from 'next/navigation'
import { authOptions } from '@/lib/auth'
import { db } from '@/lib/db'
import { SettingsContent } from './settings-content'

interface NotificationPref {
  id: string
  eventType: string
  whatsapp: boolean
  push: boolean
  inApp: boolean
  email: boolean
}

export default async function SettingsPage() {
  const session = await getServerSession(authOptions)
  if (!session?.user?.id) {
    redirect('/sign-in')
  }

  // Fetch user profile
  const user = await db.user.findUnique({
    where: { id: session.user.id },
    select: {
      id: true,
      email: true,
      name: true,
      phone: true,
      preferredLanguage: true,
      role: true,
      createdAt: true,
    },
  })

  if (!user) {
    redirect('/sign-in')
  }

  // Fetch notification preferences
  const notificationPrefs = await db.notificationPreference.findMany({
    where: { userId: session.user.id },
    select: {
      id: true,
      eventType: true,
      whatsapp: true,
      push: true,
      inApp: true,
      email: true,
    },
  })

  return (
    <SettingsContent
      user={user}
      notificationPrefs={notificationPrefs}
    />
  )
}
