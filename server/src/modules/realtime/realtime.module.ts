import { Module } from '@nestjs/common';
import { RealtimeGateway } from './realtime.gateway';
import { RealtimeService } from './realtime.service';
import { SupabaseRealtimeService } from './supabase-realtime.service';

@Module({
  providers: [RealtimeGateway, RealtimeService, SupabaseRealtimeService],
  exports: [RealtimeService, SupabaseRealtimeService],
})
export class RealtimeModule {}
