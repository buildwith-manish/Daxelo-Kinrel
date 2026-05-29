"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var CacheService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.CacheService = void 0;
const common_1 = require("@nestjs/common");
let CacheService = CacheService_1 = class CacheService {
    constructor() {
        this.logger = new common_1.Logger(CacheService_1.name);
        this.cache = new Map();
        this.maxSize = 500;
        this.routeConfigs = [
            { pattern: /^GET\/api\/family\/[^/]+$/, ttl: 60 },
            { pattern: /^GET\/api\/families\/[^/]+\/persons/, ttl: 30 },
            { pattern: /^GET\/api\/v1\/kinship/, ttl: 3600 },
            { pattern: /^GET\/api\/users\/me/, ttl: 30 },
            { pattern: /^GET\/api\/families\/[^/]+\/timeline/, ttl: 60 },
        ];
        this.noCachePatterns = [
            /\/api\/auth\//,
            /\/api\/payments\//,
            /\/api\/.*\/upload/,
            /\/api\/.*\/avatar/,
        ];
    }
    getTtlForKey(routeKey) {
        for (const pattern of this.noCachePatterns) {
            if (pattern.test(routeKey)) {
                return 0;
            }
        }
        if (!routeKey.startsWith('GET')) {
            return 0;
        }
        for (const config of this.routeConfigs) {
            if (config.pattern.test(routeKey)) {
                return config.ttl;
            }
        }
        return 0;
    }
    buildKey(method, path, userId, params) {
        const paramSuffix = params && Object.keys(params).length > 0
            ? ':' + Object.entries(params).sort(([a], [b]) => a.localeCompare(b)).map(([k, v]) => `${k}=${v}`).join('&')
            : '';
        const userSuffix = userId ? `:${userId}` : ':anonymous';
        return `${method.toUpperCase()}${path}${userSuffix}${paramSuffix}`;
    }
    get(key) {
        const entry = this.cache.get(key);
        if (!entry) {
            return { value: undefined, hit: false };
        }
        const now = Date.now();
        if (now >= entry.expiresAt) {
            this.cache.delete(key);
            return { value: undefined, hit: false };
        }
        this.cache.delete(key);
        this.cache.set(key, entry);
        return { value: entry.value, hit: true };
    }
    set(key, value, ttlSeconds) {
        while (this.cache.size >= this.maxSize) {
            const oldestKey = this.cache.keys().next().value;
            if (oldestKey !== undefined) {
                this.cache.delete(oldestKey);
            }
        }
        this.cache.set(key, {
            value,
            expiresAt: Date.now() + ttlSeconds * 1000,
            createdAt: Date.now(),
        });
    }
    invalidateByResource(method, path, userId) {
        let invalidated = 0;
        const resourcePath = path;
        for (const key of this.cache.keys()) {
            if (this.isRelatedCacheKey(key, resourcePath)) {
                this.cache.delete(key);
                invalidated++;
            }
        }
        if (invalidated > 0) {
            this.logger.debug(`Invalidated ${invalidated} cache entries for ${method} ${path}`);
        }
        return invalidated;
    }
    isRelatedCacheKey(cacheKey, mutatedPath) {
        const methodEndIdx = cacheKey.indexOf('/');
        if (methodEndIdx === -1)
            return false;
        const keyWithoutMethod = cacheKey.substring(methodEndIdx);
        const colonIdx = keyWithoutMethod.indexOf(':');
        const keyPath = colonIdx === -1 ? keyWithoutMethod : keyWithoutMethod.substring(0, colonIdx);
        if (keyPath.startsWith(mutatedPath))
            return true;
        const basePath = mutatedPath.split('/persons')[0].split('/timeline')[0];
        if (keyPath.startsWith(basePath))
            return true;
        return false;
    }
    flush() {
        this.cache.clear();
        this.logger.log('Cache flushed');
    }
    getStats() {
        return {
            size: this.cache.size,
            maxSize: this.maxSize,
        };
    }
    cleanup() {
        const now = Date.now();
        let cleaned = 0;
        for (const [key, entry] of this.cache.entries()) {
            if (now >= entry.expiresAt) {
                this.cache.delete(key);
                cleaned++;
            }
        }
        if (cleaned > 0) {
            this.logger.debug(`Cleaned up ${cleaned} expired cache entries`);
        }
        return cleaned;
    }
};
exports.CacheService = CacheService;
exports.CacheService = CacheService = CacheService_1 = __decorate([
    (0, common_1.Injectable)()
], CacheService);
//# sourceMappingURL=cache.service.js.map