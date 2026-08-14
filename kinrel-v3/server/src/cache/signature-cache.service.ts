/**
 * Daxelo-Kinrel — Session-only Signature Cache (spec §13.1)
 * ===========================================================
 * In-memory + optional Redis-backed LRU cache for KinshipSignature lookups.
 *
 * Per spec §13.1:
 *   - Key:     "familyId:personAId:personBId"
 *   - Value:   KinshipSignature
 *   - Rules:
 *       • In-memory only. Never persist.
 *       • Targeted invalidation: when Person X is mutated, delete only
 *         cache entries containing X. (spec §13.1 explicit)
 *       • Do NOT flush the entire cache on every graph change.
 *       • LRU eviction after 1,000 entries per family.
 *
 * This service provides TWO backends:
 *   1. In-process LRU (always available) — for single-instance deployments
 *      and for tests.
 *   2. Optional Redis backend — when REDIS_URL is set, the cache becomes
 *      shared across all server instances. Signatures are still considered
 *      session-only (TTL 1 hour); they are NEVER persisted to Postgres.
 */

import { Injectable, OnModuleInit, Logger, Optional } from "@nestjs/common";
import { KinshipSignature, signatureKey } from "../modules/kinship/kinship-signature";

// --- Tiny Redis client wrapper (no dep required; lazy-loaded) -----------
interface RedisLike {
  get(key: string): Promise<string | null>;
  set(key: string, value: string, mode?: string, durationSec?: number): Promise<string>;
  del(...keys: string[]): Promise<number>;
  scan(cursor: number, match: string): Promise<[string, string[]]>;
  disconnect(): Promise<void>;
}

// Minimal Redis client loader — uses 'redis' (node-redis v4) if available.
async function loadRedis(url: string): Promise<RedisLike | null> {
  try {
    // Dynamic import — optional dep. ts-ignore because the package may not be installed.
    // @ts-ignore - 'redis' is an optional peer dependency
    const mod = await import(/* @vite-ignore */ "redis");
    const client = mod.createClient({ url });
    client.on("error", () => { /* swallow */ });
    await client.connect();
    return {
      get: (k) => client.get(k),
      set: (k, v, mode, dur) => mode && dur ? client.set(k, v, { [mode]: dur } as any) : client.set(k, v),
      del: (...ks) => client.del(ks),
      scan: async (cursor, match) => {
        const reply = await (client as any).scan(cursor, { MATCH: match, COUNT: 500 });
        return [reply.cursor.toString(), reply.keys] as [string, string[]];
      },
      disconnect: () => client.disconnect(),
    } as any;
  } catch {
    return null;
  }
}

// --- In-process LRU ----------------------------------------------------
class LRU<K, V> {
  private map = new Map<K, V>();
  constructor(private readonly max: number) {}
  get(key: K): V | undefined {
    const v = this.map.get(key);
    if (v !== undefined) {
      // Refresh recency
      this.map.delete(key);
      this.map.set(key, v);
    }
    return v;
  }
  set(key: K, value: V): void {
    if (this.map.has(key)) this.map.delete(key);
    this.map.set(key, value);
    while (this.map.size > this.max) {
      const oldest = this.map.keys().next().value;
      if (oldest === undefined) break;
      this.map.delete(oldest);
    }
  }
  delete(key: K): void { this.map.delete(key); }
  clear(): void { this.map.clear(); }
  size(): number { return this.map.size; }
  keys(): IterableIterator<K> { return this.map.keys(); }
}

interface CacheEntry {
  signature: KinshipSignature;
  signatureKey: string;
  createdAt: number;
}

const MAX_PER_FAMILY = 1000;          // spec §13.1 — LRU eviction after 1,000 entries per family
const TTL_MS = 60 * 60 * 1000;         // 1 hour session TTL
const KEY_PREFIX = "kinrel:sig:";     // Redis key namespace

@Injectable()
export class SignatureCacheService implements OnModuleInit {
  private readonly logger = new Logger(SignatureCacheService.name);
  private redis: RedisLike | null = null;
  /** Per-family LRU. Map<familyId, LRU<cacheKey, CacheEntry>> */
  private familyLRU = new Map<string, LRU<string, CacheEntry>>();

