import { Injectable, NestInterceptor, ExecutionContext, CallHandler } from '@nestjs/common';
import { Observable } from 'rxjs';
import { map } from 'rxjs/operators';

/**
 * Standardizes all API responses into a consistent envelope:
 * { success: true, data: <payload>, timestamp: <ISO string> }
 *
 * This interceptor wraps the response data but does NOT apply to:
 * - Error responses (handled by AllExceptionsFilter)
 * - Streaming responses
 *
 * NOTE: This interceptor provides the `timestamp` field, so no separate
 * TimestampInterceptor is needed. Using both would cause double-wrapping
 * (data.ts inside the envelope + envelope.timestamp).
 */
@Injectable()
export class ResponseEnvelopeInterceptor implements NestInterceptor {
  intercept(context: ExecutionContext, next: CallHandler): Observable<any> {
    return next.handle().pipe(
      map((data) => ({
        success: true,
        data,
        timestamp: new Date().toISOString(),
      })),
    );
  }
}
