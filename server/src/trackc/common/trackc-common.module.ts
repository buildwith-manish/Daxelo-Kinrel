// =============================================================================
// Track C v2.0 — Common module
// =============================================================================

import { Module } from '@nestjs/common';
import { RealtimeService } from './realtime.proxy';
import { FamilyMembershipService } from './family-membership.service';
import { PrismaModule } from '../../prisma/prisma.module';

@Module({
  imports: [PrismaModule],
  providers: [RealtimeService, FamilyMembershipService],
  exports: [RealtimeService, FamilyMembershipService],
})
export class TrackcCommonModule {}
