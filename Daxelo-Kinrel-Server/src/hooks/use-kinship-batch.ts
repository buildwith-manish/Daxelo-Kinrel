'use client'

import { useState, useEffect, useRef, useSyncExternalStore, useCallback, startTransition } from 'react'

interface KinshipTermResult {
  native: string
  latin: string
}

// Shared cache across hook instances
const batchCache = new Map<string, KinshipTermResult>()
const batchSubscribers = new Set<() => void>()

function emitBatchChange() {
  for (const sub of batchSubscribers) sub()
}

function subscribeBatch(callback: () => void) {
  batchSubscribers.add(callback)
  return () => batchSubscribers.delete(callback)
}

function getBatchSnapshot() {
  return batchCache.size
}

export function useKinshipBatch(keys: string[], locale: string) {
  // Re-render when cache changes
  useSyncExternalStore(subscribeBatch, getBatchSnapshot, getBatchSnapshot)

  const [loading, setLoading] = useState(false)
  const fetchIdRef = useRef(0)
  const prevKeysRef = useRef('')
  const prevLocaleRef = useRef('')

  const getTerm = useCallback(
    (key: string): KinshipTermResult | null => {
      const cacheKey = `${key}_${locale}`
      return batchCache.get(cacheKey) ?? null
    },
    [locale]
  )

  useEffect(() => {
    const validKeys = keys.filter(Boolean)
    if (!validKeys.length || !locale) return

    const keysKey = validKeys.join(',')
    // Skip if nothing changed
    if (keysKey === prevKeysRef.current && locale === prevLocaleRef.current) return
    prevKeysRef.current = keysKey
    prevLocaleRef.current = locale

    const currentId = ++fetchIdRef.current

    const missing = validKeys.filter((k) => !batchCache.has(`${k}_${locale}`))
    if (missing.length === 0) return

    let cancelled = false

    // Use startTransition to avoid synchronous setState in effect
    startTransition(() => { setLoading(true) })

    Promise.all(
      missing.map((key) =>
        fetch(`/api/v1/kinship?key=${encodeURIComponent(key)}&lang=${locale}`)
          .then((r) => (r.ok ? r.json() : null))
          .then((data) => {
            if (cancelled || fetchIdRef.current !== currentId) return
            if (!data) return
            const cacheKey = `${key}_${locale}`

            if (data.localizedLabel) {
              batchCache.set(cacheKey, { native: data.localizedLabel, latin: data.localizedLabel })
            } else if (data.translations?.[locale]) {
              batchCache.set(cacheKey, data.translations[locale])
            } else if (data.relationship?.englishTerm) {
              batchCache.set(cacheKey, {
                native: data.relationship.englishTerm,
                latin: data.relationship.englishTerm.toLowerCase(),
              })
            }
          })
          .catch(() => {})
      )
    ).then(() => {
      if (cancelled) return
      emitBatchChange()
      startTransition(() => { setLoading(false) })
    })

    return () => {
      cancelled = true
    }
  }, [keys, locale])

  const refetch = useCallback(() => {
    // Clear all entries for current locale and re-fetch
    for (const key of batchCache.keys()) {
      if (key.endsWith(`_${locale}`)) {
        batchCache.delete(key)
      }
    }
    prevKeysRef.current = ''
    emitBatchChange()
  }, [locale])

  return { getTerm, loading, refetch }
}
