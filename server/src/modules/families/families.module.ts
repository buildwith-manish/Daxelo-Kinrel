import { Module, forwardRef } from '@nestjs/common';
import { FamiliesController } from './families.controller';
import { FamiliesService } from './families.service';
import { FamilyIdController } from './family-id.controller';
import { FamilyIdService } from './family-id.service';
import { GatewayModule } from '../gateway/gateway.module';
import { NotificationsModule } from '../notifications/notifications.module';

@Module({
  imports: [GatewayModule, forwardRef(() => NotificationsModule)],
  controllers: [FamiliesController, FamilyIdController],
  providers: [FamiliesService, FamilyIdService],
  exports: [FamiliesService, FamilyIdService],
})
export class FamiliesModule {}
