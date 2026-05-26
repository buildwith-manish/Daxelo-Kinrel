'use client';

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';

interface ApiOptions {
  baseUrl?: string;
  headers?: Record<string, string>;
}

interface ApiState<T> {
  data: T | null;
  error: string | null;
  isLoading: boolean;
  refetch: () => void;
}

const DEFAULT_BASE_URL = '/api/v2';

export function useApiGet<T>(
  endpoint: string,
  params?: Record<string, string>,
  options?: { enabled?: boolean; staleTime?: number },
) {
  const queryString = params
    ? '?' + new URLSearchParams(params).toString()
    : '';
  const url = `${DEFAULT_BASE_URL}${endpoint}${queryString}`;

  return useQuery({
    queryKey: ['api', endpoint, params],
    queryFn: async () => {
      const res = await fetch(url);
      const json = await res.json();
      if (!res.ok) {
        throw new Error(json.error?.message || 'API request failed');
      }
      return json.data as T;
    },
    enabled: options?.enabled !== false,
    staleTime: options?.staleTime ?? 30_000,
  });
}

export function useApiPost<TInput, TOutput>(endpoint: string) {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (data: TInput) => {
      const res = await fetch(`${DEFAULT_BASE_URL}${endpoint}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
      });
      const json = await res.json();
      if (!res.ok) {
        throw new Error(json.error?.message || 'API request failed');
      }
      return json.data as TOutput;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['api'] });
    },
  });
}

export function useApiPatch<TInput, TOutput>(endpoint: string) {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (data: TInput) => {
      const res = await fetch(`${DEFAULT_BASE_URL}${endpoint}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
      });
      const json = await res.json();
      if (!res.ok) {
        throw new Error(json.error?.message || 'API request failed');
      }
      return json.data as TOutput;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['api'] });
    },
  });
}

export function useApiDelete(endpoint: string) {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (params?: Record<string, string>) => {
      const queryString = params
        ? '?' + new URLSearchParams(params).toString()
        : '';
      const res = await fetch(`${DEFAULT_BASE_URL}${endpoint}${queryString}`, {
        method: 'DELETE',
      });
      if (!res.ok) {
        const json = await res.json().catch(() => ({}));
        throw new Error(json.error?.message || 'Delete failed');
      }
      return true;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['api'] });
    },
  });
}
