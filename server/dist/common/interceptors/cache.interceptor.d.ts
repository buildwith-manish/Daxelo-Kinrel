import { NestInterceptor, ExecutionContext, CallHandler } from '@nestjs/common';
import { Observable } from 'rxjs';
import { CacheService } from '../cache/cache.service';
export declare class CacheInterceptor implements NestInterceptor {
    private readonly logger;
    private readonly customTtl?;
    private readonly cacheService;
    constructor(options?: {
        ttl?: number;
        cacheService?: CacheService;
    });
    intercept(context: ExecutionContext, next: CallHandler): Observable<any>;
}
