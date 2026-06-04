import { Module } from '@nestjs/common';
import { ScheduleModule } from '@nestjs/schedule';
import { NotificationsController } from './notifications.controller';
import { NotificationsService } from './notifications.service';
import { NotificationsScheduler } from './notifications.scheduler';
import { NotificationsV2Controller } from './notifications-v2.controller';
import { NotificationsV2Service } from './notifications-v2.service';
import { FcmModule } from './fcm.module';

@Module({
  imports: [
    // ScheduleModule is registered at root level (app.module.ts),
    // but we import FcmModule here so the scheduler can use FcmService.
    FcmModule,
  ],
  controllers: [NotificationsController, NotificationsV2Controller],
  providers: [NotificationsService, NotificationsScheduler, NotificationsV2Service],
  exports: [NotificationsService, NotificationsV2Service],
})
export class NotificationsModule {}
