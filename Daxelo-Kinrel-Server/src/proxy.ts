import { NextResponse } from 'next/server'
import type { NextRequest } from 'next/server'
import { getToken } from 'next-auth/jwt'

/**
 * Kinrel Proxy — Next.js 16 replacement for deprecated middleware.ts
 *
 * Handles auth protection for dashboard routes and redirects
 * logged-in users away from auth pages (sign-in, sign-up).
 *
 * Uses next-auth/jwt getToken() for session verification,
 * compatible with the Node.js runtime that proxy runs on.
 */
export async function proxy(req: NextRequest) {
  const token = await getToken({ req, secret: process.env.NEXTAUTH_SECRET ?? 'kinrel-dev-secret-change-in-production' })
  const pathname = req.nextUrl.pathname
  const isLoggedIn = !!token

  // Redirect logged-in users away from auth pages
  if (
    isLoggedIn &&
    (pathname.startsWith('/sign-in') || pathname.startsWith('/sign-up'))
  ) {
    return NextResponse.redirect(new URL('/dashboard', req.url))
  }

  // Protect dashboard routes — require login
  const isOnDashboard =
    pathname.startsWith('/dashboard') ||
    pathname.startsWith('/families') ||
    pathname.startsWith('/settings')

  if (isOnDashboard && !isLoggedIn) {
    const signInUrl = new URL('/sign-in', req.url)
    signInUrl.searchParams.set('callbackUrl', pathname)
    return NextResponse.redirect(signInUrl)
  }

  return NextResponse.next()
}

export const config = {
  matcher: [
    '/((?!api|_next/static|_next/image|favicon.ico|brand|site.webmanifest).*)',
  ],
}
