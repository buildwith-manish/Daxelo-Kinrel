// server/src/kinrel/kinrel.module.ts
//
// Kinrel — NestJS Module
//
// Wires together all Kinrel services and exposes the REST controller.
// PrismaModule is @Global() so it doesn't need to be imported here.
// EventEmitterModule is registered globally in AppModule.

import { Module } from '@nestjs/common';
import { KinrelController } from './kinrel.controller';
import { KinrelOrchestrationService } from './kinrel-orchestration.service';
import { KinrelQueryService } from './kinrel-query.service';
import { GraphAnalysisService } from './graph-analysis.service';
import { ArchetypeClassifierService } from './archetype-classifier.service';
import { KinrelParameterGeneratorService } from './kinrel-parameter-generator.service';
import { RoleGlyphService } from './role-glyph.service';
import { KinrelEventListener } from './kinrel-event.listener';

@Module({
  controllers: [KinrelController],
  providers: [
    KinrelOrchestrationService,
    KinrelQueryService,
    GraphAnalysisService,
    ArchetypeClassifierService,
    KinrelParameterGeneratorService,
    RoleGlyphService,
    KinrelEventListener,
  ],
  exports: [KinrelOrchestrationService, KinrelEventListener],
})
export class KinrelModule {}
