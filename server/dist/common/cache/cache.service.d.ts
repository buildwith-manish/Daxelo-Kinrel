export interface CacheRouteConfig {
    pattern: RegExp;
    ttl: number;
}
export declare class CacheService {
    private readonly logger;
    private readonly cache;
    private readonly maxSize;
    private readonly routeConfigs;
    private readonly noCachePatterns;
    getTtlForKey(routeKey: string): number;
    buildKey(method: string, path: string, userId?: string, params?: Record<string, string>): string;
    get<T = any>(key: string): {
        value: T | undefined;
        hit: boolean;
    };
    set<T = any>(key: string, value: T, ttlSeconds: number): void;
    invalidateByResource(method: string, path: string, userId?: string): number;
    private isRelatedCacheKey;
    flush(): void;
    getStats(): {
        size: number;
        maxSize: number;
    };
    cleanup(): number;
}
