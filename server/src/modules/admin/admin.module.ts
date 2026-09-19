import { Module } from '@nestjs/common';
import { AdminController } from './admin.controller';
import { AdminService } from './admin.service';
import { AnalyticsModule } from '../analytics/analytics.module';

@Module({
  // AnalyticsModule provides ChatAnalyticsService for the analytics
  // query endpoint.
  imports: [AnalyticsModule],
  controllers: [AdminController],
  providers: [AdminService],
  exports: [AdminService],
})
export class AdminModule {}
