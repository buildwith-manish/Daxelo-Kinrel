import KinrelIcon from '@/components/brand/KinrelIcon'

/**
 * Kinrel Loading State — displayed during route transitions
 * and streaming suspense boundaries.
 */
export default function Loading() {
  return (
    <div
      className="min-h-dvh flex flex-col items-center justify-center"
      style={{ backgroundColor: 'var(--kinrel-bg)' }}
      aria-label="Loading"
      role="status"
    >
      <div className="flex flex-col items-center gap-4">
        {/* Animated icon */}
        <div style={{ animation: 'kinrel-pulse 1.5s ease-in-out infinite alternate' }}>
          <KinrelIcon size={64} palette="orange" animated />
        </div>

        {/* Loading text */}
        <p
          className="tracking-wider"
          style={{
            fontFamily: 'var(--kinrel-font-body)',
            fontSize: 'var(--kinrel-text-sm)',
            color: 'var(--kinrel-silver)',
            letterSpacing: '0.15em',
          }}
        >
          Loading…
        </p>
      </div>
    </div>
  )
}
