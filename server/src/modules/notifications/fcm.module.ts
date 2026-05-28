import { Module } from '@nestjs/common';
import { FcmService } from './fcm.service';

/**
 * FcmModule — Provides Firebase Cloud Messaging service.
 *
 * Imported by NotificationsModule so that the scheduler and
 * controller can inject FcmService for sending push notifications.
 */
@Module({
  providers: [FcmService],
  exports: [FcmService],
})
export class FcmModule {}
