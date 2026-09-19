import { Module } from '@nestjs/common';
import { ChatAnalyticsService } from './chat-analytics.service';
import { PrismaModule } from '../../prisma/prisma.module';

@Module({
  // PrismaModule is global, but importing it explicitly here makes the
  // dependency clear and lets this module be tested in isolation.
  imports: [PrismaModule],
  providers: [ChatAnalyticsService],
  exports: [ChatAnalyticsService],
})
export class AnalyticsModule {}
