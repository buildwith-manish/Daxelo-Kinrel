"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
var CacheInterceptor_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.CacheInterceptor = void 0;
const common_1 = require("@nestjs/common");
const rxjs_1 = require("rxjs");
const cache_service_1 = require("../cache/cache.service");
let CacheInterceptor = CacheInterceptor_1 = class CacheInterceptor {
    constructor(options) {
        this.logger = new common_1.Logger(CacheInterceptor_1.name);
        this.customTtl = options?.ttl;
        this.cacheService = options?.cacheService ?? new cache_service_1.CacheService();
    }
    intercept(context, next) {
        const request = context.switchToHttp().getRequest();
        const response = context.switchToHttp().getResponse();
        const method = request.method.toUpperCase();
        const url = request.url;
        const userId = request.user?.id;
        const params = request.params ?? {};
        const cacheKey = this.cacheService.buildKey(method, url, userId, params);
        if (['POST', 'PUT', 'DELETE', 'PATCH'].includes(method)) {
            return next.handle().pipe((0, rxjs_1.tap)(() => {
                this.cacheService.invalidateByResource(method, url, userId);
            }));
        }
        if (method !== 'GET') {
            response.setHeader('X-Cache', 'MISS');
            return next.handle();
        }
        const ttl = this.customTtl ?? this.cacheService.getTtlForKey(cacheKey);
        if (ttl <= 0) {
            response.setHeader('X-Cache', 'MISS');
            return next.handle();
        }
        const { value, hit } = this.cacheService.get(cacheKey);
        if (hit && value !== undefined) {
            response.setHeader('X-Cache', 'HIT');
            this.logger.debug(`Cache HIT: ${cacheKey}`);
            return (0, rxjs_1.of)(value);
        }
        response.setHeader('X-Cache', 'MISS');
        this.logger.debug(`Cache MISS: ${cacheKey}`);
        return next.handle().pipe((0, rxjs_1.tap)((data) => {
            if (response.statusCode >= 200 && response.statusCode < 300) {
                this.cacheService.set(cacheKey, data, ttl);
            }
        }));
    }
};
exports.CacheInterceptor = CacheInterceptor;
exports.CacheInterceptor = CacheInterceptor = CacheInterceptor_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [Object])
], CacheInterceptor);
//# sourceMappingURL=cache.interceptor.js.map