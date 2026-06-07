import { Module } from '@nestjs/common';
import { SyncController } from './sync.controller';
import { SyncService } from './sync.service';

/**
 * SyncModule — Provides the incremental sync endpoint.
 *
 * POST /api/sync — returns all data modified since a given timestamp.
 * Uses PrismaService (globally provided by PrismaModule).
 */
@Module({
  controllers: [SyncController],
  providers: [SyncService],
})
export class SyncModule {}
