import {
  Injectable,
  OnModuleInit,
  OnModuleDestroy,
  Logger,
} from '@nestjs/common';
import { PrismaClient } from '@prisma/client';

/**
 * PrismaService — Wraps PrismaClient as a NestJS injectable service.
 *
 * Lifecycle:
 *  - onModuleInit: connects to the database (gracefully handles missing DB)
 *  - onModuleDestroy: gracefully disconnects
 *
 * If DATABASE_URL is a placeholder or the database is unreachable,
 * the service logs a warning but doesn't crash the application.
 * This allows the health endpoint and other non-DB features to work
 * during initial deployment before all env vars are configured.
 */
@Injectable()
export class PrismaService
  extends PrismaClient
  implements OnModuleInit, OnModuleDestroy
{
  private readonly logger = new Logger(PrismaService.name);
  private isConnected = false;
  private _connectionFailed = false;

  constructor() {
    super({
      datasources: {
        db: {
          url: process.env.DATABASE_URL,
        },
      },
      log: [
        { emit: 'event', level: 'query' },
        // Use 'event' for all levels so we control what gets logged
        // and can suppress noise when DB is unreachable
        { emit: 'event', level: 'info' },
        { emit: 'event', level: 'warn' },
        { emit: 'event', level: 'error' },
      ],
    });

    // ── Route Prisma log events through our logger with filtering ──
    (this as any).$on('info', (event: any) => {
      // Suppress connection pool spam when DB is unreachable
      if (this._connectionFailed) return;
      this.logger.verbose(event.message);
    });

    (this as any).$on('warn', (event: any) => {
      this.logger.verbose(`Prisma warn: ${event.message}`);
    });

    (this as any).$on('error', (event: any) => {
      // Suppress "Can't reach database server" errors — we already know
      // from the connection check. Don't spam the logs every 5 seconds.
      if (
        event.message?.includes("Can't reach database server") ||
        event.message?.includes('localhost:5432') ||
        event.message?.includes('ECONNREFUSED')
      ) {
        // Log once at verbose level, not every health check
        this.logger.verbose(`DB unreachable: ${event.message}`);
        return;
      }
      this.logger.error(`Prisma error: ${event.message}`);
    });
  }

  async onModuleInit() {
    try {
      // In development, log all SQL queries with execution time
      if (process.env.NODE_ENV === 'development') {
        (this as any).$on('query', (event: any) => {
          this.logger.debug(
            `Query: ${event.query} — Params: ${event.params} — Duration: ${event.duration}ms`,
          );
        });
      }

      // Log slow queries (>100ms) in ALL environments to catch regressions
      (this as any).$on('query', (event: any) => {
        if (event.duration > 100) {
          this.logger.warn(
            `Slow query (${event.duration}ms): ${event.query}`,
          );
        }
      });

      await this.$connect();
      this.isConnected = true;
      this.logger.log('📦 Database connected successfully');
      if (process.env.NODE_ENV === 'production') {
        this.logger.log(`Connection pool: DATABASE_URL includes ${process.env.DATABASE_URL?.includes('connection_limit') ? 'explicit' : 'default'} connection_limit`);
      }
    } catch (error) {
      this._connectionFailed = true;
      this.logger.verbose(
        '📦 Database connection failed — app will start but DB features will be unavailable.',
      );
      this.logger.verbose(
        'Set DATABASE_URL to a valid PostgreSQL connection string.',
      );
    }
  }

  async onModuleDestroy() {
    if (this.isConnected) {
      await this.$disconnect();
      this.logger.log('📦 Database disconnected');
    }
  }

  /**
   * Quick check if DB is connected — used by health endpoint
   * to avoid attempting a query (which logs Prisma errors) when
   * we already know the DB is unreachable.
   */
  get connected(): boolean {
    return this.isConnected;
  }

  get connectionFailed(): boolean {
    return this._connectionFailed;
  }
}
