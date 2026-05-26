import KinrelLogo from '@/components/brand/KinrelLogo'
import Link from 'next/link'

/**
 * Kinrel 404 Page — branded not-found experience.
 * This renders when no route matches the requested URL.
 */
export default function NotFound() {
  return (
    <div
      className="min-h-dvh flex flex-col items-center justify-center px-6"
      style={{ backgroundColor: 'var(--kinrel-bg)' }}
    >
      <div className="flex flex-col items-center text-center max-w-md">
        {/* Logo */}
        <div className="mb-8">
          <KinrelLogo size="lg" layout="vertical" palette="orange" />
        </div>

        {/* 404 heading */}
        <h1
          className="font-bold mb-3"
          style={{
            fontFamily: 'var(--kinrel-font-display)',
            fontSize: 'var(--kinrel-text-2xl)',
            color: 'var(--kinrel-orange)',
          }}
        >
          404 — Page Not Found
        </h1>

        {/* Description */}
        <p
          className="mb-8 leading-relaxed"
          style={{
            fontFamily: 'var(--kinrel-font-body)',
            fontSize: 'var(--kinrel-text-base)',
            color: 'var(--kinrel-silver)',
          }}
        >
          The page you&apos;re looking for doesn&apos;t exist or has been moved.
          Let&apos;s get you back on track.
        </p>

        {/* Home link */}
        <Link
          href="/"
          className="px-6 py-3 rounded-xl font-semibold text-sm transition-all
            hover:scale-[1.03] active:scale-[0.98]
            focus-visible:outline-2 focus-visible:outline-offset-2"
          style={{
            fontFamily: 'var(--kinrel-font-body)',
            backgroundColor: 'var(--kinrel-orange)',
            color: 'var(--kinrel-white)',
            outlineColor: 'var(--kinrel-orange)',
          }}
        >
          Go Home
        </Link>
      </div>
    </div>
  )
}
