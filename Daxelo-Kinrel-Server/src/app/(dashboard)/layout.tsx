import { getServerSession } from 'next-auth'
import { authOptions } from '@/lib/auth'
import { redirect } from 'next/navigation'
import { DashboardShell } from './dashboard-shell'

export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode
}) {
  const session = await getServerSession(authOptions)

  if (!session?.user?.id) {
    redirect('/sign-in')
  }

  const userData = {
    id: session.user.id,
    name: session.user.name ?? 'User',
    email: session.user.email ?? '',
    preferredLanguage: session.user.preferredLanguage ?? 'en',
  }

  return <DashboardShell user={userData}>{children}</DashboardShell>
}
