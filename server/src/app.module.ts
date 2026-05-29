import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { ThrottlerModule } from '@nestjs/throttler';
import { ScheduleModule } from '@nestjs/schedule';
import { APP_GUARD } from '@nestjs/core';
import { PrismaModule } from './prisma/prisma.module';
import { LoggerModule } from './common/logger/logger.module';
import { AlertingModule } from './common/alerting/alerting.module';
import { CacheModule } from './common/cache/cache.module';
import { HealthModule } from './health/health.module';
import { AuthModule } from './modules/auth/auth.module';
import { UsersModule } from './modules/users/users.module';
import { GatewayModule } from './modules/gateway/gateway.module';
import { FamiliesModule } from './modules/families/families.module';
import { MembersModule } from './modules/members/members.module';
import { RelationshipsModule } from './modules/relationships/relationships.module';
import { GraphModule } from './modules/graph/graph.module';
import { ChatModule } from './modules/chat/chat.module';
import { TimelineModule } from './modules/timeline/timeline.module';
import { NotificationsModule } from './modules/notifications/notifications.module';
import { PaymentsModule } from './modules/payments/payments.module';
import { InvitationsModule } from './modules/invitations/invitations.module';
import { SupportModule } from './modules/support/support.module';
import { CommunityModule } from './modules/community/community.module';
import { DeveloperModule } from './modules/developer/developer.module';
import { ModerationModule } from './modules/moderation/moderation.module';
import { WhatsAppModule } from './modules/whatsapp/whatsapp.module';
import { ShareModule } from './modules/share/share.module';
import { AdminModule } from './modules/admin/admin.module';
import { KinshipModule } from './modules/kinship/kinship.module';
import { ProfileModule } from './modules/profile/profile.module';
import { AiChatModule } from './modules/ai-chat/ai-chat.module';
import { GamificationModule } from './modules/gamification/gamification.module';
import { AiCardsModule } from './modules/ai-cards/ai-cards.module';
import { ReferralModule } from './modules/referral/referral.module';
import { AiVoiceModule } from './modules/ai-voice/ai-voice.module';
import { SyncModule } from './modules/sync/sync.module';
import { RealtimeModule } from './modules/realtime/realtime.module';
import { CustomThrottlerGuard } from './common/guards/throttler.guard';

@Module({
  imports: [
    // ── Global configuration ────────────────────────────────
    ConfigModule.forRoot({
      isGlobal: true,
      envFilePath: '.env',
    }),

    // ── Rate limiting ───────────────────────────────────────
    ThrottlerModule.forRoot([
      {
        name: 'short',
        ttl: 1000,    // 1 second
        limit: 20,    // 20 requests per second
      },
      {
        name: 'long',
        ttl: 60000,   // 1 minute
        limit: 200,   // 200 requests per minute
      },
      {
        name: 'auth',
        ttl: 60000,   // 1 minute
        limit: 5,     // 5 auth attempts per minute per IP
      },
    ]),

    // ── Global structured logger (Winston) ──────────────────
    LoggerModule,

    // ── Global alerting service ─────────────────────────────
    AlertingModule,

    // ── Global Prisma database module ───────────────────────
    PrismaModule,

    // ── Global cache module ─────────────────────────────────
    CacheModule,

    // ── Schedule module (cron jobs) ──────────────────────────
    ScheduleModule.forRoot(),

    // ── Health check ────────────────────────────────────────
    HealthModule,

    // ── WebSocket gateway ───────────────────────────────────
    GatewayModule,

    // ── Feature modules ─────────────────────────────────────
    AuthModule,
    UsersModule,
    FamiliesModule,
    MembersModule,
    RelationshipsModule,
    GraphModule,
    ChatModule,
    TimelineModule,
    NotificationsModule,
    PaymentsModule,

    // ── New feature modules (Flutter + AI) ──────────────────
    InvitationsModule,
    SupportModule,
    CommunityModule,
    DeveloperModule,
    ModerationModule,
    WhatsAppModule,
    ShareModule,
    AdminModule,
    KinshipModule,
    ProfileModule,
    AiChatModule,
    GamificationModule,
    AiCardsModule,
    ReferralModule,
    AiVoiceModule,

    // ── Sync module ─────────────────────────────────────────
    SyncModule,

    // ── Realtime module (Supabase Realtime) ──────────────────
    RealtimeModule,
  ],
  providers: [
    // ── Global rate limiting guard ──────────────────────────
    { provide: APP_GUARD, useClass: CustomThrottlerGuard },
  ],
})
export class AppModule {}
