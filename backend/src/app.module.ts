import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { LoggerModule } from 'nestjs-pino';
import { PrismaModule } from './prisma/prisma.module';
import { AuthModule } from './auth/auth.module';
import { FamilyModule } from './family/family.module';
import { ProfileModule } from './profile/profile.module';
import { UsersModule } from './users/users.module';
import { NotificationsModule } from './notifications/notifications.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
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
    PrismaModule,
    AuthModule,
    FamilyModule,
    ProfileModule,
    UsersModule,
    NotificationsModule,
  ],
})
export class AppModule {}
