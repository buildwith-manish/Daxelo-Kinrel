'use client'

import { useState } from 'react'
import Link from 'next/link'
import { motion } from 'framer-motion'
import {
  Card,
  CardContent,
  CardFooter,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Skeleton } from '@/components/ui/skeleton'
import {
  Plus,
  TreePine,
  Users,
  ArrowRight,
  MapPin,
  Sparkles,
} from 'lucide-react'
import { CreateFamilyForm } from './create-family-form'

interface FamilyData {
  id: string
  name: string
  description: string | null
  primaryLanguage: string
  gotra: string | null
  originVillage: string | null
  role: string
  memberCount: number
  personCount: number
  createdAt: Date
}

interface DashboardContentProps {
  families: FamilyData[]
  user: {
    name: string
    preferredLanguage: string
  }
}

function getGreeting(name: string): string {
  const hour = new Date().getHours()
  let timeGreeting: string

  if (hour < 12) {
    timeGreeting = 'Good morning'
  } else if (hour < 17) {
    timeGreeting = 'Good afternoon'
  } else {
    timeGreeting = 'Good evening'
  }

  return `${timeGreeting}, ${name}`
}

const container = {
  hidden: { opacity: 0 },
  show: {
    opacity: 1,
    transition: { staggerChildren: 0.06 },
  },
}

const item = {
  hidden: { opacity: 0, y: 12 },
  show: { opacity: 1, y: 0, transition: { duration: 0.3 } },
}

