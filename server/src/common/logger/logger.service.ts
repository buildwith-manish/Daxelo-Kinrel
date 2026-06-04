import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as winston from 'winston';
import DailyRotateFile from 'winston-daily-rotate-file';

/**
 * Structured logging service built on Winston.
 *
 * Implements the NestJS LoggerService interface so it can be used with
 * app.useLogger() for framework-level logging.
 *
 * - JSON format in production, pretty-print in development
 * - Structured fields: timestamp, level, userId, route, method, duration, statusCode, correlationId
 * - Console transport (colorized in dev, JSON in prod)
 * - Daily rotate file: logs/app-%DATE%.log (14-day retention, 20MB max)
 * - Error-only file: logs/error-%DATE%.log (30-day retention)
 */
@Injectable()
export class LoggerService {
  private readonly winston: winston.Logger;

  constructor(private readonly configService: ConfigService) {
    const isDev = configService.get<string>('NODE_ENV', 'development') !== 'production';
    const logLevel = configService.get<string>('LOG_LEVEL', 'info');
    const logDir = configService.get<string>('LOG_DIR', 'logs');

    // ── Custom log levels ──────────────────────────────────────
    const levels: winston.config.AbstractConfigSetLevels = {
      error: 0,
      warn: 1,
      info: 2,
      http: 3,
      debug: 4,
      verbose: 5,
    };

    // ── Transports ─────────────────────────────────────────────
    const transports: winston.transport[] = [];

    // Console transport — colorized in dev, JSON in prod
    transports.push(
      new winston.transports.Console({
        level: logLevel,
        format: isDev
          ? winston.format.combine(
              winston.format.colorize({ all: true }),
              winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
              winston.format.printf(({ timestamp, level, message, ...meta }) => {
                const context = meta.context || '';
                const ctx = context ? ` [${context}]` : '';
                const metaStr = Object.keys(meta).length > 1 // >1 because 'context' is already shown
                  ? ` ${JSON.stringify(
                      Object.fromEntries(
                        Object.entries(meta).filter(([k]) => k !== 'context'),
                      ),
                    )}`
                  : '';
                return `${timestamp}${ctx} ${level}: ${message}${metaStr}`;
              }),
            )
          : winston.format.combine(
              winston.format.timestamp(),
              winston.format.json(),
            ),
      }),
    );

    // File transports — only in development / when log dir is writable
    // In production containers (Render, Docker), logs go to stdout which
    // the platform captures. Writing to a logs/ dir inside a container is
    // ephemeral and may fail due to filesystem permissions.
    if (isDev) {
      transports.push(
        new DailyRotateFile({
          dirname: logDir,
          filename: 'app-%DATE%.log',
          datePattern: 'YYYY-MM-DD',
          zippedArchive: true,
          maxSize: '20m',
          maxFiles: '14d',
          level: logLevel,
          format: winston.format.combine(
            winston.format.timestamp(),
            winston.format.json(),
          ),
        }),
      );

      transports.push(
        new DailyRotateFile({
          dirname: logDir,
          filename: 'error-%DATE%.log',
          datePattern: 'YYYY-MM-DD',
          zippedArchive: true,
          maxSize: '20m',
          maxFiles: '30d',
          level: 'error',
          format: winston.format.combine(
            winston.format.timestamp(),
            winston.format.json(),
          ),
        }),
      );
    }

    // ── Create Winston logger ──────────────────────────────────
    this.winston = winston.createLogger({
      levels,
      level: logLevel,
      defaultMeta: { service: 'daxelo-kinrel' },
      transports,
      exitOnError: false,
    });
  }

  // ── NestJS LoggerService interface methods ────────────────────

  log(message: string, context?: string): void {
    this.winston.info(message, { context });
  }

  error(message: string, trace?: string, context?: string): void {
    this.winston.error(message, { context, trace });
  }

  warn(message: string, context?: string): void {
    this.winston.warn(message, { context });
  }

  debug(message: string, context?: string): void {
    this.winston.debug(message, { context });
  }

  verbose(message: string, context?: string): void {
    this.winston.verbose(message, { context });
  }

  // ── Structured request logging ────────────────────────────────

  /**
   * Log an HTTP request with structured fields.
   */
  logRequest(
    req: { method: string; url: string; userId?: string; correlationId?: string },
    res: { statusCode: number },
    duration: number,
  ): void {
    const meta: Record<string, unknown> = {
      method: req.method,
      route: req.url,
      statusCode: res.statusCode,
      duration,
      userId: req.userId || undefined,
      correlationId: req.correlationId || undefined,
    };

    if (res.statusCode >= 500) {
      this.winston.error(
        `${req.method} ${req.url} ${res.statusCode} — ${duration}ms`,
        meta,
      );
    } else if (res.statusCode >= 400) {
      this.winston.warn(
        `${req.method} ${req.url} ${res.statusCode} — ${duration}ms`,
        meta,
      );
    } else if (duration > 500) {
      this.winston.warn(
        `SLOW ${req.method} ${req.url} ${res.statusCode} — ${duration}ms`,
        meta,
      );
    } else {
      this.winston.info(
        `${req.method} ${req.url} ${res.statusCode} — ${duration}ms`,
        meta,
      );
    }
  }

  // ── Structured error logging ──────────────────────────────────

  /**
   * Log an error with structured fields including stack trace.
   */
  logError(error: Error | unknown, context?: string): void {
    if (error instanceof Error) {
      this.winston.error(error.message, {
        context,
        stack: error.stack,
        errorName: error.name,
      });
    } else {
      this.winston.error(String(error), { context });
    }
  }

  // ── Alert logging (for alerting filter integration) ───────────

  /**
   * Log an alert — structured log that can be connected to
   * Logtail, Datadog, PagerDuty, etc. later.
   */
  logAlert(alertType: string, message: string, meta?: Record<string, unknown>): void {
    this.winston.error(`[ALERT][${alertType}] ${message}`, {
      alert: true,
      alertType,
      ...meta,
    });
  }
}