  async onModuleInit() {
    const redisUrl = process.env.REDIS_URL;
    if (redisUrl) {
      this.redis = await loadRedis(redisUrl);
      if (this.redis) {
        this.logger.log(`Redis signature cache connected: ${redisUrl}`);
      } else {
        this.logger.warn(`Redis requested but client failed to load — falling back to in-process LRU.`);
      }
    } else {
      this.logger.log("REDIS_URL not set — using in-process LRU signature cache.");
    }
  }

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /**
   * Get a cached signature for familyId + personAId + personBId.
   * Returns undefined if not present or expired.
   */
  async get(familyId: string, personAId: string, personBId: string): Promise<KinshipSignature | undefined> {
    const key = this.buildKey(familyId, personAId, personBId);

    if (this.redis) {
      const raw = await this.redis.get(KEY_PREFIX + key);
      if (raw) {
        try {
          const entry: CacheEntry = JSON.parse(raw);
          if (Date.now() - entry.createdAt < TTL_MS) {
            // Mirror into in-process LRU for hotter subsequent reads
            this.lru(familyId).set(key, entry);
            return entry.signature;
          }
        } catch { /* fall through */ }
      }
      return undefined;
    }

    const entry = this.lru(familyId).get(key);
    if (!entry) return undefined;
    if (Date.now() - entry.createdAt > TTL_MS) {
      this.lru(familyId).delete(key);
      return undefined;
    }
    return entry.signature;
  }

  /**
   * Store a signature in the cache. NEVER persists to Postgres.
   */
  async set(familyId: string, personAId: string, personBId: string, sig: KinshipSignature): Promise<void> {
    const key = this.buildKey(familyId, personAId, personBId);
    const entry: CacheEntry = {
      signature: sig,
      signatureKey: signatureKey(sig),
      createdAt: Date.now(),
    };
    this.lru(familyId).set(key, entry);

    if (this.redis) {
      try {
        await this.redis.set(KEY_PREFIX + key, JSON.stringify(entry), "EX", Math.floor(TTL_MS / 1000));
      } catch (e: any) {
        this.logger.warn(`Redis cache write failed: ${e.message}`);
      }
    }
  }

  /**
   * Targeted invalidation — when Person X is mutated, delete only entries
   * containing X. Per spec §13.1: do NOT flush the entire cache.
   */
  async invalidatePerson(familyId: string, personId: string): Promise<number> {
    let removed = 0;
    const lru = this.familyLRU.get(familyId);

    if (lru) {
      const toRemove: string[] = [];
      for (const k of lru.keys()) {
        if (this.keyContainsPerson(k, personId)) toRemove.push(k);
      }
      for (const k of toRemove) {
        lru.delete(k);
        removed += 1;
      }
    }

    if (this.redis) {
      // SCAN matching either A or B position
      const patterns = [
        `${KEY_PREFIX}${familyId}:${personId}:*`,
        `${KEY_PREFIX}${familyId}:*:${personId}`,
      ];
      for (const pattern of patterns) {
        let cursor = 0;
        do {
          const [next, keys] = await this.redis.scan(cursor, pattern);
          cursor = parseInt(next, 10) || 0;
          if (keys.length > 0) {
            removed += await this.redis.del(...keys.map((k) => k));
          }
        } while (cursor !== 0);
      }
    }

    return removed;
  }

  /**
   * Invalidate an entire family (used when a family is deleted).
   */
  async invalidateFamily(familyId: string): Promise<void> {
    this.familyLRU.delete(familyId);
    if (this.redis) {
      let cursor = 0;
      do {
        const [next, keys] = await this.redis.scan(cursor, `${KEY_PREFIX}${familyId}:*`);
        cursor = parseInt(next, 10) || 0;
        if (keys.length > 0) await this.redis.del(...keys);
      } while (cursor !== 0);
    }
  }

  /**
   * Stats — useful for /health endpoint and observability.
   */
  async stats(): Promise<{ engine: string; families: number; totalEntries: number; maxPerFamily: number }> {
    const families = this.familyLRU.size;
    let totalEntries = 0;
    for (const lru of this.familyLRU.values()) totalEntries += lru.size();
    return {
      engine: this.redis ? "redis" : "in-process-lru",
      families,
      totalEntries,
      maxPerFamily: MAX_PER_FAMILY,
    };
  }

  // -------------------------------------------------------------------------
  // Internal helpers
  // -------------------------------------------------------------------------

  private buildKey(familyId: string, personAId: string, personBId: string): string {
    // Use the deterministic A→B ordering — same A/B pair = same key.
    // (The signature itself encodes direction via generationDelta.)
    return `${familyId}:${personAId}:${personBId}`;
  }

  private keyContainsPerson(key: string, personId: string): boolean {
    // key = familyId:personAId:personBId — person could be A or B
    const parts = key.split(":");
    return parts.length === 3 && (parts[1] === personId || parts[2] === personId);
  }

  private lru(familyId: string): LRU<string, CacheEntry> {
    let lru = this.familyLRU.get(familyId);
    if (!lru) {
      lru = new LRU<string, CacheEntry>(MAX_PER_FAMILY);
      this.familyLRU.set(familyId, lru);
    }
    return lru;
  }
}
