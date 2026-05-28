import { Controller, Get } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

/**
 * HealthController — Lightweight health check endpoint.
 *
 * GET /api/health (no auth required)
 *
 * Used by the Flutter ConnectivityInterceptor (Phase 1 F2)
 * as a lightweight ping instead of failing a real API call.
 *
 * Requirements:
 *  - DB check via Prisma.$queryRaw`SELECT 1`
 *  - process.uptime() for uptime seconds
 *  - process.memoryUsage().heapUsed for MB used
 *  - Must respond in < 50ms always
 *  - Never throw — always return { status: 'error' } on fail
 */
@Controller('health')
export class HealthController {
  constructor(private readonly prisma: PrismaService) {}

  @Get()
  async check() {
    let db: 'ok' | 'error' = 'ok';

    try {
      await this.prisma.$queryRaw`SELECT 1`;
    } catch {
      db = 'error';
    }

    const uptime = Math.floor(process.uptime());
    const memory = parseFloat(
      (process.memoryUsage().heapUsed / 1024 / 1024).toFixed(2),
    );

    return {
      status: db === 'ok' ? ('ok' as const) : ('error' as const),
      db,
      uptime,
      memory,
      ts: Date.now(),
    };
  }
}