export function DashboardContent({ families, user }: DashboardContentProps) {
  const [showCreateForm, setShowCreateForm] = useState(false)

  const totalMembers = families.reduce((sum, f) => sum + f.memberCount, 0)
  const greeting = getGreeting(user.name)

  return (
    <div className="space-y-6 max-w-6xl mx-auto">
      {/* ── Greeting Section ───────────────────────────────────────── */}
      <motion.div
        initial={{ opacity: 0, y: -8 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.4 }}
      >
        <h1 className="text-2xl md:text-3xl font-display font-bold text-kinrel-white">
          {greeting}
        </h1>
        <p className="mt-1 text-sm text-kinrel-silver">
          {families.length} {families.length === 1 ? 'family' : 'families'}{' '}
          &middot; {totalMembers} family{' '}
          {totalMembers === 1 ? 'member' : 'members'}
        </p>
      </motion.div>

      {/* ── Empty State ────────────────────────────────────────────── */}
      {families.length === 0 && !showCreateForm && (
        <motion.div
          initial={{ opacity: 0, scale: 0.95 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ duration: 0.4, delay: 0.1 }}
          className="flex flex-col items-center justify-center py-16 md:py-24"
        >
          <div className="w-24 h-24 rounded-full bg-kinrel-elevated border border-white/10 flex items-center justify-center mb-6">
            <TreePine className="h-10 w-10 text-kinrel-orange" />
          </div>
          <h2 className="text-xl font-display font-bold text-kinrel-white mb-2">
            Your family tree awaits
          </h2>
          <p className="text-sm text-kinrel-silver text-center max-w-sm mb-8">
            Start building your family tree and discover connections across
            generations in 14 Indian languages.
          </p>
          <Button
            onClick={() => setShowCreateForm(true)}
            className="bg-kinrel-orange hover:bg-kinrel-amber text-kinrel-white font-semibold px-6"
          >
            <Sparkles className="h-4 w-4 mr-2" />
            Create First Family
          </Button>
        </motion.div>
      )}

      {/* ── Create Family Form ─────────────────────────────────────── */}
      {showCreateForm && (
        <CreateFamilyForm
          onSuccess={() => {
            setShowCreateForm(false)
            // Refresh the page to show the new family
            window.location.reload()
          }}
          onClose={() => setShowCreateForm(false)}
        />
      )}

      {/* ── Family Cards Grid ──────────────────────────────────────── */}
      {families.length > 0 && (
        <motion.div
          variants={container}
          initial="hidden"
          animate="show"
          className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4"
        >
          {families.map((family) => (
            <motion.div key={family.id} variants={item}>
              <Card className="bg-kinrel-card border-white/10 hover:border-kinrel-orange/30 transition-colors group h-full flex flex-col">
                <CardHeader className="pb-3">
                  <div className="flex items-start justify-between gap-2">
                    <CardTitle className="text-base font-display font-bold text-kinrel-white leading-tight">
                      {family.name}
                    </CardTitle>
                    {family.role === 'admin' && (
                      <Badge
                        variant="outline"
                        className="text-[10px] border-kinrel-orange/40 text-kinrel-orange shrink-0 px-1.5 py-0"
                      >
                        Admin
                      </Badge>
                    )}
                  </div>
                  {family.description && (
                    <p className="text-xs text-kinrel-dim line-clamp-2 mt-1">
                      {family.description}
                    </p>
                  )}
                </CardHeader>

                <CardContent className="pt-0 flex-1">
                  <div className="space-y-1.5">
                    <div className="flex items-center gap-2 text-xs text-kinrel-silver">
                      <Users className="h-3.5 w-3.5 text-kinrel-orange/70" />
                      <span>
                        {family.memberCount}{' '}
                        {family.memberCount === 1 ? 'member' : 'members'} &middot;{' '}
                        {family.personCount}{' '}
                        {family.personCount === 1 ? 'person' : 'persons'}
                      </span>
                    </div>

                    {family.gotra && (
                      <div className="flex items-center gap-2 text-xs text-kinrel-silver">
                        <Sparkles className="h-3.5 w-3.5 text-kinrel-amber/70" />
                        <span>Gotra: {family.gotra}</span>
                      </div>
                    )}

                    {family.originVillage && (
                      <div className="flex items-center gap-2 text-xs text-kinrel-silver">
                        <MapPin className="h-3.5 w-3.5 text-kinrel-success/70" />
                        <span>{family.originVillage}</span>
                      </div>
                    )}
                  </div>
                </CardContent>

                <CardFooter className="pt-0">
                  <Link href={`/families/${family.id}`} className="w-full">
                    <Button
                      variant="outline"
                      size="sm"
                      className="w-full border-white/10 text-kinrel-silver hover:text-kinrel-orange hover:border-kinrel-orange/30 hover:bg-kinrel-orange/5 transition-colors"
                    >
                      Open Tree
                      <ArrowRight className="h-3.5 w-3.5 ml-1" />
                    </Button>
                  </Link>
                </CardFooter>
              </Card>
            </motion.div>
          ))}

          {/* ── Add Family Card ──────────────────────────────────────── */}
          <motion.div variants={item}>
            <button
              onClick={() => setShowCreateForm(true)}
              className="w-full h-full min-h-[200px] rounded-xl border-2 border-dashed border-white/15 hover:border-kinrel-orange/40 bg-transparent hover:bg-kinrel-orange/5 transition-all flex flex-col items-center justify-center gap-3 group"
            >
              <div className="w-12 h-12 rounded-full bg-kinrel-orange/10 flex items-center justify-center group-hover:bg-kinrel-orange/20 transition-colors">
                <Plus className="h-6 w-6 text-kinrel-orange" />
              </div>
              <span className="text-sm font-medium text-kinrel-dim group-hover:text-kinrel-silver transition-colors">
                Create New Family
              </span>
            </button>
          </motion.div>
        </motion.div>
      )}
    </div>
  )
}

// ── Loading Skeleton ──────────────────────────────────────────────────────

export function DashboardSkeleton() {
  return (
    <div className="space-y-6 max-w-6xl mx-auto">
      <div>
        <Skeleton className="h-8 w-64 bg-kinrel-elevated" />
        <Skeleton className="h-4 w-40 bg-kinrel-elevated mt-2" />
      </div>
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <Card key={i} className="bg-kinrel-card border-white/10">
            <CardHeader>
              <Skeleton className="h-5 w-32 bg-kinrel-elevated" />
              <Skeleton className="h-3 w-48 bg-kinrel-elevated mt-2" />
            </CardHeader>
            <CardContent>
              <Skeleton className="h-3 w-24 bg-kinrel-elevated" />
            </CardContent>
            <CardFooter>
              <Skeleton className="h-8 w-full bg-kinrel-elevated" />
            </CardFooter>
          </Card>
        ))}
      </div>
    </div>
  )
}
