// server/src/pulse/pulse.module.ts
//
// PULSE — NestJS Module
//
// Wires together all Pulse services and exposes the REST controller.
// PrismaModule is @Global() so it doesn't need to be imported here.
// EventEmitterModule is registered globally in AppModule.
// ScheduleModule is registered globally in AppModule.
//
// On module init, we inject all 6 collectors into BriefGeneratorService via
// setCollectors(). This avoids circular deps and lets the generator iterate
// them in parallel.

import { Module, OnModuleInit } from '@nestjs/common';
import { PulseController } from './pulse.controller';
import { BriefGeneratorService } from './brief-generator.service';
import { PulseQueryService } from './pulse-query.service';
import { PulseCronService } from './pulse-cron.service';
import { PersonalizationService } from './personalization.service';
import { PulsePushListener } from './pulse-push.listener';
import { BirthdayCollector } from './collectors/birthday.collector';
import { InactivityCollector } from './collectors/inactivity.collector';
import { FeedHighlightCollector } from './collectors/feed-highlight.collector';
import { OnThisDayCollector } from './collectors/on-this-day.collector';
import { WeatherCollector } from './collectors/weather.collector';
import { MemoryOrbitCollector } from './collectors/memory-orbit.collector';
import { FcmModule } from '../modules/notifications/fcm.module';

@Module({
  imports: [
    // FcmModule provides FcmService, used by PulsePushListener to send
    // push notifications when a brief is generated.
    FcmModule,
  ],
  controllers: [PulseController],
  providers: [
    BriefGeneratorService,
    PulseQueryService,
    PulseCronService,
    PersonalizationService,
    PulsePushListener,
    // Collectors (each injects PrismaService via PrismaModule @Global)
    BirthdayCollector,
    InactivityCollector,
    FeedHighlightCollector,
    OnThisDayCollector,
    WeatherCollector,
    MemoryOrbitCollector,
  ],
  exports: [BriefGeneratorService, PulseQueryService, PulseCronService, PersonalizationService],
})
export class PulseModule implements OnModuleInit {
  constructor(
    private readonly generator: BriefGeneratorService,
    private readonly birthday: BirthdayCollector,
    private readonly inactivity: InactivityCollector,
    private readonly feedHighlight: FeedHighlightCollector,
    private readonly onThisDay: OnThisDayCollector,
    private readonly weather: WeatherCollector,
    private readonly memoryOrbit: MemoryOrbitCollector,
  ) {}

  onModuleInit() {
    // Register all collectors with the orchestrator. Order matters for
    // tie-breaking when priorities are equal — but the priority field dominates.
    this.generator.setCollectors([
      this.birthday,
      this.inactivity,
      this.feedHighlight,
      this.onThisDay,
      this.weather,
      this.memoryOrbit,
    ]);
  }
}
