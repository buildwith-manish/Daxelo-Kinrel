/**
 * KINREL — Authentication Configuration
 *
 * NextAuth v4 with Credentials provider + Prisma User model.
 * JWT strategy — no database sessions.
 */

import type { NextAuthOptions } from 'next-auth'
import CredentialsProvider from 'next-auth/providers/credentials'
import { db } from '@/lib/db'
import CryptoJS from 'crypto-js'
import { z } from 'zod'

export const authOptions: NextAuthOptions = {
  session: {
    strategy: 'jwt',
    maxAge: 30 * 24 * 60 * 60, // 30 days
  },
  pages: {
    signIn: '/sign-in',
    error: '/sign-in',
  },
  providers: [
    CredentialsProvider({
      name: 'credentials',
      credentials: {
        email: { label: 'Email', type: 'email' },
        password: { label: 'Password', type: 'password' },
      },
      async authorize(credentials) {
        const parsed = z
          .object({
            email: z.string().email(),
            password: z.string().min(8),
          })
          .safeParse(credentials)

        if (!parsed.success) return null

        const user = await db.user.findUnique({
          where: { email: parsed.data.email },
          select: {
            id: true,
            email: true,
            name: true,
            role: true,
            passwordHash: true,
            preferredLanguage: true,
          },
        })

        if (!user || !user.passwordHash) return null

        const hash = CryptoJS.SHA256(parsed.data.password).toString()
        if (hash !== user.passwordHash) return null

        return {
          id: user.id,
          email: user.email,
          name: user.name ?? 'User',
          role: user.role,
          preferredLanguage: user.preferredLanguage,
        }
      },
    }),
  ],
  callbacks: {
    async jwt({ token, user }) {
      if (user) {
        token.id = user.id
        token.role = (user as Record<string, unknown>).role as string
        token.preferredLanguage = (user as Record<string, unknown>).preferredLanguage as string
      }
      return token
    },
    async session({ session, token }) {
      if (token && session.user) {
        session.user.id = token.id as string
        ;(session.user as Record<string, unknown>).role = token.role
        ;(session.user as Record<string, unknown>).preferredLanguage = token.preferredLanguage
      }
      return session
    },
  },
  secret: process.env.NEXTAUTH_SECRET ?? 'kinrel-dev-secret-change-in-production',
  debug: process.env.NODE_ENV === 'development',
}
