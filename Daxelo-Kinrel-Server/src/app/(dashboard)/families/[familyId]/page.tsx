import { getServerSession } from 'next-auth'
import { authOptions } from '@/lib/auth'
import { db } from '@/lib/db'
import { notFound, redirect } from 'next/navigation'
import { FamilyTreeClient } from './family-tree-client'

export const dynamic = 'force-dynamic'

export default async function FamilyTreePage({
  params,
}: {
  params: Promise<{ familyId: string }>
}) {
  const session = await getServerSession(authOptions)

  if (!session?.user?.id) {
    redirect('/sign-in')
  }

  const { familyId } = await params

  // Verify membership
  const membership = await db.familyMember.findUnique({
    where: {
      familyId_userId: {
        familyId,
        userId: session.user.id,
      },
    },
  })

  if (!membership) {
    notFound()
  }

  // Fetch family with all non-deleted persons
  const family = await db.family.findUnique({
    where: { id: familyId },
    include: {
      persons: {
        where: { deletedAt: null },
        orderBy: [{ dateOfBirth: 'asc' }, { name: 'asc' }],
      },
    },
  })

  if (!family) {
    notFound()
  }

  // Fetch all relationships for this family
  const relationships = await db.relationship.findMany({
    where: { familyId },
    orderBy: { createdAt: 'desc' },
  })

  // Serialize for client (convert Date objects to strings)
  const serializedFamily = {
    id: family.id,
    name: family.name,
    description: family.description,
    primaryLanguage: family.primaryLanguage,
    gotra: family.gotra,
    originVillage: family.originVillage,
  }

  const serializedPersons = family.persons.map((p) => ({
    id: p.id,
    familyId: p.familyId,
    name: p.name,
    relationship: p.relationship,
    dateOfBirth: p.dateOfBirth ? p.dateOfBirth.toISOString() : null,
    gotra: p.gotra,
    occupation: p.occupation,
    city: p.city,
    isDeceased: p.isDeceased,
    privacyLevel: p.privacyLevel,
    deletedAt: p.deletedAt ? p.deletedAt.toISOString() : null,
  }))

  const serializedRelationships = relationships.map((r) => ({
    id: r.id,
    familyId: r.familyId,
    fromPersonId: r.fromPersonId,
    toPersonId: r.toPersonId,
    type: r.type,
    direction: r.direction,
  }))

  return (
    <FamilyTreeClient
      family={serializedFamily}
      persons={serializedPersons}
      relationships={serializedRelationships}
    />
  )
}
