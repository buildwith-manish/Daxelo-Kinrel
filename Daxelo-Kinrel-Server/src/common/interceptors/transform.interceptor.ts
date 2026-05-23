import {
  Injectable,
  NestInterceptor,
  ExecutionContext,
  CallHandler,
} from '@nestjs/common';
import { Observable } from 'rxjs';
import { map } from 'rxjs/operators';
import type { Response } from 'express';
import { v4 as uuidv4 } from 'uuid';

/**
 * TransformInterceptor — Passes response data through unchanged.
 *
 * IMPORTANT: The original Next.js API returns flat JSON responses like:
 *   { "user": {...}, "familyId": "..." }
 *
 * The Flutter app expects this exact format. We do NOT wrap responses
 * in a { data, meta } envelope to maintain API compatibility.
 *
 * Instead, we add metadata via response headers:
 *   - X-Request-Id: unique request identifier
 *   - X-Response-Time: processing timestamp
 */
@Injectable()
export class TransformInterceptor<T> implements NestInterceptor<T, T> {
  intercept(context: ExecutionContext, next: CallHandler): Observable<T> {
    const response = context.switchToHttp().getResponse<Response>();
    const requestId = response.req?.headers['x-request-id'] as string || uuidv4();

    // Set metadata headers for observability
    response.setHeader('X-Request-Id', requestId);
    response.setHeader('X-Response-Time', new Date().toISOString());

    // Pass response data through unchanged for Flutter API compatibility
    return next.handle();
  }
}
