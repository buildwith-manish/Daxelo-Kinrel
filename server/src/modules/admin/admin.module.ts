import { Module } from '@nestjs/common';
import { AdminController } from './admin.controller';
import { AdminService } from './admin.service';
import { AnalyticsModule } from '../analytics/analytics.module';
import { PredictionsModule } from '../predictions/predictions.module';

@Module({
  // AnalyticsModule provides ChatAnalyticsService for the analytics
  // query endpoint.
  // PredictionsModule provides PredictionsScheduler for the
  // /admin/predictions/backfill endpoint (manual catch-up pass).
  imports: [AnalyticsModule, PredictionsModule],
  controllers: [AdminController],
  providers: [AdminService],
  exports: [AdminService],
})
export class AdminModule {}
