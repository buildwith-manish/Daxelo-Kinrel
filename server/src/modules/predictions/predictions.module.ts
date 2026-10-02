// server/src/modules/predictions/predictions.module.ts
//
// NestJS module that wires up the Prediction Battle v1 scheduler.
// The scheduler polls Supabase for rounds that crossed the
// opens_at / reveal_at boundary in the last 15 minutes and dispatches
// FCM + in-app notifications to family members.

import { Module } from '@nestjs/common';
import { PredictionsScheduler } from './predictions.scheduler';
import { PrismaModule } from '../../prisma/prisma.module';
import { FcmModule } from '../notifications/fcm.module';
import { NotificationsModule } from '../notifications/notifications.module';

@Module({
  // FcmModule exports FcmService; NotificationsModule exports
  // NotificationsService. PrismaModule exports PrismaService.
  imports: [PrismaModule, FcmModule, NotificationsModule],
  providers: [PredictionsScheduler],
  exports: [PredictionsScheduler],
})
export class PredictionsModule {}
