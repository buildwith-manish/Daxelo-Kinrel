import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { PrismaModule } from './common/prisma/prisma.module';
import { HealthModule } from './modules/health/health.module';
import { AuthModule } from './modules/auth/auth.module';
import { UserModule } from './modules/user/user.module';
import { FamilyModule } from './modules/family/family.module';
import { KinshipModule } from './modules/kinship/kinship.module';
import { GraphModule } from './modules/graph/graph.module';
import { NotificationModule } from './modules/notification/notification.module';
import { SupportModule } from './modules/support/support.module';
import { WhatsAppModule } from './modules/whatsapp/whatsapp.module';
import { ModerationModule } from './modules/moderation/moderation.module';
import { CommunityModule } from './modules/community/community.module';
import { DeveloperModule } from './modules/developer/developer.module';
import { ShareModule } from './modules/share/share.module';
import { InvitationModule } from './modules/invitation/invitation.module';
import { KnowledgeBaseModule } from './modules/knowledge-base/knowledge-base.module';
import { WebSocketModule } from './modules/websocket/websocket.module';
import { AiChatModule } from './modules/ai-chat/ai-chat.module';
import { AiVoiceModule } from './modules/ai-voice/ai-voice.module';
import { AiCardsModule } from './modules/ai-cards/ai-cards.module';
import { GamificationModule } from './modules/gamification/gamification.module';
import { ReferralModule } from './modules/referral/referral.module';

@Module({
  imports: [
    // Global configuration
    ConfigModule.forRoot({
      isGlobal: true,
      envFilePath: '.env',
    }),

    // Global Prisma database module
    PrismaModule,

    // Health check
    HealthModule,

    // Feature modules
    AuthModule,
    UserModule,
    FamilyModule,
    KinshipModule,
    GraphModule,
    NotificationModule,
    SupportModule,
    WhatsAppModule,
    ModerationModule,
    CommunityModule,
    DeveloperModule,
    ShareModule,
    InvitationModule,
    KnowledgeBaseModule,
    WebSocketModule,

    // AI-powered modules
    AiChatModule,
    AiVoiceModule,
    AiCardsModule,

    // Growth & engagement modules
    GamificationModule,
    ReferralModule,
  ],
})
export class AppModule {}
