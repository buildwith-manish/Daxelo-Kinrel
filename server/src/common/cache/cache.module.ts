import { Global, Module } from '@nestjs/common';
import { CacheService } from './cache.service';

/**
 * CacheModule — Global module that provides the CacheService
 * to every other module in the application.
 *
 * The CacheService is a singleton in-memory LRU cache that can be
 * injected anywhere. The CacheInterceptor uses this service.
 */
@Global()
@Module({
  providers: [CacheService],
  exports: [CacheService],
})
export class CacheModule {}
