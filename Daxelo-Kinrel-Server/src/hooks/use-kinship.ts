'use client'

import { useQuery, useMutation } from '@tanstack/react-query'
import { useState, useEffect, useRef, useCallback } from 'react'

// ── TypeScript Types ────────────────────────────────────────────────

export interface KinshipTranslation {
  native: string
  latin: string
}

export interface KinshipRelationship {
  id: number
  relationshipKey: string
  englishTerm: string
  gender: 'male' | 'female' | 'neutral'
  lineage: string
  generation: number
  relationType: string
  elderYounger: string | null
  relationshipCategory: string
  cousinType: string | null
  relationshipPath: string[]
  notes: string
  searchKeywords: string[]
}

/** GET /api/v1/kinship (no params) — meta info */
export interface KinshipMetaResponse {
  version: string
  generatedAt: string
  totalRelationships: number
  supportedLanguages: string[]
  categories: string[]
  sampleQuery: string
  searchQuery: string
  categoryQuery: string
}

/** GET /api/v1/kinship?key=...&lang=... — single relationship lookup */
export interface KinshipLookupResponse {
  relationship: KinshipRelationship
  translations: Record<string, KinshipTranslation> | undefined
  localizedLabel?: string
}

/** GET /api/v1/kinship?q=... — search results */
export interface KinshipSearchResponse {
  results: KinshipRelationship[]
  total: number
  showing: number
  query: string
}

/** GET /api/v1/kinship?category=... — category filter */
export interface KinshipCategoryResponse {
  results: KinshipRelationship[]
  total: number
  category: string
}

/** GET /api/v1/kinship?gender=... — gender filter */
export interface KinshipGenderResponse {
  results: KinshipRelationship[]
  total: number
  gender: string
}

/** GET /api/v1/kinship?lineage=... — lineage filter */
export interface KinshipLineageResponse {
  results: KinshipRelationship[]
  total: number
  lineage: string
}

/** Generic filter response (category / gender / lineage share the same shape) */
export type KinshipFilterResponse = KinshipCategoryResponse | KinshipGenderResponse | KinshipLineageResponse

// ── Shared Constants ────────────────────────────────────────────────

const KINSHIP_STALE_TIME = 5 * 60 * 1000 // 5 minutes — kinship data rarely changes

const KINSHIP_QUERY_KEYS = {
  meta: ['kinship', 'meta'] as const,
  lookup: (key: string, lang?: string) => ['kinship', 'lookup', key, lang ?? ''] as const,
  search: (query: string) => ['kinship', 'search', query] as const,
  category: (category: string) => ['kinship', 'category', category] as const,
  gender: (gender: string) => ['kinship', 'gender', gender] as const,
  lineage: (lineage: string) => ['kinship', 'lineage', lineage] as const,
} as const

// ── Internal Fetch Helpers ──────────────────────────────────────────

async function fetchKinshipAPI<T>(params: Record<string, string>): Promise<T> {
  const sp = new URLSearchParams(params)
  const url = `/api/v1/kinship?${sp.toString()}`
  const res = await fetch(url)
  if (!res.ok) {
    const body = await res.json().catch(() => ({}))
    throw new Error(body.error ?? `Kinship API error: ${res.status}`)
  }
  return res.json() as Promise<T>
}

// ── Debounce Hook ───────────────────────────────────────────────────

function useDebouncedValue<T>(value: T, delay: number): T {
  const [debouncedValue, setDebouncedValue] = useState(value)

  useEffect(() => {
    const timer = setTimeout(() => setDebouncedValue(value), delay)
    return () => clearTimeout(timer)
  }, [value, delay])

  return debouncedValue
}

// ── Hooks ───────────────────────────────────────────────────────────

/**
 * Fetch kinship meta info (version, total relationships, supported languages, categories).
 * Always enabled — no parameters required.
 */
