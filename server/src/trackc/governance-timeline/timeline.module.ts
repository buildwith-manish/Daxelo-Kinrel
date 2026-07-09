// =============================================================================
// Track C v2.0 — AURA Timeline
// timeline.module.ts
// =============================================================================

import { Module } from '@nestjs/common';
import { TimelineController } from './timeline.controller';
import { TimelineService } from './timeline.service';
import { TimelineEmitter } from './timeline.emitter';
import { TimelineExporter } from './timeline.exporter';
import { TrackcCommonModule } from '../common/trackc-common.module';
import { PrismaModule } from '../../prisma/prisma.module';

@Module({
  imports: [PrismaModule, TrackcCommonModule],
  controllers: [TimelineController],
  providers: [TimelineService, TimelineEmitter, TimelineExporter],
  exports: [TimelineService, TimelineEmitter, TimelineExporter],
})
export class GovernanceTimelineModule {}
