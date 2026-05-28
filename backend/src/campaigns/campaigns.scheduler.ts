import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { CampaignsService } from './campaigns.service';

@Injectable()
export class CampaignsScheduler {
  private readonly logger = new Logger(CampaignsScheduler.name);

  constructor(private campaignsService: CampaignsService) {}

  /**
   * Dormant user campaign: runs daily at 10 AM IST (4:30 UTC)
   * Targets users inactive for 7+ days
   */
  @Cron('30 4 * * *', {
    name: 'dormant-user-campaign',
  })
  async handleDormantUserCampaign() {
    this.logger.log('⏰ Scheduled: Dormant user re-engagement campaign');
    try {
      await this.campaignsService.runDormantUserCampaign();
    } catch (error) {
      this.logger.error(
        `Dormant user campaign failed: ${error instanceof Error ? error.message : String(error)}`,
      );
    }
  }

  /**
   * Almost premium campaign: runs weekly on Monday at 11 AM IST (5:30 UTC)
   * Targets users with 45-49 members
   */
  @Cron('30 5 * * 1', {
    name: 'almost-premium-campaign',
  })
  async handleAlmostPremiumCampaign() {
    this.logger.log('⏰ Scheduled: Almost premium upgrade nudge campaign');
    try {
      await this.campaignsService.runAlmostPremiumCampaign();
    } catch (error) {
      this.logger.error(
        `Almost premium campaign failed: ${error instanceof Error ? error.message : String(error)}`,
      );
    }
  }

  /**
   * Expiring premium campaign: runs daily at 9 AM IST (3:30 UTC)
   * Targets premium users expiring in 3 days
   */
  @Cron('30 3 * * *', {
    name: 'expiring-premium-campaign',
  })
  async handleExpiringPremiumCampaign() {
    this.logger.log('⏰ Scheduled: Expiring premium renewal reminder campaign');
    try {
      await this.campaignsService.runExpiringPremiumCampaign();
    } catch (error) {
      this.logger.error(
        `Expiring premium campaign failed: ${error instanceof Error ? error.message : String(error)}`,
      );
    }
  }
}
