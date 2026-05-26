'use client'

import { useState, useEffect, useRef, useSyncExternalStore, startTransition } from 'react'

interface KinshipTerm {
  native: string
  latin: string
}

// Simple cache shared across hook instances
const termCache = new Map<string, KinshipTerm>()
const subscribers = new Set<() => void>()

function emitChange() {
  for (const sub of subscribers) sub()
}

function subscribe(callback: () => void) {
  subscribers.add(callback)
  return () => subscribers.delete(callback)
}

function getSnapshot() {
  return termCache.size
}

export function useKinshipTerm(relationshipKey: string | null, locale: string) {
  // Re-render when cache changes
  useSyncExternalStore(subscribe, getSnapshot, getSnapshot)

  const [loading, setLoading] = useState(false)
  const fetchIdRef = useRef(0)

  const cacheKey = relationshipKey && locale ? `${relationshipKey}_${locale}` : null

  // For English, compute directly without fetch
  let term: KinshipTerm | null = null
  if (cacheKey && locale === 'en' && relationshipKey) {
    const formatted = relationshipKey
      .replace(/_/g, ' ')
      .replace(/\b\w/g, (c) => c.toUpperCase())
    term = { native: formatted, latin: formatted.toLowerCase() }
  } else if (cacheKey) {
    term = termCache.get(cacheKey) ?? null
  }

  useEffect(() => {
    if (!relationshipKey || !locale || locale === 'en') return

    const currentId = ++fetchIdRef.current
    const key = `${relationshipKey}_${locale}`

    // Already cached
    if (termCache.has(key)) return

    let cancelled = false

    // Use startTransition to avoid synchronous setState in effect
    startTransition(() => { setLoading(true) })

    fetch(`/api/v1/kinship?key=${encodeURIComponent(relationshipKey)}&lang=${locale}`)
      .then((r) => (r.ok ? r.json() : null))
      .then((data) => {
        if (cancelled || fetchIdRef.current !== currentId) return

        if (data?.localizedLabel) {
          termCache.set(key, { native: data.localizedLabel, latin: data.localizedLabel })
        } else if (data?.translations?.[locale]) {
          termCache.set(key, data.translations[locale])
        } else if (data?.relationship?.englishTerm) {
          termCache.set(key, {
            native: data.relationship.englishTerm,
            latin: data.relationship.englishTerm.toLowerCase(),
          })
        }

        emitChange()
        startTransition(() => { if (!cancelled) setLoading(false) })
      })
      .catch(() => {
        startTransition(() => { if (!cancelled) setLoading(false) })
      })

    return () => {
      cancelled = true
    }
  }, [relationshipKey, locale])

  return { term, loading }
}
