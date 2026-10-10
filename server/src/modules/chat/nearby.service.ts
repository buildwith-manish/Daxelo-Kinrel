// server/src/modules/chat/nearby.service.ts
//
// DAXELO KINREL — Tier 5 Feature 5.3: People Nearby — Service
//
// Wraps the fn_ping_nearby + fn_get_nearby_users + fn_set_nearby_discovery
// RPCs. The actual Haversine distance computation lives in the SQL RPC
// (so the index on UserLastLocation can be used efficiently). The service
// is a thin passthrough.

import { Injectable, BadRequestException, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class NearbyService {
  private readonly logger = new Logger(NearbyService.name);

  constructor(private readonly prisma: PrismaService) {}

  /// Ping the caller's current location. Silently no-ops when the user
  /// hasn't opted in (nearbyDiscoveryEnabled=false).
  async pingLocation(
    userId: string,
    params: { lat: number; lng: number; accuracyM?: number | null },
  ) {
    return this.callRpc('fn_ping_nearby', [params.lat, params.lng, params.accuracyM ?? null]);
  }

  /// Get nearby users within radiusM of the given point. Honors the
  /// reciprocity rule from Tier 3 Feature 3.5 (lastSeenVisibility='nobody'
  /// → returns bucketed distances instead of exact).
  async getNearbyUsers(
    userId: string,
    params: { lat: number; lng: number; radiusM?: number; limit?: number },
  ) {
    return this.callRpc('fn_get_nearby_users', [
      params.lat,
      params.lng,
      params.radiusM ?? 1000,
      params.limit ?? 50,
    ]);
  }

  /// Opt in/out of nearby discovery. When opting out, deletes the
  /// caller's location row immediately.
  async setDiscoveryEnabled(userId: string, enabled: boolean) {
    return this.callRpc('fn_set_nearby_discovery', [enabled]);
  }

  /// Internal helper — same pattern as GroupAdminService.callRpc.
  private async callRpc(name: string, args: any[]): Promise<any> {
    try {
      const placeholders = args.map((_, i) => `$${i + 1}`).join(', ');
      const sql = `SELECT ${name}(${placeholders}) AS result;`;
      const rows = await this.prisma.$queryRawUnsafe(sql, ...args);
      if (!Array.isArray(rows) || rows.length === 0) return null;
      const raw = (rows[0] as any).result;
      if (raw == null) return null;
      try {
        return typeof raw === 'string' ? JSON.parse(raw) : raw;
      } catch {
        return raw;
      }
    } catch (err: any) {
      this.logger.error(`RPC ${name} failed: ${err?.message}`, err?.stack);
      return { success: false, error: 'rpc_failed', message: err?.message };
    }
  }
}
