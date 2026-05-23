'use client'

import KinrelIcon from '@/components/brand/KinrelIcon'
import { useEffect } from 'react'

/**
 * Kinrel Error Boundary — catches runtime errors in any route segment
 * and displays a branded recovery UI instead of a blank screen.
 */
export default function Error({
  error,
  reset,
}: {
  error: Error & { digest?: string }
  reset: () => void
}) {
  useEffect(() => {
    // Log the error to monitoring / console in development
    console.error('[Kinrel Error Boundary]', error)
  }, [error])

  return (
    <div
      className="min-h-dvh flex flex-col items-center justify-center px-6"
      style={{ backgroundColor: 'var(--kinrel-bg)' }}
      role="alert"
      aria-live="assertive"
    >
      <div className="flex flex-col items-center text-center max-w-md">
        {/* Icon */}
        <div className="mb-6 opacity-80">
          <KinrelIcon size={72} palette="orange" animated />
        </div>

        {/* Title */}
        <h1
          className="font-bold mb-2"
          style={{
            fontFamily: 'var(--kinrel-font-display)',
            fontSize: 'var(--kinrel-text-xl)',
            color: 'var(--kinrel-white)',
          }}
        >
          Something went wrong
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
          An unexpected error occurred. This has been logged and we&apos;re looking into it.
        </p>

        {/* Error digest (if available) */}
        {error.digest && (
          <p
            className="mb-6 px-3 py-1.5 rounded-md text-xs"
            style={{
              fontFamily: 'var(--kinrel-font-mono)',
              color: 'var(--kinrel-dim)',
              backgroundColor: 'var(--kinrel-elevated)',
              border: '1px solid var(--kinrel-border)',
            }}
          >
            Error ID: {error.digest}
          </p>
        )}

        {/* Retry button */}
        <button
          onClick={reset}
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
          Try Again
        </button>
      </div>
    </div>
  )
}
