// server/src/modules/chat/chat.module.ts
//
// DAXELO KINREL — Chat Module
//
// v2 — Tier 1 features: adds ScheduledMessages + Drafts + Saved
// Messages services/controllers to the existing chat module. The
// existing ChatService, ChatGateway, ChatPushScheduler, MediaService,
// StreakService, ChatThrottlerService are unchanged in behavior;
// ChatService.sendMessage and ChatPushScheduler are extended to pass
// through the new silent + caption + view-once + HD + document fields.

import { Module } from '@nestjs/common';
import { ChatController } from './chat.controller';
import { ChatService } from './chat.service';
import { ChatGateway } from './chat.gateway';
import { StreakService } from './streak.service';
import { ChatPushScheduler } from './chat-push.scheduler';
import { MediaService } from './media.service';
import { ChatThrottlerService } from './chat-throttler.service';
// Tier 1 features:
import { ScheduledMessagesService } from './scheduled-messages.service';
import { ScheduledMessagesController } from './scheduled-messages.controller';
import { DraftsService } from './drafts.service';
import { DraftsController } from './drafts.controller';
import { SavedMessagesController } from './saved-messages.controller';
import { PrismaModule } from '../../prisma/prisma.module';
import { FcmModule } from '../notifications/fcm.module';
import { AnalyticsModule } from '../analytics/analytics.module';

@Module({
  // PrismaModule is global, but importing it explicitly here makes the
  // dependency clear and lets this module be tested in isolation.
  // FcmModule provides FcmService for the batched-push scheduler.
  // AnalyticsModule provides ChatAnalyticsService for event tracking.
  imports: [PrismaModule, FcmModule, AnalyticsModule],
  controllers: [
    ChatController,
    // Tier 1 feature controllers:
    ScheduledMessagesController,
    DraftsController,
    SavedMessagesController,
  ],
  providers: [
    ChatService,
    ChatGateway,
    StreakService,
    ChatPushScheduler,
    MediaService,
    ChatThrottlerService,
    // Tier 1 feature services:
    ScheduledMessagesService,
    DraftsService,
  ],
  exports: [ChatService, StreakService, MediaService, ChatThrottlerService],
})
export class ChatModule {}