export function useKinshipMeta() {
  return useQuery<KinshipMetaResponse, Error>({
    queryKey: KINSHIP_QUERY_KEYS.meta,
    queryFn: () => fetchKinshipAPI<KinshipMetaResponse>({}),
    staleTime: KINSHIP_STALE_TIME,
    gcTime: KINSHIP_STALE_TIME * 2,
    refetchOnWindowFocus: false,
  })
}

/**
 * Search relationships by keyword.
 * Queries are debounced by 300ms to avoid excessive API calls while typing.
 * Disabled when query is empty or whitespace-only.
 */
export function useKinshipSearch(query: string) {
  const debouncedQuery = useDebouncedValue(query, 300)
  const isEnabled = debouncedQuery.trim().length > 0

  return useQuery<KinshipSearchResponse, Error>({
    queryKey: KINSHIP_QUERY_KEYS.search(debouncedQuery),
    queryFn: () =>
      fetchKinshipAPI<KinshipSearchResponse>({ q: debouncedQuery }),
    staleTime: KINSHIP_STALE_TIME,
    gcTime: KINSHIP_STALE_TIME * 2,
    refetchOnWindowFocus: false,
    enabled: isEnabled,
    placeholderData: (previousData) => previousData, // keep previous results while loading new search
  })
}

/**
 * Look up a single relationship by key with optional language translation.
 * Disabled when key is empty.
 */
export function useKinshipLookup(key: string | null | undefined, lang?: string) {
  const isEnabled = Boolean(key && key.trim().length > 0)

  return useQuery<KinshipLookupResponse, Error>({
    queryKey: KINSHIP_QUERY_KEYS.lookup(key ?? '', lang),
    queryFn: () => {
      const params: Record<string, string> = { key: key! }
      if (lang) params.lang = lang
      return fetchKinshipAPI<KinshipLookupResponse>(params)
    },
    staleTime: KINSHIP_STALE_TIME,
    gcTime: KINSHIP_STALE_TIME * 2,
    refetchOnWindowFocus: false,
    enabled: isEnabled,
  })
}

/**
 * Filter relationships by category (e.g. 'core_family', 'in_laws', 'grandparents').
 * Disabled when category is empty.
 */
export function useKinshipCategory(category: string | null | undefined) {
  const isEnabled = Boolean(category && category.trim().length > 0)

  return useQuery<KinshipCategoryResponse, Error>({
    queryKey: KINSHIP_QUERY_KEYS.category(category ?? ''),
    queryFn: () =>
      fetchKinshipAPI<KinshipCategoryResponse>({ category: category! }),
    staleTime: KINSHIP_STALE_TIME,
    gcTime: KINSHIP_STALE_TIME * 2,
    refetchOnWindowFocus: false,
    enabled: isEnabled,
  })
}

/**
 * Filter relationships by gender ('male', 'female', 'neutral').
 * Disabled when gender is empty.
 */
export function useKinshipByGender(gender: string | null | undefined) {
  const isEnabled = Boolean(gender && gender.trim().length > 0)

  return useQuery<KinshipGenderResponse, Error>({
    queryKey: KINSHIP_QUERY_KEYS.gender(gender ?? ''),
    queryFn: () =>
      fetchKinshipAPI<KinshipGenderResponse>({ gender: gender! }),
    staleTime: KINSHIP_STALE_TIME,
    gcTime: KINSHIP_STALE_TIME * 2,
    refetchOnWindowFocus: false,
    enabled: isEnabled,
  })
}

/**
 * Filter relationships by lineage ('paternal', 'maternal', 'bilateral', 'marital').
 * Disabled when lineage is empty.
 */
export function useKinshipByLineage(lineage: string | null | undefined) {
  const isEnabled = Boolean(lineage && lineage.trim().length > 0)

  return useQuery<KinshipLineageResponse, Error>({
    queryKey: KINSHIP_QUERY_KEYS.lineage(lineage ?? ''),
    queryFn: () =>
      fetchKinshipAPI<KinshipLineageResponse>({ lineage: lineage! }),
    staleTime: KINSHIP_STALE_TIME,
    gcTime: KINSHIP_STALE_TIME * 2,
    refetchOnWindowFocus: false,
    enabled: isEnabled,
  })
}
