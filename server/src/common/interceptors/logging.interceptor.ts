import {
  Injectable,
  NestInterceptor,
  ExecutionContext,
  CallHandler,
  Optional,
} from '@nestjs/common';
import { Observable } from 'rxjs';
import { tap } from 'rxjs/operators';
import { v4 as uuidv4 } from 'uuid';
import type { Request, Response } from 'express';
import { LoggerService } from '../logger/logger.service';
import { AlertingService } from '../alerting/alerting.service';

/**
 * Logging interceptor — structured request logging with correlation IDs.
 *
 * Responsibilities:
 * - Adds X-Correlation-Id header to every response (for distributed tracing)
 * - Logs every HTTP request with structured fields: method, url, userId, duration, statusCode
 * - Logs slow requests (>500ms) with WARN level
 * - Logs error responses (4xx, 5xx) with ERROR/WARN level
 * - Records request metrics in AlertingService (for error rate & p99 monitoring)
 *
 * This replaces the request ID and logging logic previously in TransformInterceptor.
 * TransformInterceptor now only handles X-Response-Time.
 */
@Injectable()
export class LoggingInterceptor implements NestInterceptor {
  constructor(
    private readonly loggerService: LoggerService,
    @Optional() private readonly alertingService?: AlertingService,
  ) {}

  intercept(context: ExecutionContext, next: CallHandler): Observable<any> {
    const request = context.switchToHttp().getRequest<Request>();
    const response = context.switchToHttp().getResponse<Response>();

    const correlationId = (request.headers['x-correlation-id'] as string) || uuidv4();
    const startTime = Date.now();

    // Attach correlation ID to response headers
    response.setHeader('X-Correlation-Id', correlationId);

    // Extract userId if available (set by auth guard)
    const userId = (request as any).user?.id || (request.headers['x-user-id'] as string) || undefined;

    return next.handle().pipe(
      tap({
        next: () => {
          const duration = Date.now() - startTime;
          this.loggerService.logRequest(
            {
              method: request.method,
              url: request.url,
              userId,
              correlationId,
            },
            { statusCode: response.statusCode },
            duration,
          );

          // Record successful request for alerting metrics
          if (this.alertingService) {
            const isError = response.statusCode >= 400;
            this.alertingService.recordRequest(duration, isError);
          }
        },
        error: () => {
          const duration = Date.now() - startTime;
          // For error responses, we log with the response status if available
          // The AllExceptionsFilter will set the status code on the response
          const statusCode = response.statusCode || 500;
          this.loggerService.logRequest(
            {
              method: request.method,
              url: request.url,
              userId,
              correlationId,
            },
            { statusCode },
            duration,
          );

          // Record failed request for alerting metrics
          if (this.alertingService) {
            this.alertingService.recordRequest(duration, true);
          }
        },
      }),
    );
  }
}
