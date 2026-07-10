// =============================================================================
// Track C v2.0 — Common module
// =============================================================================

import { Module } from '@nestjs/common';
import { RealtimeService } from './realtime.proxy';
import { FamilyMembershipService } from './family-membership.service';
import { VisibilityService } from './visibility.service';
import { PrismaModule } from '../../prisma/prisma.module';

@Module({
  imports: [PrismaModule],
  providers: [RealtimeService, FamilyMembershipService, VisibilityService],
  exports: [RealtimeService, FamilyMembershipService, VisibilityService],
})
export class TrackcCommonModule {}
