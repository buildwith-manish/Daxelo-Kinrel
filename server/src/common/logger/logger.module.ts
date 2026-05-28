import { Global, Module } from '@nestjs/common';
import { LoggerService } from './logger.service';

/**
 * Global Logger module.
 *
 * Provides LoggerService globally so any module can inject it
 * without importing LoggerModule explicitly.
 */
@Global()
@Module({
  providers: [LoggerService],
  exports: [LoggerService],
})
export class LoggerModule {}
