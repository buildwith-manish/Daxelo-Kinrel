import { Controller, Get } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { ConfigService } from '@nestjs/config';
import Redis from 'ioredis';
import { PrismaService } from '../prisma/prisma.service';
import { Public } from '../common/decorators/public.decorator';

/**
 * HealthController — Lightweight health check endpoint.
 *
 * GET /api/health → JSON health status (no auth required)
 *
 * Used by the Flutter ConnectivityInterceptor (Phase 1 F2)
 * as a lightweight ping instead of failing a real API call.
 *
 * Requirements:
 *  - DB check via Prisma.$queryRaw`SELECT 1` (only if connected)
 *  - Redis check via PING command
 *  - process.uptime() for uptime seconds
 *  - process.memoryUsage().heapUsed for MB used
 *  - Must respond in < 50ms always
 *  - Never throw — always return { status: 'error' } on fail
 */
@ApiTags('Health')
@Public()
@Controller('health')
export class HealthController {
  private redis: Redis | null = null;

  constructor(
    private readonly prisma: PrismaService,
    private readonly configService: ConfigService,
  ) {
    // Only create a Redis client when REDIS_URL is explicitly configured
    // Redis is optional — the app works fine without it (graceful degradation)
    const redisUrl = this.configService.get<string>('REDIS_URL');
    if (redisUrl && redisUrl !== 'redis://localhost:6379') {
      try {
        this.redis = new Redis(redisUrl, {
          lazyConnect: true,
          maxRetriesPerRequest: 1,
          connectTimeout: 3000,
          retryStrategy: () => null, // Don't retry on failure
        });

        this.redis.on('error', (err) => {
          if (err.message?.includes('ECONNREFUSED') || err.message?.includes('AggregateError')) {
            if (this.redis) {
              this.redis.disconnect();
              this.redis = null;
            }
          }
        });

        this.redis.connect().catch(() => {
          this.redis = null;
        });
      } catch {
        this.redis = null;
      }
    }
  }

  @Get()
  async check() {
    let db: 'ok' | 'error' = 'ok';
    let redis: 'ok' | 'error' | 'skipped' = 'ok';

    // ── DB check ────────────────────────────────────────────────────
    if (this.prisma.connectionFailed) {
      db = 'error';
    } else if (this.prisma.connected) {
      try {
        await this.prisma.$queryRaw`SELECT 1`;
      } catch {
        db = 'error';
      }
    } else {
      // Not yet connected and not known-failed — try once
      try {
        await this.prisma.$queryRaw`SELECT 1`;
      } catch {
        db = 'error';
      }
    }

    // ── Redis check (optional) ─────────────────────────────────────────
    const redisUrl = this.configService.get<string>('REDIS_URL');
    if (this.redis) {
      try {
        const result = await this.redis.ping();
        if (result !== 'PONG') {
          redis = 'error';
        }
      } catch {
        redis = 'error';
      }
    } else if (!redisUrl || redisUrl === 'redis://localhost:6379') {
      // Redis not configured — this is fine, mark as 'skipped'
      redis = 'skipped';
    } else {
      redis = 'error';
    }

    const uptime = Math.floor(process.uptime());
    const memory = parseFloat(
      (process.memoryUsage().heapUsed / 1024 / 1024).toFixed(2),
    );

    const isOk = db === 'ok' && (redis === 'ok' || redis === 'skipped');

    return {
      status: isOk ? ('ok' as const) : ('error' as const),
      db,
      redis,
      uptime,
      memory,
      ts: Date.now(),
    };
  }
}
