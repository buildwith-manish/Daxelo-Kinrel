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

export default function SignUpPage() {
  const router = useRouter()
  const [name, setName] = useState('')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setError('')

    if (password !== confirmPassword) {
      setError('Passwords do not match')
      return
    }

    if (password.length < 8) {
      setError('Password must be at least 8 characters')
      return
    }

    setLoading(true)

    try {
      const res = await fetch('/api/auth/register', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name, email, password }),
      })

      const data = await res.json()

      if (!res.ok) {
        setError(data.error || 'Registration failed')
        setLoading(false)
        return
      }

      // Auto sign-in after successful registration
      const result = await signIn('credentials', {
        email,
        password,
        redirect: false,
      })

      if (result?.ok) {
        router.push('/dashboard')
        router.refresh()
      } else {
        router.push('/sign-in')
      }
    } catch {
      setError('Something went wrong. Please try again.')
    } finally {
      setLoading(false)
    }
  }

  return (
    <Card className="w-full max-w-md bg-kinrel-card border-white/10">
      <CardHeader className="flex flex-col items-center gap-4 pb-2">
        <KinrelLogo size="md" layout="vertical" />
        <h1 className="text-xl font-display font-semibold text-kinrel-white">
          Create your account
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
            <Label htmlFor="name" className="text-kinrel-silver">Full Name</Label>
            <Input
              id="name"
              type="text"
              placeholder="Ramesh Sharma"
              value={name}
              onChange={(e) => setName(e.target.value)}
              required
              minLength={2}
              autoComplete="name"
              className="bg-kinrel-elevated border-white/10 text-kinrel-white placeholder:text-kinrel-dim"
            />
          </div>
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
              autoComplete="new-password"
              className="bg-kinrel-elevated border-white/10 text-kinrel-white placeholder:text-kinrel-dim"
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="confirm-password" className="text-kinrel-silver">Confirm Password</Label>
            <Input
              id="confirm-password"
              type="password"
              placeholder="••••••••"
              value={confirmPassword}
              onChange={(e) => setConfirmPassword(e.target.value)}
              required
              minLength={8}
              autoComplete="new-password"
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
            Create Account
          </Button>
        </form>
        <p className="mt-6 text-center text-sm text-kinrel-silver">
          Already have an account?{' '}
          <Link
            href="/sign-in"
            className="text-kinrel-orange hover:text-kinrel-amber font-medium underline underline-offset-4"
          >
            Sign in
          </Link>
        </p>
      </CardContent>
    </Card>
  )
}
