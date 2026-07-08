// server/src/aura/aura.module.ts
//
// AURA — NestJS Module
//
// Wires together all AURA services and exposes the REST controller.
// PrismaModule is @Global() so it doesn't need to be imported here.
// EventEmitterModule is registered globally in AppModule.

import { Module } from '@nestjs/common';
import { AuraController } from './aura.controller';
import { AuraOrchestrationService } from './aura-orchestration.service';
import { AuraQueryService } from './aura-query.service';
import { GraphAnalysisService } from './graph-analysis.service';
import { ArchetypeClassifierService } from './archetype-classifier.service';
import { AuraParameterGeneratorService } from './aura-parameter-generator.service';
import { RoleGlyphService } from './role-glyph.service';
import { AuraEventListener } from './aura-event.listener';

@Module({
  controllers: [AuraController],
  providers: [
    AuraOrchestrationService,
    AuraQueryService,
    GraphAnalysisService,
    ArchetypeClassifierService,
    AuraParameterGeneratorService,
    RoleGlyphService,
    AuraEventListener,
  ],
  exports: [AuraOrchestrationService, AuraEventListener],
})
export class AuraModule {}
