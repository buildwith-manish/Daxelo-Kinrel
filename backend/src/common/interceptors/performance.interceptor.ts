import {
  Injectable,
  NestInterceptor,
  ExecutionContext,
  CallHandler,
  Logger,
} from '@nestjs/common';
import { Observable } from 'rxjs';
import { tap } from 'rxjs/operators';

@Injectable()
export class PerformanceInterceptor implements NestInterceptor {
  private readonly logger = new Logger('Performance');

  intercept(context: ExecutionContext, next: CallHandler): Observable<any> {
    const request = context.switchToHttp().getRequest();
    const method = request.method;
    const url = request.url;
    const userId = request.user?.id ?? 'anonymous';
    const startTime = Date.now();

    return next.handle().pipe(
      tap({
        next: () => {
          const duration = Date.now() - startTime;
          const logData = { method, url, userId, duration: `${duration}ms` };

          if (duration > 2000) {
            // Critical: >2s response time
            this.logger.error(
              `CRITICAL SLOW REQUEST: ${method} ${url} took ${duration}ms (user: ${userId})`,
            );
          } else if (duration > 500) {
            // Warning: >500ms response time
            this.logger.warn(
              `Slow request: ${method} ${url} took ${duration}ms (user: ${userId})`,
            );
          } else {
            this.logger.log(
              `${method} ${url} — ${duration}ms (user: ${userId})`,
            );
          }
        },
        error: (error) => {
          const duration = Date.now() - startTime;
          this.logger.error(
            `${method} ${url} FAILED after ${duration}ms (user: ${userId}): ${error.message}`,
          );
        },
      }),
    );
  }
}
