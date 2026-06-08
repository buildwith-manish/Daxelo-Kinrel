import { Module } from '@nestjs/common';
import { SparqController } from './sparq.controller';
import { SparqService } from './sparq.service';
import { GatewayModule } from '../gateway/gateway.module';

@Module({
  imports: [GatewayModule],
  controllers: [SparqController],
  providers: [SparqService],
  exports: [SparqService],
})
export class SparqModule {}
