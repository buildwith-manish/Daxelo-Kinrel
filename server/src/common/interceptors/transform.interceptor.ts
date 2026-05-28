import {
  Injectable,
  NestInterceptor,
  ExecutionContext,
  CallHandler,
} from '@nestjs/common';
import { Observable } from 'rxjs';
import { tap } from 'rxjs/operators';

/**
 * Pass-through interceptor — does NOT wrap responses in an envelope.
 *
 * This is CRITICAL for Flutter API compatibility: the Flutter Dio client
 * expects flat JSON responses like { user: {...} }, not { data: { user: {...} } }.
 *
 * Adds:
 * - X-Response-Time header (ms)
 *
 * NOTE: Request ID and logging logic has been moved to LoggingInterceptor.
 * LoggingInterceptor now adds X-Correlation-Id for distributed tracing
 * and handles structured request logging.
 */
@Injectable()
export class TransformInterceptor<T> implements NestInterceptor<T, T> {
  intercept(context: ExecutionContext, next: CallHandler): Observable<T> {
    const response = context.switchToHttp().getResponse();
    const startTime = Date.now();

    return next.handle().pipe(
      tap({
        next: () => {
          const responseTime = Date.now() - startTime;
          response.setHeader('X-Response-Time', `${responseTime}ms`);
        },
        error: () => {
          const responseTime = Date.now() - startTime;
          response.setHeader('X-Response-Time', `${responseTime}ms`);
        },
      }),
    );
  }
}
