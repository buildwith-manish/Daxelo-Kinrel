import { Module } from '@nestjs/common';
import { CommunityController } from './community.controller';
import { FeedController } from './feed.controller';
import { SocialController } from './social.controller';
import { EventController } from './event.controller';
import { CommunityService } from './community.service';

@Module({
  controllers: [CommunityController, FeedController, SocialController, EventController],
  providers: [CommunityService],
  exports: [CommunityService],
})
export class CommunityModule {}
