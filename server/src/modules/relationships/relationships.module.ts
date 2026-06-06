import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { RelationshipsController } from './relationships.controller';
import { RelationshipsService } from './relationships.service';
import { GatewayModule } from '../gateway/gateway.module';

@Module({
  imports: [ConfigModule, GatewayModule],
  controllers: [RelationshipsController],
  providers: [RelationshipsService],
  exports: [RelationshipsService],
})
export class RelationshipsModule {}
