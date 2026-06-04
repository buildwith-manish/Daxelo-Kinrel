import {
  ExceptionFilter,
  Catch,
  ArgumentsHost,
  HttpException,
  HttpStatus,
  Logger,
  Optional,
} from '@nestjs/common';
import type { Request, Response } from 'express';
import { AlertingService } from '../alerting/alerting.service';

@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  private readonly logger = new Logger(AllExceptionsFilter.name);

  constructor(@Optional() private readonly alertingService?: AlertingService) {}

  catch(exception: unknown, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    const request = ctx.getRequest<Request>();

    let status = HttpStatus.INTERNAL_SERVER_ERROR;
    let message = 'Internal server error';
    let error = 'InternalServerError';

    if (exception instanceof HttpException) {
      status = exception.getStatus();
      const exceptionResponse = exception.getResponse();

      if (typeof exceptionResponse === 'string') {
        message = exceptionResponse;
      } else if (typeof exceptionResponse === 'object' && exceptionResponse !== null) {
        const resp = exceptionResponse as Record<string, unknown>;
        message = (resp.message as string) || exception.message;
        error = (resp.error as string) || error;

        // Handle class-validator array messages
        if (Array.isArray(resp.message)) {
          message = resp.message.join('; ');
        }
      }
    } else if (exception instanceof Error) {
      message = exception.message;
    }

    // ── Log based on severity ────────────────────────────────────────
    // 404s are common (bots, health checks on wrong paths) — log as warn, not error
    // 4xx client errors are less severe than 5xx server errors
    if (status === HttpStatus.NOT_FOUND) {
      this.logger.warn(`${request.method} ${request.url} — ${status} ${message}`);
    } else if (status >= 500) {
      this.logger.error(
        `${request.method} ${request.url} — ${status} ${message}`,
        exception instanceof Error ? exception.stack : undefined,
      );
    } else {
      this.logger.warn(`${request.method} ${request.url} — ${status} ${message}`);
    }

    // ── Alerting integration ────────────────────────────────────
    // Only alert on server errors (5xx), not client errors (4xx)
    if (this.alertingService && status >= 500) {
      this.alertingService.recordError();
      this.alertingService.checkAlerts(status, request.url);
    }

    response.status(status).json({
      statusCode: status,
      message,
      error,
      timestamp: new Date().toISOString(),
      path: request.url,
    });
  }
}
