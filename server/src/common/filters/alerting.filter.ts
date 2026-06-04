import {
  ExceptionFilter,
  Catch,
  ArgumentsHost,
  HttpException,
  HttpStatus,
} from '@nestjs/common';
import type { Request } from 'express';
import { AlertingService } from '../alerting/alerting.service';

/**
 * Alerting filter — tracks errors and triggers alerts.
 *
 * This filter sits alongside the existing AllExceptionsFilter.
 * It does NOT produce HTTP responses — it only monitors and alerts.
 *
 * - Records every error in the AlertingService sliding window
 * - Calls checkAlerts() on every error to evaluate alert thresholds
 * - Does NOT interfere with the AllExceptionsFilter's response handling
 *
 * NOTE: In NestJS, only the first matching global exception filter runs.
 * This filter is provided via APP_FILTER with a lower priority so it runs
 * BEFORE AllExceptionsFilter. However, since exception filters don't chain
 * in NestJS, we integrate alerting into the AllExceptionsFilter instead.
 * This file is kept as a standalone class for manual use or testing.
 */
@Catch()
export class AlertingFilter implements ExceptionFilter {
  constructor(private readonly alertingService: AlertingService) {}

  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const request = ctx.getRequest<Request>();

    let statusCode = HttpStatus.INTERNAL_SERVER_ERROR;
    if (exception instanceof HttpException) {
      statusCode = exception.getStatus();
    }

    // Record this error in the sliding window
    this.alertingService.recordError();

    // Check alert conditions
    this.alertingService.checkAlerts(statusCode, request.url);
  }
}
