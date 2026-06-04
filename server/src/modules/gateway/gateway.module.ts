import { Module } from '@nestjs/common';
import { KinrelGateway } from './kinrel.gateway';

@Module({
  providers: [KinrelGateway],
  exports: [KinrelGateway],
})
export class GatewayModule {}
