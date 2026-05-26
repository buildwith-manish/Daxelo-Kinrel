'use client'

import { useState } from 'react'
import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { signOut } from 'next-auth/react'
import { motion, AnimatePresence } from 'framer-motion'
import KinrelLogo from '@/components/brand/KinrelLogo'
import { Avatar, AvatarFallback } from '@/components/ui/avatar'
import { Button } from '@/components/ui/button'
import { Separator } from '@/components/ui/separator'
import {
  LayoutDashboard,
  Users,
  Settings,
  LogOut,
  Menu,
  X,
  Home,
  UserPlus,
  User,
} from 'lucide-react'

interface DashboardShellProps {
  children: React.ReactNode
  user: {
    id: string
    name: string
    email: string
    preferredLanguage: string
  }
}

const SIDEBAR_NAV = [
  { href: '/dashboard', label: 'Dashboard', icon: LayoutDashboard },
  { href: '/families', label: 'My Families', icon: Users },
  { href: '/settings', label: 'Settings', icon: Settings },
]

const BOTTOM_TAB_NAV = [
  { href: '/dashboard', label: 'Home', icon: Home },
  { href: '/families', label: 'Families', icon: Users },
  { href: '/families?invite=1', label: 'Invite', icon: UserPlus },
  { href: '/settings', label: 'Profile', icon: User },
]

