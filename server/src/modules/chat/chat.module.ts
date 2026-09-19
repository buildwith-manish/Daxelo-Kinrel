import { Module } from '@nestjs/common';
import { ChatController } from './chat.controller';
import { ChatService } from './chat.service';
import { ChatGateway } from './chat.gateway';
import { StreakService } from './streak.service';
import { ChatPushScheduler } from './chat-push.scheduler';
import { MediaService } from './media.service';
import { PrismaModule } from '../../prisma/prisma.module';
import { FcmModule } from '../notifications/fcm.module';

@Module({
  // PrismaModule is global, but importing it explicitly here makes the
  // dependency clear and lets this module be tested in isolation.
  // FcmModule provides FcmService for the batched-push scheduler.
  imports: [PrismaModule, FcmModule],
  controllers: [ChatController],
  providers: [ChatService, ChatGateway, StreakService, ChatPushScheduler, MediaService],
  exports: [ChatService, StreakService, MediaService],
})
export class ChatModule {}
