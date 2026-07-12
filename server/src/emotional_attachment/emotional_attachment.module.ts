// server/src/emotional_attachment/emotional attachment.module.ts
//
// emotional attachment features — NestJS Module.
//
// Wires together:
//   A-6 Festival Intelligence (FestivalService)
//   A-1 Blessing Chain (BlessingChainService)
//   A-2 Time Capsule (TimeCapsuleService)
//   Daily cron (EmotionalAttachmentCronService — refreshes festivals + delivers blessings/capsules)
//
// PrismaModule is @Global(). ScheduleModule is global. EventEmitterModule is global.

import { Module } from '@nestjs/common';
import { EmotionalAttachmentController } from './emotional_attachment.controller';
import { FestivalService } from './festival.service';
import { BlessingChainService } from './blessing-chain.service';
import { TimeCapsuleService } from './time-capsule.service';
import { FamilyQuestService } from './family-quest.service';
import { SilentAlarmService } from './silent-alarm.service';
import { FamilyChronicleService } from './family-chronicle.service';
import { EmotionalAttachmentCronService } from './emotional-attachment-cron.service';

@Module({
  controllers: [EmotionalAttachmentController],
  providers: [
    FestivalService,
    BlessingChainService,
    TimeCapsuleService,
    FamilyQuestService,
    SilentAlarmService,
    FamilyChronicleService,
    EmotionalAttachmentCronService,
  ],
  exports: [
    FestivalService,
    BlessingChainService,
    TimeCapsuleService,
    FamilyQuestService,
    SilentAlarmService,
    FamilyChronicleService,
  ],
})
export class EmotionalAttachmentModule {}
