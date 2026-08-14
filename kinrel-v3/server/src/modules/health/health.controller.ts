/**
 * Daxelo-Kinrel — Health & Observability Controller
 * ===================================================
 *   GET /health              liveness probe
 *   GET /health/cache        signature cache stats (spec §13.1)
 *   GET /health/db           database connectivity
 */
import { Controller, Get } from "@nestjs/common";
import { SignatureCacheService } from "../../cache/signature-cache.service";
import { PrismaService } from "../../prisma/prisma.service";

@Controller("health")
export class HealthController {
  constructor(
    private readonly cache: SignatureCacheService,
    private readonly prisma: PrismaService,
  ) {}

  @Get()
  async liveness() {
    return { ok: true, service: "daxelo-kinrel", version: "3.1.0", timestamp: Date.now() };
  }

  @Get("cache")
  async cacheStats() {
    return this.cache.stats();
  }

  @Get("db")
  async db() {
    try {
      await this.prisma.$queryRaw`SELECT 1`;
      return { ok: true, engine: "postgres" };
    } catch (e: any) {
      return { ok: false, error: e.message };
    }
  }
}
