import { Module } from '@nestjs/common';
import { ScheduleModule } from '@nestjs/schedule';
import { PrismaModule } from '../prisma/prisma.module';
import { NotificationsController } from './notifications.controller';
import { NotificationsService } from './notifications.service';
import { FcmService } from './fcm.service';
import { BirthdayScheduler } from './birthday.scheduler';

@Module({
  imports: [PrismaModule, ScheduleModule.forRoot()],
  controllers: [NotificationsController],
  providers: [NotificationsService, FcmService, BirthdayScheduler],
  exports: [NotificationsService, FcmService],
})
export class NotificationsModule {}
