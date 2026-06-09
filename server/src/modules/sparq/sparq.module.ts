import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { SparqController } from './sparq.controller';
import { SparqService } from './sparq.service';
import { GatewayModule } from '../gateway/gateway.module';

@Module({
  imports: [GatewayModule, ConfigModule],
  controllers: [SparqController],
  providers: [SparqService],
  exports: [SparqService],
})
export class SparqModule {}
