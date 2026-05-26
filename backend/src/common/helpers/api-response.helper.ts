import { v4 as uuidv4 } from 'uuid';

const API_VERSION = '1.0.0';

/**
 * Standard meta object attached to every API response
 */
interface ResponseMeta {
  requestId: string;
  timestamp: string;
  version: string;
}

/**
 * Pagination metadata
 */
interface PaginationMeta {
  page: number;
  limit: number;
  totalItems: number;
  totalPages: number;
  hasNextPage: boolean;
  hasPrevPage: boolean;
}

/**
 * Cursor-based pagination metadata
 */
interface CursorPaginationMeta {
  nextCursor: string | null;
  prevCursor: string | null;
  limit: number;
  hasMore: boolean;
}

/**
 * Generate standard meta object
 */
function generateMeta(): ResponseMeta {
  return {
    requestId: uuidv4(),
    timestamp: new Date().toISOString(),
    version: API_VERSION,
  };
}

/**
 * Success response helper
 * Returns: { data, meta: { requestId, timestamp, version } }
 */
export function success<T>(data: T) {
  return {
    data,
    meta: generateMeta(),
  };
}

/**
 * Error response helper
 * Returns: { error: { code, message }, meta }
 */
export function error(code: string, message: string, status: number) {
  return {
    error: {
      code,
      message,
      status,
    },
    meta: generateMeta(),
  };
}

/**
 * Collection response with pagination
 * Returns: { data, meta, pagination }
 */
export function collection<T>(data: T[], pagination: PaginationMeta) {
  return {
    data,
    meta: generateMeta(),
    pagination,
  };
}

/**
 * Calculate pagination metadata
 */
export function calculatePagination(
  totalItems: number,
  page: number,
  limit: number,
): PaginationMeta {
  const totalPages = Math.ceil(totalItems / limit);
  return {
    page,
    limit,
    totalItems,
    totalPages,
    hasNextPage: page < totalPages,
    hasPrevPage: page > 1,
  };
}

/**
 * Cursor-based pagination helper
 * Returns: { data, meta, pagination: { nextCursor, prevCursor, limit, hasMore } }
 */
export function paginated<T>(
  items: T[],
  cursorField: string,
  limit: number,
  extractCursor: (item: T) => string,
): {
  data: T[];
  meta: ResponseMeta;
  pagination: CursorPaginationMeta;
} {
  const hasMore = items.length > limit;
  const data = hasMore ? items.slice(0, limit) : items;

  const nextCursor =
    hasMore && data.length > 0 ? extractCursor(data[data.length - 1]) : null;
  const prevCursor = data.length > 0 ? extractCursor(data[0]) : null;

  return {
    data,
    meta: generateMeta(),
    pagination: {
      nextCursor,
      prevCursor,
      limit,
      hasMore,
    },
  };
}
