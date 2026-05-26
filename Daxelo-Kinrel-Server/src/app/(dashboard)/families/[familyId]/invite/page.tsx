// DAXELO KINREL — Pack 08: Invite Page (Server Component)
// Verifies membership, fetches family, passes to client form

import { getServerSession } from 'next-auth'
import { redirect } from 'next/navigation'
import { authOptions } from '@/lib/auth'
import { db } from '@/lib/db'
import { InviteForm } from './invite-form'

interface InvitePageProps {
  params: Promise<{ familyId: string }>
}

export default async function InvitePage({ params }: InvitePageProps) {
  const session = await getServerSession(authOptions)
  if (!session?.user?.id) {
    redirect('/sign-in')
  }

  const { familyId } = await params

  // Verify membership
  const membership = await db.familyMember.findUnique({
    where: { familyId_userId: { familyId, userId: session.user.id } },
  })

  if (!membership) {
    redirect('/')
  }

  // Only admin/editor can invite
  if (!['admin', 'editor'].includes(membership.role)) {
    redirect('/')
  }

  // Fetch family info
  const family = await db.family.findUnique({
    where: { id: familyId },
    select: {
      id: true,
      name: true,
      primaryLanguage: true,
    },
  })

  if (!family) {
    redirect('/')
  }

  return (
    <InviteForm
      familyId={familyId}
      familyName={family.name}
      inviterId={session.user.id}
      inviterName={session.user.name || 'Family Member'}
    />
  )
}
