import { Module } from '@nestjs/common';
import { FamiliesController } from './families.controller';
import { FamiliesService } from './families.service';
import { FamilyIdController } from './family-id.controller';
import { FamilyIdService } from './family-id.service';
import { GatewayModule } from '../gateway/gateway.module';

@Module({
  imports: [GatewayModule],
  controllers: [FamiliesController, FamilyIdController],
  providers: [FamiliesService, FamilyIdService],
  exports: [FamiliesService, FamilyIdService],
})
export class FamiliesModule {}
