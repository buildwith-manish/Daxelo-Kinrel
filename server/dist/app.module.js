"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.AppModule = void 0;
const common_1 = require("@nestjs/common");
const config_1 = require("@nestjs/config");
const throttler_1 = require("@nestjs/throttler");
const schedule_1 = require("@nestjs/schedule");
const core_1 = require("@nestjs/core");
const prisma_module_1 = require("./prisma/prisma.module");
const logger_module_1 = require("./common/logger/logger.module");
const alerting_module_1 = require("./common/alerting/alerting.module");
const cache_module_1 = require("./common/cache/cache.module");
const health_module_1 = require("./health/health.module");
const auth_module_1 = require("./modules/auth/auth.module");
const users_module_1 = require("./modules/users/users.module");
const gateway_module_1 = require("./modules/gateway/gateway.module");
const families_module_1 = require("./modules/families/families.module");
const members_module_1 = require("./modules/members/members.module");
const relationships_module_1 = require("./modules/relationships/relationships.module");
const graph_module_1 = require("./modules/graph/graph.module");
const chat_module_1 = require("./modules/chat/chat.module");
const timeline_module_1 = require("./modules/timeline/timeline.module");
const notifications_module_1 = require("./modules/notifications/notifications.module");
const payments_module_1 = require("./modules/payments/payments.module");
const invitations_module_1 = require("./modules/invitations/invitations.module");
const support_module_1 = require("./modules/support/support.module");
const community_module_1 = require("./modules/community/community.module");
const developer_module_1 = require("./modules/developer/developer.module");
const moderation_module_1 = require("./modules/moderation/moderation.module");
const whatsapp_module_1 = require("./modules/whatsapp/whatsapp.module");
const share_module_1 = require("./modules/share/share.module");
const admin_module_1 = require("./modules/admin/admin.module");
const kinship_module_1 = require("./modules/kinship/kinship.module");
const profile_module_1 = require("./modules/profile/profile.module");
const ai_chat_module_1 = require("./modules/ai-chat/ai-chat.module");
const gamification_module_1 = require("./modules/gamification/gamification.module");
const ai_cards_module_1 = require("./modules/ai-cards/ai-cards.module");
const referral_module_1 = require("./modules/referral/referral.module");
const ai_voice_module_1 = require("./modules/ai-voice/ai-voice.module");
const sync_module_1 = require("./modules/sync/sync.module");
const throttler_guard_1 = require("./common/guards/throttler.guard");
let AppModule = class AppModule {
};
exports.AppModule = AppModule;
exports.AppModule = AppModule = __decorate([
    (0, common_1.Module)({
        imports: [
            config_1.ConfigModule.forRoot({
                isGlobal: true,
                envFilePath: '.env',
            }),
            throttler_1.ThrottlerModule.forRoot([
                {
                    name: 'short',
                    ttl: 1000,
                    limit: 20,
                },
                {
                    name: 'long',
                    ttl: 60000,
                    limit: 200,
                },
                {
                    name: 'auth',
                    ttl: 60000,
                    limit: 5,
                },
            ]),
            logger_module_1.LoggerModule,
            alerting_module_1.AlertingModule,
            prisma_module_1.PrismaModule,
            cache_module_1.CacheModule,
            schedule_1.ScheduleModule.forRoot(),
            health_module_1.HealthModule,
            gateway_module_1.GatewayModule,
            auth_module_1.AuthModule,
            users_module_1.UsersModule,
            families_module_1.FamiliesModule,
            members_module_1.MembersModule,
            relationships_module_1.RelationshipsModule,
            graph_module_1.GraphModule,
            chat_module_1.ChatModule,
            timeline_module_1.TimelineModule,
            notifications_module_1.NotificationsModule,
            payments_module_1.PaymentsModule,
            invitations_module_1.InvitationsModule,
            support_module_1.SupportModule,
            community_module_1.CommunityModule,
            developer_module_1.DeveloperModule,
            moderation_module_1.ModerationModule,
            whatsapp_module_1.WhatsAppModule,
            share_module_1.ShareModule,
            admin_module_1.AdminModule,
            kinship_module_1.KinshipModule,
            profile_module_1.ProfileModule,
            ai_chat_module_1.AiChatModule,
            gamification_module_1.GamificationModule,
            ai_cards_module_1.AiCardsModule,
            referral_module_1.ReferralModule,
            ai_voice_module_1.AiVoiceModule,
            sync_module_1.SyncModule,
        ],
        providers: [
            { provide: core_1.APP_GUARD, useClass: throttler_guard_1.CustomThrottlerGuard },
        ],
    })
], AppModule);
//# sourceMappingURL=app.module.js.map