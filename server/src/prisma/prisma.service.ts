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
 *  - onModuleInit: connects to the database
 *  - onModuleDestroy: gracefully disconnects
 *
 * In development mode, all SQL queries are logged to stdout
 * for easier debugging.
 */
@Injectable()
export class PrismaService
  extends PrismaClient
  implements OnModuleInit, OnModuleDestroy
{
  private readonly logger = new Logger(PrismaService.name);

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
    this.logger.log('📦 Database connected');
  }

  async onModuleDestroy() {
    await this.$disconnect();
    this.logger.log('📦 Database disconnected');
  }
}
