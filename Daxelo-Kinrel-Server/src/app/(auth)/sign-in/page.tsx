'use client'

import { useState } from 'react'
import { signIn } from 'next-auth/react'
import { useRouter } from 'next/navigation'
import KinrelLogo from '@/components/brand/KinrelLogo'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardHeader } from '@/components/ui/card'
import Link from 'next/link'
import { Loader2 } from 'lucide-react'

export default function SignInPage() {
  const router = useRouter()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setError('')
    setLoading(true)

    const result = await signIn('credentials', {
      email,
      password,
      redirect: false,
    })

    setLoading(false)

    if (result?.error) {
      setError('Invalid email or password')
      return
    }

    router.push('/dashboard')
    router.refresh()
  }

  return (
    <Card className="w-full max-w-md bg-kinrel-card border-white/10">
      <CardHeader className="flex flex-col items-center gap-4 pb-2">
        <KinrelLogo size="md" layout="vertical" />
        <h1 className="text-xl font-display font-semibold text-kinrel-white">
          Sign in to Kinrel
        </h1>
      </CardHeader>
      <CardContent>
        <form onSubmit={handleSubmit} className="space-y-4">
          {error && (
            <div className="rounded-lg bg-destructive/10 border border-destructive/30 px-4 py-3 text-sm text-destructive">
              {error}
            </div>
          )}
          <div className="space-y-2">
            <Label htmlFor="email" className="text-kinrel-silver">Email</Label>
            <Input
              id="email"
              type="email"
              placeholder="you@example.com"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              autoComplete="email"
              className="bg-kinrel-elevated border-white/10 text-kinrel-white placeholder:text-kinrel-dim"
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="password" className="text-kinrel-silver">Password</Label>
            <Input
              id="password"
              type="password"
              placeholder="••••••••"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              minLength={8}
              autoComplete="current-password"
              className="bg-kinrel-elevated border-white/10 text-kinrel-white placeholder:text-kinrel-dim"
            />
          </div>
          <Button
            type="submit"
            disabled={loading}
            className="w-full bg-kinrel-orange hover:bg-kinrel-amber text-kinrel-white font-semibold"
          >
            {loading ? (
              <Loader2 className="mr-2 h-4 w-4 animate-spin" />
            ) : null}
            Sign In
          </Button>
        </form>
        <p className="mt-6 text-center text-sm text-kinrel-silver">
          Don&apos;t have an account?{' '}
          <Link
            href="/sign-up"
            className="text-kinrel-orange hover:text-kinrel-amber font-medium underline underline-offset-4"
          >
            Sign up
          </Link>
        </p>
      </CardContent>
    </Card>
  )
}
