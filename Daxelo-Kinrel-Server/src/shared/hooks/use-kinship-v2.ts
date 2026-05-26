'use client';

import { useApiGet } from './use-api';

export interface KinshipRelationship {
  id: number;
  relationshipKey: string;
  englishTerm: string;
  gender: 'male' | 'female' | 'neutral';
  lineage: string;
  generation: number;
  relationType: string;
  elderYounger: string | null;
  relationshipCategory: string;
  cousinType: string | null;
  relationshipPath: string[];
  notes: string;
  searchKeywords: string[];
}

export interface KinshipTranslation {
  native: string;
  latin: string;
}

export interface KinshipMeta {
  version: string;
  generatedAt: string;
  totalRelationships: number;
  supportedLanguages: string[];
  categories: string[];
}

export function useKinshipMeta() {
  return useApiGet<KinshipMeta>('/kinship');
}

export function useKinshipLookup(key: string, lang?: string) {
  const params: Record<string, string> = { key };
  if (lang) params.lang = lang;
  return useApiGet<{ relationship: KinshipRelationship; translations?: Record<string, KinshipTranslation>; localizedLabel?: string }>(
    '/kinship',
    params,
    { enabled: !!key },
  );
}

export function useKinshipSearch(query: string) {
  return useApiGet<{ results: KinshipRelationship[]; total: number; query: string }>(
    '/kinship',
    { q: query },
    { enabled: query.length >= 2, staleTime: 10_000 },
  );
}

export function useKinshipByCategory(category: string) {
  return useApiGet<{ results: KinshipRelationship[]; total: number; category: string }>(
    '/kinship',
    { category },
    { enabled: !!category },
  );
}

export function useKinshipByGender(gender: 'male' | 'female' | 'neutral') {
  return useApiGet<{ results: KinshipRelationship[]; total: number; gender: string }>(
    '/kinship',
    { gender },
    { enabled: !!gender },
  );
}