export function DashboardShell({ children, user }: DashboardShellProps) {
  const pathname = usePathname()
  const [sidebarOpen, setSidebarOpen] = useState(false)

  const userInitial = user.name?.charAt(0)?.toUpperCase() || 'U'

  function isActive(href: string) {
    if (href === '/dashboard') return pathname === '/dashboard'
    return pathname.startsWith(href.split('?')[0])
  }

  return (
    <div className="min-h-dvh flex bg-kinrel-bg">
      {/* ── Desktop Sidebar (hidden on mobile) ──────────────────────── */}
      <aside className="hidden md:flex md:w-60 md:flex-col md:fixed md:inset-y-0 bg-kinrel-card border-r border-white/10">
        {/* Logo */}
        <div className="flex items-center gap-3 px-5 h-16 shrink-0">
          <KinrelLogo size="sm" layout="horizontal" palette="orange" />
        </div>

        <Separator className="bg-white/10" />

        {/* Navigation */}
        <nav className="flex-1 px-3 py-4 space-y-1">
          {SIDEBAR_NAV.map((item) => {
            const Icon = item.icon
            const active = isActive(item.href)
            return (
              <Link
                key={item.href}
                href={item.href}
                className={`flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-colors ${
                  active
                    ? 'bg-kinrel-orange/10 text-kinrel-orange'
                    : 'text-kinrel-silver hover:bg-white/5 hover:text-kinrel-white'
                }`}
              >
                <Icon className="h-5 w-5 shrink-0" />
                {item.label}
              </Link>
            )
          })}
        </nav>

        <Separator className="bg-white/10" />

        {/* User section */}
        <div className="p-4 space-y-2">
          <div className="flex items-center gap-3 px-2">
            <Avatar className="h-8 w-8 bg-kinrel-orange/20">
              <AvatarFallback className="bg-kinrel-orange/20 text-kinrel-orange text-sm font-semibold">
                {userInitial}
              </AvatarFallback>
            </Avatar>
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium text-kinrel-white truncate">
                {user.name}
              </p>
              <p className="text-xs text-kinrel-dim truncate">{user.email}</p>
            </div>
          </div>
          <Button
            variant="ghost"
            size="sm"
            onClick={() => signOut({ callbackUrl: '/sign-in' })}
            className="w-full justify-start text-kinrel-silver hover:text-kinrel-white hover:bg-white/5"
          >
            <LogOut className="h-4 w-4 mr-2" />
            Sign out
          </Button>
        </div>
      </aside>

      {/* ── Mobile Sidebar Overlay ──────────────────────────────────── */}
      <AnimatePresence>
        {sidebarOpen && (
          <>
            <motion.div
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={{ duration: 0.2 }}
              className="fixed inset-0 z-40 bg-black/60 md:hidden"
              onClick={() => setSidebarOpen(false)}
            />
            <motion.aside
              initial={{ x: -240 }}
              animate={{ x: 0 }}
              exit={{ x: -240 }}
              transition={{ type: 'spring', damping: 25, stiffness: 250 }}
              className="fixed inset-y-0 left-0 z-50 w-60 bg-kinrel-card border-r border-white/10 md:hidden"
            >
              <div className="flex items-center justify-between px-5 h-16">
                <KinrelLogo size="sm" layout="horizontal" palette="orange" />
                <button
                  onClick={() => setSidebarOpen(false)}
                  className="p-1 text-kinrel-silver hover:text-kinrel-white"
                  aria-label="Close menu"
                >
                  <X className="h-5 w-5" />
                </button>
              </div>

              <Separator className="bg-white/10" />

              <nav className="flex-1 px-3 py-4 space-y-1">
                {SIDEBAR_NAV.map((item) => {
                  const Icon = item.icon
                  const active = isActive(item.href)
                  return (
                    <Link
                      key={item.href}
                      href={item.href}
                      onClick={() => setSidebarOpen(false)}
                      className={`flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-colors ${
                        active
                          ? 'bg-kinrel-orange/10 text-kinrel-orange'
                          : 'text-kinrel-silver hover:bg-white/5 hover:text-kinrel-white'
                      }`}
                    >
                      <Icon className="h-5 w-5 shrink-0" />
                      {item.label}
                    </Link>
                  )
                })}
              </nav>

              <Separator className="bg-white/10" />

              <div className="p-4 space-y-2">
                <div className="flex items-center gap-3 px-2">
                  <Avatar className="h-8 w-8 bg-kinrel-orange/20">
                    <AvatarFallback className="bg-kinrel-orange/20 text-kinrel-orange text-sm font-semibold">
                      {userInitial}
                    </AvatarFallback>
                  </Avatar>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium text-kinrel-white truncate">
                      {user.name}
                    </p>
                    <p className="text-xs text-kinrel-dim truncate">
                      {user.email}
                    </p>
                  </div>
                </div>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => signOut({ callbackUrl: '/sign-in' })}
                  className="w-full justify-start text-kinrel-silver hover:text-kinrel-white hover:bg-white/5"
                >
                  <LogOut className="h-4 w-4 mr-2" />
                  Sign out
                </Button>
              </div>
            </motion.aside>
          </>
        )}
      </AnimatePresence>

      {/* ── Main Content Area ───────────────────────────────────────── */}
      <div className="flex-1 md:ml-60 flex flex-col min-h-dvh">
        {/* Mobile Header */}
        <header className="md:hidden flex items-center justify-between px-4 h-14 bg-kinrel-card border-b border-white/10 shrink-0">
          <button
            onClick={() => setSidebarOpen(true)}
            className="p-2 -ml-2 text-kinrel-silver hover:text-kinrel-white"
            aria-label="Open menu"
          >
            <Menu className="h-5 w-5" />
          </button>
          <KinrelLogo size="xs" layout="horizontal" palette="orange" />
          <Avatar className="h-7 w-7 bg-kinrel-orange/20">
            <AvatarFallback className="bg-kinrel-orange/20 text-kinrel-orange text-xs font-semibold">
              {userInitial}
            </AvatarFallback>
          </Avatar>
        </header>

        {/* Page content */}
        <main className="flex-1 p-4 md:p-6 lg:p-8 pb-20 md:pb-8">
          {children}
        </main>
      </div>

      {/* ── Mobile Bottom Tab Bar ───────────────────────────────────── */}
      <nav className="fixed bottom-0 inset-x-0 z-30 md:hidden bg-kinrel-card border-t border-white/10 safe-area-pb">
        <div className="flex items-center justify-around h-14">
          {BOTTOM_TAB_NAV.map((item) => {
            const Icon = item.icon
            const active = isActive(item.href)
            return (
              <Link
                key={item.href}
                href={item.href}
                className={`flex flex-col items-center justify-center gap-0.5 px-3 py-1.5 rounded-lg transition-colors min-w-[56px] ${
                  active
                    ? 'text-kinrel-orange'
                    : 'text-kinrel-dim hover:text-kinrel-silver'
                }`}
              >
                <Icon className="h-5 w-5" />
                <span className="text-[10px] font-medium leading-none">
                  {item.label}
                </span>
              </Link>
            )
          })}
        </div>
      </nav>
    </div>
  )
}
