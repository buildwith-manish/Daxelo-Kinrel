import { Module } from '@nestjs/common';
import { CampaignsService } from './campaigns.service';
import { CampaignsScheduler } from './campaigns.scheduler';
import { PrismaModule } from '../prisma/prisma.module';
import { NotificationsModule } from '../notifications/notifications.module';

@Module({
  imports: [PrismaModule, NotificationsModule],
  providers: [CampaignsService, CampaignsScheduler],
  exports: [CampaignsService],
})
export class CampaignsModule {}
