import { Global, Module } from '@nestjs/common';
import { AlertingService } from './alerting.service';

/**
 * Global Alerting module.
 *
 * Provides AlertingService globally so any module can inject it
 * without importing AlertingModule explicitly.
 */
@Global()
@Module({
  providers: [AlertingService],
  exports: [AlertingService],
})
export class AlertingModule {}
