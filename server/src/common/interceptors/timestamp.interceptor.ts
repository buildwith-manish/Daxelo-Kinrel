import {
  Injectable,
  NestInterceptor,
  ExecutionContext,
  CallHandler,
} from '@nestjs/common';
import { Observable } from 'rxjs';
import { map } from 'rxjs/operators';

/**
 * Adds a `ts` (unix ms timestamp) to response objects.
 * This allows the Flutter client to detect stale cache entries.
 *
 * IMPORTANT: Does NOT wrap responses in an envelope.
 * The Flutter Dio client expects flat JSON — adding only `ts` is safe.
 * If the response is an object, `ts` is added as a top-level field.
 * If the response is an array or primitive, it's returned as-is (no envelope).
 */
@Injectable()
export class TimestampInterceptor<T> implements NestInterceptor<T, any> {
  intercept(context: ExecutionContext, next: CallHandler): Observable<any> {
    return next.handle().pipe(
      map((data) => {
        // Only add ts to plain objects (not arrays, strings, numbers)
        if (data && typeof data === 'object' && !Array.isArray(data) && data.constructor === Object) {
          return { ...data, ts: Date.now() };
        }
        // Arrays and primitives are returned as-is
        return data;
      }),
    );
  }
}
