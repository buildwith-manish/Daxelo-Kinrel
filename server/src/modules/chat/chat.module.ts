// server/src/modules/chat/chat.module.ts
//
// DAXELO KINREL — Chat Module
//
// v4 — Tier 3 features: adds ChatFoldersService + ChatReportsService +
// PrivacyService + their controllers. Extends ChatService with
// pin/forced-unread/mute-until methods + extended search filters.

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
// Tier 2 features:
import { GroupAdminService } from './group-admin.service';
import { GroupAdminController, JoinViaLinkController } from './group-admin.controller';
// Tier 3 features:
import { ChatFoldersService } from './chat-folders.service';
import { ChatFoldersController } from './chat-folders.controller';
import { ChatReportsService } from './chat-reports.service';
import { ChatReportsController } from './chat-reports.controller';
import { PrivacyService } from './privacy.service';
import { PrivacyController } from './privacy.controller';
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
    // Tier 2 feature controllers:
    GroupAdminController,
    JoinViaLinkController,
    // Tier 3 feature controllers:
    ChatFoldersController,
    ChatReportsController,
    PrivacyController,
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
    // Tier 2 feature services:
    GroupAdminService,
    // Tier 3 feature services:
    ChatFoldersService,
    ChatReportsService,
    PrivacyService,
  ],
  exports: [
    ChatService,
    StreakService,
    MediaService,
    ChatThrottlerService,
    GroupAdminService,
    PrivacyService,
  ],
})
export class ChatModule {}
