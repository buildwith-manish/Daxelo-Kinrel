import { Module } from '@nestjs/common';
import { ScheduleModule } from '@nestjs/schedule';
import { NotificationsController } from './notifications.controller';
import { NotificationsService } from './notifications.service';
import { NotificationsScheduler } from './notifications.scheduler';
import { UserEngagementService } from './user-engagement.service';
import { FcmModule } from './fcm.module';
import { GatewayModule } from '../gateway/gateway.module';
import { PrismaModule } from '../../prisma/prisma.module';

@Module({
  imports: [
    // ScheduleModule is registered at root level (app.module.ts),
    // but we import FcmModule here so the scheduler can use FcmService.
    FcmModule,
    GatewayModule,
    PrismaModule,
  ],
  controllers: [NotificationsController],
  providers: [NotificationsService, NotificationsScheduler, UserEngagementService],
  exports: [NotificationsService],
})
export class NotificationsModule {}
