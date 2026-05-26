/**
 * DAXELO KINREL — Token Override Store
 *
 * Zustand store for runtime design token overrides.
 * Enables A/B testing and remote config-driven token changes.
 *
 * Pack 01: Design System — Design Tokens API
 */

import { create } from 'zustand'

interface TokenOverrideStore {
  overrides: Record<string, unknown>
  setOverride: (key: string, value: unknown) => void
  removeOverride: (key: string) => void
  getOverride: <T>(key: string, defaultValue: T) => T
  clearAll: () => void
}

export const useTokenOverrides = create<TokenOverrideStore>((set, get) => ({
  overrides: {},

  setOverride: (key, value) =>
    set((state) => ({
      overrides: { ...state.overrides, [key]: value },
    })),

  removeOverride: (key) =>
    set((state) => {
      const { [key]: _, ...rest } = state.overrides
      return { overrides: rest }
    }),

  getOverride: <T,>(key: string, defaultValue: T): T => {
    const overrides = get().overrides
    return (overrides[key] as T) ?? defaultValue
  },

  clearAll: () => set({ overrides: {} }),
}))
