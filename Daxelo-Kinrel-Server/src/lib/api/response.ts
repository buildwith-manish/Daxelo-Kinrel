import { NextResponse } from 'next/server'
import { v4 as uuidv4 } from 'uuid'

// ── API Version ──────────────────────────────────────────────────────
export const API_VERSION = '1.0.0'

// ── Types ────────────────────────────────────────────────────────────

export interface ApiResponseMeta {
  requestId: string
  timestamp: string
  version: string
}

export interface ApiResponse<T> {
  data: T
  meta: ApiResponseMeta
}

export interface PaginationInfo {
  page: number
  limit: number
  total: number
  hasMore: boolean
  totalPages: number
}

export interface ApiCollectionResponse<T> {
  data: T[]
  meta: ApiResponseMeta
  pagination: PaginationInfo
}

export interface ApiErrorDetail {
  code: string
  message: string
  details?: unknown
  docsUrl?: string
}

export interface ApiErrorResponse {
  error: ApiErrorDetail
  meta: ApiResponseMeta
}

// ── Error Codes ──────────────────────────────────────────────────────

export const ERROR_CODES = {
  // Authentication & Authorization
  AUTH_REQUIRED: { code: 'AUTH_REQUIRED', status: 401, message: 'Authentication is required' },
  INVALID_API_KEY: { code: 'INVALID_API_KEY', status: 401, message: 'Invalid API key provided' },
  INSUFFICIENT_SCOPE: { code: 'INSUFFICIENT_SCOPE', status: 403, message: 'Insufficient scope for this action' },
  API_KEY_REVOKED: { code: 'API_KEY_REVOKED', status: 401, message: 'API key has been revoked' },
  API_KEY_EXPIRED: { code: 'API_KEY_EXPIRED', status: 401, message: 'API key has expired' },

  // Rate Limiting
  RATE_LIMITED: { code: 'RATE_LIMITED', status: 429, message: 'Rate limit exceeded. Please retry later.' },

  // Validation
  VALIDATION_ERROR: { code: 'VALIDATION_ERROR', status: 400, message: 'Request validation failed' },
  INVALID_PARAMETER: { code: 'INVALID_PARAMETER', status: 400, message: 'Invalid parameter value' },
  MISSING_REQUIRED_FIELD: { code: 'MISSING_REQUIRED_FIELD', status: 400, message: 'Required field is missing' },

  // Resource
  NOT_FOUND: { code: 'NOT_FOUND', status: 404, message: 'Resource not found' },
  ALREADY_EXISTS: { code: 'ALREADY_EXISTS', status: 409, message: 'Resource already exists' },
  CONFLICT: { code: 'CONFLICT', status: 409, message: 'Resource conflict' },

  // Server
  INTERNAL_ERROR: { code: 'INTERNAL_ERROR', status: 500, message: 'Internal server error' },
  SERVICE_UNAVAILABLE: { code: 'SERVICE_UNAVAILABLE', status: 503, message: 'Service temporarily unavailable' },

  // Idempotency
  IDEMPOTENCY_KEY_USED: { code: 'IDEMPOTENCY_KEY_USED', status: 200, message: 'Returning cached response for idempotency key' },
} as const

// ── Request ID ───────────────────────────────────────────────────────

export function generateRequestId(): string {
  return `req_${uuidv4().replace(/-/g, '').slice(0, 24)}`
}

// ── Helper: Build Meta ───────────────────────────────────────────────

function buildMeta(request?: Request): ApiResponseMeta {
  return {
    requestId: generateRequestId(),
    timestamp: new Date().toISOString(),
    version: API_VERSION,
  }
}

// ── Success Response ─────────────────────────────────────────────────

export function success<T>(data: T, request?: Request): NextResponse {
  const response: ApiResponse<T> = {
    data,
    meta: buildMeta(request),
  }
  return NextResponse.json(response, { status: 200 })
}

// ── Collection Response ──────────────────────────────────────────────

export function collection<T>(
  data: T[],
  pagination: { page: number; limit: number; total: number; hasMore: boolean },
  request?: Request
): NextResponse {
  const totalPages = Math.ceil(pagination.total / pagination.limit)
  const response: ApiCollectionResponse<T> = {
    data,
    meta: buildMeta(request),
    pagination: {
      page: pagination.page,
      limit: pagination.limit,
      total: pagination.total,
      hasMore: pagination.hasMore,
      totalPages,
    },
  }
  return NextResponse.json(response, { status: 200 })
}

// ── Error Response ───────────────────────────────────────────────────

export function error(
  code: string,
  message: string,
  status: number,
  details?: unknown,
  docsUrl?: string
): NextResponse {
  const errDetail: ApiErrorDetail = {
    code,
    message,
  }
  if (details !== undefined) {
    errDetail.details = details
  }
  if (docsUrl) {
    errDetail.docsUrl = docsUrl
  }
  const response: ApiErrorResponse = {
    error: errDetail,
    meta: buildMeta(),
  }
  return NextResponse.json(response, { status })
}

// ── Error from Code ──────────────────────────────────────────────────

export function errorFromCode(
  codeName: keyof typeof ERROR_CODES,
  details?: unknown
): NextResponse {
  const errInfo = ERROR_CODES[codeName]
  return error(errInfo.code, errInfo.message, errInfo.status, details, `https://docs.kinrel.in/api/errors/${errInfo.code.toLowerCase()}`)
}

// ── Paginated (cursor-based) ────────────────────────────────────────

export async function paginated<T extends { id: string }>(
  cursor: string | null,
  limit: number,
  queryFn: (take: number, cursor?: string) => Promise<T[]>
): Promise<{ data: T[]; nextCursor: string | null; hasMore: boolean }> {
  const take = limit + 1
  const items = await queryFn(take, cursor ?? undefined)
  const hasMore = items.length > limit
  const data = hasMore ? items.slice(0, -1) : items
  const nextCursor = hasMore && data.length > 0 ? data[data.length - 1].id : null

  return { data, nextCursor, hasMore }
}
