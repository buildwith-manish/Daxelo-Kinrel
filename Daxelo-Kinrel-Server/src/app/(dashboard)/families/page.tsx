'use client'

import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { useSession } from 'next-auth/react'
import { Loader2, Users, Plus } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'

interface Family {
  id: string
  name: string
  description?: string | null
  primaryLanguage: string
  memberCount: number
  personCount: number
  role: string
  createdAt: string
}

export default function FamiliesPage() {
  const { data: session, status } = useSession()
  const router = useRouter()
  const [families, setFamilies] = useState<Family[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (status === 'unauthenticated') {
      router.push('/sign-in')
      return
    }

    async function fetchFamilies() {
      try {
        const res = await fetch('/api/families')
        if (res.ok) {
          const data = await res.json()
          setFamilies(data.families || [])
        }
      } catch {
        // Silently fail
      } finally {
        setLoading(false)
      }
    }

    if (session) fetchFamilies()
  }, [session, status, router])

  if (loading || status === 'loading') {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <Loader2 className="h-8 w-8 animate-spin" style={{ color: 'var(--kinrel-orange)' }} />
      </div>
    )
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold" style={{ color: 'var(--kinrel-white)' }}>
            My Families
          </h1>
          <p className="text-sm mt-1" style={{ color: 'var(--kinrel-silver)' }}>
            Manage your family trees and relationships
          </p>
        </div>
        <Button
          onClick={() => router.push('/dashboard')}
          style={{ background: 'var(--kinrel-grad-ignite)', color: 'var(--kinrel-white)' }}
        >
          <Plus className="mr-2 h-4 w-4" />
          New Family
        </Button>
      </div>

      {families.length === 0 ? (
        <Card style={{ backgroundColor: 'var(--kinrel-card)', borderColor: 'rgba(255,255,255,0.1)' }}>
          <CardContent className="flex flex-col items-center justify-center py-16">
            <Users className="h-12 w-12 mb-4" style={{ color: 'var(--kinrel-dim)' }} />
            <h3 className="text-lg font-semibold" style={{ color: 'var(--kinrel-white)' }}>
              No families yet
            </h3>
            <p className="text-sm mt-1" style={{ color: 'var(--kinrel-silver)' }}>
              Create your first family tree to get started.
            </p>
            <Button
              className="mt-4"
              onClick={() => router.push('/dashboard')}
              style={{ background: 'var(--kinrel-grad-ignite)', color: 'var(--kinrel-white)' }}
            >
              <Plus className="mr-2 h-4 w-4" />
              Create Family
            </Button>
          </CardContent>
        </Card>
      ) : (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {families.map((family) => (
            <Card
              key={family.id}
              className="cursor-pointer transition-colors hover:border-kinrel-orange/30"
              style={{ backgroundColor: 'var(--kinrel-card)', borderColor: 'rgba(255,255,255,0.1)' }}
              onClick={() => router.push(`/families/${family.id}`)}
            >
              <CardHeader className="pb-2">
                <CardTitle className="text-base" style={{ color: 'var(--kinrel-white)' }}>
                  {family.name}
                </CardTitle>
              </CardHeader>
              <CardContent>
                <p className="text-sm" style={{ color: 'var(--kinrel-silver)' }}>
                  {family.description || 'No description'}
                </p>
                <div className="flex items-center gap-4 mt-3 text-xs" style={{ color: 'var(--kinrel-dim)' }}>
                  <span>{family.memberCount} member{family.memberCount !== 1 ? 's' : ''}</span>
                  <span>{family.personCount} person{family.personCount !== 1 ? 's' : ''}</span>
                  <span className="capitalize">{family.role}</span>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  )
}
