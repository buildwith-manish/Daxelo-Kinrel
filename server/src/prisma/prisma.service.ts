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

  constructor() {
    super({
      log: [
        { emit: 'event', level: 'query' },
        { emit: 'stdout', level: 'info' },
        { emit: 'stdout', level: 'warn' },
        { emit: 'stdout', level: 'error' },
      ],
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
      this.logger.log('📦 Database connected');
    } catch (error) {
      this.logger.warn(
        '📦 Database connection failed — app will start but DB features will be unavailable.',
      );
      this.logger.warn(
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
}
