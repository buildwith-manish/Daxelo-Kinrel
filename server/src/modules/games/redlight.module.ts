import { Module } from '@nestjs/common';
import { RedlightGateway } from './redlight-gateway';

@Module({
  providers: [RedlightGateway],
  exports: [RedlightGateway],
})
export class RedlightModule {}
