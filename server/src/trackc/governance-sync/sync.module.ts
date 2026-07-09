// =============================================================================
// Track C v2.0 — Governance Sync
// sync.module.ts
// =============================================================================

import { Module } from '@nestjs/common';
import { GovernanceSyncController } from './sync.controller';
import { SyncDeltaService } from './sync.delta.service';
import { SyncPushService } from './sync.push.service';
import { TrackcCommonModule } from '../common/trackc-common.module';
import { PrismaModule } from '../../prisma/prisma.module';

@Module({
  imports: [PrismaModule, TrackcCommonModule],
  controllers: [GovernanceSyncController],
  providers: [SyncDeltaService, SyncPushService],
  exports: [SyncDeltaService, SyncPushService],
})
export class GovernanceSyncModule {}
