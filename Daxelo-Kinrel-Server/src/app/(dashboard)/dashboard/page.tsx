import { getServerSession } from 'next-auth'
import { authOptions } from '@/lib/auth'
import { db } from '@/lib/db'
import { redirect } from 'next/navigation'
import { DashboardContent } from './dashboard-content'

export default async function DashboardPage() {
  const session = await getServerSession(authOptions)

  if (!session?.user?.id) {
    redirect('/sign-in')
  }

  const memberships = await db.familyMember.findMany({
    where: { userId: session.user.id },
    include: {
      family: {
        include: {
          _count: {
            select: { members: true, persons: true },
          },
        },
      },
    },
    orderBy: { joinedAt: 'desc' },
  })

  const families = memberships.map((m) => ({
    id: m.family.id,
    name: m.family.name,
    description: m.family.description,
    primaryLanguage: m.family.primaryLanguage,
    gotra: m.family.gotra,
    originVillage: m.family.originVillage,
    role: m.role,
    memberCount: m.family._count.members,
    personCount: m.family._count.persons,
    createdAt: m.family.createdAt,
  }))

  const userData = {
    name: session.user.name ?? 'User',
    preferredLanguage: session.user.preferredLanguage ?? 'en',
  }

  return <DashboardContent families={families} user={userData} />
}
