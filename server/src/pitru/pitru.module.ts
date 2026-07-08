// server/src/pitru/pitru.module.ts
//
// PITRU — NestJS Module
//
// Wires the PitruService + PitruController. PrismaModule is @Global().
// EventEmitterModule is registered globally in AppModule.

import { Module } from '@nestjs/common';
import { PitruController } from './pitru.controller';
import { PitruService } from './pitru.service';
import { PitruMemorialListener } from './pitru-memorial.listener';

@Module({
  controllers: [PitruController],
  providers: [PitruService, PitruMemorialListener],
  exports: [PitruService],
})
export class PitruModule {}
