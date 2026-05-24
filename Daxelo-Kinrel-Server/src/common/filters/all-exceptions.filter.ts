import {
  ExceptionFilter,
  Catch,
  ArgumentsHost,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import type { Request, Response } from 'express';
import { v4 as uuidv4 } from 'uuid';

interface StandardErrorResponse {
  error: {
    code: string;
    message: string;
    details?: any;
  };
  meta: {
    requestId: string;
    timestamp: string;
    version: string;
  };
}

@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  private readonly logger = new Logger(AllExceptionsFilter.name);
  private readonly version = '1.0.0';

  catch(exception: unknown, host: ArgumentsHost): void {
    const httpCtx = host.switchToHttp();
    const response = httpCtx.getResponse<Response>();
    const request = httpCtx.getRequest<Request>();

    const requestId = (request.headers['x-request-id'] as string) || uuidv4();
    const timestamp = new Date().toISOString();

    let status = HttpStatus.INTERNAL_SERVER_ERROR;
    let code = 'INTERNAL_SERVER_ERROR';
    let message = 'An unexpected error occurred';
    let details: any = undefined;

    if (exception instanceof HttpException) {
      status = exception.getStatus();
      const exceptionResponse = exception.getResponse();

      if (typeof exceptionResponse === 'string') {
        message = exceptionResponse;
      } else if (typeof exceptionResponse === 'object') {
        const resp = exceptionResponse as Record<string, any>;
        message = resp.message || exception.message;
        code = resp.error || exception.name;

        // Handle class-validator validation errors
        if (Array.isArray(resp.message)) {
          details = resp.message;
          message = 'Validation failed';
          code = 'VALIDATION_ERROR';
        }
      }

      // Generate appropriate error code from status
      if (status === HttpStatus.UNAUTHORIZED) code = 'UNAUTHORIZED';
      if (status === HttpStatus.FORBIDDEN) code = 'FORBIDDEN';
      if (status === HttpStatus.NOT_FOUND) code = 'NOT_FOUND';
      if (status === HttpStatus.CONFLICT) code = 'CONFLICT';
      if (status === HttpStatus.BAD_REQUEST) code = 'BAD_REQUEST';
      if (status === HttpStatus.TOO_MANY_REQUESTS) code = 'RATE_LIMITED';
    } else if (exception instanceof Error) {
      message = exception.message;
      this.logger.error(
        `Unhandled exception: ${exception.message}`,
        exception.stack,
      );
    }

    const errorResponse: StandardErrorResponse = {
      error: {
        code,
        message,
        ...(details ? { details } : {}),
      },
      meta: {
        requestId,
        timestamp,
        version: this.version,
      },
    };

    response.status(status).json(errorResponse);
  }
}
