import { Module } from '@nestjs/common';
import { ScheduleModule } from '@nestjs/schedule';
import { NotificationsController } from './notifications.controller';
import { NotificationsService } from './notifications.service';
import { NotificationsScheduler } from './notifications.scheduler';
import { FcmModule } from './fcm.module';

@Module({
  imports: [
    // ScheduleModule is registered at root level (app.module.ts),
    // but we import FcmModule here so the scheduler can use FcmService.
    FcmModule,
  ],
  controllers: [NotificationsController],
  providers: [NotificationsService, NotificationsScheduler],
  exports: [NotificationsService],
})
export class NotificationsModule {}
