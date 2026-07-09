// =============================================================================
// Track C v2.0 — AURA Search
// search.module.ts
// =============================================================================

import { Module } from '@nestjs/common';
import { SearchController } from './search.controller';
import { SearchService } from './search.service';
import { TrackcCommonModule } from '../common/trackc-common.module';
import { PrismaModule } from '../../prisma/prisma.module';

@Module({
  imports: [PrismaModule, TrackcCommonModule],
  controllers: [SearchController],
  providers: [SearchService],
  exports: [SearchService],
})
export class AuraSearchModule {}
