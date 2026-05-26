'use client'

import { useEffect, useState } from 'react'

export default function Home() {
  const [isLoading, setIsLoading] = useState(true)

  useEffect(() => {
    const timer = setTimeout(() => setIsLoading(false), 5000)
    return () => clearTimeout(timer)
  }, [])

  return (
    <div style={{ width: '100vw', height: '100vh', position: 'relative', overflow: 'hidden' }}>
      {isLoading && (
        <div
          style={{
            position: 'absolute',
            inset: 0,
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            justifyContent: 'center',
            backgroundColor: '#13141E',
            zIndex: 10,
            transition: 'opacity 0.5s ease-out',
          }}
        >
          <svg width="80" height="80" viewBox="0 0 80 80" fill="none">
            <circle cx="40" cy="40" r="36" stroke="#E8612A" strokeWidth="2" opacity="0.3" />
            <circle cx="40" cy="40" r="24" stroke="#F59240" strokeWidth="1.5" opacity="0.5" />
            <text x="40" y="52" textAnchor="middle" fill="#E8612A" fontFamily="sans-serif" fontSize="32" fontWeight="800">K</text>
          </svg>
          <div style={{ marginTop: 16, color: '#E8612A', fontFamily: 'sans-serif', fontSize: 24, fontWeight: 800, letterSpacing: 2 }}>
            KINREL
          </div>
          <div style={{ marginTop: 8, color: '#8A7A72', fontFamily: 'sans-serif', fontSize: 13, letterSpacing: 0.5 }}>
            Loading Flutter app...
          </div>
          <div style={{ marginTop: 24 }}>
            <div style={{
              width: 24,
              height: 24,
              border: '2px solid rgba(232,97,42,0.3)',
              borderTopColor: '#E8612A',
              borderRadius: '50%',
              animation: 'spin 1s linear infinite',
            }} />
          </div>
          <style>{`@keyframes spin { to { transform: rotate(360deg) } }`}</style>
        </div>
      )}

      <iframe
        src="/flutter/index.html"
        style={{
          width: '100%',
          height: '100%',
          border: 'none',
          display: 'block',
        }}
        title="KINREL — Indian Family Relationship Intelligence"
        onLoad={() => setIsLoading(false)}
      />
    </div>
  )
}
