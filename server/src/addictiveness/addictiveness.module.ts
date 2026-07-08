// server/src/addictiveness/addictiveness.module.ts
//
// Addictiveness features — NestJS Module.
//
// Wires together:
//   A-6 Festival Intelligence (FestivalService)
//   A-1 Blessing Chain (BlessingChainService)
//   A-2 Time Capsule (TimeCapsuleService)
//   Daily cron (AddictivenessCronService — refreshes festivals + delivers blessings/capsules)
//
// PrismaModule is @Global(). ScheduleModule is global. EventEmitterModule is global.

import { Module } from '@nestjs/common';
import { AddictivenessController } from './addictiveness.controller';
import { FestivalService } from './festival.service';
import { BlessingChainService } from './blessing-chain.service';
import { TimeCapsuleService } from './time-capsule.service';
import { AddictivenessCronService } from './addictiveness-cron.service';

@Module({
  controllers: [AddictivenessController],
  providers: [
    FestivalService,
    BlessingChainService,
    TimeCapsuleService,
    AddictivenessCronService,
  ],
  exports: [FestivalService, BlessingChainService, TimeCapsuleService],
})
export class AddictivenessModule {}
