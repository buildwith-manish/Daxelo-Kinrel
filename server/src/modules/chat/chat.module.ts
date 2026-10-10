// server/src/modules/chat/chat.module.ts
//
// DAXELO KINREL — Chat Module
//
// v7 — Tier 6 features: adds TranslationsService + BotsService +
// BotMiniAppsService + their controllers. Extends ChatService.sendMessage
// with effectType (iOS-style message effects).

import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
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
// Tier 5 features:
import { SecretChatsService } from './secret-chats.service';
import { SecretChatsController } from './secret-chats.controller';
import { NearbyService } from './nearby.service';
import { NearbyController } from './nearby.controller';
import { ChatExportsService } from './chat-exports.service';
import { ChatExportsController } from './chat-exports.controller';
import { CloudBackupsService } from './cloud-backups.service';
import { CloudBackupsController } from './cloud-backups.controller';
import { UsernameDiscoveryService } from './username-discovery.service';
import { UsernameDiscoveryController } from './username-discovery.controller';
// Tier 6 features:
import { TranslationsService } from './translations.service';
import { TranslationsController } from './translations.controller';
import { BotsService } from './bots.service';
import { BotsController } from './bots.controller';
import { BotMiniAppsService } from './bot-mini-apps.service';
import { BotMiniAppsController } from './bot-mini-apps.controller';
import { PrismaModule } from '../../prisma/prisma.module';
import { FcmModule } from '../notifications/fcm.module';
import { AnalyticsModule } from '../analytics/analytics.module';

@Module({
  imports: [PrismaModule, FcmModule, AnalyticsModule, ConfigModule],
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
    // Tier 5:
    SecretChatsController,
    NearbyController,
    ChatExportsController,
    CloudBackupsController,
    UsernameDiscoveryController,
    // Tier 6:
    TranslationsController,
    BotsController,
    BotMiniAppsController,
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
    // Tier 5:
    SecretChatsService,
    NearbyService,
    ChatExportsService,
    CloudBackupsService,
    UsernameDiscoveryService,
    // Tier 6:
    TranslationsService,
    BotsService,
    BotMiniAppsService,
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
    SecretChatsService,
    NearbyService,
    TranslationsService,
    BotsService,
    BotMiniAppsService,
  ],
})
export class ChatModule {}
