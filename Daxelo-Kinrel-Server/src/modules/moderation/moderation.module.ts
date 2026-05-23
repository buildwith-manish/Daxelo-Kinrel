import { Module } from '@nestjs/common';
import { ModerationController, ModerationAppealController } from './moderation.controller';
import { AdminModerationController } from './admin-moderation.controller';
import { ModerationService } from './moderation.service';

@Module({
  controllers: [ModerationController, ModerationAppealController, AdminModerationController],
  providers: [ModerationService],
  exports: [ModerationService],
})
export class ModerationModule {}
