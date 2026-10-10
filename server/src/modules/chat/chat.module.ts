// server/src/modules/chat/chat.module.ts
//
// DAXELO KINREL — Chat Module
//
// v5 — Tier 4 features: adds StickerPacksService + EmojiPacksService +
// their controllers. Extends ChatService with editMessage (text +
// media swap + edit-history append).

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
// Tier 4 features:
import { StickerPacksService } from './sticker-packs.service';
import { StickerPacksController } from './sticker-packs.controller';
import { EmojiPacksService } from './emoji-packs.service';
import { EmojiPacksController } from './emoji-packs.controller';
import { PrismaModule } from '../../prisma/prisma.module';
import { FcmModule } from '../notifications/fcm.module';
import { AnalyticsModule } from '../analytics/analytics.module';

@Module({
  imports: [PrismaModule, FcmModule, AnalyticsModule],
  controllers: [
    ChatController,
    // Tier 1:
    ScheduledMessagesController,
    DraftsController,
    SavedMessagesController,
    // Tier 2:
    GroupAdminController,
    JoinViaLinkController,
    // Tier 3:
    ChatFoldersController,
    ChatReportsController,
    PrivacyController,
    // Tier 4:
    StickerPacksController,
    EmojiPacksController,
  ],
  providers: [
    ChatService,
    ChatGateway,
    StreakService,
    ChatPushScheduler,
    MediaService,
    ChatThrottlerService,
    // Tier 1:
    ScheduledMessagesService,
    DraftsService,
    // Tier 2:
    GroupAdminService,
    // Tier 3:
    ChatFoldersService,
    ChatReportsService,
    PrivacyService,
    // Tier 4:
    StickerPacksService,
    EmojiPacksService,
  ],
  exports: [
    ChatService,
    StreakService,
    MediaService,
    ChatThrottlerService,
    GroupAdminService,
    PrivacyService,
    StickerPacksService,
    EmojiPacksService,
  ],
})
export class ChatModule {}
