/**
 * KINREL Mirror — Core Error System
 * Structured error hierarchy with codes, HTTP status mapping, and serialization.
 */

export type ErrorCategory = 
  | 'auth' | 'validation' | 'resource' | 'business' 
  | 'rate_limit' | 'system' | 'moderation' | 'payment';

export interface ErrorDetail {
  field?: string;
  message: string;
  value?: unknown;
  constraint?: string;
}

export class AppError extends Error {
  constructor(
    message: string,
    public readonly code: string,
    public readonly status: number,
    public readonly category: ErrorCategory,
    public readonly details?: ErrorDetail[],
    public readonly docsUrl?: string,
    public readonly isOperational: boolean = true,
  ) {
    super(message);
    this.name = 'AppError';
    Object.setPrototypeOf(this, AppError.prototype);
  }

  toJSON() {
    return {
      error: {
        code: this.code,
        message: this.message,
        category: this.category,
        ...(this.details && { details: this.details }),
        ...(this.docsUrl && { docsUrl: this.docsUrl }),
      },
      meta: {
        timestamp: new Date().toISOString(),
        requestId: generateRequestId(),
        version: '1.0.0',
      },
    };
  }
}

// ── Authentication Errors ────────────────────────────────────────

export class UnauthorizedError extends AppError {
  constructor(message = 'Authentication is required', details?: ErrorDetail[]) {
    super(message, 'AUTH_REQUIRED', 401, 'auth', details);
    this.name = 'UnauthorizedError';
  }
}

export class ForbiddenError extends AppError {
  constructor(message = 'Insufficient permissions', details?: ErrorDetail[]) {
    super(message, 'FORBIDDEN', 403, 'auth', details);
    this.name = 'ForbiddenError';
  }
}

export class InvalidApiKeyError extends AppError {
  constructor(message = 'Invalid API key provided') {
    super(message, 'INVALID_API_KEY', 401, 'auth');
    this.name = 'InvalidApiKeyError';
  }
}

export class ApiKeyExpiredError extends AppError {
  constructor() {
    super('API key has expired', 'API_KEY_EXPIRED', 401, 'auth');
    this.name = 'ApiKeyExpiredError';
  }
}

export class ApiKeyRevokedError extends AppError {
  constructor() {
    super('API key has been revoked', 'API_KEY_REVOKED', 401, 'auth');
    this.name = 'ApiKeyRevokedError';
  }
}

export class InsufficientScopeError extends AppError {
  constructor(required: string, have: string[]) {
    super('Insufficient scope for this action', 'INSUFFICIENT_SCOPE', 403, 'auth', [
      { field: 'scope', message: `Requires "${required}" scope`, value: have },
    ]);
    this.name = 'InsufficientScopeError';
  }
}

// ── Validation Errors ────────────────────────────────────────────

export class ValidationError extends AppError {
  constructor(message = 'Request validation failed', details?: ErrorDetail[]) {
    super(message, 'VALIDATION_ERROR', 400, 'validation', details);
    this.name = 'ValidationError';
  }
}

export class InvalidParameterError extends AppError {
  constructor(param: string, message?: string) {
    super(message ?? `Invalid parameter: ${param}`, 'INVALID_PARAMETER', 400, 'validation', [
      { field: param, message: message ?? 'Invalid value' },
    ]);
    this.name = 'InvalidParameterError';
  }
}

export class MissingFieldError extends AppError {
  constructor(field: string) {
    super(`Required field is missing: ${field}`, 'MISSING_REQUIRED_FIELD', 400, 'validation', [
      { field, message: 'This field is required' },
    ]);
    this.name = 'MissingFieldError';
  }
}

// ── Resource Errors ──────────────────────────────────────────────

export class NotFoundError extends AppError {
  constructor(resource: string, id?: string) {
    super(
      id ? `${resource} "${id}" not found` : `${resource} not found`,
      'NOT_FOUND',
      404,
      'resource',
    );
    this.name = 'NotFoundError';
  }
}

export class ConflictError extends AppError {
  constructor(message = 'Resource already exists', details?: ErrorDetail[]) {
    super(message, 'CONFLICT', 409, 'resource', details);
    this.name = 'ConflictError';
  }
}

// ── Business Logic Errors ────────────────────────────────────────

export class BusinessRuleError extends AppError {
  constructor(message: string, code = 'BUSINESS_RULE_VIOLATION') {
    super(message, code, 422, 'business');
    this.name = 'BusinessRuleError';
  }
}

export class DuplicateRelationshipError extends AppError {
  constructor(type: string) {
    super(`Relationship of type "${type}" already exists between these persons`, 'DUPLICATE_RELATIONSHIP', 409, 'business');
    this.name = 'DuplicateRelationshipError';
  }
}

export class SelfRelationshipError extends AppError {
  constructor() {
    super('Cannot create a relationship from a person to themselves', 'SELF_RELATIONSHIP', 422, 'business');
    this.name = 'SelfRelationshipError';
  }
}

// ── Rate Limit Errors ────────────────────────────────────────────

export class RateLimitError extends AppError {
  public readonly retryAfter: number;
  
  constructor(retryAfter: number) {
    super('Rate limit exceeded. Please retry later.', 'RATE_LIMITED', 429, 'rate_limit');
    this.name = 'RateLimitError';
    this.retryAfter = retryAfter;
  }
}

// ── System Errors ────────────────────────────────────────────────

export class InternalError extends AppError {
  constructor(message = 'Internal server error') {
    super(message, 'INTERNAL_ERROR', 500, 'system', undefined, undefined, false);
    this.name = 'InternalError';
  }
}

export class ServiceUnavailableError extends AppError {
  constructor(service?: string) {
    super(
      service ? `${service} is temporarily unavailable` : 'Service temporarily unavailable',
      'SERVICE_UNAVAILABLE',
      503,
      'system',
    );
    this.name = 'ServiceUnavailableError';
  }
}

// ── Moderation Errors ────────────────────────────────────────────

export class ContentBlockedError extends AppError {
  constructor(reason: string) {
    super(`Content blocked: ${reason}`, 'CONTENT_BLOCKED', 451, 'moderation', [
      { message: reason },
    ]);
    this.name = 'ContentBlockedError';
  }
}

// ── Helpers ──────────────────────────────────────────────────────

function generateRequestId(): string {
  return `req_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 10)}`;
}

export function isAppError(error: unknown): error is AppError {
  return error instanceof AppError;
}

export function toAppError(error: unknown): AppError {
  if (isAppError(error)) return error;
  if (error instanceof Error) {
    return new InternalError(error.message);
  }
  return new InternalError(String(error));
}
