import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { LoggerModule } from 'nestjs-pino';
import { ScheduleModule } from '@nestjs/schedule';
import { configuration, validationSchema } from './config/configuration';
import { PrismaModule } from './prisma/prisma.module';
import { AuthModule } from './auth/auth.module';
import { FamilyModule } from './family/family.module';
import { ProfileModule } from './profile/profile.module';
import { UsersModule } from './users/users.module';
import { NotificationsModule } from './notifications/notifications.module';
import { LegalModule } from './legal/legal.module';
import { ReferralModule } from './referral/referral.module';
import { PremiumModule } from './premium/premium.module';
import { AnalyticsModule } from './analytics/analytics.module';
import { CampaignsModule } from './campaigns/campaigns.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      load: [configuration],
      validationSchema: validationSchema,
      validationOptions: {
        allowUnknown: true,
        abortEarly: false,
      },
    }),
    LoggerModule.forRoot({
      pinoHttp: {
        level: process.env.LOG_LEVEL || (process.env.NODE_ENV === 'production' ? 'info' : 'debug'),
        transport: process.env.NODE_ENV !== 'production'
          ? { target: 'pino-pretty', options: { colorize: true } }
          : undefined,
        serializers: {
          req: (req: any) => ({
            method: req.method,
            url: req.url,
            userId: req.user?.id ?? 'anonymous',
          }),
          res: (res: any) => ({
            statusCode: res.statusCode,
          }),
        },
        redact: {
          paths: ['req.headers.authorization', 'req.body.password', 'req.body.token'],
          censor: '[REDACTED]',
        },
      },
    }),
    // P5: Required for @Cron decorators in CampaignsScheduler and PremiumService
    ScheduleModule.forRoot(),
    PrismaModule,
    AuthModule,
    FamilyModule,
    ProfileModule,
    UsersModule,
    NotificationsModule,
    LegalModule,
    ReferralModule,
    PremiumModule,
    AnalyticsModule,
    CampaignsModule,
  ],
})
export class AppModule {}
